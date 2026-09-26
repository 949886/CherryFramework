extends SceneTree
## Exercises the real native scene in an isolated user directory. Pass --render
## as a user argument in a windowed run to also capture rendered page artifacts.

var checks := 0
var failures := 0
var module_root := (get_script() as Script).resource_path.get_base_dir().get_base_dir()
var presenter: StoryGalgamePresenter
var scene: Control

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func settle() -> void:
	for i in range(4): await process_frame

func capture(name: String) -> void:
	await settle()
	if "--render" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://" + name + ".png")
	print("RENDER " + ProjectSettings.globalize_path("user://" + name + ".png"))

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	scene = load(module_root.path_join("examples/galgame_demo.tscn")).instantiate()
	presenter = scene.get_node("Presenter")
	presenter.save_directory = "user://galgame_ui_test_%d" % OS.get_process_id()
	root.add_child(scene)
	await settle()
	presenter.preferences.set_value("instant", true)
	presenter.preferences.set_value("motion", "reduced")
	presenter.advance_time(5)
	check(presenter.is_configured(), "native presenter configured")
	check(presenter.archive.player.is_playing, "actual story running")
	check(presenter.library.nodes.size() == 8, "eight real script files")
	check(presenter.library.edges.size() == 9, "branch and rejoin edges")
	check(presenter.library.errors.is_empty(), "all script files compile")
	for button in presenter.footer_buttons.values():
		check(button.icon != null and button.icon.get_width() > 0, "footer icon loads without a font glyph: " + button.text)
		check(button.icon is DPITexture, "footer retains SVG source for sharp window scaling: " + button.text)
	check(presenter.skin.icon("cherry", 24).get_width() == 24, "brand mark rasterizes at its own logical size")
	check(presenter.dialogue.voice_icon.texture.get_width() == 16, "voice badge rasterizes at its own logical size")
	presenter.auto_play = true
	presenter.advance_time(0)
	check(presenter.footer_buttons.auto.icon == presenter.skin.icon("pause"), "auto playback displays pause artwork")
	presenter.auto_play = false
	presenter.advance_time(0)
	check(presenter.footer_buttons.auto.icon == presenter.skin.icon("play"), "stopping auto playback restores play artwork")
	# Advance the greeting into the file containing the three choices.
	for i in range(12):
		if presenter._state.mode == "choice": break
		presenter.advance_time(5)
		presenter.advance()
		presenter.advance_time(0)
		await settle()
	check(presenter._state.mode == "choice", "story reaches genuine VM choice")
	check(presenter.choices_panel.get_child_count() == 3, "three branch options")
	check(presenter.dialogue.visible, "dialogue preserved behind choices")
	check(is_equal_approx(presenter.dialogue.position.y - presenter.choice_scroll.get_rect().end.y, 28), "choices anchored at 28 units")
	await capture("galgame-play")
	for dimensions in [Vector2(1280, 720), Vector2(1600, 900), Vector2(1920, 1080), Vector2(2560, 1440), Vector2(3840, 2160), Vector2(1920, 1200), Vector2(900, 900)]:
		root.size = Vector2i(dimensions)
		await settle()
		var drawn := presenter.stage.size * presenter.stage.scale
		check(is_equal_approx(drawn.x / drawn.y, 16.0 / 9.0), "stage ratio preserved at " + str(dimensions))
		check(is_equal_approx(presenter.dialogue.position.y - presenter.choice_scroll.get_rect().end.y, 28), "choice gap preserved at " + str(dimensions))
		var bounds := presenter.stage_pixel_rect()
		check(absf(float(bounds.size.x) / bounds.size.y - 16.0 / 9.0) < 0.005, "thumbnail crop excludes letterboxing")
		await capture("galgame-size-%dx%d" % [dimensions.x, dimensions.y])
	root.size = Vector2i(1280, 720)
	await settle()
	presenter.open_menu("settings")
	await settle()
	check(presenter.paused, "opening menu pauses playback")
	check(presenter.footer_buttons.save.focus_mode == Control.FOCUS_NONE, "covered stage controls cannot receive keyboard focus")
	check(presenter.menu.active_page.heading.text == "设置", "settings title")
	check(presenter.menu.active_page.preview.text.text == presenter.dialogue.text.text, "settings preview uses actual dialogue")
	check(presenter.menu.active_page.preview.text.get_theme_font("normal_font") == presenter.dialogue.text.get_theme_font("normal_font"), "shared body font resource")
	presenter.preferences.set_value("font_size", 36)
	presenter.preferences.set_value("line_height", 2.2)
	await settle()
	check(presenter.menu.active_page.preview.size == presenter.dialogue.size, "preview tracks large text panel geometry")
	presenter.preferences.set_value("font_size", 23)
	presenter.preferences.set_value("line_height", 1.5)
	await capture("galgame-settings-text")
	presenter.menu.section_id = "display"
	presenter.menu.open("settings")
	await settle()
	check(not presenter.menu.active_page.rows.glass_blur.visible, "glass details initially hidden")
	presenter.preferences.set_value("glass", true)
	check(presenter.menu.active_page.rows.glass_blur.visible and presenter.dialogue.glass.visible and presenter.menu.active_page.preview.glass.visible, "glass setting reaches both views and conditional fields")
	await capture("galgame-settings-glass")
	presenter.preferences.set_value("palette", "mint")
	check(presenter.footer_buttons.save.get_theme_color("icon_normal_color") == presenter.skin.colors.ink, "SVG buttons follow palette changes")
	check(presenter.dialogue.voice_icon.self_modulate == presenter.skin.colors.accent, "voice SVG follows palette changes")
	check(presenter.menu.active_page.preview.text.get_theme_color("default_color") == presenter.dialogue.text.get_theme_color("default_color"), "palette propagates to both dialogue instances")
	await capture("galgame-settings-mint")
	presenter.preferences.set_value("palette", "peach")
	presenter.preferences.set_value("master", 67)
	presenter.preferences.set_value("voice", 45)
	check(is_equal_approx(AudioServer.get_bus_volume_linear(0), 0.67), "master slider changes audio bus")
	check(is_equal_approx(AudioServer.get_bus_volume_linear(AudioServer.get_bus_index("Voice")), 0.45), "voice slider changes audio bus")
	presenter.preferences.set_value("mute", true)
	check(AudioServer.is_bus_mute(0), "mute changes audio output")
	presenter.preferences.set_value("mute", false)
	presenter.menu.section_id = "sound"
	presenter.menu.open("settings")
	check(presenter.menu.active_page.preview == null, "sound subpage has no preview")
	presenter.menu.confirm("确认测试", "取消不应改变剧情。", func(): pass)
	check(presenter.menu.active_page.route.state == NavigationRoute.State.COVERED, "confirmation isolates keyboard focus from settings")
	presenter.menu.dismiss_confirmation()
	check(presenter.menu.active_page.route.state == NavigationRoute.State.ACTIVE, "dismissal restores page focusability")
	presenter.close_menu()
	check(not presenter.paused, "closing menu resumes")
	check(presenter.footer_buttons.save.focus_mode != Control.FOCUS_NONE, "closing menu restores stage keyboard controls")
	var snapshot := presenter.archive.player.create_snapshot()
	check(presenter.archive.save_slot(0, presenter.thumbnail) == OK, "save current choice with thumbnail")
	check(presenter.archive.read_slot(0).snapshot.presentation.mode == "choice", "save captures genuine choice phase")
	presenter.preferences.set_value("palette", "mint")
	presenter.open_menu("save")
	var save_page := presenter.menu.active_page
	_check_slot_palette(save_page)
	await capture("galgame-save")
	check(presenter.menu.active_page.heading.text == "存档", "separate save heading")
	presenter.menu.open("load")
	check(presenter.menu.active_page.heading.text == "读档", "separate load heading")
	var load_page := presenter.menu.active_page
	var first_card: Button = load_page._slot_cards[0].button
	check(not first_card.disabled and load_page._slot_cards[1].button.disabled, "load page includes occupied and disabled empty slots")
	for palette in ["night", "peach"]:
		presenter.preferences.set_value("palette", palette)
		_check_slot_palette(save_page) # Covered pages must also update.
		_check_slot_palette(load_page)
		load_page.select_slot_page(1)
		_check_slot_palette(load_page)
		load_page.select_slot_page(0)
	check(load_page._slot_cards[0].button == first_card, "palette changes and pagination retain slot card instances")
	# Off-tree controls have no theme owner yet; inspect the authored resource.
	var template: Button = load_page.slot_card_scene.instantiate()
	check(template.theme.get_stylebox("normal", "Button").bg_color.is_equal_approx(Color(presenter.preferences.schema.palettes.peach.paper)), "runtime palettes never mutate the standalone card theme")
	check(template.theme.get_color("font_color", template.get_node("Content/Title").theme_type_variation).is_equal_approx(Color(presenter.preferences.schema.palettes.peach.accent)), "standalone card title uses the shared accent style")
	template.free()
	presenter.menu.open("flow")
	await settle()
	var flow := presenter.menu.active_page.body.get_child(0) as StoryFlowView
	check(flow.cards.size() == 8, "flow cards match script files")
	flow.fit_graph()
	await capture("galgame-flow")
	flow.canvas.zoom_at(Vector2(200, 100), 1.5)
	check(flow.canvas.zoom == 1.5, "flow zoom responds")
	flow.search.text = "不存在的标题"
	flow._filter()
	var visible_cards := 0
	for card in flow.cards.values(): visible_cards += int(card.visible)
	check(visible_cards == 0, "flow search actually filters")
	presenter.menu.open("backlog")
	await capture("galgame-backlog")
	check(presenter.archive.history.size() >= 2, "backlog collected actual dialogue")
	presenter.close_menu()
	presenter._choose(0, presenter._cancel_token)
	await settle()
	check(presenter.archive.player.current_story.get_story_id() == "dinner", "branch enters target script")
	check(presenter.portrait.texture.resource_path.ends_with("mahiro_happy.webp"), "happy expression used for answer")
	check(presenter.archive.history.any(func(row): return row.kind == "choice"), "choice recorded in backlog")
	presenter.toggle_skip()
	check(not presenter.fast_forward, "unread skip is guarded")
	presenter.preferences.set_value("skip_unread", true)
	presenter.toggle_skip()
	check(presenter.fast_forward, "explicit unread skip preference is honored")
	presenter.fast_forward = false
	presenter._lose_focus()
	check(presenter.paused, "focus loss pauses playback")
	presenter._gain_focus()
	check(not presenter.paused, "focus return resumes playback")
	check(presenter.archive.restore_snapshot(snapshot) == OK, "restore native presenter snapshot")
	await settle()
	check(presenter._state.mode == "choice" and presenter.choices_panel.get_child_count() == 3, "restore returns to real choices")
	presenter.toggle_hidden()
	check(presenter.ui_hidden and not presenter.dialogue.visible and presenter.paused, "hide pauses and conceals UI")
	presenter.toggle_hidden()
	check(presenter.choice_scroll.visible and not presenter.paused, "unhide preserves choice visibility")
	# Walk every first branch and both endings using the same checkpoint. This
	# also checks that file replay/restore does not leave the VM paused by menus.
	for route in [[0, 0, "stars"], [1, 1, "goodnight"], [2, 0, "stars"]]:
		presenter.archive.restore_snapshot(snapshot)
		presenter.close_menu()
		await settle()
		presenter._choose(route[0], presenter._cancel_token)
		await settle()
		for step in range(40):
			if not presenter.archive.player.is_playing: break
			if presenter._state.mode == "choice": presenter._choose(route[1], presenter._cancel_token)
			else:
				presenter.advance_time(5)
				presenter.advance()
				presenter.advance_time(0)
			await settle()
		check(not presenter.archive.player.is_playing and presenter.archive.player.current_story.get_story_id() == route[2], "route reaches expected ending: " + str(route))
		check(presenter.menu.page == "ending" and presenter.menu.is_open, "ending page opens without stuck playback")
	presenter.archive.player.stop()
	scene.queue_free()
	await settle()
	print("Galgame UI: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)

func _check_slot_palette(page: StoryMenuPage) -> void:
	# Query the actual native styles on every occupied/empty card. Checking the
	# parent theme alone misses child scenes that shadow it with a fixed theme.
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var matches := true
		var fill: Color = presenter.skin.colors.paper if state == "normal" else presenter.skin.colors.soft
		for card in page._slot_cards:
			var style := card.button.get_theme_stylebox(state) as StyleBoxFlat
			matches = matches and style.bg_color == fill and style.border_color == presenter.skin.colors.line
		check(matches, "%s slot %s style follows palette %s" % [page.page, state, presenter.preferences.values.palette])
	var labels_match := true
	for card in page._slot_cards:
		labels_match = labels_match and card.title.get_theme_color("font_color") == presenter.skin.colors.accent
		labels_match = labels_match and card.text.get_theme_color("font_color") == presenter.skin.colors.ink
		labels_match = labels_match and card.stamp.get_theme_color("font_color") == presenter.skin.colors.muted
	check(labels_match, page.page + " slot labels follow the live palette")
