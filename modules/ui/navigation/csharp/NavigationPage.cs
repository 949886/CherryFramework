using Godot;
using System.Collections.Generic;

/// <summary>Route presentation used when a page becomes current.</summary>
/// <remarks>
/// Dialog is intentionally not a presentation kind. NavigationDialog is a
/// specialized Modal page contract.
/// </remarks>
public enum NavigationPresentation
{
    /// <summary>Ordinary page navigation.</summary>
    Page,
    /// <summary>Non-opaque route with a blocking modal scrim.</summary>
    Modal,
    /// <summary>Non-opaque route without a scrim.</summary>
    Overlay,
}

/// <summary>
/// Processing policy applied to a page while another route is the committed
/// current route above it.
/// </summary>
/// <remarks>
/// Covered routes never own navigation-layer input in V1. This policy controls
/// only whether processing is suspended or allowed to continue and is
/// independent from NavigationPage.Opaque.
/// </remarks>
public enum CoveredBehavior
{
    /// <summary>
    /// Stops processing and blocks page input while covered. Cherry preserves
    /// the page instance and restores its original settings when revealed.
    /// </summary>
    Suspend,

    /// <summary>
    /// Keeps processing/physics running while blocking page input and Control
    /// interaction.
    /// </summary>
    Process,
}

/// <summary>Reason supplied to NavigationPage.OnNavigationEntered.</summary>
public enum NavigationEnterReason
{
    /// <summary>The route became current through a normal Push.</summary>
    Push,
    /// <summary>The route became current by replacing the previous route.</summary>
    Replace,
}

/// <summary>Reason supplied to NavigationPage.OnNavigationExited.</summary>
public enum NavigationExitReason
{
    /// <summary>The route permanently left through Pop.</summary>
    Pop,
    /// <summary>The route permanently left because it was replaced.</summary>
    Replace,
    /// <summary>The route was explicitly removed.</summary>
    Remove,
    /// <summary>The route left because Navigator.Clear removed the stack.</summary>
    Clear,
}

/// <summary>Base Control for a scene that can be mounted by Cherry Navigation.</summary>
public abstract partial class NavigationPage : Control
{
    private sealed class CoveredNodeState
    {
        public Node Node { get; }
        public Node.ProcessModeEnum ProcessMode { get; }
        public bool ProcessInput { get; }
        public bool ShortcutInput { get; }
        public bool UnhandledInput { get; }
        public bool UnhandledKeyInput { get; }
        public Control.MouseFilterEnum? MouseFilter { get; }
        public Control.FocusModeEnum? FocusMode { get; }

        public CoveredNodeState(Node node)
        {
            Node = node;
            ProcessMode = node.ProcessMode;
            ProcessInput = node.IsProcessingInput();
            ShortcutInput = node.IsProcessingShortcutInput();
            UnhandledInput = node.IsProcessingUnhandledInput();
            UnhandledKeyInput = node.IsProcessingUnhandledKeyInput();
            if (node is Control control)
            {
                MouseFilter = control.MouseFilter;
                FocusMode = control.FocusMode;
            }
        }
    }

    private readonly Dictionary<ulong, CoveredNodeState> _coveredNodeStates = new();
    private bool _coveredPolicyActive;
    private CoveredBehavior _coveredPolicy = global::CoveredBehavior.Suspend;
    private string? _coveredFocusPath;

    /// <summary>Public navigation identity serialized on the scene root.</summary>
    /// <remarks>
    /// Both <c>/settings</c> and <c>ui://settings</c> are accepted by the editor
    /// generator. The generated registry stores the canonical <c>ui://...</c>
    /// representation.
    /// </remarks>
    [Export]
    public string NavigationPath { get; set; } = "";

    /// <summary>Scene-authored route presentation.</summary>
    /// <remarks>
    /// Navigator snapshots this before configured initialization. Non-Page
    /// presentations are normalized to non-opaque composition. ShowModal and
    /// ShowOverlay can override this for one route without mutating the page.
    /// </remarks>
    [Export]
    public NavigationPresentation Presentation { get; set; } = NavigationPresentation.Page;

    /// <summary>
    /// Scene-authored default controlling whether this page visually obscures
    /// routes below it when current.
    /// </summary>
    /// <remarks>
    /// Opaque controls visibility only. Navigator snapshots this value into the
    /// route before configured initialization. Changing it afterwards does not
    /// implicitly mutate the existing route snapshot.
    /// </remarks>
    [Export]
    public bool Opaque { get; set; } = true;

    /// <summary>Scene-authored processing policy used when this page becomes Covered.</summary>
    /// <remarks>
    /// Navigator snapshots this value into the route before configured
    /// initialization. Covered routes always have input blocked; this value only
    /// decides whether processing is suspended or continues.
    /// </remarks>
    [Export]
    public CoveredBehavior CoveredBehavior { get; set; } = global::CoveredBehavior.Suspend;

    /// <summary>Optional scene-authored presentation transition for this page.</summary>
    /// <remarks>
    /// Navigator snapshots this reference into the route before configured
    /// initialization. A null value falls back to Navigator.DefaultTransition.
    /// </remarks>
    [Export]
    public NavigationTransition? Transition { get; set; }

    /// <summary>
    /// Navigator that instantiated this page. Cherry injects it before configured
    /// initialization and before the page enters the SceneTree.
    /// </summary>
    public Navigator Navigator { get; internal set; } = null!;

    /// <summary>
    /// Runtime route associated with this concrete page instance. Cherry injects
    /// it before configured initialization and before <see cref="_Ready"/>.
    /// </summary>
    public NavigationRoute Route { get; internal set; } = null!;

    /// <summary>
    /// Optional payload supplied by the parameter-based Push API. Configured Push
    /// overloads intentionally expose <c>null</c>.
    /// </summary>
    public object? Parameters => Route?.Parameters;

    /// <summary>
    /// Static registry lookup definition used to instantiate this page.
    /// PageDefinition contains only Path and Scene; effective presentation
    /// settings for this navigation entry live on Route.
    /// </summary>
    public PageDefinition Definition => Route.Definition;

    /// <summary>
    /// Called once when this route first becomes the committed current route.
    /// </summary>
    /// <param name="previousRoute">Previous current route, or null for the first route.</param>
    /// <param name="reason">Whether this route entered through Push or Replace.</param>
    /// <remarks>
    /// This runs after <see cref="_Ready"/> and after the Push transition.
    /// At callback time Route.State is Active, Navigator.CurrentRoute equals
    /// Route, and this page is inside the SceneTree. This is a synchronous
    /// notification; Navigator does not await work started from this callback.
    /// </remarks>
    protected virtual void OnNavigationEntered(NavigationRoute? previousRoute, NavigationEnterReason reason)
    {
    }

    /// <summary>Called when another route becomes current above this route.</summary>
    /// <param name="nextRoute">The newly active route covering this page.</param>
    /// <remarks>
    /// Covered is a navigation concept rather than a visibility concept. This is
    /// called even when nextRoute is non-opaque and this page remains visible.
    /// The page's CoveredBehavior has already been applied before this callback.
    /// At callback time Route.State is Covered and Navigator.CurrentRoute is
    /// nextRoute. This callback is synchronous and is never awaited.
    /// </remarks>
    protected virtual void OnNavigationCovered(NavigationRoute nextRoute)
    {
    }

    /// <summary>
    /// Called when routes above this route leave and this route becomes current again.
    /// </summary>
    /// <param name="removedRoute">
    /// Route that directly covered this route. Compound PopUntil/PopTo transactions
    /// invoke Revealed only once on the final target.
    /// </param>
    /// <remarks>
    /// This runs after the Pop transition, after the outgoing page leaves the
    /// SceneTree, and after the page's original process/input/focus state has been
    /// restored. At callback time Route.State is Active, Navigator.CurrentRoute
    /// equals Route, and this page is inside the SceneTree.
    /// </remarks>
    protected virtual void OnNavigationRevealed(NavigationRoute removedRoute)
    {
    }

    /// <summary>Called exactly once when this route permanently leaves its Navigator.</summary>
    /// <param name="result">Value used to complete NavigationRoute.Popped.</param>
    /// <param name="reason">Pop, Replace, Remove, or Clear.</param>
    /// <remarks>
    /// This runs after the page has been removed from the SceneTree and after the
    /// route becomes Disposed, but before the page is queued for freeing.
    /// Navigator.CurrentRoute does not equal this route and this page's
    /// IsInsideTree() is false. This callback is synchronous and is never awaited.
    /// </remarks>
    protected virtual void OnNavigationExited(object? result, NavigationExitReason reason)
    {
    }

    internal void NotifyNavigationEntered(NavigationRoute? previousRoute, NavigationEnterReason reason) => OnNavigationEntered(previousRoute, reason);
    internal void NotifyNavigationCovered(NavigationRoute nextRoute) => OnNavigationCovered(nextRoute);
    internal void NotifyNavigationRevealed(NavigationRoute removedRoute) => OnNavigationRevealed(removedRoute);
    internal void NotifyNavigationExited(object? result, NavigationExitReason reason) => OnNavigationExited(result, reason);


    /// <summary>
    /// Applies <paramref name="behavior"/> while this page is Covered without
    /// destroying the page instance.
    /// </summary>
    /// <remarks>
    /// Cherry snapshots every Node/Control setting it changes. Suspend disables
    /// processing and input; Process preserves authored processing while disabling
    /// input. Dynamically added children receive the active policy automatically.
    /// </remarks>
    internal void ApplyCoveredBehavior(CoveredBehavior behavior)
    {
        RestoreCoveredBehavior();
        _coveredPolicy = behavior;
        _coveredPolicyActive = true;
        Control? focusOwner = GetViewport().GuiGetFocusOwner();
        if (focusOwner != null && (ReferenceEquals(focusOwner, this) || IsAncestorOf(focusOwner)))
        {
            _coveredFocusPath = GetPathTo(focusOwner).ToString();
            focusOwner.ReleaseFocus();
        }
        CaptureCoveredSubtree(this);
    }

    /// <summary>
    /// Restores the exact process/input/mouse/focus state saved by
    /// <see cref="ApplyCoveredBehavior"/>.
    /// </summary>
    internal void RestoreCoveredBehavior()
    {
        if (!_coveredPolicyActive)
            return;

        foreach (CoveredNodeState state in _coveredNodeStates.Values)
        {
            if (GodotObject.IsInstanceValid(state.Node))
                state.Node.ChildEnteredTree -= OnCoveredChildEnteredTree;
        }

        foreach (CoveredNodeState state in _coveredNodeStates.Values)
        {
            if (!GodotObject.IsInstanceValid(state.Node))
                continue;

            Node node = state.Node;
            node.ProcessMode = state.ProcessMode;
            node.SetProcessInput(state.ProcessInput);
            node.SetProcessShortcutInput(state.ShortcutInput);
            node.SetProcessUnhandledInput(state.UnhandledInput);
            node.SetProcessUnhandledKeyInput(state.UnhandledKeyInput);

            if (node is Control control)
            {
                control.MouseFilter = state.MouseFilter!.Value;
                control.FocusMode = state.FocusMode!.Value;
            }
        }

        string? focusPath = _coveredFocusPath;
        _coveredNodeStates.Clear();
        _coveredFocusPath = null;
        _coveredPolicyActive = false;
        _coveredPolicy = global::CoveredBehavior.Suspend;

        if (!string.IsNullOrEmpty(focusPath))
        {
            Control? focusOwner = GetNodeOrNull<Control>(new NodePath(focusPath));
            if (focusOwner != null && focusOwner.IsInsideTree())
                focusOwner.GrabFocus();
        }
    }

    private void CaptureCoveredSubtree(Node node)
    {
        ulong instanceId = node.GetInstanceId();
        if (_coveredNodeStates.ContainsKey(instanceId))
            return;

        _coveredNodeStates.Add(instanceId, new CoveredNodeState(node));
        node.ChildEnteredTree += OnCoveredChildEnteredTree;

        if (_coveredPolicy == global::CoveredBehavior.Suspend)
            node.ProcessMode = Node.ProcessModeEnum.Disabled;

        node.SetProcessInput(false);
        node.SetProcessShortcutInput(false);
        node.SetProcessUnhandledInput(false);
        node.SetProcessUnhandledKeyInput(false);

        if (node is Control control)
        {
            control.MouseFilter = Control.MouseFilterEnum.Ignore;
            control.FocusMode = Control.FocusModeEnum.None;
        }

        foreach (Node child in node.GetChildren())
            CaptureCoveredSubtree(child);
    }

    private void OnCoveredChildEnteredTree(Node child)
    {
        if (_coveredPolicyActive)
            CaptureCoveredSubtree(child);
    }

}
