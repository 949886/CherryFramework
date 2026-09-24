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
	for dimensions in [Vector2(1280, 720), Vector2(1600, 900), Vector2(1920, 1200), Vector2(900, 900)]:
		scene.size = dimensions
		await settle()
		var drawn := presenter.stage.size * presenter.stage.scale
		check(is_equal_approx(drawn.x / drawn.y, 16.0 / 9.0), "stage ratio preserved at " + str(dimensions))
		check(is_equal_approx(presenter.dialogue.position.y - presenter.choice_scroll.get_rect().end.y, 28), "choice gap preserved at " + str(dimensions))
	scene.size = Vector2(1280, 720)
	await settle()
	presenter.open_menu("settings")
	await settle()
	check(presenter.paused, "opening menu pauses playback")
	check(presenter.menu.heading.text == "设置", "settings title")
	check(presenter.menu.preview.text.text == presenter.dialogue.text.text, "settings preview uses actual dialogue")
	check(presenter.menu.preview.text.get_theme_font("normal_font") == presenter.dialogue.text.get_theme_font("normal_font"), "shared body font resource")
	await capture("galgame-settings-text")
	presenter.menu.section_id = "display"
	presenter.menu.open("settings")
	await settle()
	check(not presenter.menu.rows.glass_blur.visible, "glass details initially hidden")
	presenter.preferences.set_value("glass", true)
	check(presenter.menu.rows.glass_blur.visible and presenter.dialogue.glass.visible and presenter.menu.preview.glass.visible, "glass setting reaches both views and conditional fields")
	await capture("galgame-settings-glass")
	presenter.menu.section_id = "sound"
	presenter.menu.open("settings")
	check(presenter.menu.preview == null, "sound subpage has no preview")
	presenter.close_menu()
	check(not presenter.paused, "closing menu resumes")
	var snapshot := presenter.archive.player.create_snapshot()
	check(presenter.archive.save_slot(0, presenter.thumbnail) == OK, "save current choice with thumbnail")
	check(presenter.archive.read_slot(0).snapshot.presentation.mode == "choice", "save captures genuine choice phase")
	presenter.open_menu("save")
	await capture("galgame-save")
	check(presenter.menu.heading.text == "存档", "separate save heading")
	presenter.menu.open("load")
	check(presenter.menu.heading.text == "读档", "separate load heading")
	presenter.menu.open("flow")
	await settle()
	var flow := presenter.menu.body.get_child(0) as StoryFlowView
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
	check(presenter.archive.restore_snapshot(snapshot) == OK, "restore native presenter snapshot")
	await settle()
	check(presenter._state.mode == "choice" and presenter.choices_panel.get_child_count() == 3, "restore returns to real choices")
	presenter.toggle_hidden()
	check(presenter.ui_hidden and not presenter.dialogue.visible and presenter.paused, "hide pauses and conceals UI")
	presenter.toggle_hidden()
	check(presenter.choice_scroll.visible and not presenter.paused, "unhide preserves choice visibility")
	presenter.archive.player.stop()
	scene.queue_free()
	await settle()
	print("Galgame UI: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
