@tool
extends EditorInspectorPlugin

signal check_requested(story: Story)

func _can_handle(object: Object) -> bool:
	return object is Story

func _parse_begin(object: Object) -> void:
	var button := Button.new()
	button.text = "Check Story"
	button.pressed.connect(func(): check_requested.emit(object))
	add_custom_control(button)
	var label := Label.new()
	label.text = "Story: %s\nDetected languages: %s" % [object.get_story_id(), ", ".join(object.get_available_locales())]
	add_custom_control(label)
