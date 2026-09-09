@tool
class_name StoryModule
extends PluginModule
## Markdown story runtime shared by standard and .NET Godot projects.

const MODULE_ID := &"story"
const CheckPanel = preload("editor/story_check_panel.gd")
const Inspector = preload("editor/story_inspector_plugin.gd")
const Exporter = preload("editor/story_export_plugin.gd")
const Importer = preload("editor/markdown_story_import_plugin.gd")

var _panel: Control
var _inspector: EditorInspectorPlugin
var _exporter: EditorExportPlugin
var _importer: EditorImportPlugin

func on_plugin_enter_tree() -> void:
	_importer = Importer.new()
	plugin.add_import_plugin(_importer)
	_panel = CheckPanel.new()
	plugin.add_control_to_bottom_panel(_panel, "Story")
	plugin.add_tool_menu_item("Cherry: Check Stories", _check_all)
	_inspector = Inspector.new()
	_inspector.check_requested.connect(_check_story)
	plugin.add_inspector_plugin(_inspector)
	_exporter = Exporter.new()
	plugin.add_export_plugin(_exporter)

func on_plugin_exit_tree() -> void:
	plugin.remove_tool_menu_item("Cherry: Check Stories")
	plugin.remove_import_plugin(_importer)
	plugin.remove_inspector_plugin(_inspector)
	plugin.remove_export_plugin(_exporter)
	plugin.remove_control_from_bottom_panel(_panel)
	_panel.queue_free()
	_panel = null
	_inspector = null
	_exporter = null
	_importer = null

func _check_all() -> void:
	_panel.check_all()
	plugin.make_bottom_panel_item_visible(_panel)

func _check_story(story: Story) -> void:
	_panel.check_story(story)
	plugin.make_bottom_panel_item_visible(_panel)

func get_module_id() -> StringName:
	return MODULE_ID

func get_runtime_root() -> String:
	return module_root.path_join("gdscript")

func get_example_scene_path() -> String:
	return module_root.path_join("examples/story_demo.tscn")
