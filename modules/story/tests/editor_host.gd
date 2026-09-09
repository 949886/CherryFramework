@tool
extends EditorPlugin
## Installed only in the isolated test project by run_tests.py.

var module: StoryModule

func _enter_tree() -> void:
	module = StoryModule.new()
	module._attach(self, "res://shared/cherry_core")
	module.on_plugin_enter_tree()
	if "--story-editor-check" in OS.get_cmdline_user_args():
		_probe.call_deferred()

func _probe() -> void:
	var library := load(module.module_root.path_join("examples/story_library.tres")) as StoryLibrary
	module._check_library(library)
	var report := StoryLibraryValidator.new().validate(library)
	var inspector_ok: bool = module._inspector._can_handle(library)
	var panel_ok: bool = module._panel.is_inside_tree() and module._panel.diagnostics.size() == report.diagnostics.size()
	var player := StoryPlayer.new()
	var packed := PackedScene.new()
	packed.pack(player)
	var saved_path := "res://fresh_player.tscn"
	var saved_ok := ResourceSaver.save(packed, saved_path) == OK
	var closure: Dictionary = preload("../editor/story_project_files.gd").dependency_closure([saved_path])
	var runtime_ok := closure.has(module.module_root.path_join("gdscript/story_vm.gd")) and closure.has(module.module_root.path_join("resources/default_commands.tres"))
	player.free()
	DirAccess.remove_absolute(saved_path)
	# Exercise deregistration and registration in a live editor tree.
	module.on_plugin_exit_tree()
	module.on_plugin_enter_tree()
	if report.ok and inspector_ok and panel_ok and saved_ok and runtime_ok:
		print("Editor integration: passed")
		get_tree().quit()
	else:
		printerr("Editor integration failed: ", report, " runtime dependencies: ", closure)
		get_tree().quit(1)

func _exit_tree() -> void:
	if module != null:
		module.on_plugin_exit_tree()
		module = null
