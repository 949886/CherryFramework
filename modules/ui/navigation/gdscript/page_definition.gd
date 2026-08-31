
@tool
class_name PageDefinition
extends Resource

## Generated lookup record for one navigable scene.
##
## PageDefinition intentionally contains only navigation identity and the scene
## used to instantiate that identity. Presentation/runtime policy belongs to
## NavigationPage and is snapshotted into NavigationRoute for each push.
##
## page_registry.tres is generated editor output and is not a user-authored
## configuration surface.

## Canonical application route, for example [code]ui://settings[/code].
@export var path: String = ""

## Scene instantiated whenever this definition is pushed.
@export var scene: PackedScene
