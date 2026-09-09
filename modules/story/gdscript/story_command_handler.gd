class_name StoryCommandHandler
extends Resource
## Stateless command definition. Mutable playback data belongs to the renderer.

@export var command_name: StringName
## Optional asset type used by library validation and dependency collection.
@export var asset_type := ""

func execute(_presentation: StoryPresentation, _command: Dictionary) -> Error:
	return ERR_UNAVAILABLE

func validate_argument(_command: Dictionary) -> String:
	return ""
