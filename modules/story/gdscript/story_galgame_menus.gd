class_name StoryGalgameMenus
extends Control
## Menu composition is independent of playback. Settings fields are generated
## from the validated schema; save/load share rendering but remain separate pages.

var presenter: StoryGalgamePresenter
var skin: StorySkin
var page := ""
var section_id := "text"
var slot_page := 0
var body: Control
var sheet: PanelContainer
var heading: Label
var preview: StoryDialogueBox
var rows: Dictionary = {}
var fields: Dictionary = {}
var confirmation: Control
var toast: PanelContainer
var _toast_generation := 0
var _preview_clock := 0.0
var _preview_fit: Callable
var _stage_focus: Dictionary = {}
var _sheet_focus: Dictionary = {}
var _opening: Tween

func configure(owner_presenter: StoryGalgamePresenter) -> void:
	presenter = owner_presenter
	skin = presenter.skin
	size = presenter.stage_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.25, 0.2, 0.26, 0.25)
	shade.size = size
	add_child(shade)
	sheet = PanelContainer.new()
	sheet.position = Vector2(26, 20)
	sheet.size = size - Vector2(52, 40)
	add_child(sheet)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	sheet.add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 18)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	heading = skin.label("设置", 28)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	header.add_child(skin.button("返回", presenter.close_menu, Vector2(104, 42), "back"))
	layout.add_child(HSeparator.new())
	body = Control.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(body)
	# Toast belongs to the stage, so playback notices do not require opening a menu.
	toast = PanelContainer.new()
	toast.position = Vector2(340, 80)
	toast.size = Vector2(600, 60)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	presenter.stage.add_child(toast)
	var message := Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_child(message)
	toast.hide()
	update_skin("")
	hide()

func open(target: String) -> void:
	if not visible:
		for node in [presenter.chrome, presenter.choice_scroll, presenter.dialogue, presenter.narration]:
			_suspend_focus(node, _stage_focus)
		get_viewport().gui_release_focus()
	page = target
	heading.text = {"settings": "设置", "save": "存档", "load": "读档", "backlog": "回顾", "flow": "流程图", "ending": "故事的余韵"}.get(page, page)
	_clear_body()
	show()
	if _opening != null: _opening.kill()
	modulate.a = 1.0
	if presenter.preferences.values.motion != "reduced":
		modulate.a = 0.0
		_opening = create_tween()
		_opening.tween_property(self, "modulate:a", 1.0, 0.16)
	match page:
		"settings": _settings()
		"save", "load": _slots()
		"backlog": _backlog()
		"flow":
			var graph := StoryFlowView.new()
			body.add_child(graph)
			graph.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			graph.configure(presenter, self)
		"ending": _ending()
	# First keyboard target is always on the new page, never a hidden choice.
	_focus_first.call_deferred(body)

func _clear_body() -> void:
	preview = null
	_preview_fit = Callable()
	rows.clear()
	fields.clear()
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()

func _focus_first(node: Node) -> bool:
	if not is_instance_valid(node) or not visible: return false
	for child in node.get_children():
		if child is BaseButton and child.is_visible_in_tree() and not child.disabled and child.focus_mode != Control.FOCUS_NONE:
			child.grab_focus()
			return true
		if _focus_first(child): return true
	return false

func _suspend_focus(node: Node, saved: Dictionary) -> void:
	if node is Control and node.focus_mode != Control.FOCUS_NONE:
		saved[node] = node.focus_mode
		node.focus_mode = Control.FOCUS_NONE
	for child in node.get_children(): _suspend_focus(child, saved)

func _restore_focus(saved: Dictionary) -> void:
	for node in saved:
		if is_instance_valid(node): node.focus_mode = saved[node]
	saved.clear()

func close() -> void:
	dismiss_confirmation()
	hide()
	_restore_focus(_stage_focus)
	get_viewport().gui_release_focus()

func update_skin(key: String) -> void:
	theme = skin.theme
	sheet.add_theme_stylebox_override("panel", StorySkin.box(skin.colors.paper, skin.colors.line, 20))
	toast.theme = skin.theme
	toast.add_theme_stylebox_override("panel", StorySkin.box(skin.colors.paper, skin.colors.line, 12, 16))
	if is_instance_valid(preview): preview.apply_skin(skin)
	if _preview_fit.is_valid(): _preview_fit.call_deferred()
	for field_key in rows:
		rows[field_key].visible = presenter.preferences.field_visible(fields[field_key])
	if visible and page == "settings" and key == "":
		# Reset replaces controls only after the button signal has returned.
		open.call_deferred("settings")
	if not presenter.preferences.last_error.is_empty(): notify_user(presenter.preferences.last_error)

func _settings() -> void:
	var split := HBoxContainer.new()
	body.add_child(split)
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 30)
	var tabs := VBoxContainer.new()
	tabs.custom_minimum_size.x = 185
	tabs.add_theme_constant_override("separation", 9)
	split.add_child(tabs)
	var active: Dictionary = {}
	for section in presenter.preferences.schema.sections:
		var button := skin.button(section.title, func():
			section_id = section.id
			open("settings"), Vector2(180, 52), section.get("icon", ""))
		button.toggle_mode = true
		button.button_pressed = section.id == section_id
		tabs.add_child(button)
		if section.id == section_id: active = section
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tabs.add_child(spacer)
	tabs.add_child(skin.button("重置本页", func():
		confirm("恢复默认设置？", "只重置当前分类，其他设置会保留。", func(): presenter.preferences.reset_section(section_id)), Vector2.ZERO, "restart"))
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	content.add_child(skin.label(String(active.get("title", "")), 22))
	if active.get("preview", false): _add_preview(content)
	for field in active.get("fields", []):
		_setting_row(content, field)
	if section_id == "sound":
		content.add_child(skin.label("试听", 20))
		var samples := HBoxContainer.new()
		content.add_child(samples)
		samples.add_child(skin.button("角色语音", _replay_current_voice, Vector2.ZERO, "voice"))
		samples.add_child(skin.button("界面音效", func():
			if presenter.effect_stream != null: presenter.effect_player.play()
			else: notify_user("当前故事未配置界面音效。"), Vector2.ZERO, "volume"))
	if section_id == "system":
		content.add_child(skin.label("快捷键", 20))
		var keys := skin.label("空格 / Enter / 左键：推进    Esc：返回\nA：自动    Ctrl：切换快进    H：隐藏\nS：存档    L：读档    B：回顾    M：流程图", 16, "muted")
		content.add_child(keys)
		content.add_child(skin.button("重新开始故事", func():
			confirm("重新开始？", "当前未保存的进度将丢失，存档与已读记录会保留。", func():
				presenter.archive.history.clear()
				presenter.archive.player.restart()
				presenter.close_menu()), Vector2.ZERO, "restart"))

func _add_preview(content: VBoxContainer) -> void:
	var frame := Control.new()
	frame.custom_minimum_size.y = 230
	frame.clip_contents = true
	content.add_child(frame)
	var world := Control.new()
	world.size = presenter.stage_size
	frame.add_child(world)
	var bg := presenter._texture(world, presenter.background.texture, Rect2(Vector2.ZERO, presenter.stage_size))
	bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	var character := presenter._texture(world, presenter.portrait.texture, Rect2(presenter.portrait.position, presenter.portrait.size))
	character.stretch_mode = presenter.portrait.stretch_mode
	preview = StoryDialogueBox.new()
	world.add_child(preview)
	var source := presenter.narration if presenter.narration.visible else presenter.dialogue
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
	_preview_fit = fit
	fit.call_deferred()
	_preview_clock = 0.0
	if section_id == "reading":
		content.add_child(skin.button("重播文字预览", func(): _preview_clock = 0.0, Vector2.ZERO, "restart"))

func _process(delta: float) -> void:
	if visible and page == "settings" and is_instance_valid(preview):
		preview.size = presenter.dialogue.size
		preview.position = presenter.dialogue.position
		if section_id == "reading" and not presenter.preferences.values.instant:
			_preview_clock += delta
			preview.text.visible_characters = int(_preview_clock * float(presenter.preferences.values.speed))
		else: preview.text.visible_characters = -1

func _setting_row(parent: VBoxContainer, field: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 46
	row.add_theme_constant_override("separation", 18)
	parent.add_child(row)
	rows[field.key] = row
	fields[field.key] = field
	row.visible = presenter.preferences.field_visible(field)
	var label := skin.label(field.label, 16)
	label.custom_minimum_size.x = 215
	row.add_child(label)
	var value: Variant = presenter.preferences.values[field.key]
	match String(field.type):
		"check":
			var toggle := CheckButton.new()
			toggle.button_pressed = value
			toggle.text = "开启" if value else "关闭"
			toggle.toggled.connect(func(enabled):
				toggle.text = "开启" if enabled else "关闭"
				presenter.preferences.set_value(field.key, enabled))
			row.add_child(toggle)
		"range":
			var slider := HSlider.new()
			slider.min_value = field.min
			slider.max_value = field.max
			slider.step = field.step
			slider.value = value
			slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(slider)
			var number := skin.label(str(value) + " " + field.get("unit", ""), 14, "muted")
			number.custom_minimum_size.x = 92
			row.add_child(number)
			slider.value_changed.connect(func(next):
				number.text = str(next) + " " + field.get("unit", "")
				presenter.preferences.set_value(field.key, next))
		"select", "palette":
			var select := OptionButton.new()
			select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var options: Dictionary = field.get("options", presenter.preferences.schema.palettes)
			for id in options:
				var title: String = options[id].label if options[id] is Dictionary else options[id]
				select.add_item(title)
				select.set_item_metadata(select.item_count - 1, id)
				if id == value: select.select(select.item_count - 1)
			select.item_selected.connect(func(index): presenter.preferences.set_value(field.key, select.get_item_metadata(index)))
			row.add_child(select)
		"color":
			var picker := ColorPickerButton.new()
			picker.color = Color(value)
			picker.edit_alpha = false
			picker.custom_minimum_size = Vector2(180, 32)
			picker.color_changed.connect(func(color): presenter.preferences.set_value(field.key, "#" + color.to_html(false)))
			row.add_child(picker)

func _slots() -> void:
	var layout := VBoxContainer.new()
	body.add_child(layout)
	layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 14)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	layout.add_child(grid)
	var per_page := int(presenter.preferences.schema.slots_per_page)
	for i in range(slot_page * per_page, mini((slot_page + 1) * per_page, presenter.archive.slot_count)):
		_slot_card(grid, i)
	var navigation := HBoxContainer.new()
	navigation.add_theme_constant_override("separation", 10)
	layout.add_child(navigation)
	for i in ceili(float(presenter.archive.slot_count) / per_page):
		var button := skin.button("%02d" % (i + 1), func():
			slot_page = i
			open(page), Vector2(58, 36))
		button.toggle_mode = true
		button.button_pressed = i == slot_page
		navigation.add_child(button)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	navigation.add_child(spacer)
	navigation.add_child(skin.label("%d 个栏位" % presenter.archive.slot_count, 14, "muted"))
	if page == "load":
		navigation.add_child(skin.button("读取自动存档", func():
			_request_load(func(): return presenter.archive.load_automatic()), Vector2.ZERO, "load"))

func _slot_card(grid: GridContainer, index: int) -> void:
	var slot := presenter.archive.read_slot(index)
	var button := skin.button("", func(): _slot_action(index))
	button.custom_minimum_size = Vector2(370, 220)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_EXPAND_FILL
	button.disabled = page == "load" and slot.status != "ready"
	grid.add_child(button)
	var content := VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(content)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 14
	content.offset_right = -14
	content.offset_top = 12
	content.offset_bottom = -12
	var title := skin.label("SLOT %02d" % (index + 1), 13, "accent")
	content.add_child(title)
	var image := TextureRect.new()
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.custom_minimum_size.y = 106
	image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(image)
	if slot.status == "ready":
		var metadata: Dictionary = slot.metadata
		var encoded := String(metadata.get("thumbnail", ""))
		if not encoded.is_empty():
			var picture := Image.new()
			if picture.load_jpg_from_buffer(Marshalls.base64_to_raw(encoded)) == OK: image.texture = ImageTexture.create_from_image(picture)
		var snippet := RichTextLabel.new()
		snippet.bbcode_enabled = true
		snippet.text = String(metadata.get("text", ""))
		var plain := snippet.get_parsed_text().replace("\n", " ")
		snippet.free()
		var text_label := skin.label(plain, 16)
		text_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		content.add_child(text_label)
		content.add_child(skin.label(String(metadata.get("time", "")), 12, "muted"))
	else:
		image.texture = presenter.backdrop
		image.modulate.a = 0.35
		content.add_child(skin.label("空白的故事页" if slot.status == "empty" else "存档已损坏", 16, "muted"))
		content.add_child(skin.label("点击保存此刻" if page == "save" else "暂无记录", 12, "muted"))
	_ignore_pointer(content)

func _ignore_pointer(node: Node) -> void:
	if node is Control: node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in node.get_children(): _ignore_pointer(child)

func _slot_action(index: int) -> void:
	if page == "load":
		_request_load(func(): return presenter.archive.load_slot(index))
		return
	var save := func():
		if presenter.archive.save_slot(index, presenter.thumbnail) == OK:
			open("save")
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

func confirm(title: String, message: String, action: Callable) -> void:
	dismiss_confirmation()
	_suspend_focus(sheet, _sheet_focus)
	confirmation = Control.new()
	confirmation.size = size
	add_child(confirmation)
	var shade := ColorRect.new()
	shade.color = Color(0.1, 0.08, 0.12, 0.48)
	shade.size = size
	confirmation.add_child(shade)
	var card := PanelContainer.new()
	card.position = Vector2(365, 235)
	card.size = Vector2(550, 225)
	card.add_theme_stylebox_override("panel", StorySkin.box(skin.colors.paper, skin.colors.line, 18, 28))
	confirmation.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 20)
	card.add_child(content)
	content.add_child(skin.label(title, 24))
	var text := skin.label(message, 16, "muted")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(text)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	content.add_child(buttons)
	var cancel := skin.button("取消", dismiss_confirmation, Vector2(110, 40), "close")
	buttons.add_child(cancel)
	buttons.add_child(skin.button("确定", func():
		dismiss_confirmation()
		action.call(), Vector2(110, 40), "check"))
	cancel.grab_focus()

func dismiss_confirmation() -> bool:
	if not is_instance_valid(confirmation): return false
	remove_child(confirmation)
	confirmation.queue_free()
	confirmation = null
	_restore_focus(_sheet_focus)
	return true

func notify_user(message: String) -> void:
	_toast_generation += 1
	var generation := _toast_generation
	(toast.get_child(0) as Label).text = message
	toast.show()
	await get_tree().create_timer(3.5).timeout
	if generation == _toast_generation: toast.hide()

func show_ending() -> void:
	presenter.paused = true
	open("ending")

func _ending() -> void:
	var center := CenterContainer.new()
	body.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 24)
	center.add_child(content)
	content.add_child(skin.label("这一页的故事，先写到这里。", 30))
	content.add_child(skin.label("每一次选择，都会留下不同的余韵。", 18, "muted"))
	content.add_child(skin.button("在流程图中回望故事", func(): open("flow"), Vector2.ZERO, "flow"))
	content.add_child(skin.button("读取存档", func(): open("load"), Vector2.ZERO, "load"))
