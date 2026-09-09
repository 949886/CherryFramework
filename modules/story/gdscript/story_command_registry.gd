class_name StoryCommandRegistry
extends Resource

@export var handlers: Array[StoryCommandHandler] = []

func find(command_name: StringName) -> StoryCommandHandler:
	for handler in handlers:
		if handler != null and handler.command_name == command_name:
			return handler
	return null

func register(handler: StoryCommandHandler, replace: bool = false) -> Error:
	if handler == null or String(handler.command_name).is_empty():
		return ERR_INVALID_PARAMETER
	for index in handlers.size():
		if handlers[index] != null and handlers[index].command_name == handler.command_name:
			if not replace:
				return ERR_ALREADY_EXISTS
			handlers[index] = handler
			return OK
	handlers.append(handler)
	return OK

func validate() -> PackedStringArray:
	var errors: PackedStringArray = []
	var seen := {}
	for handler in handlers:
		if handler == null:
			errors.append("Command registry contains a null handler.")
			continue
		var name := String(handler.command_name)
		if name.is_empty() or name != name.to_lower() or name.contains(" ") or name.contains(":") or name.contains("]"):
			errors.append("Invalid command name: %s" % name)
		if seen.has(name):
			errors.append("Duplicate command: %s" % name)
		seen[name] = true
	return errors
