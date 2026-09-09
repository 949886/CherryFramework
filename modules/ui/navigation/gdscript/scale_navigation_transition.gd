@tool
class_name ScaleNavigationTransition
extends TweenNavigationTransition

## Relative scale at the hidden endpoint. Below 1 grows in; above 1 shrinks in.
@export_range(0.01, 2.0, 0.01, "or_greater") var hidden_scale: float = 0.9
## Normalized pivot within the page. (0.5, 0.5) is the center.
@export var pivot_ratio: Vector2 = Vector2(0.5, 0.5)
@export var fade: bool = true

func _init() -> void:
    duration = 0.24
    ease_type = Tween.EASE_OUT
    transition_type = Tween.TRANS_CUBIC

func push(incoming: NavigationPage, _outgoing: NavigationPage) -> void:
    await _animate(incoming, true, Vector2.ZERO, hidden_scale, fade, pivot_ratio)

func pop(outgoing: NavigationPage, _incoming: NavigationPage) -> void:
    await _animate(outgoing, false, Vector2.ZERO, hidden_scale, fade, pivot_ratio)
