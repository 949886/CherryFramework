@tool
class_name FadeNavigationTransition
extends TweenNavigationTransition

## Fades the incoming page from transparent to its normal modulate alpha.
func push(incoming: NavigationPage, _outgoing: NavigationPage) -> void:
    await _animate(incoming, true, Vector2.ZERO, 1.0, true)

## Fades the outgoing page to transparent before Navigator removes it.
func pop(outgoing: NavigationPage, _incoming: NavigationPage) -> void:
    await _animate(outgoing, false, Vector2.ZERO, 1.0, true)
