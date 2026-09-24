class_name StoryGalgamePresenter
extends StoryPresenter
## Native galgame shell. The VM owns execution; this class owns presentation,
## input and the single virtual stage shared by gameplay and all menu pages.

@export var stage_size := Vector2(1280, 720)
@export var save_directory := "user://cherry_galgame"
@export_file("*.json") var catalog_path := ""
@export var backdrop: Texture2D
@export var music_stream: AudioStream
@export var effect_stream: AudioStream
@export var game_title := "Cherry Story"
@export var footer_caption := "CHERRY STORY / 黄昏的问候"
var preferences := StoryPreferences.new()
var archive := StoryArchive.new()
var library := StoryLibrary.new()
var skin: StorySkin
var stage: Control
var dialogue: StoryDialogueBox
var narration: StoryDialogueBox
var choice_scroll: ScrollContainer
var chrome: Control
var menu: StoryGalgameMenus
var music_player: AudioStreamPlayer
var effect_player: AudioStreamPlayer
var replay_player: AudioStreamPlayer
var footer_buttons: Dictionary = {}
var location_label: Label
var thumbnail := PackedByteArray()
var ui_hidden := false
var _initialized := false
var _line_read := false
var _focus_paused := false
var _hidden_state: Array[bool] = []

func _ready() -> void:
	preferences.path = save_directory.path_join("settings.cfg")
	preferences.load_settings()
	skin = StorySkin.new(preferences)
	var root := get_node(".") as Control
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bars := ColorRect.new()
	bars.color = Color("17151c")
	bars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bars)
	bars.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stage = Control.new()
	stage.size = stage_size
	stage.clip_contents = true
	root.add_child(stage)
	background = _texture(stage, backdrop, Rect2(Vector2.ZERO, stage_size))
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	portrait = _texture(stage, null, Rect2(12, 36, 614, 1044))
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dialogue = StoryDialogueBox.new()
	stage.add_child(dialogue)
	dialogue_panel = dialogue
	dialogue_text = dialogue.text
	speaker_label = dialogue.speaker
	narration = StoryDialogueBox.new()
	narration.narration = true
	stage.add_child(narration)
	article_panel = narration
	article_text = narration.text
	narration.hide()
	choice_scroll = ScrollContainer.new()
	choice_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	stage.add_child(choice_scroll)
	choices_panel = VBoxContainer.new()
	choices_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	choices_panel.add_theme_constant_override("separation", 12)
	choice_scroll.add_child(choices_panel)
	choices_panel.hide()
	popup_layer = ColorRect.new()
	popup_layer.color = Color(0.08, 0.06, 0.09, 0.82)
	popup_layer.size = stage_size
	popup_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(popup_layer)
	popup_texture = _texture(popup_layer, null, Rect2(140, 80, 1000, 520))
	popup_texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	popup_layer.hide()
	for id in ["Voice", "Music", "Effects"]:
		if AudioServer.get_bus_index(id) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, id)
	audio_player = _audio("Voice")
	replay_player = _audio("Voice")
	music_player = _audio("Music")
	effect_player = _audio("Effects")
	music_player.stream = music_stream
	music_player.finished.connect(func():
		if music_player.stream != null: music_player.play())
	if music_stream != null: music_player.play()
	effect_player.stream = effect_stream
	_build_chrome()
	menu = StoryGalgameMenus.new()
	stage.add_child(menu)
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

func _audio(bus_name: String) -> AudioStreamPlayer:
	var result := AudioStreamPlayer.new()
	result.bus = bus_name
	add_child(result)
	return result

func _build_chrome() -> void:
	chrome = Control.new()
	chrome.size = stage_size
	chrome.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(chrome)
	var brand := skin.label("♧  " + game_title, 24)
	brand.position = Vector2(32, 24)
	chrome.add_child(brand)
	location_label = skin.label("黄昏 / 客厅", 14, "muted")
	location_label.position = Vector2(990, 30)
	location_label.size.x = 258
	location_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	chrome.add_child(location_label)
	var caption := skin.label(footer_caption, 11, "muted")
	caption.position = Vector2(44, 687)
	chrome.add_child(caption)
	var footer := HBoxContainer.new()
	footer.position = Vector2(522, 678)
	footer.add_theme_constant_override("separation", 3)
	chrome.add_child(footer)
	var actions := [
		["backlog", "◷ 回顾", func(): open_menu("backlog")],
		["auto", "▷ 自动", toggle_auto], ["save", "♧ 存档", func(): open_menu("save")],
		["load", "▱ 读档", func(): open_menu("load")], ["hide", "◉ 隐藏", toggle_hidden],
		["flow", "◇ 流程图", func(): open_menu("flow")], ["skip", "▹▹ 快进", toggle_skip],
		["settings", "⚙ 设置", func(): open_menu("settings")],
	]
	for action in actions:
		var button := skin.button(action[1], action[2], Vector2(83, 34))
		button.flat = true
		button.add_theme_font_size_override("font_size", 14)
		footer.add_child(button)
		footer_buttons[action[0]] = button

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
	# The choice stack shares the dialogue's anchor, not a percentage of the
	# viewport. Changing the window aspect can only add letterbox margins.
	var height := maxf(185.0, float(preferences.values.font_size) * float(preferences.values.line_height) * 2 + 102)
	for panel in [dialogue, narration]:
		panel.position = Vector2(42, stage_size.y - 54 - height)
		panel.size = Vector2(stage_size.x - 84, height)
	var count := choices_panel.get_child_count()
	var stack_height := minf(count * 60.0 + maxi(0, count - 1) * 12.0, dialogue.position.y - 122)
	choice_scroll.position = Vector2(stage_size.x * 0.5, dialogue.position.y - 28 - stack_height)
	choice_scroll.size = Vector2(stage_size.x * 0.5 - 60, stack_height)
	choice_scroll.visible = choices_panel.visible and not ui_hidden

func _begin(mode: String, payload: Dictionary) -> int:
	if mode in ["dialogue", "narration"] and not preferences.values.keep_voice and _pending_state == null:
		audio_player.stop()
	var token := super._begin(mode, payload)
	if mode == "dialogue":
		for character in characters:
			if character.display_name == speaker_label.text:
				dialogue.roman.text = String(character.id).to_upper()
				dialogue.voice.text = "▥  " + dialogue.roman.text
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
	super._build_choices(payload)
	for index in choices_panel.get_child_count():
		var button := choices_panel.get_child(index) as Button
		button.text = "%02d    %s    ›" % [index + 1, button.text]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 60)
		button.add_theme_font_size_override("font_size", 18)
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _choose(index: int, token: int) -> void:
	if token != _cancel_token or not _active or paused: return
	var options: Array = _state.payload.get("options", [])
	if index < 0 or index >= options.size(): return
	archive.record_choice(String(options[index].get("text", "")))
	if effect_stream != null: effect_player.play()
	super._choose(index, token)
	choice_scroll.hide()

func advance_time(delta: float) -> void:
	if not _initialized: return
	# Keep typewriter and command timing intact; only suspend automatic advance
	# at a finished line while speech is playing. A deliberate click still wins.
	var hold_auto: bool = auto_play and preferences.values.wait_voice and audio_player.playing and _state.phase == "end" and not _advance_pressed
	if hold_auto:
		auto_play = false
	super.advance_time(delta)
	if hold_auto: auto_play = true
	var duck: bool = preferences.values.duck_music and (audio_player.playing or replay_player.playing)
	music_player.volume_db = -10.0 if duck else 0.0
	footer_buttons.auto.text = "Ⅱ 自动" if auto_play else "▷ 自动"
	footer_buttons.skip.text = "Ⅱ 快进" if fast_forward else "▹▹ 快进"

func _settings_changed(key: String) -> void:
	if not _initialized: return
	skin.rebuild()
	stage.theme = skin.theme
	skin.refresh_labels(stage)
	dialogue.apply_skin(skin)
	narration.apply_skin(skin)
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
	_capture_thumbnail()
	paused = true
	menu.open(page)

func close_menu() -> void:
	menu.close()
	replay_player.stop()
	paused = _focus_paused

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
		paused = menu.visible or ui_hidden

func _input(event: InputEvent) -> void:
	if not _initialized: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			if menu.dismiss_confirmation(): pass
			elif menu.visible: close_menu()
			elif ui_hidden: toggle_hidden()
			else: open_menu("settings")
			get_viewport().set_input_as_handled()
			return
		if preferences.values.keyboard and not menu.visible and not ui_hidden:
			var shortcuts := {KEY_A: toggle_auto, KEY_S: func(): open_menu("save"), KEY_L: func(): open_menu("load"), KEY_H: toggle_hidden, KEY_B: func(): open_menu("backlog"), KEY_M: func(): open_menu("flow"), KEY_CTRL: toggle_skip}
			if shortcuts.has(event.keycode):
				shortcuts[event.keycode].call()
				get_viewport().set_input_as_handled()
				return
	if ui_hidden and event is InputEventMouseButton and event.pressed:
		toggle_hidden()
		get_viewport().set_input_as_handled()
		return
	if menu.visible or ui_hidden: return
	if event is InputEventKey and not preferences.values.keyboard: return
	super._input(event)

func _pointer_is_over_button() -> bool:
	var current: Node = get_viewport().gui_get_hovered_control()
	while current != null:
		if current is BaseButton or current is Range: return true
		current = current.get_parent()
	return false
