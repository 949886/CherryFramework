@tool
extends EditorImportPlugin
## Makes .md files assignable to StoryPlayer.story without a separate .tres.

func _get_importer_name() -> String:
	return "cherry.story.markdown"

func _get_visible_name() -> String:
	return "Story (Markdown)"

func _get_recognized_extensions() -> PackedStringArray:
	return ["md"]

func _get_save_extension() -> String:
	return "res"

func _get_resource_type() -> String:
	return "Resource"

func _get_preset_count() -> int:
	return 1

func _get_preset_name(_index: int) -> String:
	return "Default"

func _get_import_options(_path: String, _preset: int) -> Array[Dictionary]:
	return [
		{"name": "commands", "default_value": "", "property_hint": PROPERTY_HINT_FILE, "hint_string": "*.tres,*.res"},
		{"name": "extra_files", "default_value": PackedStringArray()},
	]

func _import(source_file: String, save_path: String, options: Dictionary, _platform_variants: Array[String], _gen_files: Array[String]) -> Error:
	var story := MarkdownStory.from_file(source_file)
	if story == null:
		return ERR_FILE_CANT_READ
	var commands_path := String(options.get("commands", ""))
	if not commands_path.is_empty():
		story.commands = load(commands_path) as StoryCommandRegistry
		if story.commands == null:
			return ERR_INVALID_DATA
	story.extra_files = options.get("extra_files", PackedStringArray())
	# Importing identifies the resource only; story code is compiled on demand.
	return ResourceSaver.save(story, save_path + "." + _get_save_extension())
