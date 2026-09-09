@tool
class_name SlideFadeNavigationTransition
extends SlideNavigationTransition

## A short slide with an alpha fade, useful for panels and modal content.
func _init() -> void:
    duration = 0.22
    from_edge = Edge.BOTTOM
    distance_ratio = 0.08

func _uses_fade() -> bool:
    return true
