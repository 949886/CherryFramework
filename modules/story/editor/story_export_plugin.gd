@tool
extends EditorExportPlugin
## String paths in Markdown are invisible to Godot's normal resource graph.

const ProjectFiles = preload("story_project_files.gd")
var _injected: Dictionary = {}

func _get_name() -> String:
	return "CherryStory"

func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
	_injected.clear()
	var preset := get_export_preset()
	var roots := preset.get_files_to_export()
	# Selected-scene/resource presets still export autoload dependencies.
	for setting in ProjectSettings.get_property_list():
		if String(setting.name).begins_with("autoload/"):
			roots.append(String(ProjectSettings.get_setting(setting.name)).trim_prefix("*"))
	var selected_only := preset.get_export_filter() in [EditorExportPreset.EXPORT_SELECTED_SCENES, EditorExportPreset.EXPORT_SELECTED_RESOURCES]
	if selected_only and roots.is_empty():
		return
	for story in ProjectFiles.stories(roots if selected_only else PackedStringArray()):
		if _excluded(story.resource_path):
			continue
		var report := StoryValidator.new().validate(story)
		for diagnostic in report.diagnostics:
			var severity := EditorExportPlatform.EXPORT_MESSAGE_ERROR if diagnostic.severity == "error" else EditorExportPlatform.EXPORT_MESSAGE_WARNING
			get_export_platform().add_message(severity, "Cherry Story", "%s:%d: %s" % [diagnostic.path, diagnostic.line, diagnostic.message])
		var dependencies := ProjectFiles.dependency_closure(report.dependencies)
		for dependency in dependencies:
			_include_resource(dependency)

func _include_resource(path: String) -> void:
	if _excluded(path):
		get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "Cherry Story", "Required dependency is excluded by the export preset: " + path)
		return
	if not path.begins_with("res://"):
		get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "Cherry Story", "Dependency must be inside res://: " + path)
		return
	var import_path := path + ".import"
	if FileAccess.file_exists(import_path):
		var config := ConfigFile.new()
		if config.load(import_path) != OK:
			return
		# add_file does not run importers: preserve remap metadata and binaries.
		_include_file(import_path)
		for imported in config.get_value("deps", "dest_files", PackedStringArray()):
			_include_file(imported)
	_include_file(path)

func _include_file(path: String) -> void:
	if _injected.has(path):
		return
	if _excluded(path):
		get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "Cherry Story", "Required dependency is excluded by the export preset: " + path)
		return
	if not FileAccess.file_exists(path):
		get_export_platform().add_message(EditorExportPlatform.EXPORT_MESSAGE_ERROR, "Cherry Story", "Cannot read export dependency: " + path)
		return
	_injected[path] = true
	add_file(path, FileAccess.get_file_as_bytes(path), false)

func _excluded(path: String) -> bool:
	var preset := get_export_preset()
	if preset.get_export_filter() == EditorExportPreset.EXCLUDE_SELECTED_RESOURCES and path in preset.get_files_to_export():
		return true
	for pattern in preset.get_exclude_filter().split(",", false):
		if path.trim_prefix("res://").matchn(pattern.strip_edges()) or path.get_file().matchn(pattern.strip_edges()):
			return true
	return false

func _export_file(path: String, _type: String, _features: PackedStringArray) -> void:
	# Keep source text even when Godot exports an imported .md resource directly.
	if path.get_extension().to_lower() == "md" and not _injected.has(path):
		_include_resource(path)
	if _injected.has(path):
		skip()

func _export_end() -> void:
	_injected.clear()
