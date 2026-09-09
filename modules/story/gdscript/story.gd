@tool
@icon("../icons/story.svg")
class_name Story
extends Resource
## One playable story. Subclasses provide their own source format and resolver.

@export var commands: StoryCommandRegistry = preload("../resources/default_commands.tres")
## Files loaded through computed author-code paths, relative to the source file.
@export var extra_files: PackedStringArray = []

func get_story_id() -> String:
	return ""

func get_identity() -> String:
	return resource_path

## Normalized locale -> physical source path. Empty locale means unsuffixed file.
func get_sources() -> Dictionary:
	return {}

func get_available_locales() -> PackedStringArray:
	var locales := PackedStringArray()
	for language in get_sources():
		if not String(language).is_empty():
			locales.append(language)
	locales.sort()
	return locales

func get_source_path(_locale: String = "") -> String:
	return ""

func resolve_story(target: String) -> Story:
	return self if target == get_story_id() else null

func compile(_locale: String, _cache: StoryProgramCache = null) -> StoryProgram:
	return null

static func normalize_locale(locale: String) -> String:
	# Preserve explicit regions: Godot standardization can collapse zh_CN to zh.
	return locale.strip_edges().to_lower().replace("_", "-")
