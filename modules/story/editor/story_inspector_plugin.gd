@tool
extends EditorInspectorPlugin

signal check_requested(library: StoryLibrary)

func _can_handle(object: Object) -> bool:
	return object is StoryLibrary

func _parse_begin(object: Object) -> void:
	var button := Button.new()
	button.text = "Check Story Library"
	button.pressed.connect(func(): check_requested.emit(object))
	add_custom_control(button)
