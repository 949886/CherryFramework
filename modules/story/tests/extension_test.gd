extends SceneTree

class RecordingPresentation extends StoryPresentation:
	var lines: Array[String] = []
	func get_presenter_id() -> String:
		return "recording"
	func present_dialogue(payload: Dictionary) -> bool:
		lines.append(payload.content)
		return true
	func present_narration(_payload: Dictionary) -> bool:
		return true
	func present_choice(_payload: Dictionary) -> int:
		return 0
	func capture_state() -> StoryPresentationState:
		var state := super.capture_state()
		state.extensions = {"lines": lines.duplicate()}
		return state
	func restore_state(state: StoryPresentationState, _resume: bool) -> void:
		lines.assign(state.extensions.get("lines", []))

class MarkCommand extends StoryCommandHandler:
	func execute(presentation: StoryPresentation, command: Dictionary) -> Error:
		presentation.set_meta("mark", command.argument)
		return OK

var checks := 0
var failures := 0
var errors: Array[String] = []
var module_root := (get_script() as Script).resource_path.get_base_dir().get_base_dir()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var view := load(module_root.path_join("scenes/story_presenter.tscn")).instantiate() as StoryPresenter
	root.add_child(view)
	view.set_process(false)
	view.commands = view.commands.duplicate(true) as StoryCommandRegistry
	view.presentation_failed.connect(func(message): errors.append(message))
	check(view.is_configured(), "default scene wires exported view references")
	view.background.name = "RenamedBackdrop"
	view.article_text.name = "CustomArticle"
	check(view.is_configured(), "view survives changed node names")
	var mark := MarkCommand.new()
	mark.command_name = &"mark"
	check(view.commands.register(mark) == OK, "register custom command resource")
	check(view.commands.register(mark) == ERR_ALREADY_EXISTS, "reject implicit command override")
	check(view.commands.register(mark, true) == OK, "explicit command replacement")
	var hold := StoryBuiltinCommand.new()
	hold.command_name = &"hold"
	hold.method = &"command_wait"
	hold.argument_kind = "duration"
	view.commands.register(hold)
	view.present_narration({"silent": true, "content": "[mark:first][hold:1s][mark:second]"})
	view.advance_time(0.0)
	check(view.get_meta("mark") == "first" and view.capture_state().phase == "wait", "custom command and configured capability alias execute")
	view.advance_time(1.0)
	check(view.get_meta("mark") == "second" and not view._active, "registered wait uses unified clock")
	view.present_narration({"silent": true, "content": "[unknown]"})
	view.advance_time(0.0)
	check(errors.size() == 1 and not view._active, "unknown command cancels with diagnostic")
	view.present_narration({"silent": true, "content": "[hold:bad]"})
	view.advance_time(0.0)
	check(errors.size() == 2 and not view._active, "handler validates its arguments")
	var duplicate := view.commands.duplicate(true) as StoryCommandRegistry
	duplicate.handlers.append(mark)
	check(not duplicate.validate().is_empty(), "resource-level duplicate detection")
	var missing := StoryPresenter.new()
	check(not missing.is_configured(), "unwired view fails configuration check")
	missing.free()
	var recorder := RecordingPresentation.new()
	root.add_child(recorder)
	var player := StoryPlayer.new()
	player.autoplay = false
	player.library = load(module_root.path_join("examples/story_library.tres"))
	player.presenter = recorder
	root.add_child(player)
	check(player.play("mahiro", "", {}, "ja") == OK, "player accepts non-Control renderer")
	await process_frame
	check(not player.is_playing and recorder.lines.size() > 1, "headless renderer completes branching story")
	var state := recorder.capture_state()
	var restored := RecordingPresentation.new()
	restored.restore_state(StoryPresentationState.from_dict(state.to_dict()), true)
	check(restored.lines == recorder.lines, "renderer-specific state roundtrip")
	check(not view.can_restore(state), "incompatible renderer state rejected")
	restored.free()
	player.queue_free()
	recorder.queue_free()
	view.queue_free()
	await process_frame
	print("Extension: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
