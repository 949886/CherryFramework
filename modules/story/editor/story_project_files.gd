@tool
extends RefCounted
## Discover referenced Story resources; documentation Markdown is not an entry.

static func stories(roots: PackedStringArray = []) -> Array[Story]:
	var sources := roots.duplicate()
	if sources.is_empty():
		_collect_roots("res://", sources)
	var result: Array[Story] = []
	for path in dependency_closure(sources):
		var extension := String(path).get_extension().to_lower()
		var candidate := MarkdownStory.supports_path(path)
		if extension == "tres":
			candidate = FileAccess.get_file_as_string(path).contains('script_class="MarkdownStory"')
		elif extension == "res":
			candidate = true
		if not candidate:
			continue
		var story := load(path) as Story
		if story != null:
			result.append(story)
	return result

static func _collect_roots(directory: String, roots: PackedStringArray) -> void:
	if FileAccess.file_exists(directory.path_join(".gdignore")):
		return
	for file in DirAccess.get_files_at(directory):
		if file.get_extension() in ["tres", "res", "tscn", "scn"]:
			roots.append(directory.path_join(file))
	for child in DirAccess.get_directories_at(directory):
		if not child.begins_with("."):
			_collect_roots(directory.path_join(child), roots)

static func dependency_closure(roots: PackedStringArray) -> Dictionary:
	var result := {}
	var pending := Array(roots)
	while not pending.is_empty():
		var path := String(pending.pop_back())
		if result.has(path):
			continue
		result[path] = true
		if not ResourceLoader.exists(path):
			continue
		for dependency in ResourceLoader.get_dependencies(path):
			var target := String(dependency).get_slice("::", String(dependency).get_slice_count("::") - 1)
			if target.begins_with("uid://"):
				var uid := ResourceUID.text_to_id(target)
				target = ResourceUID.get_id_path(uid) if ResourceUID.has_id(uid) else ""
			if not target.is_empty():
				if not target.is_absolute_path():
					target = path.get_base_dir().path_join(target).simplify_path()
				pending.append(target)
	return result
