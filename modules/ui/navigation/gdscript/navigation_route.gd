class_name NavigationRoute
extends RefCounted

## Emitted after the page has entered the SceneTree and its initial mount has
## completed. For configured Push/Replace this is emitted only after the configuration
## Callable has completed.
signal mounted

## Emitted when this route leaves the Navigator stack normally.
##
## [param result] is the value supplied to [method Navigator.pop],
## [method Navigator.remove], [method Navigator.replace], or [method Navigator.clear].
signal popped(result: Variant)

## Emitted whenever [member state] changes.
signal state_changed(state: State)

## Emitted when mounting cannot complete before the route becomes active.
##
## GDScript has no catchable exception model, so configuration errors raised
## inside user code are still reported by Godot itself. This signal is used for
## framework-detected failures such as an invalid configuration Callable.
signal failed(message: String)

## Runtime lifecycle of one navigation stack entry.
enum State {
    ## Route object exists but no page has started mounting.
    CREATED,
    ## Page is being instantiated/configured/mounted.
    PUSHING,
    ## Route is the current visible route.
    ACTIVE,
    ## Route remains in the stack underneath another route.
    COVERED,
    ## Route is leaving the stack.
    POPPING,
    ## Route completed normally and is no longer active.
    DISPOSED,
    ## Route failed before becoming active.
    FAILED,
}

## Static definition resolved from [PageRegistry].
##
## [member definition].[member PageDefinition.path] is the stable page identity
## and never contains query or fragment data.
var definition: PageDefinition

## Concrete URI used for this navigation entry.
##
## Unlike [member path], this preserves the request's Query and Fragment. Dynamic
## URI pushes therefore keep values such as [code]?id=123[/code] and
## [code]#friends[/code] on the route.
var uri: Uri

## Optional route-level payload used by parameter-based Push/Replace APIs.
##
## Configured Push/Replace APIs intentionally leave this as [code]null[/code].
var parameters: Variant

## Navigator that owns this route. It is injected before page configuration and
## before the page enters the SceneTree.
var navigator: Navigator

## Instantiated page for this route. It becomes available before a configured
## push invokes its Callable.
var page: NavigationPage

## Effective presentation for this concrete route.
##
## This is snapshotted from NavigationPage.presentation unless a ShowModal or
## ShowOverlay API supplied an explicit one-route override.
var presentation: NavigationPage.Presentation = NavigationPage.Presentation.PAGE

## Effective visibility policy for this route.
##
## Navigator snapshots this from NavigationPage.opaque immediately after
## instantiation/injection and before configured initialization.
var opaque: bool = true

## Effective Covered policy for this route.
##
## Navigator snapshots this from NavigationPage.covered_behavior before
## configured initialization.
var covered_behavior: NavigationPage.CoveredBehavior = NavigationPage.CoveredBehavior.SUSPEND

## Effective presentation transition for this route.
##
## This is the NavigationPage.transition reference captured before configured
## initialization. A null value falls back to Navigator.default_transition.
var transition: NavigationTransition

# Optional route-local presentation override supplied before enqueue. Null means
# use the scene-authored NavigationPage.presentation snapshot.
var _presentation_override: Variant = null

# Modal scrim is a Navigator-owned implementation detail and is never exposed as
# the route page.
var _presentation_scrim: Control

## Current lifecycle state.
var state: State = State.CREATED:
    set(value):
        if state == value:
            return
        state = value
        state_changed.emit(state)

## Canonical [code]ui://...[/code] path of this route.
var path: String:
    get:
        return definition.path if definition != null else ""

## Whether this route is the committed navigation-current route.
var is_current: bool:
    get:
        return navigator != null and navigator.current_route == self

## Whether this route is the first route in its Navigator stack.
var is_first: bool:
    get:
        return navigator != null and navigator.first_route == self

## Whether this route still represents a usable stack operation.
var is_active: bool:
    get:
        return state != State.DISPOSED and state != State.FAILED

func _init(
    p_definition: PageDefinition = null,
    p_parameters: Variant = null,
    p_uri: Uri = null,
    p_presentation_override: Variant = null
) -> void:
    definition = p_definition
    parameters = p_parameters
    uri = p_uri if p_uri != null else _create_definition_uri(p_definition)
    _presentation_override = p_presentation_override

static func _create_definition_uri(p_definition: PageDefinition) -> Uri:
    if p_definition == null:
        return null
    var value := p_definition.path
    if value == "ui://":
        value = "ui:///"
    return Uri.parse(value)

## Captures scene-authored navigation policy for this concrete route.
##
## This happens after Navigator/Route injection but before configured
## initialization, so changing page authoring properties inside configure does
## not implicitly change the route's navigation behavior.
func _snapshot_page_settings(p_page: NavigationPage) -> void:
    presentation = p_page.presentation
    if _presentation_override != null:
        presentation = int(_presentation_override)
    opaque = p_page.opaque if presentation == NavigationPage.Presentation.PAGE else false
    covered_behavior = p_page.covered_behavior
    transition = p_page.transition
