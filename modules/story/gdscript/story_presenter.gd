class_name StoryPresenter
extends StoryPresentation
## Default view with a serializable, frame-driven presentation state machine.

signal event_completed

@export_range(0.0, 1.0, 0.005) var character_delay := 0.035
@export_range(0.0, 10.0, 0.1) var background_fade_duration := 1.2
@export var characters: Array[StoryCharacter] = []
@export var advance_keys: Array[Key] = [KEY_F, KEY_SPACE, KEY_ENTER]
@export var advance_mouse_button: MouseButton = MOUSE_BUTTON_LEFT
@export var choice_minimum_size := Vector2(0, 54)
@export var choice_font_size := 22
@export var commands: StoryCommandRegistry = preload("../resources/default_commands.tres")

@export_group("View Nodes")
@export var background: TextureRect
@export var portrait: TextureRect
@export var article_panel: PanelContainer
@export var article_text: RichTextLabel
@export var dialogue_panel: PanelContainer
@export var speaker_label: Label
@export var dialogue_text: RichTextLabel
@export var choices_panel: VBoxContainer
@export var popup_layer: ColorRect
@export var popup_texture: TextureRect
@export var audio_player: AudioStreamPlayer

var _host: Object
var _state := StoryPresentationState.new()
var _pending_state: StoryPresentationState
var _resume_progress := false
var _tokens: Array[Dictionary] = []
var _active := false
var _advance_pressed := false
var _cancel_token := 0
var _chosen_index := -1
var _label: RichTextLabel

func setup(host: Object) -> void:
	_host = host

func get_presenter_id() -> String:
	return "default"

func is_configured() -> bool:
	for node in [background, portrait, article_panel, article_text, dialogue_panel, speaker_label, dialogue_text, choices_panel, popup_layer, popup_texture, audio_player]:
		if not is_instance_valid(node):
			return false
	return commands != null and commands.validate().is_empty()

func _on_pause_changed(value: bool) -> void:
	if is_instance_valid(audio_player):
		audio_player.stream_paused = value

func _exit_tree() -> void:
	cancel_current()

func advance() -> void:
	if _active and not paused:
		_advance_pressed = true

func cancel_current() -> void:
	_cancel_token += 1
	_active = false
	_advance_pressed = false
	_chosen_index = -1
	_pending_state = null
	if is_configured():
		audio_player.stop()
		choices_panel.hide()
		popup_layer.hide()
		article_panel.hide()
		dialogue_panel.hide()
	event_completed.emit()

func present_dialogue(payload: Dictionary) -> bool:
	var token := _begin("dialogue", payload)
	while token == _cancel_token and _active:
		await event_completed
	return token == _cancel_token

func present_narration(payload: Dictionary) -> bool:
	var token := _begin("silent" if payload.get("silent", false) else "narration", payload)
	while token == _cancel_token and _active:
		await event_completed
	return token == _cancel_token

func present_choice(payload: Dictionary) -> int:
	var token := _begin("choice", payload)
	while token == _cancel_token and _active:
		await event_completed
	return _chosen_index if token == _cancel_token else -1

func capture_state() -> StoryPresentationState:
	if not is_configured():
		return StoryPresentationState.new()
	_state.dialogue_text = dialogue_text.text
	_state.dialogue_characters = maxi(0, dialogue_text.visible_characters)
	_state.speaker = speaker_label.text
	_state.article_text = article_text.text
	_state.article_characters = maxi(0, article_text.visible_characters)
	_state.dialogue_shown = dialogue_panel.visible
	_state.article_shown = article_panel.visible
	_state.audio_playing = audio_player.playing
	_state.audio_position = audio_player.get_playback_position() if audio_player.playing else 0.0
	return _state.copy()

func can_restore(state: StoryPresentationState) -> bool:
	if state.renderer != get_presenter_id():
		return false
	for path in [state.background_path, state.portrait_path, state.popup_path]:
		if not path.is_empty() and (not ResourceLoader.exists(path) or not load(path) is Texture2D):
			return false
	return state.audio_path.is_empty() or (ResourceLoader.exists(state.audio_path) and load(state.audio_path) is AudioStream)

func restore_state(state: StoryPresentationState, resume_progress: bool) -> void:
	_pending_state = state.copy()
	_resume_progress = resume_progress
	_state = state.copy()
	_apply_visuals()

func _begin(mode: String, payload: Dictionary) -> int:
	if not is_configured():
		presentation_failed.emit("StoryPresenter requires configured view nodes and a valid command registry.")
		return -1
	# Supersede previous awaiters without stopping audio between ordinary lines.
	_cancel_token += 1
	_active = false
	event_completed.emit()
	var restoring := _pending_state != null and _resume_progress and _pending_state.mode == mode and _pending_state.payload == payload
	if restoring:
		_state = _pending_state.copy()
	else:
		_state.mode = mode
		_state.payload = payload.duplicate(true)
		_state.token_index = 0
		_state.visible_characters = 0
		_state.text_time = 0.0
		_state.remaining = 0.0
		_state.phase = "choice" if mode == "choice" else "next"
	_pending_state = null
	_advance_pressed = false
	_chosen_index = -1
	_active = true
	if mode in ["dialogue", "narration"]:
		article_panel.visible = mode == "narration"
		dialogue_panel.visible = mode == "dialogue"
	choices_panel.visible = mode == "choice"
	popup_layer.visible = _state.phase == "popup"
	_label = dialogue_text if mode == "dialogue" else article_text
	if mode == "dialogue":
		speaker_label.text = String(payload.get("speaker", ""))
		_show_character(speaker_label.text, StringName(payload.get("state", "default")))
	if mode == "choice":
		_build_choices(payload)
	else:
		_tokens = StoryInlineParser.new().parse(String(payload.get("content", "")))
		var bbcode := ""
		for item in _tokens:
			if item.type == "text":
				bbcode += item.bbcode
		_label.bbcode_enabled = true
		_label.text = bbcode
		_label.visible_characters = _state.visible_characters
		if _state.token_index > _tokens.size():
			_state.token_index = 0
			_state.phase = "next"
	return _cancel_token

func _process(delta: float) -> void:
	advance_time(delta)

## Single simulation clock; can also be advanced explicitly in deterministic tests.
func advance_time(delta: float) -> void:
	if not _active or paused or delta < 0:
		return
	var budget := delta * (fast_forward_multiplier if fast_forward else 1.0)
	for transition in range(64):
		match _state.phase:
			"choice":
				return
			"next":
				if _state.token_index >= _tokens.size():
					if _state.mode == "silent":
						_finish()
						return
					_state.phase = "end"
					_state.remaining = auto_advance_delay
					continue
				var item: Dictionary = _tokens[_state.token_index]
				if item.type == "text":
					_state.phase = "text"
					continue
				_state.token_index += 1 # [save] resumes after itself, never repeats.
				var token := _cancel_token
				_execute_command(item)
				if token != _cancel_token:
					return
			"text":
				var target := _text_target(_state.token_index)
				if _advance_pressed or character_delay <= 0.0:
					_state.visible_characters = target
					_advance_pressed = false
					_state.text_time = 0.0
				else:
					var available := _state.text_time + budget
					var count := mini(target - _state.visible_characters, int((available + 0.0000001) / character_delay))
					_state.visible_characters += count
					_state.text_time = maxf(0.0, available - count * character_delay)
					budget = _state.text_time if _state.visible_characters == target else 0.0
					if _state.visible_characters == target:
						_state.text_time = 0.0
				_label.visible_characters = _state.visible_characters
				if _state.visible_characters < target:
					return
				_state.token_index += 1
				_state.phase = "next"
			"wait", "fade":
				var elapsed := minf(budget, _state.remaining)
				if _state.phase == "fade":
					_state.background_alpha = lerpf(_state.background_alpha, 1.0, elapsed / _state.remaining) if _state.remaining > 0 else 1.0
					background.modulate.a = _state.background_alpha
				_state.remaining = maxf(0.0, _state.remaining - elapsed)
				budget -= elapsed
				_advance_pressed = false
				if _state.remaining > 0.0:
					return
				_state.phase = "next"
			"input", "end", "popup":
				if auto_play or fast_forward:
					_state.remaining = maxf(0.0, _state.remaining - budget)
				if not _advance_pressed and not ((auto_play or fast_forward) and _state.remaining <= 0.0):
					return
				_advance_pressed = false
				if _state.phase == "end":
					_finish()
					return
				if _state.phase == "popup":
					popup_layer.hide()
					_state.popup_path = ""
				_state.phase = "next"
				budget = 0.0
			_:
				return

func _finish() -> void:
	_active = false
	if _state.mode == "narration":
		article_panel.hide()
	event_completed.emit()

func _text_target(index: int) -> int:
	var target := 0
	for i in range(mini(index + 1, _tokens.size())):
		if _tokens[i].type == "text":
			target += int(_tokens[i].visible_length)
	return target

func _execute_command(command: Dictionary) -> void:
	var handler := commands.find(StringName(command.get("name", "")))
	var message := "Unknown inline command: %s" % command.get("name", "")
	if handler != null:
		message = handler.validate_argument(command)
		if message.is_empty():
			var error := handler.execute(self, command)
			if error == OK:
				return
			message = "Command '%s' failed (error %d)." % [handler.command_name, error]
	cancel_current()
	presentation_failed.emit(message)

func command_wait(command: Dictionary) -> Error:
	_state.phase = "wait"
	_state.remaining = _parse_seconds(String(command.get("argument", "")))
	return OK

func command_input(_command: Dictionary) -> Error:
	_state.phase = "input"
	_state.remaining = auto_advance_delay
	return OK

func command_save(_command: Dictionary) -> Error:
	if is_instance_valid(_host) and _host.has_method("save_game"):
		var result: Variant = _host.call("save_game", true)
		return OK if result == null else int(result)
	return ERR_UNCONFIGURED

func command_audio(command: Dictionary) -> Error:
	var path := resolve_asset_path(String(command.get("argument", "")))
	if not _asset_exists(path, "AudioStream"):
		return ERR_FILE_NOT_FOUND
	_state.audio_path = path
	audio_player.stream = load(path) as AudioStream
	audio_player.play()
	return OK

func command_background(command: Dictionary) -> Error:
	var path := resolve_asset_path(String(command.get("argument", "")))
	if not _asset_exists(path, "Texture2D"):
		return ERR_FILE_NOT_FOUND
	_state.background_path = path
	background.texture = load(path) as Texture2D
	var fade := String(command.get("attributes", {}).get("transition", "none")) == "fadein"
	_state.background_alpha = 0.0 if fade and background_fade_duration > 0 else 1.0
	background.modulate.a = _state.background_alpha
	if fade:
		_state.phase = "fade"
		_state.remaining = background_fade_duration
	return OK

func command_popup(command: Dictionary) -> Error:
	var path := resolve_asset_path(String(command.get("argument", "")))
	if not _asset_exists(path, "Texture2D"):
		return ERR_FILE_NOT_FOUND
	_state.popup_path = path
	popup_texture.texture = load(path) as Texture2D
	popup_layer.show()
	_state.phase = "popup"
	_state.remaining = auto_advance_delay
	return OK

func _asset_exists(path: String, type: String) -> bool:
	if ResourceLoader.exists(path, type):
		return true
	presentation_failed.emit("Missing %s: %s" % [type, path])
	return false

func _apply_visuals() -> void:
	dialogue_text.text = _state.dialogue_text
	dialogue_text.visible_characters = _state.dialogue_characters
	speaker_label.text = _state.speaker
	article_text.text = _state.article_text
	article_text.visible_characters = _state.article_characters
	dialogue_panel.visible = _state.dialogue_shown
	article_panel.visible = _state.article_shown
	background.texture = load(_state.background_path) as Texture2D if not _state.background_path.is_empty() else null
	background.modulate.a = _state.background_alpha
	portrait.texture = load(_state.portrait_path) as Texture2D if not _state.portrait_path.is_empty() else null
	portrait.visible = portrait.texture != null
	popup_texture.texture = load(_state.popup_path) as Texture2D if not _state.popup_path.is_empty() else null
	popup_layer.visible = _state.phase == "popup"
	if not _state.audio_path.is_empty() and _state.audio_playing:
		audio_player.stream = load(_state.audio_path) as AudioStream
		audio_player.play(_state.audio_position)
		audio_player.stream_paused = paused

func _show_character(speaker: String, state_id: StringName) -> void:
	for character in characters:
		if character == null or character.display_name != speaker:
			continue
		var state := character.get_state(state_id)
		if state != null and state.portrait != null:
			portrait.texture = state.portrait
			portrait.show()
			_state.portrait_path = state.portrait.resource_path
		return

func _build_choices(payload: Dictionary) -> void:
	for child in choices_panel.get_children():
		choices_panel.remove_child(child)
		child.queue_free()
	var options: Array = payload.get("options", [])
	for index in options.size():
		var button := Button.new()
		button.text = String(options[index].get("text", ""))
		button.custom_minimum_size = choice_minimum_size
		button.add_theme_font_size_override("font_size", choice_font_size)
		button.pressed.connect(_choose.bind(index, _cancel_token))
		choices_panel.add_child(button)

func _choose(index: int, token: int) -> void:
	if token != _cancel_token or not _active or paused:
		return
	_chosen_index = index
	choices_panel.hide()
	_finish()

func resolve_asset_path(path: String) -> String:
	return path if path.is_absolute_path() else source_path.get_base_dir().path_join(path).simplify_path()

func _parse_seconds(value: String) -> float:
	var normalized := value.strip_edges().to_lower()
	if normalized.ends_with("ms"):
		return maxf(0.0, normalized.trim_suffix("ms").to_float() / 1000.0)
	return maxf(0.0, normalized.trim_suffix("s").to_float())

func _input(event: InputEvent) -> void:
	if not _active or paused or _state.phase == "choice":
		return
	var pressed := false
	if event is InputEventMouseButton:
		pressed = event.pressed and advance_mouse_button != MOUSE_BUTTON_NONE and event.button_index == advance_mouse_button and not _pointer_is_over_button()
	elif event is InputEventKey:
		pressed = event.pressed and not event.echo and event.keycode in advance_keys
	if pressed:
		advance()
		get_viewport().set_input_as_handled()

func _pointer_is_over_button() -> bool:
	var current: Node = get_viewport().gui_get_hovered_control()
	while current != null:
		if current is BaseButton:
			return true
		current = current.get_parent()
	return false
