extends SceneTree
## Deterministic presentation clock tests: animated feedback must never change
## the choice hit area, bypass pause, double-commit, or survive a canceled VM.

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

func capture(label: String) -> void:
	if "--render" not in OS.get_cmdline_user_args(): return
	await settle()
	await RenderingServer.frame_post_draw
	var path := "user://choice-motion-" + label + ".png"
	root.get_texture().get_image().save_png(path)
	print("RENDER " + ProjectSettings.globalize_path(path))

func _run() -> void:
	var scene: Control = load(module_root.path_join("examples/galgame_demo.tscn")).instantiate()
	var presenter := scene.get_node("Presenter") as StoryGalgamePresenter
	presenter.save_directory = "user://choice_motion_test_%d" % OS.get_process_id()
	root.add_child(scene)
	await settle()
	presenter.set_process(false)
	presenter.preferences.set_value("motion", "reduced")
	presenter.preferences.set_value("instant", true)
	for step in range(12):
		if presenter._state.mode == "choice": break
		presenter.advance_time(5)
		presenter.advance()
		presenter.advance_time(0)
		await settle()
	check(presenter._state.mode == "choice", "fixture reaches real choices")
	var snapshot := presenter.archive.player.create_snapshot()
	presenter.preferences.set_value("motion", "normal")
	presenter.archive.restore_snapshot(snapshot)
	await settle()
	var first := presenter.choices_panel.get_child(0) as StoryChoiceButton
	var second := presenter.choices_panel.get_child(1) as StoryChoiceButton
	check(first.reveal == 0.0 and second.reveal == 0.0, "all options begin at the same entrance state")
	presenter.advance_time(0.06)
	check(first.reveal > 0.0 and first.reveal < 1.0 and first.reveal == second.reveal, "same entrance timing for every option")
	presenter.advance_time(1)
	check(first.modulate.a == 1.0 and second.modulate.a == 1.0, "all options finish fully opaque")
	await capture("idle")
	var original_rect := first.get_rect()
	var minimum := first.get_combined_minimum_size()
	first.set_interaction(true, false)
	first.advance_visuals(0.04)
	check(first.emphasis.x > 0.0 and first.emphasis.x < 1.0, "hover is interpolated")
	await capture("hover")
	var mid := first.emphasis.x
	first.set_interaction(false, false)
	check(first.emphasis.x == mid, "reversing hover does not jump")
	first.advance_visuals(1)
	check(first.emphasis == Vector2.ZERO, "rapid exit restores idle state")
	first.set_interaction(true, true)
	first.advance_visuals(1)
	await settle()
	check(first.get_rect() == original_rect and first.get_combined_minimum_size() == minimum, "hover/press preserve layout and hit area")
	check(first.get_theme_stylebox("pressed") == first.get_theme_stylebox("hover"), "native button states cannot replace animated style")
	presenter.preferences.set_value("palette", "mint")
	check(first.get_theme_color("font_color") == presenter.skin.colors.accent, "palette updates preserve current animation state")
	presenter.preferences.set_value("motion", "reduced")
	first.set_interaction(false, false)
	check(first.reveal == 1.0 and first.emphasis == Vector2.ZERO, "reduced motion settles immediately")
	check(first.get_theme_stylebox("normal").content_margin_left == 12, "reduced motion removes content movement")
	presenter.preferences.set_value("motion", "normal")
	var history_size := presenter.archive.history.size()
	presenter._choose(0, presenter._cancel_token)
	check(presenter._choice_pending == 0 and presenter.archive.history.size() == history_size, "selection feedback precedes one committed result")
	check(first.selected and first.disabled and second.disabled, "selection locks all options during feedback")
	check(second.modulate.a == 1.0, "unselected rows do not jump to dimmed opacity")
	presenter.advance_time(0.07)
	check(second.modulate.a < 1.0 and second.modulate.a > 0.55, "unselected rows fade smoothly during confirmation")
	await capture("selected")
	presenter.paused = true
	presenter.advance_time(10)
	check(presenter._choice_pending == 0 and presenter.archive.player.current_story.get_story_id() == "home", "paused menu freezes choice confirmation")
	presenter.paused = false
	presenter._choose(1, presenter._cancel_token)
	check(presenter._choice_pending == 0, "double-click cannot replace the selected option")
	presenter.advance_time(1)
	await settle()
	check(presenter.archive.player.current_story.get_story_id() == "dinner", "feedback completes the correct VM branch")
	check(presenter.archive.history.filter(func(row): return row.kind == "choice").size() == 1, "choice logged exactly once")
	presenter.archive.restore_snapshot(snapshot)
	await settle()
	presenter._choose(2, presenter._cancel_token)
	presenter.archive.restore_snapshot(snapshot)
	await settle()
	presenter.advance_time(1)
	check(presenter._state.mode == "choice" and presenter._choice_pending == -1, "restore cancels pending feedback from the old VM")
	presenter.preferences.set_value("motion", "reduced")
	presenter._choose(1, presenter._cancel_token)
	await settle()
	check(presenter.archive.player.current_story.get_story_id() == "bath", "reduced motion commits immediately")
	presenter.archive.player.stop()
	scene.queue_free()
	await settle()
	print("Choice motion: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
