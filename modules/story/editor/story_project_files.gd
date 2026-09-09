@tool
extends RefCounted
## Discover libraries and walk resource dependencies without creating scenes.

static func libraries() -> Array[StoryLibrary]:
	var result: Array[StoryLibrary] = []
	_scan("res://", result)
	return result

static func _scan(directory: String, result: Array[StoryLibrary]) -> void:
	if FileAccess.file_exists(directory.path_join(".gdignore")):
		return
	for file in DirAccess.get_files_at(directory):
		if file.get_extension() not in ["tres", "res"]:
			continue
		var path := directory.path_join(file)
		# Avoid loading every unrelated .tres (and any tool scripts it uses).
		if file.get_extension() == "tres" and not FileAccess.get_file_as_string(path).contains('script_class="StoryLibrary"'):
			continue
		var resource := load(path)
		if resource is StoryLibrary:
			result.append(resource)
	for child in DirAccess.get_directories_at(directory):
		if not child.begins_with("."):
			_scan(directory.path_join(child), result)

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
