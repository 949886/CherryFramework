@tool
class_name StoryBuiltinCommand
extends StoryCommandHandler
## Maps a configured command to a renderer capability; the registry defines names.

@export var method: StringName
@export_enum("none", "duration", "asset") var argument_kind := "none"

func execute(presentation: StoryPresentation, command: Dictionary) -> Error:
	if not presentation.has_method(method):
		return ERR_UNAVAILABLE
	return presentation.call(method, command)

func validate_argument(command: Dictionary) -> String:
	var argument := String(command.get("argument", ""))
	if argument_kind == "asset" and argument.is_empty():
		return "Asset path cannot be empty."
	if argument_kind == "duration":
		var value := argument.trim_suffix("ms").trim_suffix("s")
		if not value.is_valid_float() or not is_finite(value.to_float()) or value.to_float() < 0:
			return "Duration must be a finite non-negative number followed optionally by ms or s."
	return ""
