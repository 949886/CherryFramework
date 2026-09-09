class_name StoryCharacter
extends Resource
## Resourceized character definition used by the presentation layer.

@export var id: StringName
@export var display_name: String
@export var default_state: StringName = &"default"
@export var states: Array[StoryCharacterState] = []


func get_state(state_id: StringName) -> StoryCharacterState:
	for state in states:
		if state != null and state.id == state_id:
			return state
	# Missing/empty states fall back to the configured default.
	for state in states:
		if state != null and state.id == default_state:
			return state
	return states[0] if not states.is_empty() else null
