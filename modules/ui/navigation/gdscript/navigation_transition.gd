@tool
class_name NavigationTransition
extends Resource

## Base class for Cherry page presentation transitions.
##
## A transition runs inside Navigator's serialized operation queue. The next
## stack mutation does not begin until the current transition completes.
##
## [param incoming] is already inside the SceneTree when [method push] runs.
## [param outgoing] may be null when the first route is mounted.
func push(_incoming: NavigationPage, _outgoing: NavigationPage) -> void:
    pass

## Runs while [param outgoing] is still mounted and [param incoming], when
## present, has been made visible underneath it.
##
## Navigator removes [param outgoing] only after this method completes.
func pop(_outgoing: NavigationPage, _incoming: NavigationPage) -> void:
    pass
