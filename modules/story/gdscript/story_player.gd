class_name StoryPlayer
extends Node
## Owns story playback, cross-file jumps and save/locale transitions. UI hosts
## configure resources and subscribe to signals; the VM stays presentation-free.

signal story_started(story_id: String)
signal instruction_changed(instruction: Dictionary)
signal story_finished(story_id: String)
signal story_failed(message: String)
signal saved(automatic: bool)
signal restored(quality: int)

@export var library: StoryLibrary
@export var presenter: StoryPresentation
@export var initial_story := ""
@export var locale := ""
@export var autoplay := true
@export var save_path := "user://cherry_story_save.json"
## Prevent author-written jump loops from locking the main thread.
@export_range(1, 10000) var instructions_per_frame := 256

var vm := StoryVM.new()
var save_manager := StorySaveManager.new()
var current_story_id := ""
var is_playing := false
var _generation := 0

func _ready() -> void:
	if presenter != null:
		presenter.setup(self)
		presenter.presentation_failed.connect(func(message): story_failed.emit(message))
	if autoplay and not initial_story.is_empty():
		_start_initial.call_deferred()

func _start_initial() -> void:
	play(initial_story)

func _exit_tree() -> void:
	stop()

func stop() -> void:
	_generation += 1
	is_playing = false
	if is_instance_valid(presenter) and presenter.is_inside_tree():
		presenter.cancel_current()

## Returns after preparing the story; completion is reported by signals.
## Preparation is transactional: a failed load leaves current playback intact.
func play(story_id: String, label: String = "", snapshot: Dictionary = {}, target_locale: String = "") -> Error:
	if library == null or presenter == null or not is_inside_tree() or not presenter.is_configured():
		return _fail("StoryPlayer requires a library, presenter and scene tree.", ERR_UNCONFIGURED)
	var next_locale := locale if target_locale.is_empty() else target_locale
	var program := library.compile_story(story_id, next_locale)
	if program == null:
		return _fail("Cannot compile story '%s' (%s)." % [story_id, next_locale], ERR_PARSE_ERROR)
	var start_ip := 0 if label.is_empty() else program.resolve_label(label)
	if start_ip < 0:
		return _fail("Unknown story heading: %s" % label, ERR_DOES_NOT_EXIST)
	var next_vm := StoryVM.new()
	next_vm.setup(program, start_ip)
	if not snapshot.is_empty():
		var error := save_manager.restore_snapshot(next_vm, snapshot)
		if error != OK:
			return _fail(save_manager.last_restore_message, error)
	var presentation_state: StoryPresentationState
	if snapshot.has("presentation"):
		if not snapshot.presentation is Dictionary:
			return _fail("Invalid presentation snapshot.", ERR_INVALID_DATA)
		presentation_state = StoryPresentationState.from_dict(snapshot.presentation)
		if presentation_state == null or not presenter.can_restore(presentation_state):
			return _fail("Invalid presentation state or missing saved assets.", ERR_INVALID_DATA)
	stop()
	vm = next_vm
	locale = next_locale
	current_story_id = story_id
	program.runtime.set("__gal_host", self)
	presenter.setup(self)
	presenter.source_path = program.source_path
	if presentation_state != null:
		var same_text := String(snapshot.get("exact_signature", "")) == String(vm.current_instruction().get("exact_signature", ""))
		presenter.restore_state(presentation_state, same_text and next_locale == String(snapshot.get("locale", "")))
	is_playing = true
	var generation := _generation
	story_started.emit(story_id)
	if not snapshot.is_empty():
		restored.emit(save_manager.last_restore_quality)
	_run_story_loop.call_deferred(generation)
	return OK

func restart() -> Error:
	return play(initial_story)

func save_game(automatic: bool = false) -> Error:
	var snapshot := create_snapshot()
	var error := save_manager.write_snapshot(save_path, snapshot) if not snapshot.is_empty() else ERR_INVALID_DATA
	if error != OK:
		return _fail(save_manager.last_file_error, error)
	saved.emit(automatic)
	return OK

func load_game() -> Error:
	var snapshot := save_manager.load_from_file(save_path)
	if snapshot.is_empty():
		return _fail(save_manager.last_file_error, ERR_FILE_CORRUPT)
	return play(String(snapshot.get("story_id", initial_story)), "", snapshot, String(snapshot.get("locale", locale)))

func switch_locale(next_locale: String) -> Error:
	if vm.program == null:
		return _fail("No active story to translate.", ERR_UNCONFIGURED)
	var snapshot := create_snapshot()
	if snapshot.is_empty():
		return _fail(save_manager.last_file_error, ERR_INVALID_DATA)
	return play(current_story_id, "", snapshot, next_locale)

func create_snapshot() -> Dictionary:
	var snapshot := save_manager.create_snapshot(vm, locale)
	if not snapshot.is_empty() and presenter != null:
		snapshot["presentation"] = presenter.capture_state().to_dict()
	return snapshot

func pause() -> void:
	if presenter != null:
		presenter.paused = true

func resume() -> void:
	if presenter != null:
		presenter.paused = false

func set_auto_play(enabled: bool) -> void:
	presenter.auto_play = enabled

func set_fast_forward(enabled: bool) -> void:
	presenter.fast_forward = enabled

func _fail(message: String, error: Error) -> Error:
	story_failed.emit(message)
	return error

func _run_story_loop(generation: int) -> void:
	var steps := 0
	while generation == _generation and is_inside_tree():
		if presenter.paused:
			await get_tree().process_frame
			continue
		var instruction := vm.current_instruction()
		instruction_changed.emit(instruction)
		if generation != _generation:
			return
		var op := int(instruction["op"])
		var data: Variant = instruction.get("data")
		match op:
			StoryProgram.Op.DIA, StoryProgram.Op.NAR:
				var completed: bool
				if op == StoryProgram.Op.DIA:
					completed = await presenter.present_dialogue(data)
				else:
					completed = await presenter.present_narration(data)
				if generation != _generation:
					return
				if not completed:
					stop()
					return
				vm.advance()
			StoryProgram.Op.CHO:
				var index := await presenter.present_choice(data)
				if generation != _generation:
					return
				if index < 0:
					stop()
					return
				var options: Array = data.get("options", [])
				if index >= options.size():
					stop()
					_fail("Invalid story choice.", ERR_INVALID_DATA)
					return
				vm.jump_to_ip(int(options[index]["target"]))
			_:
				var result := vm.execute_internal(instruction)
				if generation != _generation:
					return
				if not bool(result.get("ok", false)):
					stop()
					_fail(String(result.get("error", "Story VM execution failed.")), FAILED)
					return
				if bool(result.get("finished", false)):
					is_playing = false
					story_finished.emit(current_story_id)
					return
				if bool(result.get("external_jump", false)):
					await get_tree().process_frame
					if generation != _generation:
						return
					var error := play(String(result.get("story", "")), String(result.get("label", "")))
					if error != OK:
						stop()
					# Yield between files as well as within them, including JMP-only cycles.
					return
		steps += 1
		if steps >= maxi(1, instructions_per_frame):
			steps = 0
			await get_tree().process_frame
