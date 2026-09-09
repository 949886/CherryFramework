@tool
extends RefCounted
## One-way migration from the retired importer to native resource files.

static func migrate(directory: String = "res://") -> PackedStringArray:
	var changed := PackedStringArray()
	if FileAccess.file_exists(directory.path_join(".gdignore")):
		return changed
	for name in DirAccess.get_files_at(directory):
		if name.get_extension() != "import":
			continue
		var source := directory.path_join(name.trim_suffix(".import"))
		var metadata := source + ".import"
		var config := ConfigFile.new()
		if config.load(metadata) != OK or config.get_value("remap", "importer", "") != "cherry.story.markdown":
			continue
		if not String(config.get_value("params", "commands", "")).is_empty() or not config.get_value("params", "extra_files", PackedStringArray()).is_empty():
			push_warning("Migrate custom Story import options to a MarkdownStory .tres before removing: " + metadata)
			continue
		var backup := EditorInterface.get_editor_paths().get_project_settings_dir().path_join("story_legacy_imports").path_join(metadata.trim_prefix("res://"))
		if DirAccess.make_dir_recursive_absolute(backup.get_base_dir()) != OK or config.save(backup) != OK:
			continue
		# Retain IDs used by existing scene references when switching to .uid files.
		if MarkdownStory.supports_path(source) and not FileAccess.file_exists(source + ".uid") and config.has_section_key("remap", "uid"):
			var uid_file := FileAccess.open(source + ".uid", FileAccess.WRITE)
			if uid_file == null:
				continue
			uid_file.store_line(config.get_value("remap", "uid"))
			uid_file.close()
		if DirAccess.remove_absolute(metadata) == OK:
			changed.append(source)
	var access := DirAccess.open(directory)
	for child in DirAccess.get_directories_at(directory):
		if not child.begins_with(".") and not access.is_link(child):
			changed.append_array(migrate(directory.path_join(child)))
	return changed
