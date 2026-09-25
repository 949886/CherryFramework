class_name StoryGalgamePresenter
extends StoryPresenter
## Native galgame shell. The VM owns execution; this class owns presentation,
## input and the single virtual stage shared by gameplay and all menu pages.

## The Stage node is the authored virtual canvas. Resize it in the scene.
var stage_size: Vector2:
	get: return stage.size
@export_group("Galgame")
@export var choice_scene: PackedScene
@export_range(0, 100, 1) var choice_gap := 28.0
@export_range(0, 300, 1) var choice_top_margin := 122.0
@export var save_directory := "user://cherry_galgame"
@export_file("*.json") var catalog_path := ""
@export var backdrop: Texture2D
@export var music_stream: AudioStream
@export var effect_stream: AudioStream
@export var game_title := "Cherry Story"
@export var footer_caption := "CHERRY STORY"
var preferences := StoryPreferences.new()
var archive := StoryArchive.new()
var library := StoryLibrary.new()
var skin: StorySkin
@export_group("Galgame View Nodes")
@export var game_view: Control
@export var brand_label: Label
@export var caption_label: Label
@export var footer: HBoxContainer
@export var stage: Control
@export var dialogue: StoryDialogueBox
@export var narration: StoryDialogueBox
@export var choice_scroll: ScrollContainer
@export var chrome: Control
@export var menu: StoryGalgameMenus
@export var music_player: AudioStreamPlayer
@export var effect_player: AudioStreamPlayer
@export var replay_player: AudioStreamPlayer
var footer_buttons: Dictionary = {}
@export var location_label: Label
var thumbnail := PackedByteArray()
var ui_hidden := false
var _initialized := false
var _line_read := false
var _focus_paused := false
var _hidden_state: Array[bool] = []
var _authored_panel_heights: Dictionary = {}
var _choice_layout_pending := false
var _choice_icon: Texture2D
var _choice_pending := -1
var _choice_token := -1
var _choice_remaining := 0.0

func _ready() -> void:
	preferences.path = save_directory.path_join("settings.cfg")
	preferences.load_settings()
	skin = StorySkin.new(preferences)
	var root := get_node(".") as Control
	# Fixed controls and their references are authored in galgame_presenter.tscn.
	# Capture only the minimum height; horizontal anchors and bottom margins
	# remain scene-owned, including overrides on inherited presenter scenes.
	for panel in [dialogue, narration]:
		_authored_panel_heights[panel] = panel.size.y
	if backdrop != null: background.texture = backdrop
	_bind_chrome()
	_choice_icon = skin.icon("chevron-right")
	choices_panel.minimum_size_changed.connect(_schedule_choice_layout)
	for id in ["Voice", "Music", "Effects"]:
		if AudioServer.get_bus_index(id) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, id)
	audio_player.bus = &"Voice"
	replay_player.bus = &"Voice"
	music_player.bus = &"Music"
	effect_player.bus = &"Effects"
	music_player.stream = music_stream
	music_player.finished.connect(func():
		if music_player.stream != null: music_player.play())
	if music_stream != null: music_player.play()
	effect_player.stream = effect_stream
	menu.configure(self)
	preferences.changed.connect(_settings_changed)
	archive.failed.connect(func(message): menu.notify_user(message))
	root.resized.connect(_layout_stage)
	get_window().focus_exited.connect(_lose_focus)
	get_window().focus_entered.connect(_gain_focus)
	_initialized = true
	_settings_changed("")
	_layout_stage()

func _texture(parent: Node, texture: Texture2D, rect: Rect2) -> TextureRect:
	var result := TextureRect.new()
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.texture = texture
	result.position = rect.position
	result.size = rect.size
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(result)
	return result

func _bind_chrome() -> void:
	brand_label.text = game_title
	caption_label.text = footer_caption
	var brand_icon := brand_label.get_parent().get_node("Icon") as TextureRect
	brand_icon.texture = skin.icon("cherry", int(brand_icon.custom_minimum_size.x))
	# Scene metadata binds semantic actions without depending on node names or
	# ordering; labels, icons, spacing and dimensions belong to the scene.
	var actions := {
		"backlog": open_menu.bind("backlog"), "auto": toggle_auto,
		"save": open_menu.bind("save"), "load": open_menu.bind("load"),
		"hide": toggle_hidden, "flow": open_menu.bind("flow"),
		"skip": toggle_skip, "settings": open_menu.bind("settings"),
	}
	for child in footer.get_children():
		if not child is Button: continue
		var identity := String(child.get_meta("action", ""))
		if not actions.has(identity): continue
		child.pressed.connect(actions[identity])
		footer_buttons[identity] = child

func setup(host: Object) -> void:
	super.setup(host)
	if archive.player == host: return
	archive.configure(host as StoryPlayer, save_directory)
	archive.slot_count = int(preferences.schema.get("slot_count", 24))
	var descriptions: Dictionary = {}
	if not catalog_path.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(catalog_path))
		if parsed is Dictionary: descriptions = parsed
	library.build(archive.player.story, archive.player.locale, descriptions)
	archive.player.story_failed.connect(func(message): menu.notify_user(message))
	archive.player.story_finished.connect(func(_id):
		auto_play = false
		fast_forward = false
		menu.show_ending())

func _layout_stage() -> void:
	var available := (get_node(".") as Control).size
	var factor := minf(available.x / stage_size.x, available.y / stage_size.y)
	stage.scale = Vector2.ONE * factor
	stage.position = (available - stage_size * factor) / 2.0
	_layout_dialogue()

func _layout_dialogue() -> void:
	# Only grow the text panels upward. Keep the authored bottom and both
	# horizontal anchors, so editor layout changes survive settings and resize.
	for panel in [dialogue, narration]:
		var height: float = panel.fitted_height(preferences.values, _authored_panel_heights[panel])
		panel.offset_top = panel.offset_bottom - height
	_layout_choices()

func _schedule_choice_layout() -> void:
	# Wrapping/theme changes settle through Godot's container pass. Measure the
	# real row minimums afterwards instead of assuming every option is 60px.
	if _choice_layout_pending: return
	_choice_layout_pending = true
	_layout_choices.call_deferred()

func _layout_choices() -> void:
	_choice_layout_pending = false
	var bottom := dialogue.position.y - choice_gap
	var height := minf(choices_panel.get_combined_minimum_size().y, maxf(0, bottom - choice_top_margin))
	choice_scroll.offset_top = bottom - height
	choice_scroll.offset_bottom = bottom
	choice_scroll.visible = choices_panel.visible and not ui_hidden

func _begin(mode: String, payload: Dictionary) -> int:
	_choice_pending = -1
	if mode in ["dialogue", "narration"] and not preferences.values.keep_voice and _pending_state == null:
		audio_player.stop()
	var token := super._begin(mode, payload)
	if mode == "dialogue":
		for character in characters:
			if character.display_name == speaker_label.text:
				dialogue.roman.text = String(character.id).to_upper()
				dialogue.voice.text = dialogue.roman.text
				break
	_line_read = archive.begin_presentation(payload)
	if not _line_read and not preferences.values.skip_unread: fast_forward = false
	if mode == "choice":
		fast_forward = false
		if preferences.values.autosave: _autosave.call_deferred(token)
	_layout_dialogue()
	if archive.player != null and archive.player.current_story != null:
		var node: Dictionary = library.nodes.get(archive.player.current_story.get_identity(), {})
		location_label.text = node.get("chapter", "故事") + " / " + node.get("title", "")
	return token

func _autosave(token: int) -> void:
	if token == _cancel_token and _active: archive.save_automatic()

func _finish() -> void:
	if _state.mode != "silent": archive.complete_presentation()
	super._finish()

func _build_choices(payload: Dictionary) -> void:
	for child in choices_panel.get_children():
		choices_panel.remove_child(child)
		child.queue_free()
	var options: Array = payload.get("options", [])
	for index in options.size():
		var button := choice_scene.instantiate() as StoryChoiceButton
		button.text = "%02d    %s" % [index + 1, String(options[index].get("text", ""))]
		button.icon = _choice_icon
		button.pressed.connect(_choose.bind(index, _cancel_token))
		choices_panel.add_child(button)
		button.configure(skin)

func _choose(index: int, token: int) -> void:
	if token != _cancel_token or not _active or paused or _state.mode != "choice" or _choice_pending >= 0: return
	var options: Array = _state.payload.get("options", [])
	if index < 0 or index >= options.size(): return
	_choice_pending = index
	_choice_token = token
	_choice_remaining = 0.0 if preferences.values.motion == "reduced" else float(preferences.schema.choice_motion.commit_duration)
	for item in choices_panel.get_child_count():
		(choices_panel.get_child(item) as StoryChoiceButton).confirm_choice(item == index)
	if effect_stream != null: effect_player.play()
	if _choice_remaining <= 0.0: _commit_choice()

func _commit_choice() -> void:
	var index := _choice_pending
	_choice_pending = -1
	if _choice_token != _cancel_token or not _active or _state.mode != "choice" or index < 0: return
	archive.record_choice(String(_state.payload.options[index].get("text", "")))
	choice_scroll.hide()
	super._choose(index, _choice_token)

func cancel_current() -> void:
	_choice_pending = -1
	super.cancel_current()

func _advance_choices(delta: float) -> void:
	if paused or delta < 0.0 or not _active or _state.mode != "choice": return
	# Mouse hover takes precedence over retained keyboard focus, so moving
	# between options cannot leave two different rows highlighted.
	var highlighted := -1
	for index in choices_panel.get_child_count():
		if (choices_panel.get_child(index) as Button).has_focus(): highlighted = index
	for index in choices_panel.get_child_count():
		if (choices_panel.get_child(index) as Button).is_hovered(): highlighted = index
	for index in choices_panel.get_child_count():
		var button := choices_panel.get_child(index) as StoryChoiceButton
		button.set_interaction(index == highlighted, button.is_pressed())
		button.advance_visuals(delta)
	if _choice_pending >= 0:
		_choice_remaining -= delta
		if _choice_remaining <= 0.0: _commit_choice()

func advance_time(delta: float) -> void:
	if not _initialized: return
	_advance_choices(delta)
	# Keep typewriter and command timing intact; only suspend automatic advance
	# at a finished line while speech is playing. A deliberate click still wins.
	var hold_auto: bool = auto_play and preferences.values.wait_voice and audio_player.playing and _state.phase == "end" and not _advance_pressed
	if hold_auto:
		auto_play = false
	super.advance_time(delta)
	if hold_auto: auto_play = true
	var duck: bool = preferences.values.duck_music and (audio_player.playing or replay_player.playing)
	music_player.volume_db = -10.0 if duck else 0.0
	footer_buttons.auto.icon = skin.icon("pause" if auto_play else "play")
	footer_buttons.skip.icon = skin.icon("pause" if fast_forward else "fast-forward")

func _settings_changed(key: String) -> void:
	if not _initialized: return
	skin.rebuild()
	stage.theme = skin.theme
	skin.refresh_labels(stage)
	dialogue.apply_skin(skin)
	narration.apply_skin(skin)
	for button in choices_panel.get_children():
		(button as StoryChoiceButton).configure(skin)
	if preferences.values.motion == "reduced": _choice_remaining = 0.0
	character_delay = 0.0 if preferences.values.instant else 1.0 / float(preferences.values.speed)
	auto_advance_delay = float(preferences.values.auto_delay)
	fast_forward_multiplier = float(preferences.values.skip_speed)
	if not preferences.values.skip_unread and not _line_read: fast_forward = false
	background_fade_duration = 0.0 if preferences.values.motion == "reduced" else 0.6
	for pair in [["Master", "master"], ["Voice", "voice"], ["Music", "music"], ["Effects", "effects"]]:
		AudioServer.set_bus_volume_linear(AudioServer.get_bus_index(pair[0]), float(preferences.values[pair[1]]) / 100.0)
	AudioServer.set_bus_mute(0, preferences.values.mute)
	if key in ["", "window_mode", "resolution"] and DisplayServer.get_name() != "headless":
		var mode := String(preferences.values.window_mode)
		get_window().mode = {"window": Window.MODE_WINDOWED, "borderless": Window.MODE_FULLSCREEN, "exclusive": Window.MODE_EXCLUSIVE_FULLSCREEN}[mode]
		if mode == "window":
			var parts := String(preferences.values.resolution).split("x")
			get_window().size = Vector2i(int(parts[0]), int(parts[1]))
	_layout_dialogue()
	menu.update_skin(key)

func toggle_auto() -> void:
	auto_play = not auto_play
	fast_forward = false

func toggle_skip() -> void:
	if not _line_read and not preferences.values.skip_unread:
		menu.notify_user("遇到未读内容，已停止快进。可在「阅读播放」中允许快进未读。")
		return
	fast_forward = not fast_forward
	auto_play = false

func toggle_hidden() -> void:
	ui_hidden = not ui_hidden
	if ui_hidden:
		_hidden_state.assign([dialogue.visible, narration.visible, choice_scroll.visible])
		dialogue.hide()
		narration.hide()
		choice_scroll.hide()
	else:
		dialogue.visible = _hidden_state[0]
		narration.visible = _hidden_state[1]
		choice_scroll.visible = _hidden_state[2]
	chrome.visible = not ui_hidden
	paused = ui_hidden

func open_menu(page: String) -> void:
	if ui_hidden: toggle_hidden()
	if not menu.is_open: _capture_thumbnail()
	paused = true
	menu.open(page)

func close_menu() -> void:
	menu.close()
	replay_player.stop()
	paused = menu.is_open or _focus_paused

func _capture_thumbnail() -> void:
	if DisplayServer.get_name() == "headless": return
	var picture := get_viewport().get_texture().get_image()
	if picture == null or picture.is_empty(): return
	var bounds := stage_pixel_rect()
	bounds = bounds.intersection(Rect2i(Vector2i.ZERO, picture.get_size()))
	if bounds.has_area(): picture = picture.get_region(bounds)
	picture.resize(320, 180, Image.INTERPOLATE_LANCZOS)
	thumbnail = picture.save_jpg_to_buffer(0.8)

func stage_pixel_rect() -> Rect2i:
	# Screenshot textures use physical viewport pixels. canvas_items stretch can
	# differ from logical Control coordinates at non-default window resolutions.
	var transform := get_viewport().get_stretch_transform() * stage.get_global_transform_with_canvas()
	return Rect2i(transform * Rect2(Vector2.ZERO, stage.size))

func _lose_focus() -> void:
	if _initialized and preferences.values.pause_blur and not paused:
		_focus_paused = true
		paused = true

func _gain_focus() -> void:
	if _focus_paused:
		_focus_paused = false
		paused = menu.is_open or ui_hidden

func _input(event: InputEvent) -> void:
	if not _initialized: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if menu.dismiss_confirmation(): pass
			elif menu.is_open: menu.back()
			elif ui_hidden: toggle_hidden()
			else: open_menu("settings")
			get_viewport().set_input_as_handled()
			return
		if preferences.values.keyboard and not menu.is_open and not ui_hidden:
			var shortcuts := {KEY_A: toggle_auto, KEY_S: func(): open_menu("save"), KEY_L: func(): open_menu("load"), KEY_H: toggle_hidden, KEY_B: func(): open_menu("backlog"), KEY_M: func(): open_menu("flow"), KEY_CTRL: toggle_skip}
			if shortcuts.has(event.keycode):
				shortcuts[event.keycode].call()
				get_viewport().set_input_as_handled()
				return
	if ui_hidden and event is InputEventMouseButton and event.pressed:
		toggle_hidden()
		get_viewport().set_input_as_handled()
		return
	if menu.is_open or ui_hidden: return
	if event is InputEventKey and not preferences.values.keyboard: return
	super._input(event)

func _pointer_is_over_button() -> bool:
	var current: Node = get_viewport().gui_get_hovered_control()
	while current != null:
		if current is BaseButton or current is Range: return true
		current = current.get_parent()
	return false
