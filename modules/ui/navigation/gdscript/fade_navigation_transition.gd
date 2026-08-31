@tool
class_name FadeNavigationTransition
extends NavigationTransition

## Duration of the fade in seconds.
@export_range(0.0, 5.0, 0.01) var duration: float = 0.18

## Fades the incoming page from transparent to its normal modulate alpha.
func push(incoming: NavigationPage, _outgoing: NavigationPage) -> void:
    if duration <= 0.0:
        return
    incoming.modulate.a = 0.0
    var tween := incoming.create_tween()
    tween.tween_property(incoming, "modulate:a", 1.0, duration)
    await tween.finished

## Fades the outgoing page to transparent before Navigator removes it.
func pop(outgoing: NavigationPage, _incoming: NavigationPage) -> void:
    if duration <= 0.0:
        return
    var tween := outgoing.create_tween()
    tween.tween_property(outgoing, "modulate:a", 0.0, duration)
    await tween.finished
