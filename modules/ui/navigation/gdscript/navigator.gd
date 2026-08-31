class_name Navigator
extends Control

class QueuedOperation:
    extends RefCounted

    var name: StringName
    var action: Callable

    func _init(p_name: StringName, p_action: Callable) -> void:
        name = p_name
        action = p_action

signal route_pushing(route: NavigationRoute)
signal route_pushed(route: NavigationRoute)
signal route_popping(route: NavigationRoute, result: Variant)
signal route_popped(route: NavigationRoute, result: Variant)
signal route_replaced(old_route: NavigationRoute, new_route: NavigationRoute)
signal route_removed(route: NavigationRoute)
signal operation_queue_changed(pending_count: int)
signal operation_started(name: StringName)
signal operation_finished(name: StringName)
signal navigation_error(code: StringName, message: String)

## Fallback transition used when a route's snapshotted transition is null.
@export var default_transition: NavigationTransition

# _routes is the scheduled logical stack. It changes synchronously when an
# operation is accepted. _mounted_routes is the committed SceneTree stack.
var _routes: Array[NavigationRoute] = []
var _mounted_routes: Array[NavigationRoute] = []
var _operation_queue: Array[QueuedOperation] = []
var _current_route: NavigationRoute
var _explicit_parent_navigator: Navigator
var _is_processing_operations := false
var _operation_running := false
var _is_transitioning := false

## Parent used only for back/MaybePop propagation.
##
## A valid explicit assignment overrides SceneTree discovery. Assigning
## [code]null[/code] clears that override and restores automatic lookup of the
## nearest ancestor [Navigator]. The fallback is resolved dynamically, so
## reparenting this Navigator also updates its automatic parent relationship.
##
## This relation does not imply route or SceneTree ownership. Structural
## operations such as [method pop], [method replace], and [method clear] always
## operate on this Navigator only.
##
## Explicit self-reference and cycles are rejected.
var parent_navigator: Navigator:
    get:
        if is_instance_valid(_explicit_parent_navigator):
            return _explicit_parent_navigator
        return _find_ancestor_navigator()
    set(value):
        if value != null and not is_instance_valid(value):
            value = null
        if value == null:
            _explicit_parent_navigator = null
            return
        if value == _explicit_parent_navigator:
            return
        if value == self or _would_create_parent_cycle(value):
            _error(&"invalid_parent_navigator", "Navigator parent relation cannot contain a cycle.")
            return
        _explicit_parent_navigator = value

## Route that is currently committed as navigation-current.
##
## This property changes only at transaction commit points. Therefore lifecycle
## callbacks can rely on current_route matching their documented invariants.
var current_route: NavigationRoute:
    get:
        return _current_route

## First currently mounted route, or null.
var first_route: NavigationRoute:
    get:
        return _mounted_routes.front() if not _mounted_routes.is_empty() else null

## Number of currently mounted routes.
var route_count: int:
    get:
        return _mounted_routes.size()

## Route that will be current after all already accepted operations complete.
var scheduled_current_route: NavigationRoute:
    get:
        return _routes.back() if not _routes.is_empty() else null

## Number of routes in the scheduled logical stack.
var scheduled_route_count: int:
    get:
        return _routes.size()

## Whether a transition is currently running.
var is_transitioning: bool:
    get:
        return _is_transitioning

## Whether an operation is running or waiting.
var is_operating: bool:
    get:
        return _is_processing_operations or not _operation_queue.is_empty()

## Running operation plus operations still waiting.
var pending_operation_count: int:
    get:
        return _operation_queue.size() + (1 if _operation_running else 0)

## Whether another logical Pop can be accepted while preserving one root route.
var can_pop: bool:
    get:
        return _routes.size() > 1

## Returns a copy of the currently committed mounted stack.
func routes() -> Array[NavigationRoute]:
    return _mounted_routes.duplicate()

## Returns a copy of the logical stack after all accepted operations.
func scheduled_routes() -> Array[NavigationRoute]:
    return _routes.duplicate()

## Schedules a parameter-based Push from a navigation URI.
##
## Query and Fragment are preserved in [member NavigationRoute.uri] but do not
## participate in PageRegistry matching.
func push(path: String, parameters: Variant = null) -> NavigationRoute:
    var address := _parse_navigation_address(path)
    if address.is_empty():
        return null
    var route_path := str(address["path"])
    var definition: PageDefinition = PageRegistry.instance.resolve(route_path)
    if definition == null:
        _error(&"page_not_found", "Navigation page not found: %s" % route_path)
        return null
    if not _validate_definition(definition):
        return null
    var route := NavigationRoute.new(definition, parameters, address["uri"] as Uri)
    _routes.append(route)
    _enqueue_operation(&"push", Callable(self, "_execute_push").bind(route, Callable(), NavigationPage.EnterReason.PUSH))
    return route

## Schedules a configured Push. Configuration is awaited before AddChild and this
## API intentionally has no parameters argument.
##
## Do not await another operation on this same Navigator from inside configure;
## that operation is queued behind the current transaction and would deadlock.
## Scheduling a non-awaited operation is allowed.
func push_configured(path: String, configure: Callable) -> NavigationRoute:
    if not configure.is_valid():
        _error(&"invalid_configuration", "Configured push requires a valid Callable.")
        return null
    var address := _parse_navigation_address(path)
    if address.is_empty():
        return null
    var route_path := str(address["path"])
    var definition: PageDefinition = PageRegistry.instance.resolve(route_path)
    if definition == null:
        _error(&"page_not_found", "Navigation page not found: %s" % route_path)
        return null
    if not _validate_definition(definition):
        return null
    var route := NavigationRoute.new(definition, null, address["uri"] as Uri)
    _routes.append(route)
    _enqueue_operation(&"push_configured", Callable(self, "_execute_push").bind(route, configure, NavigationPage.EnterReason.PUSH))
    return route

## Shows a route as a Modal regardless of its scene-authored presentation.
##
## Modal routes are non-opaque and receive a Navigator-owned blocking scrim.
func show_modal(path: String, parameters: Variant = null) -> NavigationRoute:
    return _push_with_presentation(path, NavigationPage.Presentation.MODAL, parameters, Callable(), &"show_modal")

## Configured Modal variant. The Callable runs after injection/snapshot/Modal
## override and before AddChild/_ready.
func show_modal_configured(path: String, configure: Callable) -> NavigationRoute:
    if not configure.is_valid():
        _error(&"invalid_configuration", "Configured modal requires a valid Callable.")
        return null
    return _push_with_presentation(path, NavigationPage.Presentation.MODAL, null, configure, &"show_modal_configured")

## Shows a route as a non-opaque Overlay without a modal scrim.
func show_overlay(path: String, parameters: Variant = null) -> NavigationRoute:
    return _push_with_presentation(path, NavigationPage.Presentation.OVERLAY, parameters, Callable(), &"show_overlay")

## Configured Overlay variant. Covered routes remain input-blocked according to
## Cherry's V1 CoveredBehavior contract; Overlay does not imply click-through.
func show_overlay_configured(path: String, configure: Callable) -> NavigationRoute:
    if not configure.is_valid():
        _error(&"invalid_configuration", "Configured overlay requires a valid Callable.")
        return null
    return _push_with_presentation(path, NavigationPage.Presentation.OVERLAY, null, configure, &"show_overlay_configured")

## Shows Cherry's built-in [DefaultDialog] as a Modal route.
##
## Dialog intentionally supports configured initialization only. The built-in
## definition is generated in memory and never enters the user's PageRegistry.
func show_dialog(configure: Callable) -> NavigationRoute:
    if not configure.is_valid():
        _error(&"invalid_configuration", "ShowDialog requires a valid Callable.")
        return null
    if _routes.is_empty():
        _error(&"dialog_requires_base_route", "ShowDialog requires an existing route beneath the dialog.")
        return null
    var definition := _create_default_dialog_definition()
    if definition == null:
        return null
    var route := NavigationRoute.new(definition, null, null, NavigationPage.Presentation.MODAL)
    _routes.append(route)
    _enqueue_operation(&"show_dialog", Callable(self, "_execute_push").bind(route, configure, NavigationPage.EnterReason.PUSH))
    return route

## Shows a registered custom [NavigationDialog] scene as a Modal route.
##
## GDScript has no generic type argument, so the custom dialog is selected by URI.
func show_custom_dialog(path: String, configure: Callable) -> NavigationRoute:
    if not configure.is_valid():
        _error(&"invalid_configuration", "ShowCustomDialog requires a valid Callable.")
        return null
    if _routes.is_empty():
        _error(&"dialog_requires_base_route", "ShowCustomDialog requires an existing route beneath the dialog.")
        return null
    var address := _parse_navigation_address(path)
    if address.is_empty():
        return null
    var route_path := str(address["path"])
    var definition: PageDefinition = PageRegistry.instance.resolve(route_path)
    if definition == null or not _validate_definition(definition):
        return null
    var probe := definition.scene.instantiate()
    if not probe is NavigationDialog:
        probe.free()
        _error(&"invalid_dialog_scene", "Custom dialog scene must inherit NavigationDialog: %s" % route_path)
        return null
    probe.free()
    var route := NavigationRoute.new(definition, null, address["uri"] as Uri, NavigationPage.Presentation.MODAL)
    _routes.append(route)
    _enqueue_operation(&"show_custom_dialog", Callable(self, "_execute_push").bind(route, configure, NavigationPage.EnterReason.PUSH))
    return route

## Schedules a parameter-based Push for a pre-resolved definition.
func push_definition(definition: PageDefinition, parameters: Variant = null) -> NavigationRoute:
    if not _validate_definition(definition):
        return null
    var route := NavigationRoute.new(definition, parameters)
    _routes.append(route)
    _enqueue_operation(&"push", Callable(self, "_execute_push").bind(route, Callable(), NavigationPage.EnterReason.PUSH))
    return route

## Schedules a configured Push for a pre-resolved definition.
func push_definition_configured(definition: PageDefinition, configure: Callable) -> NavigationRoute:
    if not _validate_definition(definition):
        return null
    if not configure.is_valid():
        _error(&"invalid_configuration", "Configured push requires a valid Callable.")
        return null
    var route := NavigationRoute.new(definition, null)
    _routes.append(route)
    _enqueue_operation(&"push_configured", Callable(self, "_execute_push").bind(route, configure, NavigationPage.EnterReason.PUSH))
    return route

## Schedules a caller-created route. A route instance is single-use.
func push_route(route: NavigationRoute) -> NavigationRoute:
    if route == null or route.definition == null:
        _error(&"invalid_route", "NavigationRoute or definition is null.")
        return null
    if route.navigator != null or route.state != NavigationRoute.State.CREATED:
        _error(&"route_already_used", "A NavigationRoute instance can only be pushed once.")
        return null
    if not _validate_definition(route.definition):
        return null
    _routes.append(route)
    _enqueue_operation(&"push_route", Callable(self, "_execute_push").bind(route, Callable(), NavigationPage.EnterReason.PUSH))
    return route

func _push_with_presentation(
    path: String,
    presentation: NavigationPage.Presentation,
    parameters: Variant,
    configure: Callable,
    operation_name: StringName
) -> NavigationRoute:
    var address := _parse_navigation_address(path)
    if address.is_empty():
        return null
    var route_path := str(address["path"])
    var definition: PageDefinition = PageRegistry.instance.resolve(route_path)
    if definition == null:
        _error(&"page_not_found", "Navigation page not found: %s" % route_path)
        return null
    if not _validate_definition(definition):
        return null
    var route := NavigationRoute.new(definition, parameters, address["uri"] as Uri, presentation)
    _routes.append(route)
    _enqueue_operation(operation_name, Callable(self, "_execute_push").bind(route, configure, NavigationPage.EnterReason.PUSH))
    return route

## Schedules Pop for the logical current route.
##
## Returns whether the transaction was accepted. Await route.popped when
## completion after transition/lifecycle callbacks matters.
func pop(result: Variant = null) -> bool:
    if not can_pop:
        return false
    var route: NavigationRoute = _routes.pop_back()
    _enqueue_operation(&"pop", Callable(self, "_execute_pop").bind(route, result, NavigationPage.ExitReason.POP, true))
    return true

## Attempts synchronous PopScope-aware back navigation.
##
## [method pop] is always local. This method is the back-policy entry point:
## when the local logical stack cannot Pop, an allowed request is delegated to
## [member parent_navigator].
##
## PopScopes on the local committed page are consulted before either a local Pop
## or parent propagation. A denying scope therefore prevents leaving the nested
## flow through its parent as well. PopScopes inside descendant Navigators are
## not collected by this Navigator; each nested Navigator owns its own guard
## boundary.
##
## Returns false while this Navigator is operating. Async PopScope remains a
## later V1 feature.
func maybe_pop(result: Variant = null) -> bool:
    if is_operating:
        return false

    var scopes: Array[PopScope] = []
    if current_route != null and current_route.page != null:
        _collect_pop_scopes(current_route.page, scopes)
        for scope: PopScope in scopes:
            if not scope.can_pop:
                _notify_pop_scopes(scopes, false, result)
                return false

    if can_pop:
        var did_schedule := pop(result)
        _notify_pop_scopes(scopes, did_schedule, result)
        return did_schedule

    var parent := parent_navigator
    var did_propagate := parent != null and parent.maybe_pop(result)
    _notify_pop_scopes(scopes, did_propagate, result)
    return did_propagate

## Schedules replacement of the logical current route.
##
## The old route does not receive Covered. After the transition it receives
## Exited(REPLACE), then the new route receives Entered(REPLACE).
func replace(path: String, parameters: Variant = null, old_result: Variant = null) -> NavigationRoute:
    var address := _parse_navigation_address(path)
    if address.is_empty():
        return null
    var route_path := str(address["path"])
    var definition: PageDefinition = PageRegistry.instance.resolve(route_path)
    if definition == null:
        _error(&"page_not_found", "Navigation page not found: %s" % route_path)
        return null
    if not _validate_definition(definition):
        return null
    if _routes.is_empty():
        return push(path, parameters)
    var old_route: NavigationRoute = _routes.back()
    var new_route := NavigationRoute.new(definition, parameters, address["uri"] as Uri)
    _routes[_routes.size() - 1] = new_route
    _enqueue_operation(&"replace", Callable(self, "_execute_replace").bind(old_route, new_route, Callable(), old_result))
    return new_route

## Schedules a configured replacement of the logical current route.
##
## Configuration is awaited after Navigator/Route injection and route-setting
## snapshot, but before AddChild/_ready and before the Replace transition.
## This API intentionally has no parameters argument: configured initialization
## is the alternative to route parameters.
##
## The callback may inspect the old committed CurrentRoute. Do not await another
## operation on this same Navigator from inside configure; it is queued behind
## this transaction and would deadlock. Scheduling a non-awaited operation is
## allowed.
##
## When the logical stack is empty this behaves as configured Push and the new
## page receives Entered(PUSH), because there is no route to replace.
func replace_configured(path: String, configure: Callable, old_result: Variant = null) -> NavigationRoute:
    if not configure.is_valid():
        _error(&"invalid_configuration", "Configured replace requires a valid Callable.")
        return null
    var address := _parse_navigation_address(path)
    if address.is_empty():
        return null
    var route_path := str(address["path"])
    var definition: PageDefinition = PageRegistry.instance.resolve(route_path)
    if definition == null:
        _error(&"page_not_found", "Navigation page not found: %s" % route_path)
        return null
    if not _validate_definition(definition):
        return null
    if _routes.is_empty():
        return push_configured(path, configure)
    var old_route: NavigationRoute = _routes.back()
    var new_route := NavigationRoute.new(definition, null, address["uri"] as Uri)
    _routes[_routes.size() - 1] = new_route
    _enqueue_operation(&"replace_configured", Callable(self, "_execute_replace").bind(old_route, new_route, configure, old_result))
    return new_route

## Schedules a compound Pop transaction until predicate accepts the logical
## current route. Intermediate routes receive Exited(POP), but only the final
## target receives Revealed once.
func pop_until(predicate: Callable) -> int:
    if not predicate.is_valid():
        return 0
    var targets: Array[NavigationRoute] = []
    while _routes.size() > 1 and not predicate.call(_routes.back()):
        targets.append(_routes.pop_back())
    if not targets.is_empty():
        _enqueue_operation(&"pop_until", Callable(self, "_execute_pop_many").bind(targets))
    return targets.size()

## Schedules a compound Pop transaction until path becomes logical current.
func pop_to(path: String) -> int:
    var address := _parse_navigation_address(path, false)
    if address.is_empty():
        return 0
    var target := str(address["path"])
    return pop_until(func(route: NavigationRoute) -> bool: return route.path == target)

## Schedules removal of a route.
##
## Removing current uses the Pop presentation but exits with REMOVE. Removing a
## covered route does not trigger lifecycle on other pages.
func remove(route: NavigationRoute, result: Variant = null) -> bool:
    var index := _routes.find(route)
    if index < 0 or (index == _routes.size() - 1 and _routes.size() <= 1):
        return false
    _routes.remove_at(index)
    _enqueue_operation(&"remove", Callable(self, "_execute_remove").bind(route, result))
    return true

## Schedules structural removal of the entire stack, top to bottom.
##
## Every route receives Exited(CLEAR). No route receives Revealed during Clear.
func clear(result: Variant = null) -> int:
    var targets := _routes.duplicate()
    targets.reverse()
    _routes.clear()
    if not targets.is_empty():
        _enqueue_operation(&"clear", Callable(self, "_execute_clear").bind(targets, result))
    return targets.size()

## Parses a public navigation address while keeping URI parsing separate from
## PageRegistry identity lookup.
##
## Cherry's legacy /path shorthand is canonicalized here. The returned path has
## Query/Fragment removed and is suitable for PageRegistry.resolve; the Uri
## retains the complete request.
func _parse_navigation_address(value: String, report_error: bool = true) -> Dictionary:
    var raw := value.strip_edges()
    if raw.is_empty():
        if report_error:
            _error(&"invalid_navigation_uri", "Navigation URI is empty.")
        return {}

    var canonical := raw
    if raw.begins_with("/"):
        var suffix := raw
        while suffix.begins_with("/"):
            suffix = suffix.substr(1)
        canonical = "ui:///" + suffix if suffix.is_empty() or suffix.begins_with("?") or suffix.begins_with("#") else "ui://" + suffix
    elif raw == "ui://":
        canonical = "ui:///"
    elif raw.begins_with("ui://?") or raw.begins_with("ui://#"):
        canonical = "ui:///" + raw.substr(5)

    var parsed := Uri.try_parse(canonical)
    if parsed == null or parsed.scheme != "ui":
        if report_error:
            _error(&"invalid_navigation_uri", "Unsupported navigation URI: %s" % value)
        return {}

    var identity_source := canonical
    var query_index := identity_source.find("?")
    var fragment_index := identity_source.find("#")
    var end_index := identity_source.length()
    if query_index >= 0:
        end_index = min(end_index, query_index)
    if fragment_index >= 0:
        end_index = min(end_index, fragment_index)
    identity_source = identity_source.left(end_index)

    var route_path := PageRegistry.normalize_path(identity_source)
    if route_path.is_empty():
        if report_error:
            _error(&"invalid_navigation_uri", "Unsupported navigation URI: %s" % value)
        return {}
    return {"uri": parsed, "path": route_path}

func _enqueue_operation(operation_name: StringName, action: Callable) -> void:
    _operation_queue.append(QueuedOperation.new(operation_name, action))
    operation_queue_changed.emit(pending_operation_count)
    if not _is_processing_operations:
        _drain_operation_queue()

func _drain_operation_queue() -> void:
    _is_processing_operations = true
    operation_queue_changed.emit(pending_operation_count)
    while not _operation_queue.is_empty():
        var operation: QueuedOperation = _operation_queue.pop_front()
        _operation_running = true
        operation_started.emit(operation.name)
        operation_queue_changed.emit(pending_operation_count)
        await operation.action.call()
        _operation_running = false
        operation_finished.emit(operation.name)
        operation_queue_changed.emit(pending_operation_count)
    _is_processing_operations = false
    operation_queue_changed.emit(0)

func _execute_push(route: NavigationRoute, configure: Callable, enter_reason: NavigationPage.EnterReason) -> void:
    var page := _prepare_route(route)
    if page == null:
        _routes.erase(route)
        return
    if configure.is_valid():
        await configure.call(page)
        if route.state != NavigationRoute.State.PUSHING:
            return
    await _mount_prepared_route(route, enter_reason)

func _execute_replace(old_route: NavigationRoute, new_route: NavigationRoute, configure: Callable, old_result: Variant) -> void:
    var page := _prepare_route(new_route)
    if page == null:
        _restore_failed_replace_logical_route(old_route, new_route)
        return
    if configure.is_valid():
        await configure.call(page)
        if new_route.state != NavigationRoute.State.PUSHING:
            _restore_failed_replace_logical_route(old_route, new_route)
            if is_instance_valid(page):
                page.queue_free()
            return
    var previous := _current_route
    _add_route_visuals(new_route)
    old_route.state = NavigationRoute.State.POPPING
    await _run_push_transition(new_route, previous)
    _mounted_routes.erase(old_route)
    _mounted_routes.append(new_route)
    if old_route.page != null:
        old_route.page._restore_covered_behavior()
    _remove_route_visuals(old_route)
    old_route.state = NavigationRoute.State.DISPOSED
    _current_route = null
    if old_route.page != null:
        old_route.page._notify_navigation_exited(old_result, NavigationPage.ExitReason.REPLACE)
    new_route.state = NavigationRoute.State.ACTIVE
    _current_route = new_route
    _update_route_visibility()
    new_route.page._notify_navigation_entered(old_route, NavigationPage.EnterReason.REPLACE)
    new_route.mounted.emit()
    route_pushed.emit(new_route)
    old_route.popped.emit(old_result)
    if old_route.page != null:
        old_route.page.queue_free()
    route_replaced.emit(old_route, new_route)

## Restores the old logical route in the exact slot still occupied by a failed
## replacement.
##
## If a later accepted operation has already removed the replacement route from
## ScheduledRoutes, this helper deliberately does not resurrect the old route.
func _restore_failed_replace_logical_route(old_route: NavigationRoute, new_route: NavigationRoute) -> void:
    var index := _routes.find(new_route)
    if index >= 0:
        _routes[index] = old_route

func _execute_pop(route: NavigationRoute, result: Variant, exit_reason: NavigationPage.ExitReason, emit_pop_events: bool) -> void:
    var index := _mounted_routes.find(route)
    if index < 0:
        return
    if index != _mounted_routes.size() - 1:
        _remove_covered_route(route, result, exit_reason, not emit_pop_events)
        return
    var incoming: NavigationRoute = _mounted_routes[index - 1] if index > 0 else null
    route.state = NavigationRoute.State.POPPING
    if emit_pop_events:
        route_popping.emit(route, result)
    _prepare_pop_visibility(route)
    await _run_pop_transition(route, incoming)
    _mounted_routes.pop_back()
    _remove_route_visuals(route)
    route.state = NavigationRoute.State.DISPOSED
    _current_route = null
    if route.page != null:
        route.page._notify_navigation_exited(result, exit_reason)
    if incoming != null:
        incoming.state = NavigationRoute.State.ACTIVE
        _current_route = incoming
        if incoming.page != null:
            incoming.page._restore_covered_behavior()
    _update_route_visibility()
    if incoming != null and incoming.page != null:
        incoming.page._notify_navigation_revealed(route)
    route.popped.emit(result)
    if emit_pop_events:
        route_popped.emit(route, result)
    if route.page != null:
        route.page.queue_free()

func _execute_pop_many(targets: Array[NavigationRoute]) -> void:
    var mounted_targets: Array[NavigationRoute] = []
    for route: NavigationRoute in targets:
        if _mounted_routes.has(route):
            mounted_targets.append(route)
    if mounted_targets.is_empty():
        return
    var bottom_target := mounted_targets.back()
    var bottom_index := _mounted_routes.find(bottom_target)
    var final_incoming: NavigationRoute = _mounted_routes[bottom_index - 1] if bottom_index > 0 else null
    var top_outgoing := mounted_targets.front()
    for route: NavigationRoute in mounted_targets:
        route.state = NavigationRoute.State.POPPING
        route_popping.emit(route, null)
    _prepare_compound_pop_visibility(mounted_targets)
    await _run_pop_transition(top_outgoing, final_incoming)
    _current_route = null
    for route: NavigationRoute in mounted_targets:
        _mounted_routes.erase(route)
        if route.page != null:
            route.page._restore_covered_behavior()
        _remove_route_visuals(route)
        route.state = NavigationRoute.State.DISPOSED
        if route.page != null:
            route.page._notify_navigation_exited(null, NavigationPage.ExitReason.POP)
    if final_incoming != null:
        final_incoming.state = NavigationRoute.State.ACTIVE
        _current_route = final_incoming
        if final_incoming.page != null:
            final_incoming.page._restore_covered_behavior()
    _update_route_visibility()
    if final_incoming != null and final_incoming.page != null:
        final_incoming.page._notify_navigation_revealed(bottom_target)
    for route: NavigationRoute in mounted_targets:
        route.popped.emit(null)
        route_popped.emit(route, null)
        if route.page != null:
            route.page.queue_free()

func _execute_remove(route: NavigationRoute, result: Variant) -> void:
    var index := _mounted_routes.find(route)
    if index < 0:
        return
    if index == _mounted_routes.size() - 1 and _mounted_routes.size() > 1:
        await _execute_pop(route, result, NavigationPage.ExitReason.REMOVE, false)
        route_removed.emit(route)
        return
    _remove_covered_route(route, result, NavigationPage.ExitReason.REMOVE, true)

func _execute_clear(targets: Array[NavigationRoute], result: Variant) -> void:
    _current_route = null
    for route: NavigationRoute in targets:
        if not _mounted_routes.has(route):
            continue
        _mounted_routes.erase(route)
        route.state = NavigationRoute.State.POPPING
        if route.page != null:
            route.page._restore_covered_behavior()
        _remove_route_visuals(route)
        route.state = NavigationRoute.State.DISPOSED
        if route.page != null:
            route.page._notify_navigation_exited(result, NavigationPage.ExitReason.CLEAR)
        route.popped.emit(result)
        route_removed.emit(route)
        if route.page != null:
            route.page.queue_free()

func _prepare_route(route: NavigationRoute) -> NavigationPage:
    if route == null or route.definition == null:
        _fail_route(route, "NavigationRoute or definition is null.")
        return null
    if route.navigator != null or route.state != NavigationRoute.State.CREATED:
        _fail_route(route, "A NavigationRoute instance can only be pushed once.")
        return null
    if route.definition.scene == null:
        _fail_route(route, "Page has no PackedScene: %s" % route.path)
        return null
    var instance := route.definition.scene.instantiate()
    if not instance is NavigationPage:
        instance.free()
        _fail_route(route, "Scene root must inherit NavigationPage: %s" % route.path)
        return null
    var page := instance as NavigationPage
    route.navigator = self
    route.page = page
    route.state = NavigationRoute.State.PUSHING
    page.navigator = self
    page.route = route
    route._snapshot_page_settings(page)
    route_pushing.emit(route)
    return page

func _mount_prepared_route(route: NavigationRoute, enter_reason: NavigationPage.EnterReason) -> void:
    var previous := _current_route
    _add_route_visuals(route)
    await _run_push_transition(route, previous)
    _mounted_routes.append(route)
    if previous != null:
        previous.state = NavigationRoute.State.COVERED
    route.state = NavigationRoute.State.ACTIVE
    _current_route = route
    _update_route_visibility()
    if previous != null and previous.page != null:
        previous.page._apply_covered_behavior(previous.covered_behavior)
        previous.page._notify_navigation_covered(route)
    route.page._notify_navigation_entered(previous, enter_reason)
    route.mounted.emit()
    route_pushed.emit(route)

func _run_push_transition(route: NavigationRoute, previous: NavigationRoute) -> void:
    var transition := _resolve_transition(route)
    if transition == null:
        return
    _is_transitioning = true
    await transition.push(route.page, previous.page if previous != null else null)
    _is_transitioning = false

func _run_pop_transition(route: NavigationRoute, incoming: NavigationRoute) -> void:
    var transition := _resolve_transition(route)
    if transition == null:
        return
    _is_transitioning = true
    await transition.pop(route.page, incoming.page if incoming != null else null)
    _is_transitioning = false

func _resolve_transition(route: NavigationRoute) -> NavigationTransition:
    if route != null and route.transition != null:
        return route.transition
    return default_transition

func _create_default_dialog_definition() -> PageDefinition:
    var dialog := DefaultDialog.new()
    var scene := PackedScene.new()
    var pack_result := scene.pack(dialog)
    dialog.free()
    if pack_result != OK:
        _error(&"default_dialog_pack_failed", "Unable to create Cherry DefaultDialog PackedScene.")
        return null
    var definition := PageDefinition.new()
    definition.path = "ui://cherry/default-dialog"
    definition.scene = scene
    return definition

func _add_route_visuals(route: NavigationRoute) -> void:
    if route.presentation == NavigationPage.Presentation.MODAL:
        var scrim := ColorRect.new()
        scrim.name = "ModalScrim"
        scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        scrim.color = Color(0.0, 0.0, 0.0, 0.45)
        scrim.mouse_filter = Control.MOUSE_FILTER_STOP
        route._presentation_scrim = scrim
        add_child(scrim)
    add_child(route.page)

func _remove_route_visuals(route: NavigationRoute) -> void:
    if route.page != null and route.page.get_parent() == self:
        remove_child(route.page)
    if route._presentation_scrim != null and is_instance_valid(route._presentation_scrim):
        if route._presentation_scrim.get_parent() == self:
            remove_child(route._presentation_scrim)
        route._presentation_scrim.queue_free()
        route._presentation_scrim = null

func _set_route_visual_visibility(route: NavigationRoute, value: bool) -> void:
    if route.page != null:
        route.page.visible = value
    if route._presentation_scrim != null and is_instance_valid(route._presentation_scrim):
        route._presentation_scrim.visible = value

## Recomputes visibility for the complete committed mounted stack.
##
## Starting from the top route, pages remain visible until the first visible
## opaque route is encountered. Opaque therefore affects presentation only and
## never changes CoveredBehavior.
func _update_route_visibility() -> void:
    var obscured := false
    for index: int in range(_mounted_routes.size() - 1, -1, -1):
        var route: NavigationRoute = _mounted_routes[index]
        _set_route_visual_visibility(route, not obscured)
        if not obscured and route.opaque:
            obscured = true

## Makes the stack underneath [param outgoing] visible exactly as it will appear
## after the Pop, while keeping the outgoing page visible for its transition.
##
## CoveredBehavior remains active until the Pop commits, so revealing a page for
## animation does not prematurely re-enable its processing or input.
func _prepare_pop_visibility(outgoing: NavigationRoute) -> void:
    var outgoing_index := _mounted_routes.find(outgoing)
    if outgoing_index < 0:
        return
    var obscured := false
    for index: int in range(outgoing_index - 1, -1, -1):
        var route: NavigationRoute = _mounted_routes[index]
        _set_route_visual_visibility(route, not obscured)
        if not obscured and route.opaque:
            obscured = true
    _set_route_visual_visibility(outgoing, true)

## Prepares the visual stack for a compound PopUntil/PopTo transaction without
## restoring any covered page's process/input state before commit.
func _prepare_compound_pop_visibility(targets: Array[NavigationRoute]) -> void:
    if targets.is_empty():
        return
    var bottom_index := _mounted_routes.find(targets.back())
    if bottom_index < 0:
        return
    var obscured := false
    for index: int in range(bottom_index - 1, -1, -1):
        var route: NavigationRoute = _mounted_routes[index]
        _set_route_visual_visibility(route, not obscured)
        if not obscured and route.opaque:
            obscured = true
    for target: NavigationRoute in targets:
        _set_route_visual_visibility(target, target == targets.front())

func _remove_covered_route(route: NavigationRoute, result: Variant, exit_reason: NavigationPage.ExitReason, emit_removed: bool) -> bool:
    var index := _mounted_routes.find(route)
    if index < 0:
        return false
    _mounted_routes.remove_at(index)
    route.state = NavigationRoute.State.POPPING
    if route.page != null:
        route.page._restore_covered_behavior()
    _remove_route_visuals(route)
    route.state = NavigationRoute.State.DISPOSED
    if route.page != null:
        route.page._notify_navigation_exited(result, exit_reason)
    route.popped.emit(result)
    if emit_removed:
        route_removed.emit(route)
    if route.page != null:
        route.page.queue_free()
    _update_route_visibility()
    return true

func _validate_definition(definition: PageDefinition) -> bool:
    if definition == null:
        _error(&"invalid_definition", "PageDefinition cannot be null.")
        return false
    if definition.scene == null:
        _error(&"invalid_page_scene", "Page has no PackedScene: %s" % definition.path)
        return false
    return true

func _fail_route(route: NavigationRoute, message: String) -> void:
    _error(&"route_failed", message)
    if route == null:
        return
    route.state = NavigationRoute.State.FAILED
    route.failed.emit(message)

## Collects only PopScopes owned by this Navigator's current page.
##
## Descendant Navigator subtrees are separate back-policy domains and are
## intentionally skipped.
func _collect_pop_scopes(node: Node, output: Array[PopScope]) -> void:
    if node is Navigator and node != self:
        return
    if node is PopScope:
        output.append(node as PopScope)
    for child: Node in node.get_children():
        _collect_pop_scopes(child, output)

func _notify_pop_scopes(scopes: Array[PopScope], did_pop: bool, result: Variant) -> void:
    for scope: PopScope in scopes:
        scope.pop_invoked.emit(did_pop, result)

func _find_ancestor_navigator() -> Navigator:
    var cursor := get_parent()
    while cursor != null:
        if cursor is Navigator:
            return cursor as Navigator
        cursor = cursor.get_parent()
    return null

func _would_create_parent_cycle(candidate: Navigator) -> bool:
    var cursor := candidate
    var visited: Dictionary = {}
    while cursor != null and is_instance_valid(cursor):
        if cursor == self:
            return true
        var instance_id := cursor.get_instance_id()
        if visited.has(instance_id):
            return true
        visited[instance_id] = true
        cursor = cursor.parent_navigator
    return false

func _error(code: StringName, message: String) -> void:
    push_error(message)
    navigation_error.emit(code, message)
