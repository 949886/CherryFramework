extends SceneTree

var checks := 0
var failures := 0
var files: Array[String] = []
var root_path := ""

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func write(name: String, text: String) -> String:
	var directory := "user://validator_%d" % OS.get_process_id()
	DirAccess.make_dir_recursive_absolute(directory)
	var path := directory.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	if path not in files: files.append(path)
	return path

func has_code(report: Dictionary, code: String) -> bool:
	return report.diagnostics.any(func(d): return d.code == code)

func _initialize() -> void:
	root_path = (get_script() as Script).resource_path.get_base_dir().get_base_dir()
	var validator := StoryValidator.new()
	check(has_code(validator.validate(null), "story_missing"), "missing story")
	check(has_code(validator.validate(MarkdownStory.new()), "story_file_missing"), "empty source")
	var missing := MarkdownStory.new()
	missing.source_file = "user://missing_story.md"
	check(has_code(validator.validate(missing), "story_file_missing"), "missing story source")
	var start := write("start.en.md", "Guide: Start\n>>[go](end.story#finish)")
	write("end.zh-cn.story", "# finish\nGuide: End\n>>[back](start.md)")
	var entry := MarkdownStory.from_file(start)
	var report := validator.validate(entry)
	check(report.ok and report.dependencies.size() == 2, "mixed formats, fallback, cyclic cross-file dependency closure")
	entry = MarkdownStory.from_file(write("bad_heading.md", ">>[go](end.story#missing)"))
	check(has_code(validator.validate(entry), "jump_heading_missing"), "missing cross-file heading")
	entry = MarkdownStory.from_file(write("bad_jump.md", ">>[go](missing.story)"))
	check(has_code(validator.validate(entry), "jump_story_missing"), "missing cross-file target")
	entry = MarkdownStory.from_file(write("syntax.md", "Guide: First\n`else:`\nGuide: Orphan"))
	report = validator.validate(entry)
	check(not report.ok and report.diagnostics[0].line == 2, "parser source line preserved")
	entry = MarkdownStory.from_file(write("commands.md", "Guide: [unknown]\nGuide: [wait:-1s]\nGuide: [audio:missing.wav]"))
	report = validator.validate(entry)
	check(has_code(report, "unknown_command"), "unknown command")
	check(has_code(report, "command_argument"), "invalid command argument")
	check(has_code(report, "asset_missing"), "missing dynamic asset")
	var texture := root_path.path_join("examples/assets/room.svg")
	var audio := root_path.path_join("examples/assets/mahiro_voice.wav")
	entry = MarkdownStory.from_file(write("assets.md", "Guide: [bg:%s][audio:%s]" % [texture, audio]))
	report = validator.validate(entry)
	check(report.ok and texture in report.dependencies and audio in report.dependencies, "inline assets included with type checks")
	entry = MarkdownStory.from_file(write("wrong_asset.md", "Guide: [audio:%s]" % texture))
	check(has_code(validator.validate(entry), "asset_type"), "wrong resource type")
	entry = MarkdownStory.from_file(write("translated.en.md", "<!-- @sid:intro -->\nGuide: English"))
	write("translated.zh-cn.story", "<!-- @sid:intro -->\nGuide: 中文")
	check(validator.validate(entry).ok, "matching translation SIDs")
	write("translated.zh-cn.story", "<!-- @sid:other -->\nGuide: 中文")
	report = validator.validate(entry)
	check(report.ok and has_code(report, "translation_sid_mismatch"), "translation SID drift is a warning")
	var extra := write("extra.json", "{}")
	entry.extra_files = [extra]
	check(extra in validator.validate(entry).dependencies, "explicit dynamic dependency")
	entry.extra_files = ["user://missing_extra.json"]
	check(has_code(validator.validate(entry), "extra_dependency_missing"), "missing explicit dependency")
	entry.extra_files = []
	var sentinel := "user://validator_init_%d.txt" % OS.get_process_id()
	entry = MarkdownStory.from_file(write("init.md", "```gdscript\nfunc _init():\n\tFileAccess.open(\"%s\", FileAccess.WRITE).store_string(\"executed\")\n```\nGuide: Safe" % sentinel))
	report = validator.validate(entry)
	check(report.ok and not FileAccess.file_exists(sentinel), "checking never instantiates author runtime")
	entry.commands = null
	check(has_code(validator.validate(entry), "registry_missing"), "missing command registry")
	for path in files:
		DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(start.get_base_dir())
	print("Validator: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
