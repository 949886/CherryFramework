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
	var preview := presenter.menu.active_page.preview
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
