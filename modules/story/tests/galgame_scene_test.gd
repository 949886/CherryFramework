extends SceneTree
## Exercise the reusable scene independently of the demo wrapper. Serialize
## editor-like overrides before mounting, then check they survive settings,
## layout, Cherry route reparenting and the actual settings preview.

var checks := 0
var failures := 0
var module_root := (get_script() as Script).resource_path.get_base_dir().get_base_dir()

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func settle() -> void:
	for frame in range(4): await process_frame

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	var packed := load(module_root.path_join("scenes/galgame_presenter.tscn")) as PackedScene
	var authored := packed.instantiate() as StoryGalgamePresenter
	check(authored.is_configured(), "base presenter view references exist before ready")
	check(authored.backdrop == null and authored.characters.is_empty() and authored.catalog_path.is_empty(), "reusable scene does not include demo content")
	check(authored.menu.navigator != null and authored.menu.toast.get_child_count() == 1, "navigator and toast are authored nodes")
	check(authored.dialogue.text != null and authored.dialogue.speaker != null, "dialogue internals are editable scene nodes")
	check(authored.footer.get_child_count() == 8, "footer buttons exist in the editor scene tree")
	authored.dialogue.offset_left = 80
	authored.dialogue.offset_right = -96
	authored.dialogue.offset_top = -316
	authored.dialogue.offset_bottom = -66
	authored.choice_scroll.offset_left = 32
	authored.choice_scroll.offset_right = -80
	authored.choice_gap = 36
	authored.dialogue.nameplate.position.x = 48
	authored.dialogue.text.get_parent().get_parent().add_theme_constant_override("margin_left", 48)
	var style := authored.dialogue.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.corner_radius_top_left = 26
	authored.dialogue.add_theme_stylebox_override("panel", style)
	var custom_choice := authored.choice_scene.instantiate() as StoryChoiceButton
	custom_choice.custom_minimum_size.y = 84
	custom_choice.add_theme_font_size_override("font_size", 20)
	var choice_template := PackedScene.new()
	check(choice_template.pack(custom_choice) == OK, "custom choice template serializes")
	custom_choice.free()
	authored.choice_scene = choice_template
	var customized := PackedScene.new()
	check(customized.pack(authored) == OK, "presenter layout overrides serialize")
	authored.free()
	var presenter := customized.instantiate() as StoryGalgamePresenter
	presenter.save_directory = "user://galgame_scene_test_%d" % OS.get_process_id()
	_customize_settings(presenter)
	var untouched := packed.instantiate() as StoryGalgamePresenter
	check(untouched.dialogue.offset_left == 42 and untouched.dialogue.nameplate.position.x == 26, "base scene unchanged by instance edits")
	check(untouched.dialogue.glass.material != presenter.dialogue.glass.material, "glass material is local to each instance")
	untouched.free()
	var host := Control.new()
	root.add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	host.add_child(presenter)
	# A fresh player uses the scene via the normal StoryPresentation interface;
	# no galgame_demo script, catalog or special bootstrap is required.
	var player := StoryPlayer.new()
	player.story = load(module_root.path_join("examples/galgame/entry.tres"))
	player.presenter = presenter
	player.locale = "zh-CN"
	host.add_child(player)
	await settle()
	presenter.preferences.set_value("instant", true)
	presenter.preferences.set_value("motion", "reduced")
	check(player.is_playing and presenter.archive.player == player, "standalone presenter binds a fresh StoryPlayer")
	check(presenter.menu.navigator.first_route.page.is_ancestor_of(presenter.game_view), "authored GameView is retained under Cherry root route")
	check(presenter.dialogue.offset_left == 80 and presenter.dialogue.offset_right == -96 and presenter.dialogue.offset_bottom == -66, "ready preserves authored margins")
	check(presenter.dialogue.size.y == 250, "authored panel height is the minimum")
	presenter.preferences.set_value("font_size", 36)
	presenter.preferences.set_value("line_height", 2.2)
	await settle()
	check(presenter.dialogue.size.y > 250 and presenter.dialogue.offset_bottom == -66, "large text grows upward from the authored bottom")
	presenter.preferences.set_value("font_size", 23)
	presenter.preferences.set_value("line_height", 1.5)
	check(presenter.dialogue.size.y == 250, "smaller text returns to the authored minimum height")
	for step in range(20):
		if presenter._state.mode == "choice": break
		presenter.advance_time(5)
		presenter.advance()
		presenter.advance_time(0)
		await settle()
	check(presenter.choices_panel.get_child_count() == 3, "fresh player reaches real choice data")
	for button in presenter.choices_panel.get_children():
		check(button.custom_minimum_size.y == 84 and button.get_theme_font_size("font_size") == 20, "dynamic option uses customized scene")
	check(is_equal_approx(presenter.choices_panel.get_combined_minimum_size().y, 3 * 84 + 2 * 12), "choice stack measures actual template dimensions")
	check(presenter.choice_scroll.size.y < presenter.choices_panel.size.y and presenter.choice_scroll.position.y >= presenter.choice_top_margin, "tall customized choices scroll within available space")
	for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1200)]:
		root.size = dimensions
		await settle()
		check(presenter.dialogue.offset_left == 80 and presenter.choice_scroll.offset_right == -80, "resizing preserves authored horizontal layout")
		check(is_equal_approx(presenter.dialogue.position.y - presenter.choice_scroll.get_rect().end.y, 36), "custom choice gap follows dialogue across resolutions")
	presenter.preferences.set_value("glass", true)
	presenter.preferences.set_value("palette", "mint")
	check(presenter.dialogue.get_theme_stylebox("panel").corner_radius_top_left == 26, "palette and glass preserve authored corners")
	presenter.open_menu("settings")
	await settle()
	var settings := presenter.menu.active_page
	check(settings.rows.size() == presenter.preferences.fields().size(), "all authored fields bind before visiting other tabs")
	check(settings.rows.font_size.name == "CustomSize" and settings.rows.font_size.get_node("Label").text == "定制字号", "authored row name and label survive runtime binding")
	check(settings._controls.font_size.name == "CustomSlider" and settings.rows.font_size.get_theme_constant("separation") == 27, "custom control names and row layout remain intact")
	check(settings._tab_buttons.text.name == "CustomCategory" and settings._tab_buttons.text.text == "定制文字", "category labels and names remain scene owned")
	check(settings.settings_tabs.current_tab == 1, "initial section follows metadata after scene tabs reorder")
	var size_control: HSlider = settings._controls.font_size
	size_control.value = 29
	check(presenter.preferences.values.font_size == 29 and settings._numbers.font_size.text == str(presenter.preferences.values.font_size) + " px", "authored slider updates preferences and value label")
	presenter.preferences.reset_section("text")
	check(size_control.value == 23 and settings._controls.font_size == size_control, "reset updates existing authored slider")
	settings._tab_buttons.display.pressed.emit()
	check(settings.settings_tabs.current_tab == 0, "selection uses authored tab order instead of schema order")
	var glass_control: CheckButton = settings._controls.glass
	glass_control.button_pressed = false
	check(not presenter.preferences.values.glass and not settings.rows.glass_blur.visible, "authored checkbox hides conditional settings")
	glass_control.button_pressed = true
	check(presenter.preferences.values.glass and settings.rows.glass_blur.visible, "authored checkbox reveals conditional settings")
	var palette_control: OptionButton = settings._controls.palette
	palette_control.select(0)
	palette_control.item_selected.emit(0)
	check(presenter.preferences.values.palette == palette_control.get_item_metadata(0), "authored selector writes schema option identity")
	settings.select_section("text")
	settings._controls.theme_text.button_pressed = false
	check(settings.rows.text_color.visible, "custom text color row follows authored toggle")
	var color_control: ColorPickerButton = settings._controls.text_color
	color_control.color = Color("#123456")
	color_control.color_changed.emit(color_control.color)
	check(presenter.preferences.values.text_color == "#123456", "authored color picker writes preferences")
	presenter.preferences.reset_section("text")
	await settle()
	var preview := settings.preview
	check(preview.nameplate.position.x == 48, "preview preserves authored nameplate placement")
	check(preview.text.get_parent().get_parent().get_theme_constant("margin_left") == 48, "preview preserves authored text inset")
	check(preview.size == presenter.dialogue.size and preview.text.text == presenter.dialogue.text.text, "preview reproduces actual dialogue geometry and text")
	check(preview.glass.material != presenter.dialogue.glass.material and preview.text != presenter.dialogue.text, "preview state and shader stay independent of gameplay")
	preview.text.text = "预览独立"
	check(presenter.dialogue.text.text != preview.text.text, "preview edits cannot mutate live text")
	player.stop()
	host.queue_free()
	await settle()
	print("Galgame scene reuse: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)

func _customize_settings(presenter: StoryGalgamePresenter) -> void:
	var packed := load(module_root.path_join("scenes/galgame/settings.tscn")) as PackedScene
	check(packed.get_state().get_base_scene_state() == null, "settings is an independent scene without inherited page state")
	var view := packed.instantiate() as StoryMenuPage
	var split := view.get_node("Sheet/Margin/Layout/Body/Split")
	var categories := split.get_node("Sidebar/Categories")
	var pages := split.get_node("Pages")
	var schema: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(module_root.path_join("resources/galgame_settings.json")))
	check(categories.get_child_count() == schema.sections.size() and pages.get_child_count() == schema.sections.size(), "all sidebar categories and pages exist before ready")
	var authored_rows := {}
	for node in pages.find_children("*", "", true, false):
		if node.has_meta("setting_key"): authored_rows[node.get_meta("setting_key")] = node
	for section in schema.sections:
		for field in section.fields:
			check(authored_rows.has(field.key) and authored_rows[field.key].owner == view, "editable settings row exists before ready: " + field.key)
		var scroll: Node
		for child in pages.get_children():
			if child.get_meta("section_id") == section.id: scroll = child
		var frames := 0
		for child in scroll.find_children("*", "", true, false):
			if child.has_meta("dialogue_preview"): frames += 1
		check(frames == int(section.preview), "authored preview only appears in relevant sections: " + section.id)
	var category: Button = categories.get_child(0)
	category.name = "CustomCategory"
	category.text = "定制文字"
	var row: HBoxContainer = authored_rows.font_size
	row.name = "CustomSize"
	row.get_node("Label").text = "定制字号"
	row.get_node("Value").name = "CustomSlider"
	row.add_theme_constant_override("separation", 27)
	pages.move_child(pages.get_node("Display"), 0)
	var custom := PackedScene.new()
	check(custom.pack(view) == OK, "independent settings customization serializes")
	view.free()
	# Override the route's scene only. Cherry still configures, mounts and
	# navigates this customized page through the production code path.
	var catalog := presenter.menu.page_catalog.duplicate()
	var definitions: Dictionary = catalog.get_meta("pages").duplicate()
	var definition := (definitions.settings as PageDefinition).duplicate() as PageDefinition
	definition.scene = custom
	definitions.settings = definition
	catalog.set_meta("pages", definitions)
	presenter.menu.page_catalog = catalog
