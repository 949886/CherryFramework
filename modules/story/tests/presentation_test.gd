extends SceneTree

var checks := 0
var failures := 0
var saved_state: StoryPresentationState
var saves := 0
var module_root := (get_script() as Script).resource_path.get_base_dir().get_base_dir()
var view: StoryPresenter

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	_run.call_deferred()

func save_game(_automatic: bool) -> void:
	saves += 1
	saved_state = view.capture_state()

func _run() -> void:
	view = load(module_root.path_join("scenes/story_presenter.tscn")).instantiate()
	root.add_child(view)
	view.set_process(false)
	view.setup(self)
	view.character_delay = 0.1
	var payload := {"speaker": "Guide", "content": "ABCDE[wait:2s]FG[i]HI[save]JK"}
	view.present_dialogue(payload)
	view.advance_time(0.25)
	check(view.dialogue_text.visible_characters == 2, "partial text cursor")
	var partial := view.capture_state()
	view.paused = true
	view.advance()
	view.advance_time(100.0)
	check(view.capture_state().visible_characters == 2, "pause blocks clock and advance input")
	view.paused = false
	view.cancel_current()
	view.restore_state(partial, true)
	view.present_dialogue(payload)
	view.advance_time(0.05)
	check(view.dialogue_text.visible_characters == 3, "restore sub-character elapsed time")
	view.advance_time(0.7)
	var waiting := view.capture_state()
	check(waiting.phase == "wait" and is_equal_approx(waiting.remaining, 1.5), "unused text time flows into wait")
	view.cancel_current()
	view.restore_state(waiting, true)
	view.present_dialogue(payload)
	view.advance_time(1.5)
	view.advance_time(0.2)
	check(view.capture_state().phase == "input" and view.dialogue_text.visible_characters == 7, "resume remaining wait and reach inline input")
	view.advance()
	view.advance_time(0.0)
	view.advance_time(0.2)
	check(saves == 1 and saved_state.token_index > 0, "inline save captures next command cursor")
	view.cancel_current()
	view.restore_state(saved_state, true)
	view.present_dialogue(payload)
	view.advance_time(0.2)
	check(saves == 1 and view.capture_state().phase == "end", "restore skips executed save command")
	var changed := {"speaker": "Guide", "content": "Translated text"}
	view.cancel_current()
	view.restore_state(partial, false)
	view.present_dialogue(changed)
	check(view.dialogue_text.visible_characters == 0, "translated content restarts inline cursor")
	view.auto_play = true
	view.auto_advance_delay = 0.2
	view.character_delay = 0.0
	view.advance_time(1.0)
	check(not view._active, "auto play completes presentation")
	view.auto_play = false
	view.fast_forward = true
	view.fast_forward_multiplier = 10.0
	view.present_narration({"content": "[wait:2s]", "silent": true})
	view.advance_time(0.2)
	check(not view._active, "fast forward scales timed waits")
	view.present_choice({"options": [{"text": "Choose", "target": 0}]})
	view.advance_time(100.0)
	check(view._active, "auto/skip never chooses for the player")
	view.fast_forward = false
	view.cancel_current()
	view.source_path = module_root.path_join("examples/stories/mahiro.ja.md")
	view.background_fade_duration = 2.0
	var bg := {"content": "[bg:../assets/room.svg|transition=fadein]", "silent": true}
	view.present_narration(bg)
	view.advance_time(0.5)
	var fading := view.capture_state()
	check(is_equal_approx(fading.background_alpha, 0.25), "fade uses simulation clock")
	view.paused = true
	view.advance_time(10.0)
	check(is_equal_approx(view.background.modulate.a, 0.25), "pause freezes fade")
	view.paused = false
	view.cancel_current()
	view.restore_state(fading, true)
	view.present_narration(bg)
	view.advance_time(1.5)
	check(is_equal_approx(view.background.modulate.a, 1.0), "resume fade from saved alpha")
	var popup := {"content": "[popup:../assets/omelette.svg]", "silent": true}
	view.present_narration(popup)
	view.advance_time(0.0)
	var popup_state := view.capture_state()
	view.cancel_current()
	view.popup_texture.texture = null
	view.restore_state(popup_state, true)
	view.present_narration(popup)
	check(view.popup_layer.visible and view.popup_texture.texture != null, "restore popup image and waiting phase")
	view.advance()
	view.advance_time(0.0)
	check(not view.popup_layer.visible and not view._active, "restored popup can complete")
	var malformed := partial.to_dict()
	malformed.token_index = 100000
	check(StoryPresentationState.from_dict(malformed) == null, "reject invalid presentation cursor")
	# Save view context while choices cover the preceding dialogue; restore into
	# another fresh view to rule out accidentally retaining the old scene state.
	view.present_dialogue({"speaker": "Guide", "content": "Remember this"})
	view.advance_time(0.0)
	view.present_choice({"options": [{"text": "Next", "target": 0}]})
	var choice_state := view.capture_state()
	var second := load(module_root.path_join("scenes/story_presenter.tscn")).instantiate() as StoryPresenter
	root.add_child(second)
	second.set_process(false)
	second.restore_state(choice_state, true)
	second.present_choice(choice_state.payload)
	check(second.dialogue_text.text == "Remember this" and second.speaker_label.text == "Guide", "fresh view restores dialogue beneath choices")
	check(second.background.texture == view.background.texture, "fresh view restores persistent background")
	view.characters = [load(module_root.path_join("examples/characters/mahiro.tres")) as StoryCharacter]
	view.present_dialogue({"speaker": "真尋", "state": "happy", "content": "[audio:../assets/mahiro_voice.wav]Voice"})
	view.advance_time(0.0)
	var voiced := view.capture_state()
	check(voiced.audio_playing and not voiced.portrait_path.is_empty(), "capture voice and character portrait")
	second.cancel_current()
	second.restore_state(voiced, true)
	second.present_dialogue(voiced.payload)
	check(second.audio_player.playing and second.portrait.texture != null, "fresh view restores audio and portrait")
	second.paused = true
	check(second.audio_player.stream_paused, "pause reaches audio stream")
	second.paused = false
	var wrong_asset := voiced.copy()
	wrong_asset.background_path = voiced.audio_path
	check(not second.can_restore(wrong_asset), "reject wrong asset type before restoration")
	view.characters = []
	view.character_delay = 0.02
	view.auto_play = false
	var timed := {"content": "AB[wait:0.5s]CDEFGHIJKLMNOP", "silent": false}
	view.present_narration(timed)
	for frame in range(42):
		view.advance_time(1.0 / 60.0)
	var at_60 := view.capture_state()
	view.present_narration(timed)
	for frame in range(84):
		view.advance_time(1.0 / 120.0)
	var at_120 := view.capture_state()
	check(at_60.phase == at_120.phase and at_60.visible_characters == at_120.visible_characters and is_equal_approx(at_60.text_time, at_120.text_time), "60/120 Hz produce equivalent text/wait progress")
	view.queue_free()
	second.queue_free()
	await process_frame
	await _check_player()
	print("Presentation: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)

func _check_player() -> void:
	var demo := load(module_root.path_join("examples/story_demo.tscn")).instantiate() as Control
	var player := demo.get_node("StoryPlayer") as StoryPlayer
	player.autoplay = false
	root.add_child(demo)
	(player.presenter as StoryPresenter).set_process(false)
	(player.presenter as StoryPresenter).background_fade_duration = 2.0
	check(player.play("mahiro") == OK, "player prepares stateful story")
	await process_frame
	(player.presenter as StoryPresenter).advance_time(0.5)
	var snapshot := player.create_snapshot()
	check(snapshot.has("presentation"), "player snapshot includes view state")
	var file := "user://presentation_%d.json" % OS.get_process_id()
	player.save_path = file
	check(player.save_game() == OK, "player writes full save")
	(player.presenter as StoryPresenter).advance_time(1.0)
	check(player.load_game() == OK, "player loads full save")
	await process_frame
	check(is_equal_approx((player.presenter as StoryPresenter).background.modulate.a, 0.25), "player restores partial fade through JSON")
	player.pause()
	(player.presenter as StoryPresenter).advance_time(100.0)
	check(is_equal_approx((player.presenter as StoryPresenter).background.modulate.a, 0.25), "player pause controls view clock")
	player.resume()
	var old_vm := player.vm
	snapshot.presentation.phase = "invalid"
	check(player.play("mahiro", "", snapshot) != OK and player.vm == old_vm, "bad view state leaves active story intact")
	DirAccess.remove_absolute(file)
	demo.queue_free()
	await process_frame
