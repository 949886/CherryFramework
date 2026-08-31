class_name NavigationPage
extends Control

## Route presentation used when this page becomes current.
##
## PAGE is ordinary full-page navigation. MODAL keeps lower routes visually
## composited and adds a blocking scrim. OVERLAY keeps lower routes visually
## composited without a scrim. Dialog is intentionally not a presentation kind;
## [NavigationDialog] is a specialized Modal page contract.
enum Presentation {
    PAGE,
    MODAL,
    OVERLAY,
}

## Processing policy applied to this page while another route is the committed
## current route above it.
##
## Covered routes never own navigation-layer input in V1. This policy controls
## only whether processing is suspended or allowed to continue. It is
## independent from [member opaque].
enum CoveredBehavior {
    ## Stops processing and blocks page input while covered.
    ##
    ## Cherry preserves the page instance and snapshots/restores the affected
    ## Node and Control settings when the page is revealed.
    SUSPEND,

    ## Keeps processing and physics processing running, but blocks page input
    ## and Control interaction while covered.
    PROCESS,
}

## Reason supplied to [method on_navigation_entered].
enum EnterReason {
    ## The route was added by a normal Push operation.
    PUSH,
    ## The route became current by replacing the previous route.
    REPLACE,
}

## Reason supplied to [method on_navigation_exited].
enum ExitReason {
    ## The route permanently left because it was popped.
    POP,
    ## The route permanently left because another route replaced it.
    REPLACE,
    ## The route was explicitly removed from the Navigator.
    REMOVE,
    ## The route left because Navigator.clear() removed the stack.
    CLEAR,
}

## Navigation identity serialized on the root of a navigable scene.
##
## Both [code]/settings[/code] and [code]ui://settings[/code] are accepted by
## the registry generator. The generated registry stores the canonical
## [code]ui://...[/code] form.
@export var navigation_path: String = ""

## Scene-authored route presentation.
##
## Navigator snapshots this before configured initialization. Non-PAGE
## presentations are normalized to non-opaque composition for the concrete
## route. ShowModal/ShowOverlay may override this value for one route without
## mutating the page instance.
@export var presentation: Presentation = Presentation.PAGE

## Scene-authored default controlling whether this page visually obscures all
## routes below it when current.
##
## Opaque controls visibility only. Navigator snapshots this value into the
## route before configured initialization. Changing this property afterwards
## does not implicitly mutate the existing route snapshot.
@export var opaque: bool = true

## Scene-authored processing policy used when this page later becomes Covered.
##
## Navigator snapshots this value into the route before configured
## initialization. Covered routes always have input blocked; this value only
## decides whether processing is suspended or continues.
@export var covered_behavior: CoveredBehavior = CoveredBehavior.SUSPEND

## Optional scene-authored presentation transition for this page.
##
## Navigator snapshots this reference into the route before configured
## initialization. When null, [member Navigator.default_transition] is used.
@export var transition: NavigationTransition

## Navigator that instantiated this page.
##
## Cherry injects this before configured initialization and before the page
## enters the SceneTree.
var navigator: Navigator

## Runtime route associated with this concrete page instance.
##
## Cherry injects it before configured initialization and before _ready().
var route: NavigationRoute

## Optional payload supplied by the parameter-based Push API.
##
## Configured Push APIs intentionally leave this value null.
var parameters: Variant:
    get:
        return route.parameters if route != null else null

## Static registry lookup definition used to instantiate this page.
##
## PageDefinition contains only Path and Scene. Effective presentation settings
## for this concrete navigation entry are available from [member route].
var definition: PageDefinition:
    get:
        return route.definition if route != null else null

# CoveredBehavior temporarily overrides Node/Control state without changing the
# user's authored values. These values are internal implementation details and
# are deliberately separate from NavigationRoute.State.
var _covered_policy_active := false
var _covered_policy: CoveredBehavior = CoveredBehavior.SUSPEND
var _covered_node_states: Array[Dictionary] = []
var _covered_focus_path := ""

## Called once when this route first becomes the committed current route.
##
## This callback runs after _ready() and after the Push transition completes.
## At callback time:
## - route.state == NavigationRoute.State.ACTIVE
## - navigator.current_route == route
## - the page is inside the SceneTree
##
## [param previous_route] is null for the first route in a Navigator.
## [param reason] distinguishes a normal Push from Replace.
##
## This is a synchronous notification. Navigator never awaits work started from
## this method.
func on_navigation_entered(_previous_route: NavigationRoute, _reason: EnterReason) -> void:
    pass

## Called when another route becomes current above this route.
##
## This callback runs after the incoming Push transition completes and after
## this page's [member PageDefinition.covered_behavior] has been applied.
## Covered is a navigation concept, not a visibility concept: this callback also
## runs when the incoming page has opaque == false and this page remains visible.
##
## At callback time:
## - route.state == NavigationRoute.State.COVERED
## - navigator.current_route != route
## - [param next_route] is ACTIVE and is the committed current route
##
## This is a synchronous notification and is not awaited by Navigator.
func on_navigation_covered(_next_route: NavigationRoute) -> void:
    pass

## Called when routes above this route leave and this route becomes current again.
##
## This callback runs after the Pop transition, after the outgoing page has
## left the SceneTree, and after this page's original process/input/focus state
## has been restored.
##
## At callback time:
## - route.state == NavigationRoute.State.ACTIVE
## - navigator.current_route == route
## - the page is inside the SceneTree
##
## [param removed_route] is the route that directly covered this route. For a
## compound pop_until/pop_to transaction, intermediate routes do not receive
## Revealed and the final target receives this callback exactly once.
##
## This is a synchronous notification and is not awaited by Navigator.
func on_navigation_revealed(_removed_route: NavigationRoute) -> void:
    pass

## Called exactly once when this route permanently leaves its Navigator.
##
## This callback runs after the page has been removed from the SceneTree and
## after route.state becomes DISPOSED, but before the page is queued for freeing.
##
## At callback time:
## - route.state == NavigationRoute.State.DISPOSED
## - navigator.current_route != route
## - route is absent from navigator.scheduled_routes()
## - is_inside_tree() == false
##
## [param result] is the value used to complete route.popped.
## [param reason] identifies Pop, Replace, Remove, or Clear.
##
## This is a synchronous notification and is not awaited by Navigator.
func on_navigation_exited(_result: Variant, _reason: ExitReason) -> void:
    pass

func _notify_navigation_entered(previous_route: NavigationRoute, reason: EnterReason) -> void:
    on_navigation_entered(previous_route, reason)

func _notify_navigation_covered(next_route: NavigationRoute) -> void:
    on_navigation_covered(next_route)

func _notify_navigation_revealed(removed_route: NavigationRoute) -> void:
    on_navigation_revealed(removed_route)

func _notify_navigation_exited(result: Variant, reason: ExitReason) -> void:
    on_navigation_exited(result, reason)

## Applies [param behavior] while this page is Covered without destroying the
## page instance.
##
## Cherry snapshots every Node/Control setting it changes and restores the exact
## original values in [_restore_covered_behavior]. For [code]PROCESS[/code],
## processing is left untouched while all page input is blocked. For
## [code]SUSPEND[/code], processing is disabled in addition to input blocking.
##
## Nodes dynamically added to the page while it is Covered inherit the active
## policy and are restored with the rest of the subtree.
func _apply_covered_behavior(behavior: CoveredBehavior) -> void:
    _restore_covered_behavior()
    _covered_policy = behavior
    _covered_policy_active = true
    var focus_owner := get_viewport().gui_get_focus_owner()
    if focus_owner != null and (focus_owner == self or is_ancestor_of(focus_owner)):
        _covered_focus_path = str(get_path_to(focus_owner))
        focus_owner.release_focus()
    _capture_covered_subtree(self)

## Restores process/input/mouse/focus state previously changed by
## [_apply_covered_behavior].
##
## If a Control inside this page owned keyboard focus before it was covered and
## still exists when revealed, Cherry restores that focus after restoring the
## subtree's original properties.
func _restore_covered_behavior() -> void:
    if not _covered_policy_active:
        return
    for state: Dictionary in _covered_node_states:
        var node := state["node"] as Node
        if is_instance_valid(node) and node.child_entered_tree.is_connected(_on_covered_child_entered_tree):
            node.child_entered_tree.disconnect(_on_covered_child_entered_tree)
    for state: Dictionary in _covered_node_states:
        var node := state["node"] as Node
        if not is_instance_valid(node):
            continue
        node.process_mode = int(state["process_mode"])
        node.set_process_input(bool(state["process_input"]))
        node.set_process_shortcut_input(bool(state["shortcut_input"]))
        node.set_process_unhandled_input(bool(state["unhandled_input"]))
        node.set_process_unhandled_key_input(bool(state["unhandled_key_input"]))
        if node is Control:
            var control := node as Control
            control.mouse_filter = int(state["mouse_filter"])
            control.focus_mode = int(state["focus_mode"])
    var focus_path := _covered_focus_path
    _covered_node_states.clear()
    _covered_focus_path = ""
    _covered_policy_active = false
    _covered_policy = CoveredBehavior.SUSPEND
    if not focus_path.is_empty():
        var focus_owner := get_node_or_null(NodePath(focus_path)) as Control
        if focus_owner != null and focus_owner.is_inside_tree():
            focus_owner.grab_focus()

func _capture_covered_subtree(node: Node) -> void:
    for state: Dictionary in _covered_node_states:
        if state["node"] == node:
            return
    var state := {
        "node": node,
        "process_mode": node.process_mode,
        "process_input": node.is_processing_input(),
        "shortcut_input": node.is_processing_shortcut_input(),
        "unhandled_input": node.is_processing_unhandled_input(),
        "unhandled_key_input": node.is_processing_unhandled_key_input(),
    }
    if node is Control:
        var control := node as Control
        state["mouse_filter"] = control.mouse_filter
        state["focus_mode"] = control.focus_mode
    _covered_node_states.append(state)
    if not node.child_entered_tree.is_connected(_on_covered_child_entered_tree):
        node.child_entered_tree.connect(_on_covered_child_entered_tree)
    if _covered_policy == CoveredBehavior.SUSPEND:
        node.process_mode = Node.PROCESS_MODE_DISABLED
    node.set_process_input(false)
    node.set_process_shortcut_input(false)
    node.set_process_unhandled_input(false)
    node.set_process_unhandled_key_input(false)
    if node is Control:
        var control := node as Control
        control.mouse_filter = Control.MOUSE_FILTER_IGNORE
        control.focus_mode = Control.FOCUS_NONE
    for child: Node in node.get_children():
        _capture_covered_subtree(child)

func _on_covered_child_entered_tree(child: Node) -> void:
    if _covered_policy_active:
        _capture_covered_subtree(child)

