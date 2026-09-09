@tool
class_name StoryModule
extends PluginModule
## Markdown story runtime shared by standard and .NET Godot projects.

const MODULE_ID := &"story"

func get_module_id() -> StringName:
	return MODULE_ID

func get_runtime_root() -> String:
	return module_root.path_join("gdscript")

func get_example_scene_path() -> String:
	return module_root.path_join("examples/story_demo.tscn")
