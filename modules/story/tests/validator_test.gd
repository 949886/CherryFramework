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
	var path := "user://validator_%d_%s" % [OS.get_process_id(), name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	files.append(path)
	return path

func has_code(report: Dictionary, code: String) -> bool:
	return report.diagnostics.any(func(d): return d.code == code)

func _initialize() -> void:
	root_path = (get_script() as Script).resource_path.get_base_dir().get_base_dir()
	var validator := StoryLibraryValidator.new()
	check(has_code(validator.validate(null), "library_missing"), "missing library")
	var library := StoryLibrary.new()
	check(has_code(validator.validate(library), "library_empty"), "empty library")
	library.stories = {12: {}, "bad": 42, "empty": {}, "locale": {"": "bad"}}
	var report := validator.validate(library)
	check(has_code(report, "library_entry") and has_code(report, "library_locale"), "malformed mappings are diagnosed without crashing")
	library.stories = {"missing": {"en": "user://missing_story.md"}}
	check(has_code(validator.validate(library), "story_file_missing"), "missing story source")
	var start := write("start.md", "Guide: Start\n>>[go](end.md#finish)")
	var end := write("end.md", "# finish\nGuide: End")
	library.stories = {"start": {"en": start}, "end": {"en": end}}
	report = validator.validate(library)
	check(report.ok and report.dependencies.size() == 2, "cross-file heading and source dependencies")
	library.stories.end = {"zh": end}
	check(has_code(validator.validate(library), "jump_story_missing"), "jump needs a target in the current locale")
	library.fallback_locales = ["zh"]
	check(validator.validate(library).ok, "locale fallback validates target")
	library.stories = {"start": {"en": write("bad_heading.md", ">>[go](end.md#missing)")}, "end": {"en": end}}
	check(has_code(validator.validate(library), "jump_heading_missing"), "missing cross-file heading")
	library.stories = {"a": {"en": end}, "b": {"en": end}}
	check(has_code(validator.validate(library), "ambiguous_story_path"), "ambiguous localized aliases")
	library.stories = {"start": {"en": write("syntax.md", "Guide: First\n`else:`\nGuide: Orphan")}}
	report = validator.validate(library)
	check(not report.ok and report.diagnostics[0].line == 2, "parser source line preserved")
	library.stories = {"start": {"en": write("commands.md", "Guide: [unknown]\nGuide: [wait:-1s]\nGuide: [audio:missing.wav]")}}
	report = validator.validate(library)
	check(has_code(report, "unknown_command"), "unknown command")
	check(has_code(report, "command_argument"), "invalid command argument")
	check(has_code(report, "asset_missing"), "missing dynamic asset")
	var texture := root_path.path_join("examples/assets/room.svg")
	var audio := root_path.path_join("examples/assets/mahiro_voice.wav")
	library.stories = {"start": {"en": write("assets.md", "Guide: [bg:%s][audio:%s]" % [texture, audio])}}
	report = validator.validate(library)
	check(report.ok and texture in report.dependencies and audio in report.dependencies, "inline assets included with type checks")
	library.stories = {"start": {"en": write("wrong_asset.md", "Guide: [audio:%s]" % texture)}}
	check(has_code(validator.validate(library), "asset_type"), "wrong resource type")
	library.stories = {"start": {"en": write("en.md", "<!-- @sid:intro -->\nGuide: English"), "zh": write("zh.md", "<!-- @sid:intro -->\nGuide: 中文")}}
	check(validator.validate(library).ok, "matching translation SIDs")
	library.stories.start.zh = write("drift.md", "<!-- @sid:other -->\nGuide: 中文")
	report = validator.validate(library)
	check(report.ok and has_code(report, "translation_sid_mismatch"), "translation SID drift is a warning")
	var extra := write("extra.json", "{}")
	library.extra_files = [extra]
	check(extra in validator.validate(library).dependencies, "explicit dynamic dependency")
	library.extra_files = ["user://missing_extra.json"]
	check(has_code(validator.validate(library), "extra_dependency_missing"), "missing explicit dependency")
	library.extra_files = []
	var sentinel := "user://validator_init_%d.txt" % OS.get_process_id()
	library.stories = {"safe": {"en": write("init.md", "```gdscript\nfunc _init():\n\tFileAccess.open(\"%s\", FileAccess.WRITE).store_string(\"executed\")\n```\nGuide: Safe" % sentinel)}}
	report = validator.validate(library)
	check(report.ok and not FileAccess.file_exists(sentinel), "checking never instantiates author runtime")
	library.commands = null
	check(has_code(validator.validate(library), "registry_missing"), "missing command registry")
	for path in files:
		DirAccess.remove_absolute(path)
	print("Validator: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
