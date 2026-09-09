extends SceneTree
## Behavioral regression checks; run with --headless --script after editor import.

var failures: Array[String] = []
var checks := 0
var module_root := (get_script() as Script).resource_path.get_base_dir().get_base_dir()

func _initialize() -> void:
	_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		printerr("FAIL: " + message)

func _run() -> void:
	var entry := load(module_root.path_join("examples/stories/mahiro.ja.md")) as Story
	check(entry != null, "native Markdown entry loads")
	check(entry.get_source_path("missing") == entry.get_source_path("ja"), "entry language fallback")
	check(entry.resolve_story("unknown") == null, "unknown story cannot resolve")
	for story_id in ["mahiro", "mahiro_h"]:
		var variant := entry.resolve_story(story_id)
		for locale in variant.get_available_locales():
			var program := variant.compile(locale)
			check(program != null, "compile %s.%s" % [story_id, locale])
			_check_assets(program)
	for locale in ["ja", "zh-cn"]:
		for scenario in [
			{"tire": 50, "favor": 70, "choice": 0, "count": 3, "next": "", "result": 70},
			{"tire": 50, "favor": 85, "choice": 1, "count": 3, "next": "", "result": 85},
			{"tire": 50, "favor": 70, "choice": 2, "count": 3, "next": "", "result": 70},
			{"tire": 50, "favor": 40, "choice": 2, "count": 3, "next": "", "result": 20},
			{"tire": 50, "favor": 95, "choice": 2, "count": 3, "next": "mahiro_h", "result": 95},
			{"tire": 90, "favor": 70, "choice": 0, "count": 1, "next": "", "result": 70},
		]:
			_check_route(entry, locale, scenario)
	_check_parser_and_save()
	await _check_scene(entry)
	print("Story checks: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)

func _check_assets(program: StoryProgram) -> void:
	var presenter := StoryPresenter.new()
	presenter.source_path = program.source_path
	for instruction in program.instructions:
		if instruction.op not in [StoryProgram.Op.DIA, StoryProgram.Op.NAR]:
			continue
		for token in StoryInlineParser.new().parse(String(instruction.data.get("content", ""))):
			if token.type == "command" and token.name in ["bg", "popup", "audio"]:
				check(ResourceLoader.exists(presenter.resolve_asset_path(token.argument)), "relative inline asset: " + token.argument)
	presenter.free()

func _check_route(entry: Story, locale: String, scenario: Dictionary) -> void:
	var vm := StoryVM.new()
	vm.setup(entry.compile(locale))
	vm.program.runtime.set("tire", scenario.tire)
	vm.program.runtime.set("mahiro_favorability", scenario.favor)
	var finished := false
	for step in range(200):
		var instruction := vm.current_instruction()
		if instruction.op in [StoryProgram.Op.DIA, StoryProgram.Op.NAR]:
			vm.advance()
		elif instruction.op == StoryProgram.Op.CHO:
			check(instruction.data.options.size() == scenario.count, "conditional choice count")
			vm.jump_to_ip(instruction.data.options[scenario.choice].target)
		else:
			var result := vm.execute_internal(instruction)
			check(result.get("ok", false), "VM instruction executes")
			if result.get("external_jump", false):
				check(result.story == scenario.next, "external jump target")
				finished = true
				break
			if result.get("finished", false):
				check(scenario.next.is_empty(), "local route ends")
				finished = true
				break
	check(finished, "route terminates within budget")
	check(vm.program.runtime.get("mahiro_favorability") == scenario.result, "real GDScript branch state")

func _check_parser_and_save() -> void:
	var source := "```gdscript\nvar points = 1\nfunc helper():\n\tvar local_only = 3\n\treturn local_only\n```\n<!-- @sid:first -->\nGuide: Hello\n`points += helper()`\n# ending\nGuide: Bye\n"
	var parser := StoryParser.new()
	var program := parser.compile_source(source, "test")
	check(program.save_variables == [&"points"], "function locals are excluded from save variables")
	var vm := StoryVM.new()
	vm.setup(program)
	program.runtime.set("points", 9)
	var saves := StorySaveManager.new()
	var snapshot := saves.create_snapshot(vm, "en")
	var second := StoryVM.new()
	second.setup(parser.compile_source(source, "test"))
	check(second.program.runtime.get("points") == 1, "runtimes are isolated")
	check(saves.restore_snapshot(second, snapshot) == OK and second.program.runtime.get("points") == 9, "snapshot restores variables")
	check(saves.last_restore_quality == StorySaveManager.RestoreQuality.SID, "SID restore")
	snapshot.sid = "removed"
	check(saves.restore_snapshot(second, snapshot) == OK and saves.last_restore_quality == StorySaveManager.RestoreQuality.EXACT_POSITION, "exact-position restore")
	second.setup(parser.compile_source(source.replace("<!--", "> Inserted\n<!--"), "test"))
	check(saves.restore_snapshot(second, snapshot) == OK and saves.last_restore_quality == StorySaveManager.RestoreQuality.EXACT_NEARBY, "nearby exact restore")
	snapshot.exact_signature = "changed"
	check(saves.restore_snapshot(second, snapshot) == OK and saves.last_restore_quality == StorySaveManager.RestoreQuality.FALLBACK_SAME_TYPE, "same-type fallback")
	snapshot.op = StoryProgram.Op.CHO
	check(saves.restore_snapshot(second, snapshot) == OK and saves.last_restore_quality == StorySaveManager.RestoreQuality.FALLBACK_DIALOGUE, "dialogue fallback")
	var save_path := "user://cherry_story_test_%d.json" % OS.get_process_id()
	check(saves.save_to_file(save_path, vm, "en") == OK, "save JSON file")
	var loaded := saves.load_from_file(save_path)
	check(loaded.get("format_version") == 2 and loaded.variables.points == 9, "save JSON roundtrip")
	DirAccess.remove_absolute(save_path)
	var tokens := StoryInlineParser.new().parse("**Hello**[wait:50ms][i][save]")
	check(tokens.size() == 4 and tokens[0].visible_length == 5 and tokens[0].bbcode == "[b]Hello[/b]", "inline text and commands stay separate")
	var branches := "```gdscript\nvar value = 1\n```\n`if value == 1:`\n    Guide: One\n`else:`\n    Guide: Other\n>>[finish](##end)\nGuide: Skipped\n# end\nGuide: Done"
	var spaces := parser.compile_source(branches, "indent")
	var tabs := parser.compile_source(branches.replace("    ", "\t"), "indent")
	check(spaces.instructions == tabs.instructions, "tab/space lowering agrees including heading jump")

func _check_scene(entry: Story) -> void:
	var scene := load(module_root.path_join("examples/story_demo.tscn")) as PackedScene
	var demo := scene.instantiate()
	var player := demo.get_node("StoryPlayer") as StoryPlayer
	player.autoplay = false
	root.add_child(demo)
	var presenter := (player.presenter as StoryPresenter)
	presenter.character_delay = 0.0
	presenter.background_fade_duration = 0.0
	check(presenter.characters.size() == 1 and presenter.characters[0].get_state(&"happy").portrait != null, "scene injects character resources")
	check(player.play(null) == OK, "player starts example")
	await process_frame
	# Jump directly to the dialogue for migration, avoiding the demo's timed intro.
	var first_dialogue := -1
	for i in player.vm.program.instructions.size():
		if player.vm.program.instructions[i].op == StoryProgram.Op.DIA:
			first_dialogue = i
			break
	player.vm.jump_to_ip(first_dialogue)
	var snapshot := player.save_manager.create_snapshot(player.vm, "ja")
	check(player.play(null, "", snapshot) == OK, "replace active presentation")
	await process_frame
	check(player.switch_locale("zh-cn") == OK and player.locale == "zh-cn", "locale switches active playback")
	await process_frame
	var old_vm := player.vm
	var missing := MarkdownStory.new()
	missing.source_file = module_root.path_join("examples/stories/missing.md")
	check(player.play(missing) != OK and player.vm == old_vm and player.is_playing, "failed replacement preserves active story")
	player.stop()
	await process_frame
	# Replace a pending choice twice in the same frame; the old coroutine must
	# never hide or clear the newly displayed choices/input state.
	var choice := {"options": [{"text": "Continue", "target": 0}]}
	presenter.present_choice(choice)
	presenter.cancel_current()
	presenter.present_choice(choice)
	await process_frame
	check(presenter.choices_panel.visible and presenter.choices_panel.get_child_count() == 1, "cancelled choice cannot hide replacement")
	presenter.cancel_current()
	await process_frame
	# End-to-end playback through actual UI and cross-file JMP, driven by input.
	check(player.play(null, "", snapshot, "ja") == OK, "restart UI route")
	player.vm.program.runtime.set("mahiro_favorability", 95)
	var deadline := Time.get_ticks_msec() + 10000
	while player.is_playing and Time.get_ticks_msec() < deadline:
		presenter.advance()
		if presenter.choices_panel.visible and presenter.choices_panel.get_child_count() > 2:
			(presenter.choices_panel.get_child(2) as Button).pressed.emit()
		await process_frame
	check(not player.is_playing and player.current_story_id == "mahiro_h", "real presenter reaches cross-file END: %s ip=%s phase=%s processing=%s paused=%s remaining=%s" % [demo.get_node("TopBar/Status").text, player.vm.ip, presenter.capture_state().phase, presenter.is_processing(), presenter.paused, presenter.capture_state().remaining])
	check(player.vm.program.runtime.get("entered_from_main_route") == true, "destination has independent script variables")
	check(player.story == entry, "entry resource is shared without runtime state")
	# A save made in a destination file must restore that file from the main entry.
	player.vm.jump_to_ip(0)
	var destination_snapshot := player.create_snapshot()
	player.save_path = "user://cross_file_save.json"
	check(player.save_manager.write_snapshot(player.save_path, destination_snapshot) == OK, "cross-file snapshot writes to disk")
	check(player.play(null, "", snapshot, "zh-cn") == OK, "switch back to entry before loading destination save")
	check(player.load_game() == OK and player.current_story_id == "mahiro_h" and player.locale == "ja", "loading restores destination source and saved language")
	player.stop()
	DirAccess.remove_absolute(player.save_path)
	demo.queue_free()
	await process_frame
