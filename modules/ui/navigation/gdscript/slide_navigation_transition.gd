@tool
class_name SlideNavigationTransition
extends TweenNavigationTransition

## Edge from which the page enters, and toward which it leaves on Pop.
enum Edge { LEFT, RIGHT, TOP, BOTTOM }
@export var from_edge: Edge = Edge.RIGHT
## Travel as a fraction of the page width/height (1 = one full page).
@export_range(0.0, 2.0, 0.01, "or_greater") var distance_ratio: float = 1.0

func _init() -> void:
    duration = 0.28
    ease_type = Tween.EASE_OUT
    transition_type = Tween.TRANS_CUBIC

func push(incoming: NavigationPage, _outgoing: NavigationPage) -> void:
    await _animate(incoming, true, _offset(incoming), 1.0, _uses_fade())

func pop(outgoing: NavigationPage, _incoming: NavigationPage) -> void:
    await _animate(outgoing, false, _offset(outgoing), 1.0, _uses_fade())

func _uses_fade() -> bool:
    return false

func _offset(page: NavigationPage) -> Vector2:
    var extent := page.size
    # A page without an authored size can still use its Navigator's dimensions.
    var parent_control := page.get_parent_control()
    var fallback := parent_control.size if parent_control != null else page.get_viewport_rect().size
    if extent.x <= 0.0:
        extent.x = fallback.x
    if extent.y <= 0.0:
        extent.y = fallback.y
    var distance := maxf(distance_ratio, 0.0)
    match from_edge:
        Edge.LEFT:
            return Vector2(-extent.x * distance, 0.0)
        Edge.TOP:
            return Vector2(0.0, -extent.y * distance)
        Edge.BOTTOM:
            return Vector2(0.0, extent.y * distance)
        _:
            return Vector2(extent.x * distance, 0.0)
