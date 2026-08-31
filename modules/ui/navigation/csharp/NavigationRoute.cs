using Godot;
using System;
using System.Threading.Tasks;

/// <summary>Describes the lifecycle of one runtime navigation stack entry.</summary>
public enum NavigationRouteState
{
    /// <summary>The route exists but page mounting has not started.</summary>
    Created,
    /// <summary>The page is being instantiated, configured, or mounted.</summary>
    Pushing,
    /// <summary>The route is the current active route.</summary>
    Active,
    /// <summary>The route remains in the stack underneath another route.</summary>
    Covered,
    /// <summary>The route is leaving the stack.</summary>
    Popping,
    /// <summary>The route completed normally and is no longer active.</summary>
    Disposed,
    /// <summary>The route failed before it could become active.</summary>
    Failed,
}

/// <summary>
/// Represents one concrete runtime navigation operation.
/// </summary>
/// <remarks>
/// Routes are pure CLR navigation state and intentionally do not derive from
/// <c>GodotObject</c>. A route owns the eventual mounted and popped tasks for
/// its page instance.
/// </remarks>
public class NavigationRoute
{
    private readonly TaskCompletionSource<bool> _mounted = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly TaskCompletionSource<object?> _popped = new(TaskCreationOptions.RunContinuationsAsynchronously);

    /// <summary>
    /// Static registry definition used to create this route. Definition.Path is
    /// the stable page identity and never contains query or fragment data.
    /// </summary>
    public PageDefinition Definition { get; internal set; }

    /// <summary>
    /// Concrete URI used for this navigation entry.
    /// </summary>
    /// <remarks>
    /// This is the standard <see cref="System.Uri"/> type. Unlike <see cref="Path"/>,
    /// it preserves the request's Query and Fragment.
    /// </remarks>
    public Uri Uri { get; internal set; }

    /// <summary>
    /// Optional route-level payload supplied by parameter-based Push/Replace.
    /// Configured Push/Replace overloads intentionally set this value to <c>null</c>.
    /// </summary>
    public object? Parameters { get; internal set; }

    /// <summary>Navigator that owns this route.</summary>
    public Navigator Navigator { get; internal set; } = null!;

    /// <summary>
    /// Instantiated page for this route. Configured push overloads assign this
    /// before invoking their configuration callback.
    /// </summary>
    public NavigationPage? Page { get; internal set; }

    /// <summary>
    /// Effective presentation for this concrete route. ShowModal/ShowOverlay may
    /// supply a one-route override without changing NavigationPage.Presentation.
    /// </summary>
    public NavigationPresentation Presentation { get; internal set; } = NavigationPresentation.Page;

    /// <summary>
    /// Effective visibility policy snapshotted from NavigationPage.Opaque before
    /// configured initialization.
    /// </summary>
    public bool Opaque { get; internal set; } = true;

    /// <summary>
    /// Effective Covered policy snapshotted from NavigationPage.CoveredBehavior
    /// before configured initialization.
    /// </summary>
    public CoveredBehavior CoveredBehavior { get; internal set; } = global::CoveredBehavior.Suspend;

    /// <summary>
    /// Effective presentation transition snapshotted from NavigationPage.Transition
    /// before configured initialization. Null uses Navigator.DefaultTransition.
    /// </summary>
    public NavigationTransition? Transition { get; internal set; }

    internal NavigationPresentation? PresentationOverride { get; }
    internal Control? PresentationScrim { get; set; }

    /// <summary>Current route lifecycle state.</summary>
    public NavigationRouteState State { get; internal set; } = NavigationRouteState.Created;

    /// <summary>Canonical <c>ui://...</c> route path.</summary>
    public string Path => Definition.Path;

    /// <summary>Whether this route is the committed navigation-current route.</summary>
    public bool IsCurrent => Navigator != null && ReferenceEquals(Navigator.CurrentRoute, this);

    /// <summary>Whether this route is the first route in its Navigator stack.</summary>
    public bool IsFirst => Navigator != null && ReferenceEquals(Navigator.FirstRoute, this);

    /// <summary>Whether this route still represents a usable navigation operation.</summary>
    public bool IsActive => State is not NavigationRouteState.Disposed and not NavigationRouteState.Failed;

    /// <summary>
    /// Completes after the page has entered the scene tree and become active.
    /// For configured Push/Replace this does not complete until the configuration
    /// callback has completed successfully.
    /// </summary>
    public Task Mounted => _mounted.Task;

    /// <summary>
    /// Completes with the result supplied when this route leaves the stack.
    /// If configured mounting fails, this task faults with the same exception.
    /// </summary>
    public Task<object?> Popped => _popped.Task;

    internal NavigationRoute(
        PageDefinition definition,
        object? parameters,
        Uri? uri = null,
        NavigationPresentation? presentationOverride = null)
    {
        Definition = definition;
        Parameters = parameters;
        Uri = uri ?? CreateDefinitionUri(definition);
        PresentationOverride = presentationOverride;
    }

    private static Uri CreateDefinitionUri(PageDefinition definition)
    {
        string value = definition.Path == "ui://" ? "ui:///" : definition.Path;
        return new Uri(value, UriKind.Absolute);
    }

    internal void SnapshotPageSettings(NavigationPage page)
    {
        Presentation = PresentationOverride ?? page.Presentation;
        Opaque = Presentation == NavigationPresentation.Page ? page.Opaque : false;
        CoveredBehavior = page.CoveredBehavior;
        Transition = page.Transition;
    }

    internal void MarkMounted() => _mounted.TrySetResult(true);
    internal void Complete(object? result) => _popped.TrySetResult(result);

    internal void Fail(Exception exception)
    {
        State = NavigationRouteState.Failed;
        _mounted.TrySetException(exception);
        _popped.TrySetException(exception);
    }
}

/// <summary>
/// Strongly typed route handle whose <see cref="Page"/> is known at compile time.
/// </summary>
/// <typeparam name="TPage">Concrete registered NavigationPage type.</typeparam>
public sealed class NavigationRoute<TPage> : NavigationRoute where TPage : NavigationPage
{
    /// <summary>Typed view of the instantiated route page.</summary>
    public new TPage? Page => (TPage?)base.Page;

    internal NavigationRoute(
        PageDefinition definition,
        object? parameters,
        Uri? uri = null,
        NavigationPresentation? presentationOverride = null)
        : base(definition, parameters, uri, presentationOverride)
    {
    }
}
