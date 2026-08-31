using Godot;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

/// <summary>
/// Owns a Cherry Navigation stack and serializes every structural mutation.
/// </summary>
/// <remarks>
/// The Navigator maintains two views:
/// <list type="bullet">
/// <item><description>Committed mounted state exposed by CurrentRoute/Routes.</description></item>
/// <item><description>Already accepted logical state exposed by ScheduledCurrentRoute/ScheduledRoutes.</description></item>
/// </list>
/// Lifecycle callbacks are emitted only at transaction commit points, so their
/// documented CurrentRoute and Route.State invariants always hold.
/// </remarks>
public partial class Navigator : Control
{
    private sealed record QueuedOperation(StringName Name, Func<Task> Execute);

    private readonly List<NavigationRoute> _routes = new();
    private readonly List<NavigationRoute> _mountedRoutes = new();
    private readonly Queue<QueuedOperation> _operationQueue = new();
    private NavigationRoute? _currentRoute;
    private Navigator? _explicitParentNavigator;
    private bool _isProcessingOperations;
    private bool _operationRunning;

    /// <summary>Fallback transition when a route's snapshotted Transition is null.</summary>
    [Export] public NavigationTransition? DefaultTransition { get; set; }

    /// <summary>
    /// Parent used only for MaybePop/back propagation.
    /// </summary>
    /// <remarks>
    /// A valid explicit assignment overrides SceneTree discovery. Assigning
    /// <c>null</c> clears that override and restores automatic lookup of the
    /// nearest ancestor Navigator. The fallback is resolved dynamically, so
    /// reparenting this Navigator updates its automatic parent relationship.
    ///
    /// This relation does not imply route or SceneTree ownership. Structural
    /// operations such as Pop, Replace, Remove, and Clear always act on this
    /// Navigator only. Explicit self-reference and parent cycles are rejected.
    /// </remarks>
    public Navigator? ParentNavigator
    {
        get
        {
            if (_explicitParentNavigator != null && GodotObject.IsInstanceValid(_explicitParentNavigator))
                return _explicitParentNavigator;
            return FindAncestorNavigator();
        }
        set
        {
            if (value != null && !GodotObject.IsInstanceValid(value))
                value = null;
            if (value == null)
            {
                _explicitParentNavigator = null;
                return;
            }
            if (ReferenceEquals(value, _explicitParentNavigator))
                return;
            if (ReferenceEquals(value, this) || WouldCreateParentCycle(value))
                throw new InvalidOperationException("Navigator parent relation cannot contain a cycle.");
            _explicitParentNavigator = value;
        }
    }

    /// <summary>Raised when a route starts its queued push lifecycle.</summary>
    public event Action<NavigationRoute>? RoutePushing;

    /// <summary>Raised after a route becomes Active and receives OnNavigationEntered.</summary>
    public event Action<NavigationRoute>? RoutePushed;

    /// <summary>Raised before an outgoing route starts its Pop presentation.</summary>
    public event Action<NavigationRoute, object?>? RoutePopping;

    /// <summary>Raised after lifecycle callbacks complete for a normal Pop.</summary>
    public event Action<NavigationRoute, object?>? RoutePopped;

    /// <summary>Raised after a Replace transaction fully commits.</summary>
    public event Action<NavigationRoute, NavigationRoute>? RouteReplaced;

    /// <summary>Raised after Remove/Clear permanently removes a route.</summary>
    public event Action<NavigationRoute>? RouteRemoved;

    /// <summary>Raised when configured Push/Replace creation fails before lifecycle entry.</summary>
    public event Action<NavigationRoute, Exception>? RouteFailed;

    /// <summary>
    /// Raised when a transition throws. Structural navigation still commits so
    /// the operation queue cannot become inconsistent.
    /// </summary>
    public event Action<NavigationRoute, Exception>? TransitionFailed;

    /// <summary>Raised immediately before a serialized operation starts.</summary>
    public event Action<StringName>? OperationStarted;

    /// <summary>Raised after a serialized operation fully completes.</summary>
    public event Action<StringName>? OperationFinished;

    /// <summary>Raised whenever running + waiting operation count changes.</summary>
    public event Action<int>? OperationQueueChanged;

    /// <summary>
    /// Route currently committed as navigation-current.
    /// </summary>
    /// <remarks>
    /// Unlike V0.1.13 this is not the speculative queued route. During
    /// OnNavigationEntered/Revealed it always equals the callback page's Route.
    /// </remarks>
    public NavigationRoute? CurrentRoute => _currentRoute;

    /// <summary>First currently mounted route, or null.</summary>
    public NavigationRoute? FirstRoute => _mountedRoutes.Count == 0 ? null : _mountedRoutes[0];

    /// <summary>Number of currently mounted routes.</summary>
    public int RouteCount => _mountedRoutes.Count;

    /// <summary>Route that will be current after all accepted operations finish.</summary>
    public NavigationRoute? ScheduledCurrentRoute => _routes.Count == 0 ? null : _routes[^1];

    /// <summary>Number of routes in the accepted logical stack.</summary>
    public int ScheduledRouteCount => _routes.Count;

    /// <summary>Whether a presentation transition is currently executing.</summary>
    public bool IsTransitioning { get; private set; }

    /// <summary>Whether an operation is running or waiting.</summary>
    public bool IsOperating => _isProcessingOperations || _operationQueue.Count > 0;

    /// <summary>Running operation plus operations still waiting.</summary>
    public int PendingOperationCount => _operationQueue.Count + (_operationRunning ? 1 : 0);

    /// <summary>Whether another logical Pop can be accepted while preserving one root route.</summary>
    public bool CanPop => _routes.Count > 1;

    /// <summary>Read-only committed mounted stack.</summary>
    public IReadOnlyList<NavigationRoute> Routes => _mountedRoutes;

    /// <summary>Read-only logical stack after all accepted operations.</summary>
    public IReadOnlyList<NavigationRoute> ScheduledRoutes => _routes;

    /// <summary>Schedules a type-safe parameter-based Push.</summary>
    public NavigationRoute<TPage> Push<TPage>(object? parameters = null) where TPage : NavigationPage
    {
        PageDefinition definition = PageRegistry.Instance.Resolve<TPage>();
        ValidateDefinition(definition);
        var route = new NavigationRoute<TPage>(definition, parameters);
        _routes.Add(route);
        EnqueueOperation("push", () => ExecutePushAsync(route, typeof(TPage), null, NavigationEnterReason.Push));
        return route;
    }

    /// <summary>
    /// Schedules a type-safe configured Push. Configuration is awaited before
    /// AddChild and before OnNavigationEntered.
    /// </summary>
    /// <remarks>
    /// This overload intentionally has no parameters argument. Do not await
    /// another operation on this same Navigator from inside configure: that
    /// operation is queued behind the current transaction and would deadlock.
    /// Scheduling a non-awaited operation is allowed.
    /// </remarks>
    public NavigationRoute<TPage> Push<TPage>(Func<TPage, Task> configure) where TPage : NavigationPage
    {
        ArgumentNullException.ThrowIfNull(configure);
        PageDefinition definition = PageRegistry.Instance.Resolve<TPage>();
        ValidateDefinition(definition);
        var route = new NavigationRoute<TPage>(definition, null);
        _routes.Add(route);
        EnqueueOperation("push_configured", () => ExecutePushAsync(route, typeof(TPage), page => configure((TPage)page), NavigationEnterReason.Push));
        return route;
    }

    /// <summary>Schedules a type-safe Push and waits until the route permanently exits.</summary>
    public async Task<object?> PushAsync<TPage>(object? parameters = null) where TPage : NavigationPage => await Push<TPage>(parameters).Popped;

    /// <summary>Schedules a configured Push and waits until the route permanently exits.</summary>
    public async Task<object?> PushAsync<TPage>(Func<TPage, Task> configure) where TPage : NavigationPage => await Push<TPage>(configure).Popped;

    /// <summary>Pushes, waits for exit, and casts the result.</summary>
    public async Task<TResult?> PushAsync<TPage, TResult>(object? parameters = null) where TPage : NavigationPage => CastResult<TPage, TResult>(await PushAsync<TPage>(parameters));

    /// <summary>Configured Push variant that waits for exit and casts the result.</summary>
    public async Task<TResult?> PushAsync<TPage, TResult>(Func<TPage, Task> configure) where TPage : NavigationPage => CastResult<TPage, TResult>(await PushAsync<TPage>(configure));

    /// <summary>
    /// Schedules a dynamic URI Push with optional route parameters.
    /// Query and Fragment are preserved on NavigationRoute.Uri and excluded from
    /// PageRegistry identity matching.
    /// </summary>
    public NavigationRoute Push(string path, object? parameters = null)
    {
        (Uri uri, string routePath) = ParseNavigationAddress(path);
        PageDefinition definition = PageRegistry.Instance.Resolve(routePath);
        ValidateDefinition(definition);
        var route = new NavigationRoute(definition, parameters, uri);
        _routes.Add(route);
        EnqueueOperation("push", () => ExecutePushAsync(route, null, null, NavigationEnterReason.Push));
        return route;
    }

    /// <summary>Schedules a dynamic configured Push.</summary>
    public NavigationRoute Push(string path, Func<NavigationPage, Task> configure)
    {
        ArgumentNullException.ThrowIfNull(configure);
        (Uri uri, string routePath) = ParseNavigationAddress(path);
        PageDefinition definition = PageRegistry.Instance.Resolve(routePath);
        ValidateDefinition(definition);
        var route = new NavigationRoute(definition, null, uri);
        _routes.Add(route);
        EnqueueOperation("push_configured", () => ExecutePushAsync(route, null, configure, NavigationEnterReason.Push));
        return route;
    }

    /// <summary>Shows a registered page as a Modal route.</summary>
    public NavigationRoute<TPage> ShowModal<TPage>(object? parameters = null) where TPage : NavigationPage
        => PushWithPresentation<TPage>(NavigationPresentation.Modal, parameters, null, "show_modal");

    /// <summary>Shows a configured registered page as a Modal route.</summary>
    public NavigationRoute<TPage> ShowModal<TPage>(Func<TPage, Task> configure) where TPage : NavigationPage
    {
        ArgumentNullException.ThrowIfNull(configure);
        return PushWithPresentation<TPage>(NavigationPresentation.Modal, null, page => configure((TPage)page), "show_modal_configured");
    }

    /// <summary>Shows a dynamic URI as a Modal route.</summary>
    public NavigationRoute ShowModal(string uri, object? parameters = null)
        => PushWithPresentation(uri, NavigationPresentation.Modal, parameters, null, "show_modal");

    /// <summary>Shows a configured dynamic URI as a Modal route.</summary>
    public NavigationRoute ShowModal(string uri, Func<NavigationPage, Task> configure)
    {
        ArgumentNullException.ThrowIfNull(configure);
        return PushWithPresentation(uri, NavigationPresentation.Modal, null, configure, "show_modal_configured");
    }

    /// <summary>Shows a registered page as a non-opaque Overlay route.</summary>
    public NavigationRoute<TPage> ShowOverlay<TPage>(object? parameters = null) where TPage : NavigationPage
        => PushWithPresentation<TPage>(NavigationPresentation.Overlay, parameters, null, "show_overlay");

    /// <summary>Shows a configured registered page as a non-opaque Overlay route.</summary>
    public NavigationRoute<TPage> ShowOverlay<TPage>(Func<TPage, Task> configure) where TPage : NavigationPage
    {
        ArgumentNullException.ThrowIfNull(configure);
        return PushWithPresentation<TPage>(NavigationPresentation.Overlay, null, page => configure((TPage)page), "show_overlay_configured");
    }

    /// <summary>Shows a dynamic URI as a non-opaque Overlay route.</summary>
    public NavigationRoute ShowOverlay(string uri, object? parameters = null)
        => PushWithPresentation(uri, NavigationPresentation.Overlay, parameters, null, "show_overlay");

    /// <summary>Shows a configured dynamic URI as a non-opaque Overlay route.</summary>
    public NavigationRoute ShowOverlay(string uri, Func<NavigationPage, Task> configure)
    {
        ArgumentNullException.ThrowIfNull(configure);
        return PushWithPresentation(uri, NavigationPresentation.Overlay, null, configure, "show_overlay_configured");
    }

    /// <summary>Shows Cherry's built-in DefaultDialog as a Modal route.</summary>
    /// <remarks>
    /// Dialog intentionally supports configured initialization only. Its
    /// PageDefinition/PackedScene is generated in memory and never enters the
    /// user's generated PageRegistry.
    /// </remarks>
    public NavigationRoute<DefaultDialog> ShowDialog(Func<DefaultDialog, Task> configure)
    {
        ArgumentNullException.ThrowIfNull(configure);
        if (_routes.Count == 0)
            throw new InvalidOperationException("ShowDialog requires an existing route beneath the dialog.");
        PageDefinition definition = CreateDefaultDialogDefinition();
        var route = new NavigationRoute<DefaultDialog>(definition, null, null, NavigationPresentation.Modal);
        _routes.Add(route);
        EnqueueOperation("show_dialog", () => ExecutePushAsync(route, typeof(DefaultDialog), page => configure((DefaultDialog)page), NavigationEnterReason.Push));
        return route;
    }

    /// <summary>Shows a registered NavigationDialog subclass as a Modal route.</summary>
    public NavigationRoute<TDialog> ShowDialog<TDialog>(Func<TDialog, Task> configure)
        where TDialog : NavigationDialog
    {
        ArgumentNullException.ThrowIfNull(configure);
        if (_routes.Count == 0)
            throw new InvalidOperationException("ShowDialog requires an existing route beneath the dialog.");
        return PushWithPresentation<TDialog>(NavigationPresentation.Modal, null, page => configure((TDialog)page), "show_dialog");
    }

    /// <summary>Dynamic path Push that waits until the route permanently exits.</summary>
    public async Task<object?> PushAsync(string path, object? parameters = null) => await Push(path, parameters).Popped;

    /// <summary>Dynamic configured Push that waits until the route permanently exits.</summary>
    public async Task<object?> PushAsync(string path, Func<NavigationPage, Task> configure) => await Push(path, configure).Popped;

    /// <summary>Schedules a Push from a pre-resolved PageDefinition.</summary>
    public NavigationRoute PushDefinition(PageDefinition definition, object? parameters = null)
    {
        ValidateDefinition(definition);
        var route = new NavigationRoute(definition, parameters);
        _routes.Add(route);
        EnqueueOperation("push_definition", () => ExecutePushAsync(route, null, null, NavigationEnterReason.Push));
        return route;
    }

    /// <summary>Schedules a configured Push from a pre-resolved PageDefinition.</summary>
    public NavigationRoute PushDefinition(PageDefinition definition, Func<NavigationPage, Task> configure)
    {
        ArgumentNullException.ThrowIfNull(configure);
        ValidateDefinition(definition);
        var route = new NavigationRoute(definition, null);
        _routes.Add(route);
        EnqueueOperation("push_definition_configured", () => ExecutePushAsync(route, null, configure, NavigationEnterReason.Push));
        return route;
    }

    private NavigationRoute<TPage> PushWithPresentation<TPage>(
        NavigationPresentation presentation,
        object? parameters,
        Func<NavigationPage, Task>? configure,
        StringName operationName)
        where TPage : NavigationPage
    {
        PageDefinition definition = PageRegistry.Instance.Resolve<TPage>();
        ValidateDefinition(definition);
        var route = new NavigationRoute<TPage>(definition, parameters, null, presentation);
        _routes.Add(route);
        EnqueueOperation(operationName, () => ExecutePushAsync(route, typeof(TPage), configure, NavigationEnterReason.Push));
        return route;
    }

    private NavigationRoute PushWithPresentation(
        string value,
        NavigationPresentation presentation,
        object? parameters,
        Func<NavigationPage, Task>? configure,
        StringName operationName)
    {
        (Uri uri, string routePath) = ParseNavigationAddress(value);
        PageDefinition definition = PageRegistry.Instance.Resolve(routePath);
        ValidateDefinition(definition);
        var route = new NavigationRoute(definition, parameters, uri, presentation);
        _routes.Add(route);
        EnqueueOperation(operationName, () => ExecutePushAsync(route, null, configure, NavigationEnterReason.Push));
        return route;
    }

    /// <summary>
    /// Schedules Pop for the logical current route.
    /// </summary>
    /// <returns>
    /// True when accepted. The route's Popped Task completes only after Exited and
    /// the revealed page's OnNavigationRevealed have run.
    /// </returns>
    public bool Pop(object? result = null)
    {
        if (!CanPop)
            return false;
        NavigationRoute route = _routes[^1];
        _routes.RemoveAt(_routes.Count - 1);
        EnqueueOperation("pop", () => ExecutePopAsync(route, result, NavigationExitReason.Pop, true));
        return true;
    }

    /// <summary>
    /// Attempts synchronous PopScope-aware back navigation.
    /// </summary>
    /// <remarks>
    /// Pop is always local. MaybePop is the back-policy entry point: after local
    /// PopScopes allow the request, it pops this Navigator when possible;
    /// otherwise it delegates to ParentNavigator.
    ///
    /// A local denying PopScope prevents parent propagation. PopScopes inside
    /// descendant Navigators are not collected here because every nested
    /// Navigator owns its own back-policy boundary.
    ///
    /// Returns false while this Navigator is operating. Async PopScope remains a
    /// later V1 feature.
    /// </remarks>
    public bool MaybePop(object? result = null)
    {
        if (IsOperating)
            return false;

        var scopes = new List<PopScope>();
        if (CurrentRoute?.Page != null)
        {
            CollectPopScopes(CurrentRoute.Page, scopes);
            foreach (PopScope scope in scopes)
            {
                if (scope.CanPop)
                    continue;
                NotifyPopScopes(scopes, false, result);
                return false;
            }
        }

        if (CanPop)
        {
            bool scheduled = Pop(result);
            NotifyPopScopes(scopes, scheduled, result);
            return scheduled;
        }

        Navigator? parent = ParentNavigator;
        bool propagated = parent != null && parent.MaybePop(result);
        NotifyPopScopes(scopes, propagated, result);
        return propagated;
    }

    /// <summary>
    /// Schedules replacement of the logical current route.
    /// </summary>
    /// <remarks>
    /// The old page does not receive OnNavigationCovered. After transition it
    /// receives OnNavigationExited(Replace); the new page then becomes Active and
    /// receives OnNavigationEntered(Replace).
    /// </remarks>
    public NavigationRoute<TPage> Replace<TPage>(object? parameters = null, object? oldResult = null) where TPage : NavigationPage
    {
        PageDefinition definition = PageRegistry.Instance.Resolve<TPage>();
        ValidateDefinition(definition);
        if (_routes.Count == 0)
            return Push<TPage>(parameters);
        NavigationRoute oldRoute = _routes[^1];
        var newRoute = new NavigationRoute<TPage>(definition, parameters);
        _routes[^1] = newRoute;
        EnqueueOperation("replace", () => ExecuteReplaceAsync(oldRoute, newRoute, typeof(TPage), null, oldResult));
        return newRoute;
    }

    /// <summary>
    /// Schedules a type-safe configured Replace.
    /// </summary>
    /// <remarks>
    /// Navigator/Route injection and route-setting snapshot happen before
    /// <paramref name="configure"/>. The callback is awaited before AddChild,
    /// _Ready, transition, and Replace lifecycle commit. This overload
    /// intentionally has no parameters argument.
    ///
    /// The old route remains the committed CurrentRoute while configure runs.
    /// Do not await another operation on this same Navigator inside configure;
    /// it is queued behind this transaction and would deadlock. Scheduling a
    /// non-awaited operation is allowed.
    ///
    /// With an empty logical stack this behaves as configured Push.
    /// </remarks>
    public NavigationRoute<TPage> Replace<TPage>(Func<TPage, Task> configure, object? oldResult = null) where TPage : NavigationPage
    {
        ArgumentNullException.ThrowIfNull(configure);
        PageDefinition definition = PageRegistry.Instance.Resolve<TPage>();
        ValidateDefinition(definition);
        if (_routes.Count == 0)
            return Push<TPage>(configure);
        NavigationRoute oldRoute = _routes[^1];
        var newRoute = new NavigationRoute<TPage>(definition, null);
        _routes[^1] = newRoute;
        EnqueueOperation("replace_configured", () => ExecuteReplaceAsync(oldRoute, newRoute, typeof(TPage), page => configure((TPage)page), oldResult));
        return newRoute;
    }

    /// <summary>Dynamic path Replace.</summary>
    public NavigationRoute Replace(string path, object? parameters = null, object? oldResult = null)
    {
        (Uri uri, string routePath) = ParseNavigationAddress(path);
        PageDefinition definition = PageRegistry.Instance.Resolve(routePath);
        ValidateDefinition(definition);
        if (_routes.Count == 0)
            return Push(path, parameters);
        NavigationRoute oldRoute = _routes[^1];
        var newRoute = new NavigationRoute(definition, parameters, uri);
        _routes[^1] = newRoute;
        EnqueueOperation("replace", () => ExecuteReplaceAsync(oldRoute, newRoute, null, null, oldResult));
        return newRoute;
    }

    /// <summary>
    /// Schedules a dynamic-path configured Replace.
    /// </summary>
    /// <remarks>
    /// Configuration is awaited after Navigator/Route injection and snapshot,
    /// but before AddChild/_Ready and the Replace transition. The configured
    /// overload intentionally has no parameters argument. With an empty stack it
    /// behaves as configured Push.
    /// </remarks>
    public NavigationRoute Replace(string path, Func<NavigationPage, Task> configure, object? oldResult = null)
    {
        ArgumentNullException.ThrowIfNull(configure);
        (Uri uri, string routePath) = ParseNavigationAddress(path);
        PageDefinition definition = PageRegistry.Instance.Resolve(routePath);
        ValidateDefinition(definition);
        if (_routes.Count == 0)
            return Push(path, configure);
        NavigationRoute oldRoute = _routes[^1];
        var newRoute = new NavigationRoute(definition, null, uri);
        _routes[^1] = newRoute;
        EnqueueOperation("replace_configured", () => ExecuteReplaceAsync(oldRoute, newRoute, null, configure, oldResult));
        return newRoute;
    }

    /// <summary>
    /// Schedules a compound PopUntil transaction.
    /// </summary>
    /// <remarks>
    /// Intermediate routes receive OnNavigationExited(Pop), but no intermediate
    /// route receives OnNavigationRevealed. The final target is Revealed once.
    /// </remarks>
    public int PopUntil(Predicate<NavigationRoute> predicate)
    {
        ArgumentNullException.ThrowIfNull(predicate);
        var targets = new List<NavigationRoute>();
        while (_routes.Count > 1 && !predicate(_routes[^1]))
        {
            targets.Add(_routes[^1]);
            _routes.RemoveAt(_routes.Count - 1);
        }
        if (targets.Count > 0)
            EnqueueOperation("pop_until", () => ExecutePopManyAsync(targets));
        return targets.Count;
    }

    /// <summary>Schedules PopUntil by canonical/dynamic path.</summary>
    public int PopTo(string path)
    {
        return TryParseNavigationAddress(path, out _, out string routePath)
            ? PopUntil(route => string.Equals(route.Path, routePath, StringComparison.Ordinal))
            : 0;
    }

    /// <summary>Schedules PopUntil by concrete page type.</summary>
    public int PopTo<TPage>() where TPage : NavigationPage
    {
        PageDefinition target = PageRegistry.Instance.Resolve<TPage>();
        return PopUntil(route => ReferenceEquals(route.Definition, target));
    }

    /// <summary>
    /// Schedules removal of a route. Removing CurrentRoute uses Pop presentation
    /// but exits with NavigationExitReason.Remove.
    /// </summary>
    public bool Remove(NavigationRoute route, object? result = null)
    {
        int index = _routes.IndexOf(route);
        if (index < 0 || (index == _routes.Count - 1 && _routes.Count <= 1))
            return false;
        _routes.RemoveAt(index);
        EnqueueOperation("remove", () => ExecuteRemoveAsync(route, result));
        return true;
    }

    /// <summary>
    /// Schedules structural removal of the entire stack from top to bottom.
    /// Every route receives Exited(Clear); no route receives Revealed.
    /// </summary>
    public int Clear(object? result = null)
    {
        var targets = new List<NavigationRoute>(_routes);
        targets.Reverse();
        _routes.Clear();
        if (targets.Count > 0)
            EnqueueOperation("clear", () => ExecuteClearAsync(targets, result));
        return targets.Count;
    }

    /// <summary>
    /// Parses a public navigation address while keeping PageRegistry concerned
    /// only with stable route identity.
    /// </summary>
    private static (Uri Uri, string RoutePath) ParseNavigationAddress(string value)
    {
        if (!TryParseNavigationAddress(value, out Uri? uri, out string routePath))
            throw new InvalidOperationException($"Unsupported navigation URI: {value}");
        return (uri, routePath);
    }

    private static bool TryParseNavigationAddress(string value, out Uri uri, out string routePath)
    {
        uri = null!;
        routePath = "";
        if (string.IsNullOrWhiteSpace(value))
            return false;

        string raw = value.Trim();
        string canonical = raw;
        if (raw.StartsWith("/", StringComparison.Ordinal))
        {
            string suffix = raw.TrimStart('/');
            canonical = suffix.Length == 0 || suffix[0] is '?' or '#'
                ? "ui:///" + suffix
                : "ui://" + suffix;
        }
        else if (string.Equals(raw, "ui://", StringComparison.Ordinal))
        {
            canonical = "ui:///";
        }
        else if (raw.StartsWith("ui://?", StringComparison.Ordinal) || raw.StartsWith("ui://#", StringComparison.Ordinal))
        {
            canonical = "ui:///" + raw[5..];
        }

        if (!System.Uri.TryCreate(canonical, UriKind.Absolute, out Uri? parsed) ||
            !string.Equals(parsed.Scheme, "ui", StringComparison.OrdinalIgnoreCase))
            return false;

        int queryIndex = canonical.IndexOf('?');
        int fragmentIndex = canonical.IndexOf('#');
        int endIndex = canonical.Length;
        if (queryIndex >= 0)
            endIndex = Math.Min(endIndex, queryIndex);
        if (fragmentIndex >= 0)
            endIndex = Math.Min(endIndex, fragmentIndex);

        string identitySource = canonical[..endIndex];
        routePath = PageRegistry.NormalizePath(identitySource);
        if (routePath.Length == 0)
            return false;

        uri = parsed;
        return true;
    }

    private void EnqueueOperation(StringName name, Func<Task> execute)
    {
        _operationQueue.Enqueue(new QueuedOperation(name, execute));
        OperationQueueChanged?.Invoke(PendingOperationCount);
        if (!_isProcessingOperations)
            _ = DrainOperationQueueAsync();
    }

    private async Task DrainOperationQueueAsync()
    {
        _isProcessingOperations = true;
        OperationQueueChanged?.Invoke(PendingOperationCount);
        while (_operationQueue.Count > 0)
        {
            QueuedOperation operation = _operationQueue.Dequeue();
            _operationRunning = true;
            OperationStarted?.Invoke(operation.Name);
            OperationQueueChanged?.Invoke(PendingOperationCount);
            try
            {
                await operation.Execute();
            }
            catch (Exception exception)
            {
                GD.PushError($"Cherry Navigation operation '{operation.Name}' failed: {exception}");
            }
            _operationRunning = false;
            OperationFinished?.Invoke(operation.Name);
            OperationQueueChanged?.Invoke(PendingOperationCount);
        }
        _isProcessingOperations = false;
        OperationQueueChanged?.Invoke(0);
    }

    private async Task ExecutePushAsync(NavigationRoute route, Type? expectedPageType, Func<NavigationPage, Task>? configure, NavigationEnterReason enterReason)
    {
        NavigationPage? page = null;
        try
        {
            page = PrepareRoute(route, expectedPageType);
            if (configure != null)
                await configure(page);
            await MountPreparedRouteAsync(route, enterReason);
        }
        catch (Exception exception)
        {
            CleanupFailedPush(route, page, exception);
        }
    }

    private async Task ExecuteReplaceAsync(NavigationRoute oldRoute, NavigationRoute newRoute, Type? expectedPageType, Func<NavigationPage, Task>? configure, object? oldResult)
    {
        NavigationPage? newPage = null;
        try
        {
            newPage = PrepareRoute(newRoute, expectedPageType);
            if (configure != null)
                await configure(newPage);
            NavigationRoute? previous = _currentRoute;
            AddRouteVisuals(newRoute);
            oldRoute.State = NavigationRouteState.Popping;
            await RunPushTransitionAsync(newRoute, previous);
            _mountedRoutes.Remove(oldRoute);
            _mountedRoutes.Add(newRoute);
            oldRoute.Page?.RestoreCoveredBehavior();
            RemoveRouteVisuals(oldRoute);
            oldRoute.State = NavigationRouteState.Disposed;
            _currentRoute = null;
            oldRoute.Page?.NotifyNavigationExited(oldResult, NavigationExitReason.Replace);
            newRoute.State = NavigationRouteState.Active;
            _currentRoute = newRoute;
            UpdateRouteVisibility();
            newPage.NotifyNavigationEntered(oldRoute, NavigationEnterReason.Replace);
            newRoute.MarkMounted();
            RoutePushed?.Invoke(newRoute);
            oldRoute.Complete(oldResult);
            oldRoute.Page?.QueueFree();
            RouteReplaced?.Invoke(oldRoute, newRoute);
        }
        catch (Exception exception)
        {
            bool oldRouteStillCommitted = ReferenceEquals(_currentRoute, oldRoute) && _mountedRoutes.Contains(oldRoute) && !_mountedRoutes.Contains(newRoute);
            if (oldRouteStillCommitted)
                RestoreFailedReplaceLogicalRoute(oldRoute, newRoute);
            CleanupFailedPush(newRoute, newPage, exception);
        }
    }

    private void RestoreFailedReplaceLogicalRoute(NavigationRoute oldRoute, NavigationRoute newRoute)
    {
        int index = _routes.IndexOf(newRoute);
        if (index >= 0)
            _routes[index] = oldRoute;
    }

    private async Task ExecutePopAsync(NavigationRoute route, object? result, NavigationExitReason exitReason, bool emitPopEvents)
    {
        int index = _mountedRoutes.IndexOf(route);
        if (index < 0)
            return;
        if (index != _mountedRoutes.Count - 1)
        {
            RemoveCoveredRoute(route, result, exitReason, !emitPopEvents);
            return;
        }
        NavigationRoute? incoming = index > 0 ? _mountedRoutes[index - 1] : null;
        route.State = NavigationRouteState.Popping;
        if (emitPopEvents)
            RoutePopping?.Invoke(route, result);
        PreparePopVisibility(route);
        await RunPopTransitionAsync(route, incoming);
        _mountedRoutes.RemoveAt(_mountedRoutes.Count - 1);
        RemoveRouteVisuals(route);
        route.State = NavigationRouteState.Disposed;
        _currentRoute = null;
        route.Page?.NotifyNavigationExited(result, exitReason);
        if (incoming != null)
        {
            incoming.State = NavigationRouteState.Active;
            _currentRoute = incoming;
            incoming.Page?.RestoreCoveredBehavior();
        }
        UpdateRouteVisibility();
        incoming?.Page?.NotifyNavigationRevealed(route);
        route.Complete(result);
        if (emitPopEvents)
            RoutePopped?.Invoke(route, result);
        route.Page?.QueueFree();
    }

    private async Task ExecutePopManyAsync(IReadOnlyList<NavigationRoute> targets)
    {
        var mountedTargets = new List<NavigationRoute>();
        foreach (NavigationRoute route in targets)
        {
            if (_mountedRoutes.Contains(route))
                mountedTargets.Add(route);
        }
        if (mountedTargets.Count == 0)
            return;
        NavigationRoute bottomTarget = mountedTargets[^1];
        int bottomIndex = _mountedRoutes.IndexOf(bottomTarget);
        NavigationRoute? finalIncoming = bottomIndex > 0 ? _mountedRoutes[bottomIndex - 1] : null;
        NavigationRoute topOutgoing = mountedTargets[0];
        foreach (NavigationRoute route in mountedTargets)
        {
            route.State = NavigationRouteState.Popping;
            RoutePopping?.Invoke(route, null);
        }
        PrepareCompoundPopVisibility(mountedTargets);
        await RunPopTransitionAsync(topOutgoing, finalIncoming);
        _currentRoute = null;
        foreach (NavigationRoute route in mountedTargets)
        {
            _mountedRoutes.Remove(route);
            route.Page?.RestoreCoveredBehavior();
            RemoveRouteVisuals(route);
            route.State = NavigationRouteState.Disposed;
            route.Page?.NotifyNavigationExited(null, NavigationExitReason.Pop);
        }
        if (finalIncoming != null)
        {
            finalIncoming.State = NavigationRouteState.Active;
            _currentRoute = finalIncoming;
            finalIncoming.Page?.RestoreCoveredBehavior();
        }
        UpdateRouteVisibility();
        finalIncoming?.Page?.NotifyNavigationRevealed(bottomTarget);
        foreach (NavigationRoute route in mountedTargets)
        {
            route.Complete(null);
            RoutePopped?.Invoke(route, null);
            route.Page?.QueueFree();
        }
    }

    private async Task ExecuteRemoveAsync(NavigationRoute route, object? result)
    {
        int index = _mountedRoutes.IndexOf(route);
        if (index < 0)
            return;
        if (index == _mountedRoutes.Count - 1 && _mountedRoutes.Count > 1)
        {
            await ExecutePopAsync(route, result, NavigationExitReason.Remove, false);
            RouteRemoved?.Invoke(route);
            return;
        }
        RemoveCoveredRoute(route, result, NavigationExitReason.Remove, true);
    }

    private Task ExecuteClearAsync(IReadOnlyList<NavigationRoute> targets, object? result)
    {
        _currentRoute = null;
        foreach (NavigationRoute route in targets)
        {
            if (!_mountedRoutes.Contains(route))
                continue;
            _mountedRoutes.Remove(route);
            route.State = NavigationRouteState.Popping;
            route.Page?.RestoreCoveredBehavior();
            RemoveRouteVisuals(route);
            route.State = NavigationRouteState.Disposed;
            route.Page?.NotifyNavigationExited(result, NavigationExitReason.Clear);
            route.Complete(result);
            RouteRemoved?.Invoke(route);
            route.Page?.QueueFree();
        }
        return Task.CompletedTask;
    }

    private NavigationPage PrepareRoute(NavigationRoute route, Type? expectedPageType)
    {
        if (route.Navigator != null || route.State != NavigationRouteState.Created)
            throw new InvalidOperationException("A NavigationRoute instance can only be pushed once.");
        Node node = route.Definition.Scene.Instantiate();
        if (node is not NavigationPage page)
        {
            node.Free();
            throw new InvalidOperationException($"Scene root for {route.Definition.Path} must inherit NavigationPage.");
        }
        if (expectedPageType != null && !expectedPageType.IsInstanceOfType(page))
        {
            string actualType = page.GetType().FullName ?? page.GetType().Name;
            page.Free();
            throw new InvalidOperationException($"Registry resolved {route.Definition.Path}, but its root is {actualType}, expected {expectedPageType.FullName}.");
        }
        route.Navigator = this;
        route.Page = page;
        route.State = NavigationRouteState.Pushing;
        page.Navigator = this;
        page.Route = route;
        route.SnapshotPageSettings(page);
        RoutePushing?.Invoke(route);
        return page;
    }

    private async Task MountPreparedRouteAsync(NavigationRoute route, NavigationEnterReason enterReason)
    {
        NavigationRoute? previous = _currentRoute;
        AddRouteVisuals(route);
        await RunPushTransitionAsync(route, previous);
        _mountedRoutes.Add(route);
        if (previous != null)
            previous.State = NavigationRouteState.Covered;
        route.State = NavigationRouteState.Active;
        _currentRoute = route;
        UpdateRouteVisibility();
        if (previous?.Page != null)
        {
            previous.Page.ApplyCoveredBehavior(previous.CoveredBehavior);
            previous.Page.NotifyNavigationCovered(route);
        }
        route.Page!.NotifyNavigationEntered(previous, enterReason);
        route.MarkMounted();
        RoutePushed?.Invoke(route);
    }

    private async Task RunPushTransitionAsync(NavigationRoute route, NavigationRoute? previous)
    {
        NavigationTransition? transition = ResolveTransition(route);
        if (transition == null)
            return;
        IsTransitioning = true;
        try
        {
            await transition.PushAsync(route.Page!, previous?.Page);
        }
        catch (Exception exception)
        {
            GD.PushError($"Cherry Navigation push transition failed for {route.Path}: {exception}");
            TransitionFailed?.Invoke(route, exception);
        }
        finally
        {
            IsTransitioning = false;
        }
    }

    private async Task RunPopTransitionAsync(NavigationRoute route, NavigationRoute? incoming)
    {
        NavigationTransition? transition = ResolveTransition(route);
        if (transition == null)
            return;
        IsTransitioning = true;
        try
        {
            await transition.PopAsync(route.Page!, incoming?.Page);
        }
        catch (Exception exception)
        {
            GD.PushError($"Cherry Navigation pop transition failed for {route.Path}: {exception}");
            TransitionFailed?.Invoke(route, exception);
        }
        finally
        {
            IsTransitioning = false;
        }
    }

    private NavigationTransition? ResolveTransition(NavigationRoute route) => route.Transition ?? DefaultTransition;

    private static PageDefinition CreateDefaultDialogDefinition()
    {
        var dialog = new DefaultDialog();
        var scene = new PackedScene();
        Error result = scene.Pack(dialog);
        dialog.Free();
        if (result != Error.Ok)
            throw new InvalidOperationException("Unable to create Cherry DefaultDialog PackedScene.");
        return new PageDefinition
        {
            Path = "ui://cherry/default-dialog",
            Scene = scene,
        };
    }

    private void AddRouteVisuals(NavigationRoute route)
    {
        if (route.Presentation == NavigationPresentation.Modal)
        {
            var scrim = new ColorRect
            {
                Name = "ModalScrim",
                Color = new Color(0.0f, 0.0f, 0.0f, 0.45f),
                MouseFilter = Control.MouseFilterEnum.Stop,
            };
            scrim.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
            route.PresentationScrim = scrim;
            AddChild(scrim);
        }
        AddChild(route.Page!);
    }

    private void RemoveRouteVisuals(NavigationRoute route)
    {
        if (route.Page != null && ReferenceEquals(route.Page.GetParent(), this))
            RemoveChild(route.Page);
        if (route.PresentationScrim != null && GodotObject.IsInstanceValid(route.PresentationScrim))
        {
            if (ReferenceEquals(route.PresentationScrim.GetParent(), this))
                RemoveChild(route.PresentationScrim);
            route.PresentationScrim.QueueFree();
            route.PresentationScrim = null;
        }
    }

    private static void SetRouteVisualVisibility(NavigationRoute route, bool visible)
    {
        if (route.Page != null)
            route.Page.Visible = visible;
        if (route.PresentationScrim != null && GodotObject.IsInstanceValid(route.PresentationScrim))
            route.PresentationScrim.Visible = visible;
    }

    /// <summary>
    /// Recomputes visibility for the complete committed mounted stack.
    /// </summary>
    /// <remarks>
    /// Walking from top to bottom, pages stay visible until the first visible
    /// opaque route is encountered. Opaque affects presentation only and never
    /// changes CoveredBehavior.
    /// </remarks>
    private void UpdateRouteVisibility()
    {
        bool obscured = false;
        for (int index = _mountedRoutes.Count - 1; index >= 0; index--)
        {
            NavigationRoute route = _mountedRoutes[index];
            SetRouteVisualVisibility(route, !obscured);
            if (!obscured && route.Opaque)
                obscured = true;
        }
    }

    /// <summary>
    /// Prepares the visual stack underneath an outgoing route for its Pop
    /// transition without restoring CoveredBehavior before commit.
    /// </summary>
    private void PreparePopVisibility(NavigationRoute outgoing)
    {
        int outgoingIndex = _mountedRoutes.IndexOf(outgoing);
        if (outgoingIndex < 0)
            return;

        bool obscured = false;
        for (int index = outgoingIndex - 1; index >= 0; index--)
        {
            NavigationRoute route = _mountedRoutes[index];
            SetRouteVisualVisibility(route, !obscured);
            if (!obscured && route.Opaque)
                obscured = true;
        }

        SetRouteVisualVisibility(outgoing, true);
    }

    /// <summary>
    /// Prepares visibility for a compound PopUntil/PopTo transaction while all
    /// covered pages remain process/input-suspended until commit.
    /// </summary>
    private void PrepareCompoundPopVisibility(IReadOnlyList<NavigationRoute> targets)
    {
        if (targets.Count == 0)
            return;

        int bottomIndex = _mountedRoutes.IndexOf(targets[^1]);
        if (bottomIndex < 0)
            return;

        bool obscured = false;
        for (int index = bottomIndex - 1; index >= 0; index--)
        {
            NavigationRoute route = _mountedRoutes[index];
            SetRouteVisualVisibility(route, !obscured);
            if (!obscured && route.Opaque)
                obscured = true;
        }

        foreach (NavigationRoute target in targets)
            SetRouteVisualVisibility(target, ReferenceEquals(target, targets[0]));
    }

    private void CleanupFailedPush(NavigationRoute route, NavigationPage? page, Exception exception)
    {
        _routes.Remove(route);
        _mountedRoutes.Remove(route);
        if (page != null && GodotObject.IsInstanceValid(page))
        {
            page.RestoreCoveredBehavior();
            RemoveRouteVisuals(route);
            page.QueueFree();
        }
        if (ReferenceEquals(_currentRoute, route))
            _currentRoute = null;
        route.Fail(exception);
        RouteFailed?.Invoke(route, exception);
        UpdateRouteVisibility();
    }

    private bool RemoveCoveredRoute(NavigationRoute route, object? result, NavigationExitReason exitReason, bool emitRemoved)
    {
        int index = _mountedRoutes.IndexOf(route);
        if (index < 0)
            return false;
        _mountedRoutes.RemoveAt(index);
        route.State = NavigationRouteState.Popping;
        route.Page?.RestoreCoveredBehavior();
        RemoveRouteVisuals(route);
        route.State = NavigationRouteState.Disposed;
        route.Page?.NotifyNavigationExited(result, exitReason);
        route.Complete(result);
        if (emitRemoved)
            RouteRemoved?.Invoke(route);
        route.Page?.QueueFree();
        UpdateRouteVisibility();
        return true;
    }

    private static void ValidateDefinition(PageDefinition definition)
    {
        ArgumentNullException.ThrowIfNull(definition);
        if (definition.Scene == null)
            throw new InvalidOperationException($"Page {definition.Path} has no PackedScene.");
    }

    private static TResult? CastResult<TPage, TResult>(object? result) where TPage : NavigationPage
    {
        if (result is null)
            return default;
        if (result is TResult typed)
            return typed;
        throw new InvalidCastException($"Page {typeof(TPage).Name} returned {result.GetType().FullName}, which cannot be cast to {typeof(TResult).FullName}.");
    }

    /// <summary>
    /// Collects only PopScopes owned by this Navigator's current page.
    /// Descendant Navigator subtrees are separate back-policy domains.
    /// </summary>
    private void CollectPopScopes(Node node, List<PopScope> output)
    {
        if (node is Navigator navigator && !ReferenceEquals(navigator, this))
            return;
        if (node is PopScope scope)
            output.Add(scope);
        foreach (Node child in node.GetChildren())
            CollectPopScopes(child, output);
    }

    private static void NotifyPopScopes(IEnumerable<PopScope> scopes, bool didPop, object? result)
    {
        foreach (PopScope scope in scopes)
            scope.Notify(didPop, result);
    }

    private Navigator? FindAncestorNavigator()
    {
        Node? cursor = GetParent();
        while (cursor != null)
        {
            if (cursor is Navigator navigator)
                return navigator;
            cursor = cursor.GetParent();
        }
        return null;
    }

    private bool WouldCreateParentCycle(Navigator? candidate)
    {
        var visited = new HashSet<ulong>();
        Navigator? cursor = candidate;
        while (cursor != null && GodotObject.IsInstanceValid(cursor))
        {
            if (ReferenceEquals(cursor, this))
                return true;
            ulong id = cursor.GetInstanceId();
            if (!visited.Add(id))
                return true;
            cursor = cursor.ParentNavigator;
        }
        return false;
    }
}
