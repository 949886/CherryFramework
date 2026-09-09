class_name StoryLibrary
extends Resource
## Maps logical story IDs to locale/file dictionaries. Relative paths resolve
## beside this .tres resource, allowing the entire module/library to move.

@export var stories: Dictionary = {}
@export var fallback_locales: PackedStringArray = []
@export var locale_labels: Dictionary = {}

func resolve_path(story_id: String, locale: String) -> String:
	var variants: Dictionary = stories.get(story_id, {})
	var candidates: Array[String] = [locale]
	for fallback in fallback_locales:
		if fallback not in candidates:
			candidates.append(fallback)
	for candidate in candidates:
		var path := String(variants.get(candidate, ""))
		if path.is_empty():
			continue
		if not path.is_absolute_path():
			path = resource_path.get_base_dir().path_join(path).simplify_path()
		if FileAccess.file_exists(path):
			return path
	return ""

func compile_story(story_id: String, locale: String) -> StoryProgram:
	var path := resolve_path(story_id, locale)
	return StoryParser.new().compile_file(path, story_id) if not path.is_empty() else null
