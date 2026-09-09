@tool
class_name StoryModule
extends PluginModule
## Markdown story runtime shared by standard and .NET Godot projects.

const MODULE_ID := &"story"
const EditorScreen = preload("editor/story_editor.gd")
const Inspector = preload("editor/story_inspector_plugin.gd")
const Exporter = preload("editor/story_export_plugin.gd")
const LegacyImports = preload("editor/legacy_story_imports.gd")

var _panel: Control
var _inspector: EditorInspectorPlugin
var _exporter: EditorExportPlugin

func on_plugin_enter_tree() -> void:
	_refresh_sources.call_deferred(LegacyImports.migrate())
	_panel = EditorScreen.new()
	EditorInterface.get_editor_main_screen().add_child(_panel)
	_panel.hide()
	plugin.add_tool_menu_item("Cherry: Check Stories", _check_all)
	_inspector = Inspector.new()
	_inspector.check_requested.connect(_check_story)
	_inspector.edit_requested.connect(edit_story)
	plugin.add_inspector_plugin(_inspector)
	_exporter = Exporter.new()
	plugin.add_export_plugin(_exporter)

func on_plugin_exit_tree() -> void:
	plugin.remove_tool_menu_item("Cherry: Check Stories")
	plugin.remove_inspector_plugin(_inspector)
	plugin.remove_export_plugin(_exporter)
	_panel.store_recovery()
	_panel.queue_free()
	_panel = null
	_inspector = null
	_exporter = null

func _refresh_sources(paths: PackedStringArray) -> void:
	if _panel == null:
		return
	for path in paths:
		EditorInterface.get_resource_filesystem().update_file(path)

func _check_all() -> void:
	_panel.check_all()
	EditorInterface.set_main_screen_editor("Story")

func _check_story(story: Story) -> void:
	_panel.check_story(story)
	EditorInterface.set_main_screen_editor("Story")

func edit_story(story: Story) -> void:
	if _panel != null and story != null:
		_panel.open_path(story.source_file if story is MarkdownStory else story.get_source_path())
		EditorInterface.set_main_screen_editor("Story")

func make_visible(visible: bool) -> void:
	if _panel != null:
		_panel.visible = visible

func save_all() -> bool:
	return _panel.save_all() if _panel != null else true

func unsaved_status() -> String:
	return "\n".join(_panel.unsaved_files()) if _panel != null else ""

func get_module_id() -> StringName:
	return MODULE_ID

func get_runtime_root() -> String:
	return module_root.path_join("gdscript")

func get_example_scene_path() -> String:
	return module_root.path_join("examples/story_demo.tscn")
