class_name StoryPresentation
extends Node
## Renderer contract. Implementations may be UI, world-space, or headless nodes.

signal presentation_failed(message: String)

@export var auto_play := false
@export_range(0.0, 10.0, 0.1) var auto_advance_delay := 1.0
@export var fast_forward := false
@export_range(1.0, 100.0, 1.0) var fast_forward_multiplier := 10.0
@export var paused := false:
	set(value):
		paused = value
		_on_pause_changed(value)

var source_path := ""

func setup(_host: Object) -> void:
	pass

func configure_commands(_registry: StoryCommandRegistry) -> void:
	pass

func is_configured() -> bool:
	return true

func get_presenter_id() -> String:
	return "base"

## Keep the base contract asynchronous for calls through a StoryPresentation
## reference; renderer overrides may suspend until input or complete immediately.
func present_dialogue(_payload: Dictionary) -> bool:
	await get_tree().process_frame
	return false

func present_narration(_payload: Dictionary) -> bool:
	await get_tree().process_frame
	return false

func present_choice(_payload: Dictionary) -> int:
	await get_tree().process_frame
	return -1

func cancel_current() -> void:
	pass

func capture_state() -> StoryPresentationState:
	var state := StoryPresentationState.new()
	state.renderer = get_presenter_id()
	return state

func can_restore(state: StoryPresentationState) -> bool:
	return state.renderer == get_presenter_id()

func restore_state(_state: StoryPresentationState, _resume_progress: bool) -> void:
	pass

func _on_pause_changed(_value: bool) -> void:
	pass
