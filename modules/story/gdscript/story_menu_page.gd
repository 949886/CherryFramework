class_name StoryMenuPage
extends NavigationPage
## A mounted native game page. Cherry owns its route lifetime and focus when
## covered; local tabs and slot cards keep their nodes throughout that lifetime.

@export var slot_card_scene: PackedScene
## The shared shell has no page-specific controls. Derived scenes explicitly
## choose their content type, so opening a base scene never assumes settings.
@export var page := "shell"
@export var title := "菜单"
var menus: StoryGalgameMenus
var presenter: StoryGalgamePresenter
var skin: StorySkin
var body: Control
var sheet: PanelContainer
var heading: Label
var preview: StoryDialogueBox
var section_id := "text"
var slot_page := 0
var rows: Dictionary = {}
var fields: Dictionary = {}
var settings_tabs: TabContainer
var _tab_buttons: Dictionary = {}
var _section_pages: Dictionary = {}
var _preview_frames: Dictionary = {}
var _controls: Dictionary = {}
var _numbers: Dictionary = {}
var _previews: Dictionary = {}
var _preview_fits: Dictionary = {}
var _preview_clock := 0.0
var _slot_cards: Array[Dictionary] = []
var _slot_buttons: Array[Button] = []

func configure(owner_menus: StoryGalgameMenus) -> void:
	menus = owner_menus
	presenter = menus.presenter
	skin = presenter.skin

func _ready() -> void:
	build_content()

func build_content() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	sheet = $Sheet
	heading = $Sheet/Margin/Layout/Header/Heading
	heading.text = title
	var back_button: Button = $Sheet/Margin/Layout/Header/Back
	back_button.icon = skin.icon("back")
	back_button.pressed.connect(menus.back)
	body = $Sheet/Margin/Layout/Body
	match page:
		"settings": _settings()
		"slots", "save", "load": _slots()
		"backlog": _backlog()
		"flow":
			var graph := StoryFlowView.new()
			body.add_child(graph)
			graph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			graph.configure(presenter, menus)
		"ending": _ending()
	update_skin()

func on_navigation_entered(_previous: NavigationRoute, _reason: EnterReason) -> void:
	if page == "settings": _tab_buttons[section_id].grab_focus()
	else: _focus_first(body)

func on_navigation_revealed(_removed: NavigationRoute) -> void:
	# Covered pages are retained by Cherry. Refresh mutable save metadata only;
	# their tab, scroll, graph selection and keyboard focus remain intact.
	if page in ["save", "load"]: refresh_slots()

func _focus_first(node: Node) -> bool:
	for child in node.get_children():
		if child is BaseButton and child.is_visible_in_tree() and not child.disabled:
			child.grab_focus()
			return true
		if _focus_first(child): return true
	return false

func update_skin() -> void:
	theme = skin.theme
	skin.refresh_labels(self)

	for item in _previews.values(): item.apply_skin(skin)
	for fit in _preview_fits.values(): fit.call_deferred()
	for key in rows:
		var field: Dictionary = fields[key]
		rows[key].visible = presenter.preferences.field_visible(field)
		var control: Control = _controls[key]
		var value: Variant = presenter.preferences.values[key]
		if control is CheckButton:
			control.set_pressed_no_signal(value)
			control.text = "开启" if value else "关闭"
		elif control is Range:
			control.set_value_no_signal(value)
			_numbers[key].text = str(value) + " " + field.get("unit", "")
		elif control is OptionButton:
			for i in control.item_count:
				if control.get_item_metadata(i) == value: control.select(i)
		elif control is ColorPickerButton: control.color = Color(value)

func _settings() -> void:
	# The scene owns all fixed controls. Metadata binds their meaning, so names,
	# text, row layout and tab ordering remain editable without changing code.
	var categories: VBoxContainer = body.get_node("Split/Sidebar/Categories")
	settings_tabs = body.get_node("Split/Pages")
	var reset: Button = body.get_node("Split/Sidebar/Reset")
	reset.pressed.connect(func():
		confirm("恢复默认设置？", "只重置当前分类，其他设置会保留。", func(): presenter.preferences.reset_section(section_id)))
	var definitions: Dictionary = {}
	for section in presenter.preferences.schema.sections:
		for field in section.get("fields", []): definitions[field.key] = field
	for button in categories.get_children():
		if not button is Button or not button.has_meta("section_id"): continue
		var identity := String(button.get_meta("section_id"))
		_tab_buttons[identity] = button
		button.pressed.connect(select_section.bind(identity))
	for scroll in settings_tabs.get_children():
		if not scroll is ScrollContainer or not scroll.has_meta("section_id"): continue
		var identity := String(scroll.get_meta("section_id"))
		_section_pages[identity] = scroll
		for node in scroll.find_children("*", "", true, false):
			if node.has_meta("setting_key"):
				var key := String(node.get_meta("setting_key"))
				assert(definitions.has(key), "Unknown settings field: " + key)
				_bind_setting(node, definitions[key])
			elif node.has_meta("dialogue_preview"):
				_preview_frames[identity] = node
	var actions := {
		"replay_preview": func(): _preview_clock = 0.0,
		"replay_voice": _replay_current_voice,
		"replay_effect": _replay_effect,
		"restart_story": _restart_story,
	}
	for button in settings_tabs.find_children("*", "Button", true, false):
		if button.has_meta("action"):
			button.pressed.connect(actions[String(button.get_meta("action"))])
	select_section(menus.section_id)

func select_section(identity: String) -> void:
	if not _tab_buttons.has(identity) or not _section_pages.has(identity): return
	section_id = identity
	menus.section_id = identity
	for key in _tab_buttons:
		_tab_buttons[key].set_pressed_no_signal(key == identity)
	# Read the scene's actual order, independent of JSON or category ordering.
	settings_tabs.current_tab = _section_pages[identity].get_index()
	if _preview_frames.has(identity) and not _previews.has(identity):
		_add_preview(_preview_frames[identity], identity)
	preview = _previews.get(identity)
	if is_inside_tree() and route.state == NavigationRoute.State.ACTIVE:
		_tab_buttons[identity].grab_focus()

func _replay_effect() -> void:
	if presenter.effect_stream != null: presenter.effect_player.play()
	else: notify_user("当前故事未配置界面音效。")

func _restart_story() -> void:
	confirm("重新开始？", "当前未保存的进度将丢失，存档与已读记录会保留。", func():
		presenter.archive.history.clear()
		presenter.archive.player.restart()
		presenter.close_menu())

func confirm(caption: String, message: String, action: Callable) -> void:
	menus.confirm(caption, message, action)

func notify_user(message: String) -> void:
	menus.notify_user(message)

func _add_preview(frame: Control, identity: String) -> void:
	# Only live story content is instantiated. The preview frame, settings rows
	# and actions already exist in the scene before this page enters the tree.
	var world: Control = frame.get_node("World")
	world.size = presenter.stage_size
	var bg: TextureRect = world.get_node("Background")
	bg.texture = presenter.background.texture
	bg.stretch_mode = presenter.background.stretch_mode
	var character: TextureRect = world.get_node("Portrait")
	character.texture = presenter.portrait.texture
	character.position = presenter.portrait.position
	character.size = presenter.portrait.size
	character.stretch_mode = presenter.portrait.stretch_mode
	var source := presenter.narration if presenter.narration.visible else presenter.dialogue
	preview = source.duplicate() as StoryDialogueBox
	world.add_child(preview)
	preview.set_anchors_preset(Control.PRESET_TOP_LEFT)
	preview.show()
	preview.position = source.position
	preview.size = source.size
	preview.narration = source.narration
	preview.text.text = source.text.text
	preview.speaker.text = source.speaker.text
	preview.roman.text = source.roman.text
	preview.voice.text = source.voice.text
	preview.apply_skin(skin)
	# Render the same virtual stage and crop the preview card, preserving glyph
	# metrics, line wrapping and panel geometry exactly at the chosen scale.
	var fit := func():
		var factor := frame.size.x / presenter.stage_size.x
		world.scale = Vector2.ONE * factor
		world.position.y = -(source.position.y - 100) * factor
		frame.custom_minimum_size.y = (source.size.y + 140) * factor
	frame.resized.connect(fit)
	_preview_fits[identity] = fit
	_previews[identity] = preview
	fit.call_deferred()
	_preview_clock = 0.0

func _process(delta: float) -> void:
	if is_visible_in_tree() and page == "settings" and is_instance_valid(preview):
		preview.size = presenter.dialogue.size
		preview.position = presenter.dialogue.position
		if section_id == "reading" and not presenter.preferences.values.instant:
			_preview_clock += delta
			preview.text.visible_characters = int(_preview_clock * float(presenter.preferences.values.speed))
		else: preview.text.visible_characters = -1

func _bind_setting(row: Control, field: Dictionary) -> void:
	rows[field.key] = row
	fields[field.key] = field
	var control: Control
	for node in row.find_children("*", "Control", true, false):
		if node.has_meta("setting_control"): control = node
		if node.has_meta("setting_number"): _numbers[field.key] = node
	assert(control != null, "Settings row needs a setting_control: " + String(field.key))
	_controls[field.key] = control
	# Defaults, constraints, choices and visibility come from the preference
	# schema. Scene values are design-time samples; saved player values win at
	# runtime. Do not replace the scene's labels, layout or control instances.
	match String(field.type):
		"check":
			var toggle := control as CheckButton
			toggle.toggled.connect(func(enabled): presenter.preferences.set_value(field.key, enabled))
		"range":
			var slider := control as HSlider
			slider.min_value = field.min
			slider.max_value = field.max
			slider.step = field.step
			slider.value_changed.connect(func(next): presenter.preferences.set_value(field.key, next))
		"select", "palette":
			var select := control as OptionButton
			select.clear()
			var options: Dictionary = field.get("options", presenter.preferences.schema.palettes)
			for id in options:
				var caption: String = options[id].label if options[id] is Dictionary else options[id]
				select.add_item(caption)
				select.set_item_metadata(select.item_count - 1, id)
			select.item_selected.connect(func(index): presenter.preferences.set_value(field.key, select.get_item_metadata(index)))
		"color":
			var picker := control as ColorPickerButton
			picker.color_changed.connect(func(color): presenter.preferences.set_value(field.key, "#" + color.to_html(false)))

func _slots() -> void:
	var grid: GridContainer = body.get_node("Layout/Grid")
	# One scene per reusable card; only slot data and page count are dynamic.
	for index in int(presenter.preferences.schema.slots_per_page):
		var button := slot_card_scene.instantiate() as Button
		# The standalone template carries an editor theme. Once mounted, inherit
		# the page's live theme so every button state follows palette changes,
		# including while this page is covered. Local style overrides stay intact.
		button.theme = null
		button.pressed.connect(func(): _slot_action(int(button.get_meta("slot_index"))))
		grid.add_child(button)
		_slot_cards.append({"button": button, "title": button.get_node("Content/Title"),
			"image": button.get_node("Content/Image"), "text": button.get_node("Content/Text"),
			"stamp": button.get_node("Content/Stamp")})
	var navigation: HBoxContainer = body.get_node("Layout/Navigation")
	var group := ButtonGroup.new()
	for index in ceili(float(presenter.archive.slot_count) / _slot_cards.size()):
		var button := skin.button("%02d" % (index + 1), func(): select_slot_page(index), Vector2(58, 36))
		button.toggle_mode = true
		button.button_group = group
		navigation.get_node("Pages").add_child(button)
		_slot_buttons.append(button)
	(navigation.get_node("Count") as Label).text = "%d 个栏位" % presenter.archive.slot_count
	var automatic: Button = navigation.get_node("Automatic")
	automatic.visible = page == "load"
	automatic.icon = skin.icon("load")
	automatic.pressed.connect(func():
		_request_load(func(): return presenter.archive.load_automatic()))
	select_slot_page(menus.slot_page)

func select_slot_page(index: int) -> void:
	if _slot_cards.is_empty(): return
	slot_page = clampi(index, 0, _slot_buttons.size() - 1)
	menus.slot_page = slot_page
	for i in _slot_buttons.size(): _slot_buttons[i].set_pressed_no_signal(i == slot_page)
	refresh_slots()

func refresh_slots() -> void:
	# Bind new slot data to the existing six card nodes. Focus, hover and grid
	# geometry survive pagination; no scene subtree is torn down or faded out.
	for offset in _slot_cards.size():
		var card: Dictionary = _slot_cards[offset]
		var index := slot_page * _slot_cards.size() + offset
		card.button.visible = index < presenter.archive.slot_count
		if not card.button.visible: continue
		card.button.set_meta("slot_index", index)
		var slot := presenter.archive.read_slot(index)
		card.button.disabled = page == "load" and slot.status != "ready"
		card.title.text = "SLOT %02d" % (index + 1)
		card.image.texture = presenter.backdrop
		card.image.modulate.a = 1.0 if slot.status == "ready" else 0.35
		if slot.status == "ready":
			var metadata: Dictionary = slot.metadata
			var encoded := String(metadata.get("thumbnail", ""))
			if not encoded.is_empty():
				var picture := Image.new()
				if picture.load_jpg_from_buffer(Marshalls.base64_to_raw(encoded)) == OK:
					card.image.texture = ImageTexture.create_from_image(picture)
			var snippet := RichTextLabel.new()
			snippet.bbcode_enabled = true
			snippet.text = String(metadata.get("text", ""))
			card.text.text = snippet.get_parsed_text().replace("\n", " ")
			snippet.free()
			card.stamp.text = String(metadata.get("time", ""))
		else:
			card.text.text = "空白的故事页" if slot.status == "empty" else "存档已损坏"
			card.stamp.text = "点击保存此刻" if page == "save" else "暂无记录"

func _slot_action(index: int) -> void:
	if page == "load":
		_request_load(func(): return presenter.archive.load_slot(index))
		return
	var save := func():
		if presenter.archive.save_slot(index, presenter.thumbnail) == OK:
			refresh_slots()
			notify_user("已保存到栏位 %02d" % (index + 1))
	if presenter.archive.read_slot(index).status != "empty" and presenter.preferences.values.confirm_overwrite:
		confirm("覆盖栏位 %02d？" % (index + 1), "这个栏位原有的存档将被当前进度替换。", save)
	else: save.call()

func _request_load(action: Callable) -> void:
	var load_action := func():
		if action.call() == OK: presenter.close_menu()
	if presenter.preferences.values.confirm_load:
		confirm("读取这份存档？", "当前未保存的进度将丢失。", load_action)
	else: load_action.call()

func _backlog() -> void:
	var scroll := ScrollContainer.new()
	body.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var timeline := VBoxContainer.new()
	timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timeline.add_theme_constant_override("separation", 16)
	scroll.add_child(timeline)
	if presenter.archive.history.is_empty(): timeline.add_child(skin.label("故事才刚刚开始，还没有回顾记录。", 20, "muted"))
	for record in presenter.archive.history:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", StorySkin.box(skin.colors.soft if record.kind == "choice" else skin.colors.paper, skin.colors.line, 12, 20))
		timeline.add_child(card)
		var content := VBoxContainer.new()
		content.add_theme_constant_override("separation", 10)
		card.add_child(content)
		var row := HBoxContainer.new()
		content.add_child(row)
		if record.kind == "choice": row.add_child(skin.icon_view("flow", 17, "accent"))
		var name_label := skin.label(record.speaker, 17, "accent")
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_label)
		if not record.voice.is_empty():
			row.add_child(skin.button("重播语音", func(): _play_voice(record.voice), Vector2.ZERO, "play"))
		var text := RichTextLabel.new()
		text.bbcode_enabled = true
		text.fit_content = true
		text.scroll_active = false
		text.text = record.text
		skin.style_body(text)
		content.add_child(text)
	_scroll_end.call_deferred(scroll)

func _scroll_end(scroll: ScrollContainer) -> void:
	await get_tree().process_frame
	if is_instance_valid(scroll): scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)

func _play_voice(path: String) -> void:
	if ResourceLoader.exists(path) and load(path) is AudioStream:
		presenter.replay_player.stream = load(path)
		presenter.replay_player.play()
	else: notify_user("这句对白的语音资源暂不可用。")

func _replay_current_voice() -> void:
	var stream := presenter.audio_player.stream
	if stream != null:
		presenter.replay_player.stream = stream
		presenter.replay_player.play()
	else: notify_user("当前对白没有语音。")

func _ending() -> void:
	var center := CenterContainer.new()
	body.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 24)
	center.add_child(content)
	content.add_child(skin.label("这一页的故事，先写到这里。", 30))
	content.add_child(skin.label("每一次选择，都会留下不同的余韵。", 18, "muted"))
	content.add_child(skin.button("在流程图中回望故事", func(): menus.open("flow"), Vector2.ZERO, "flow"))
	content.add_child(skin.button("读取存档", func(): menus.open("load"), Vector2.ZERO, "load"))
