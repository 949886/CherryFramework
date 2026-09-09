class_name StoryPresenter
extends Control
## Presentation layer for DIA/NAR/CHO.
##
## This class owns all asynchronous UI behavior: typewriter timing, [wait],
## [i], audio, background transitions and popup images.  StoryVM never needs
## opcodes for these effects.

@export_range(0.0, 1.0, 0.005) var character_delay := 0.035
@export_range(0.0, 10.0, 0.1) var background_fade_duration := 1.2
@export var characters: Array[StoryCharacter] = []
@export var advance_keys: Array[Key] = [KEY_F, KEY_SPACE, KEY_ENTER]
@export var advance_mouse_button: MouseButton = MOUSE_BUTTON_LEFT
@export var choice_minimum_size := Vector2(0, 54)
@export var choice_font_size := 22

## Relative inline asset paths resolve against the current Markdown source.
var source_path := ""

@onready var background: TextureRect = $Background
@onready var portrait: TextureRect = $CharacterLayer/Portrait
@onready var article_panel: PanelContainer = $ArticlePanel
@onready var article_text: RichTextLabel = $ArticlePanel/Margin/ArticleText
@onready var dialogue_panel: PanelContainer = $DialoguePanel
@onready var speaker_label: Label = $DialoguePanel/Margin/VBox/Speaker
@onready var dialogue_text: RichTextLabel = $DialoguePanel/Margin/VBox/Text
@onready var choices_panel: VBoxContainer = $ChoicesPanel
@onready var popup_layer: ColorRect = $PopupLayer
@onready var popup_texture: TextureRect = $PopupLayer/Center/PopupTexture
@onready var audio_player: AudioStreamPlayer = $AudioPlayer

var _inline_parser := StoryInlineParser.new()
var _host: Object
var _advance_pressed := false
var _accept_input := false
var _chosen_index := -1
var _cancel_token := 0
var _background_tween: Tween


func setup(host: Object) -> void:
	_host = host


func _exit_tree() -> void:
	cancel_current()


## Hosts can advance from their own buttons, touch controls or input actions.
func advance() -> void:
	if _accept_input:
		_advance_pressed = true


func cancel_current() -> void:
	## Invalidates any active coroutine. StoryPlayer uses this before load,
	## restart or locale switching so an old await chain cannot resume later.
	_cancel_token += 1
	_advance_pressed = true
	_accept_input = false
	_chosen_index = -1
	if _background_tween != null:
		_background_tween.kill()
		_background_tween = null
	audio_player.stop()
	background.modulate.a = 1.0
	choices_panel.hide()
	popup_layer.hide()
	article_panel.hide()
	dialogue_panel.hide()


func present_dialogue(payload: Dictionary) -> bool:
	var token := _cancel_token
	article_panel.hide()
	choices_panel.hide()
	dialogue_panel.show()

	var speaker := String(payload.get("speaker", ""))
	var state := StringName(payload.get("state", "default"))
	speaker_label.text = speaker
	_show_character(speaker, state)

	if not await _play_inline(String(payload.get("content", "")), dialogue_text, token):
		return false
	if not await _wait_for_advance(token):
		return false
	return token == _cancel_token


func present_narration(payload: Dictionary) -> bool:
	var token := _cancel_token
	var silent := bool(payload.get("silent", false))
	var content := String(payload.get("content", ""))

	if silent:
		# Silent NAR is the IR representation for standalone presentation content
		# such as [save], background changes, or popup image syntax.
		return await _play_inline(content, article_text, token, true)

	dialogue_panel.hide()
	choices_panel.hide()
	article_panel.show()
	if not await _play_inline(content, article_text, token):
		return false
	if not await _wait_for_advance(token):
		return false
	article_panel.hide()
	return token == _cancel_token


func present_choice(payload: Dictionary) -> int:
	var token := _cancel_token
	_accept_input = false
	_chosen_index = -1
	choices_panel.show()

	for old_child in choices_panel.get_children():
		choices_panel.remove_child(old_child)
		old_child.queue_free()

	var options: Array = payload.get("options", [])
	for option_index in range(options.size()):
		var option: Dictionary = options[option_index]
		var button := Button.new()
		button.text = String(option.get("text", ""))
		button.custom_minimum_size = choice_minimum_size
		button.add_theme_font_size_override("font_size", choice_font_size)
		button.pressed.connect(_on_choice_pressed.bind(option_index))
		choices_panel.add_child(button)

	while _chosen_index < 0 and token == _cancel_token:
		await get_tree().process_frame

	if token != _cancel_token:
		return -1
	choices_panel.hide()
	return _chosen_index


func _play_inline(content: String, label: RichTextLabel, token: int, silent := false) -> bool:
	var tokens := _inline_parser.parse(content)
	var full_bbcode := ""
	for item in tokens:
		if item["type"] == "text":
			full_bbcode += String(item["bbcode"])

	label.bbcode_enabled = true
	label.text = full_bbcode
	label.visible_characters = 0
	var visible_cursor := 0
	_accept_input = not silent
	_advance_pressed = false

	for item in tokens:
		if token != _cancel_token:
			return false

		if item["type"] == "text":
			visible_cursor += int(item["visible_length"])
			if not await _reveal_until(label, visible_cursor, token):
				return false
			continue

		if not await _execute_command(item, token):
			return false

	if token != _cancel_token:
		return false
	label.visible_characters = -1
	_accept_input = false if silent else _accept_input
	return token == _cancel_token


func _reveal_until(label: RichTextLabel, target: int, token: int) -> bool:
	_accept_input = true
	while label.visible_characters < target:
		if token != _cancel_token:
			return false
		if _advance_pressed:
			# A click/F while typing completes only the current text segment.  A
			# later [wait] or [i] command still receives its own fresh interaction.
			_advance_pressed = false
			label.visible_characters = target
			break
		label.visible_characters += 1
		if character_delay > 0.0:
			await get_tree().create_timer(character_delay).timeout
	return token == _cancel_token


func _execute_command(command: Dictionary, token: int) -> bool:
	var name := String(command.get("name", ""))
	var argument := String(command.get("argument", ""))
	var attributes: Dictionary = command.get("attributes", {})

	match name:
		"audio":
			_play_audio(argument)

		"wait":
			_advance_pressed = false
			var seconds := _parse_seconds(argument)
			if not await _wait_seconds(seconds, token):
				return false
			_advance_pressed = false

		"i":
			if not await _wait_for_advance(token):
				return false

		"save":
			if _host != null and _host.has_method("save_game"):
				_host.call("save_game", true)

		"bg":
			if not await _set_background(argument, String(attributes.get("transition", "none")), token):
				return false

		"popup":
			if not await _show_popup(argument, token):
				return false

		_:
			push_warning("Unknown inline command: [%s]" % name)

	return token == _cancel_token


func _wait_for_advance(token: int) -> bool:
	_advance_pressed = false
	_accept_input = true
	while not _advance_pressed and token == _cancel_token:
		await get_tree().process_frame
	if token != _cancel_token:
		return false
	_advance_pressed = false
	_accept_input = false
	return token == _cancel_token


func _set_background(path: String, transition: String, token: int) -> bool:
	var texture := load(resolve_asset_path(path)) as Texture2D
	if texture == null:
		push_warning("Background not found: %s" % path)
		return true

	if transition.to_lower() == "fadein":
		background.texture = texture
		background.modulate.a = 0.0
		_background_tween = create_tween()
		_background_tween.tween_property(background, "modulate:a", 1.0, background_fade_duration)
		if not await _wait_seconds(background_fade_duration, token):
			return false
		return token == _cancel_token

	background.texture = texture
	background.modulate.a = 1.0
	return true


func _show_popup(path: String, token: int) -> bool:
	var texture := load(resolve_asset_path(path)) as Texture2D
	if texture == null:
		push_warning("Popup texture not found: %s" % path)
		return true
	popup_texture.texture = texture
	popup_layer.show()
	if not await _wait_for_advance(token):
		return false
	popup_layer.hide()
	return true


func _play_audio(path: String) -> void:
	var stream := load(resolve_asset_path(path)) as AudioStream
	if stream == null:
		push_warning("Audio stream not found: %s" % path)
		return
	audio_player.stream = stream
	audio_player.play() # Non-blocking by design.


func _show_character(speaker: String, state_id: StringName) -> void:
	for character in characters:
		if character == null or character.display_name != speaker:
			continue
		var state := character.get_state(state_id)
		if state != null and state.portrait != null:
			portrait.texture = state.portrait
			portrait.show()
		return
	# Unknown speakers do not implicitly replace the previous portrait.


func _parse_seconds(value: String) -> float:
	var normalized := value.strip_edges().to_lower()
	if normalized.ends_with("ms"):
		return maxf(0.0, normalized.trim_suffix("ms").to_float() / 1000.0)
	if normalized.ends_with("s"):
		normalized = normalized.trim_suffix("s")
	return maxf(0.0, normalized.to_float())


func resolve_asset_path(path: String) -> String:
	return path if path.is_absolute_path() else source_path.get_base_dir().path_join(path).simplify_path()


func _wait_seconds(seconds: float, token: int) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if token != _cancel_token:
			return false
		await get_tree().process_frame
	return token == _cancel_token


func _on_choice_pressed(index: int) -> void:
	_chosen_index = index


func _input(event: InputEvent) -> void:
	## Advance input is handled in _input rather than _unhandled_input.
	##
	## Why: RichTextLabel/PanelContainer are Controls and may consume mouse clicks
	## during Godot's GUI input phase.  In that case _unhandled_input never sees the
	## click, which made narration advance with F but not with the mouse.
	##
	## We deliberately ignore clicks over BaseButton controls so Save/Load/Debug
	## and choice buttons keep their normal UI semantics and never advance text as
	## a side effect of being clicked.
	if not _accept_input:
		return

	var advance := false
	if event is InputEventMouseButton:
		if event.pressed and advance_mouse_button != MOUSE_BUTTON_NONE and event.button_index == advance_mouse_button:
			if _pointer_is_over_button():
				return
			advance = true
	elif event is InputEventKey:
		advance = event.pressed and not event.echo and event.keycode in advance_keys

	if advance:
		_advance_pressed = true
		get_viewport().set_input_as_handled()


func _pointer_is_over_button() -> bool:
	## `gui_get_hovered_control()` returns the deepest Control under the pointer.
	## Walk upward because the hovered node may be a Label/Icon nested in a Button.
	var hovered := get_viewport().gui_get_hovered_control()
	var current: Node = hovered
	while current != null:
		if current is BaseButton:
			return true
		current = current.get_parent()
	return false
