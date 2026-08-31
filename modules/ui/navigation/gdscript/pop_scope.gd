class_name PopScope
extends Node

## Whether system-style back navigation is currently allowed through this scope.
@export var can_pop: bool = true

## Emitted when [method Navigator.maybe_pop] consults this page.
##
## [param did_pop] is true when the back request caused a route to Pop either in
## this Navigator or, for a nested root route, in an ancestor Navigator reached
## through [member Navigator.parent_navigator]. [param result] is the requested
## pop result.
signal pop_invoked(did_pop: bool, result: Variant)
