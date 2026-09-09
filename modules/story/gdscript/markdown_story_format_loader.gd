@tool
class_name MarkdownStoryFormatLoader
extends ResourceFormatLoader
## Registered by Godot from the global script class list, including at runtime.

func _get_recognized_extensions() -> PackedStringArray:
	return PackedStringArray(MarkdownStory.SUPPORTED_EXTENSIONS)

func _handles_type(type: StringName) -> bool:
	return type in [&"Resource", &"Story", &"MarkdownStory"]

func _recognize_path(path: String, type: StringName) -> bool:
	return MarkdownStory.supports_path(path) and (type.is_empty() or _handles_type(type))

func _get_resource_type(path: String) -> String:
	return "Resource" if MarkdownStory.supports_path(path) else ""

func _get_resource_script_class(path: String) -> String:
	return "MarkdownStory" if MarkdownStory.supports_path(path) else ""

func _load(path: String, _original_path: String, _use_sub_threads: bool, _cache_mode: int) -> Variant:
	var story := MarkdownStory.from_file(path)
	return story if story != null else ERR_FILE_CANT_READ

func _get_dependencies(_path: String, _add_types: bool) -> PackedStringArray:
	# Include runtime class registration even when only a Story resource is exported.
	var loader_path := (get_script() as Script).resource_path
	return [loader_path, loader_path.get_base_dir().path_join("../resources/runtime_dependencies.tres").simplify_path()]
