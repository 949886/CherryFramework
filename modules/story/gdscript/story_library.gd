@tool
class_name StoryLibrary
extends Resource
## Maps logical story IDs to locale/file dictionaries. Relative paths resolve
## beside this .tres resource, allowing the entire module/library to move.

@export var stories: Dictionary = {}
@export var fallback_locales: PackedStringArray = []
@export var locale_labels: Dictionary = {}
@export var commands: StoryCommandRegistry = preload("../resources/default_commands.tres")
## Dependencies computed by author GDScript cannot be inferred from inline tokens.
@export var extra_files: PackedStringArray = []
@export var cache_enabled := true
@export_range(0, 1024) var cache_capacity := 64

var program_cache := StoryProgramCache.new()

func resolve_path(story_id: String, locale: String) -> String:
	var value: Variant = stories.get(story_id, {})
	if not value is Dictionary:
		return ""
	var variants: Dictionary = value
	var candidates: Array[String] = [locale]
	for fallback in fallback_locales:
		if fallback not in candidates:
			candidates.append(fallback)
	for candidate in candidates:
		var configured: Variant = variants.get(candidate, "")
		if not configured is String:
			continue
		var path := String(configured)
		if path.is_empty():
			continue
		if not path.is_absolute_path():
			path = resource_path.get_base_dir().path_join(path).simplify_path()
		if FileAccess.file_exists(path):
			return path
	return ""

func absolute_path(path: String) -> String:
	return path if path.is_absolute_path() else resource_path.get_base_dir().path_join(path).simplify_path()

func compile_story(story_id: String, locale: String) -> StoryProgram:
	var path := resolve_path(story_id, locale)
	program_cache.capacity = cache_capacity
	return program_cache.compile_file(path, story_id, get_story_aliases(), cache_enabled) if not path.is_empty() else null

func clear_cache() -> void:
	program_cache.clear()

func get_story_aliases() -> Dictionary:
	var aliases := {}
	for story_id in stories:
		if not stories[story_id] is Dictionary:
			continue
		for value in stories[story_id].values():
			if value is String and not value.is_empty():
				var path: String = value if value.is_absolute_path() else resource_path.get_base_dir().path_join(value).simplify_path()
				aliases[path] = story_id
	return aliases
