@tool
class_name TweenNavigationTransition
extends NavigationTransition

## Shared timing and state restoration for built-in page transitions.
## All per-run state is local, so a resource can be shared by multiple Navigators.
@export_range(0.0, 5.0, 0.01, "or_greater") var duration: float = 0.18
@export var ease_type: Tween.EaseType = Tween.EASE_IN_OUT
@export var transition_type: Tween.TransitionType = Tween.TRANS_LINEAR

func _animate(page: NavigationPage, entering: bool, offset: Vector2, scale_factor: float, fade: bool, pivot_ratio: Vector2 = Vector2(0.5, 0.5)) -> void:
    if duration <= 0.0:
        return

    var original_position := page.position
    var original_scale := page.scale
    var original_pivot := page.pivot_offset
    var original_modulate := page.modulate
    var scaling := not is_equal_approx(scale_factor, 1.0)
    var moving := not offset.is_zero_approx() or scaling

    if scaling:
        page.pivot_offset = page.size * pivot_ratio
        # Changing a pivot must preserve the authored transform, including rotation.
        var pivot_delta := page.pivot_offset - original_pivot
        page.position += (pivot_delta * original_scale).rotated(page.rotation) - pivot_delta

    var shown_position := page.position
    var hidden_position := shown_position + offset
    var hidden_scale := original_scale * maxf(scale_factor, 0.01)
    if entering:
        if moving:
            page.position = hidden_position
        if scaling:
            page.scale = hidden_scale
        if fade:
            page.modulate.a = 0.0

    var tween := page.create_tween().set_parallel()
    tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
    tween.set_trans(transition_type).set_ease(ease_type)
    if moving:
        tween.tween_property(page, "position", shown_position if entering else hidden_position, duration)
    if scaling:
        tween.tween_property(page, "scale", original_scale if entering else hidden_scale, duration)
    if fade:
        tween.tween_property(page, "modulate:a", original_modulate.a if entering else 0.0, duration)
    if not moving and not scaling and not fade:
        tween.tween_interval(duration)
    await tween.finished

    # Navigator removes a popped page after this returns, without another draw.
    if is_instance_valid(page):
        if scaling:
            page.scale = original_scale
            page.pivot_offset = original_pivot
        if moving:
            page.position = original_position
        if fade:
            page.modulate = original_modulate
