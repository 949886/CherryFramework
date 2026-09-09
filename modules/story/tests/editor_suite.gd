@tool
extends RefCounted

const ProjectFiles = preload("../editor/story_project_files.gd")
var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()

func run(host: EditorPlugin) -> Dictionary:
	var module: StoryModule = host.module
	var screen: Control = module._panel
	var module_root: String = module.module_root
	check(module.get_module_id() == &"story" and module.get_runtime_root() == module_root.path_join("gdscript"), "module ID and paths survive relocation")
	check(module.get_example_scene_path() == module_root.path_join("examples/story_demo.tscn"), "example path follows installation")
	EditorInterface.set_main_screen_editor("Story")
	await host.get_tree().process_frame
	check(screen.is_visible_in_tree() and screen.get_parent() == EditorInterface.get_editor_main_screen(), "Story is a selectable main screen")
	check(not screen.find_children("*", "MenuButton", true, false).is_empty(), "main screen provides menu bar")
	var entry := load(module_root.path_join("examples/stories/mahiro.ja.md")) as Story
	check(module._inspector._can_handle(entry) and not module._inspector._can_handle(Resource.new()), "inspector actions target Story resources")
	module._check_story(entry)
	check(screen.diagnostics.item_count == 0 and screen.summary.text.contains("0 errors"), "example validation reports success")
	screen.refresh_files()
	check("res://original.ja.md" in screen.paths and "res://copy.ja.story" in screen.paths and "res://unused.md" in screen.paths, "source browser includes both formats and unreferenced stories")
	check("res://README.md" not in screen.paths, "source browser excludes README")
	screen.filter.text = "original.ja"
	screen.filter.text_changed.emit(screen.filter.text)
	check(screen.files.item_count == 2, "file filter applies to both formats")
	screen.filter.clear()
	screen.filter.text_changed.emit(screen.filter.text)
	var path := "res://copy.ja.md"
	screen.open_path(path)
	var editor: CodeEdit = screen.active_editor()
	check(editor != null and editor.gutters_draw_line_numbers and editor.minimap_draw, "native CodeEdit includes line numbers and minimap")
	check(not screen.is_dirty(path), "CRLF source opens without false dirty state")
	var original := FileAccess.get_file_as_string(path)
	editor.insert_text_at_caret("Edited ")
	check(screen.is_dirty(path) and path in screen.unsaved_files(), "edits mark the document dirty")
	screen.open_path("res://copy.ja.story")
	var second: CodeEdit = screen.active_editor()
	check(second != editor and not screen.is_dirty("res://copy.ja.story"), "documents own independent text and undo state")
	screen.open_path(path)
	editor.undo()
	check(not screen.is_dirty(path), "undo returns to saved CRLF baseline")
	editor.redo()
	check(screen.save_path(path) and not screen.is_dirty(path), "save updates disk and dirty state")
	var saved := FileAccess.get_file_as_string(path)
	check(saved.contains("Edited") and saved.contains("\r\n") and not saved.contains("\r\r\n"), "save preserves CRLF without doubling CR")
	editor.insert_text_at_caret("Unsaved ")
	write(path, "Guide: External edit\n")
	check(not screen.save_path(path) and FileAccess.get_file_as_string(path) == "Guide: External edit\n", "external changes cannot be overwritten")
	check(editor.text.contains("Unsaved"), "conflict preserves the editor buffer")
	screen.store_recovery()
	var recovery := ConfigFile.new()
	check(recovery.load(screen._recovery_path()) == OK and recovery.get_value(path, "text", "") == editor.text, "recovery retains unsaved text")
	module.on_plugin_exit_tree()
	await host.get_tree().process_frame
	module.on_plugin_enter_tree()
	screen = module._panel
	check(screen.documents.has(path) and screen.documents[path].editor.text.contains("Unsaved"), "plugin reenable restores recovery buffer")
	check(not screen.save_path(path), "recovered edit retains original conflict baseline")
	screen._reload(path)
	check(not screen.is_dirty(path), "explicit reload accepts external content")
	screen.active_editor().insert_text_at_caret("Do not resurrect ")
	DirAccess.remove_absolute(path)
	check(not screen.save_path(path) and not FileAccess.file_exists(path), "saving cannot resurrect a deleted file")
	write(path, original)
	screen._reload(path)
	write("res://diagnostic.story", "Guide: [undefined_editor_test_command]\n")
	screen.check_story(MarkdownStory.from_file("res://diagnostic.story"))
	check(screen.diagnostics.item_count == 1, "validation diagnostics appear in main screen")
	screen._select_diagnostic(0)
	check(screen.current_path == "res://diagnostic.story" and screen.active_editor().get_caret_line() == 0, "diagnostic selects source and line")
	# Keep the independent export stage's source discovery free of this fixture.
	write("res://diagnostic.story", "Guide: Fixed\n")
	screen._reload("res://diagnostic.story")

	for extension in MarkdownStory.SUPPORTED_EXTENSIONS:
		var source: String = "res://original.ja." + extension
		var target: String = "res://duplicated.ja." + extension
		var resource := load(source) as MarkdownStory
		var original_uid := ResourceLoader.get_resource_uid(source)
		check(resource != null and ResourceSaver.save(resource, target) == OK, "native Duplicate accepts ." + extension)
		check(FileAccess.get_file_as_bytes(source) == FileAccess.get_file_as_bytes(target), "Duplicate preserves exact source bytes: " + extension)
		check(resource.resource_path == source and resource.source_file == source, "Duplicate preserves original identity: " + extension)
		var copy_uid := ResourceUID.create_id()
		check(ResourceSaver.set_uid(target, copy_uid) == OK and copy_uid != original_uid, "Duplicate assigns independent UID: " + extension)
		check(ResourceLoader.get_resource_uid(source) == original_uid, "Duplicate keeps source UID: " + extension)
		EditorInterface.get_resource_filesystem().update_file(target)
		check(ResourceLoader.get_resource_uid(target) == copy_uid, "assigned destination UID survives filesystem refresh: " + extension)
		var copy := load(target) as MarkdownStory
		check(copy != null and copy.source_file == target and copy.get_story_id() == "duplicated", "duplicate loads with destination identity: " + extension)
		var picker := EditorResourcePicker.new()
		picker.base_type = "Story"
		picker.edited_resource = copy
		check(picker.edited_resource == copy, "Story resource slot accepts native ." + extension)
		picker.free()
		var player := StoryPlayer.new()
		player.name = "StoryPlayer"
		player.autoplay = false
		player.story = copy
		var packed := PackedScene.new()
		var scene_path: String = "res://duplicate_" + extension + ".tscn"
		check(packed.pack(player) == OK and ResourceSaver.save(packed, scene_path) == OK, "duplicate saves as scene external resource: " + extension)
		var restored := (load(scene_path) as PackedScene).instantiate() as StoryPlayer
		check(restored.story is MarkdownStory and restored.story.source_file == target, "scene reload keeps duplicate reference: " + extension)
		var closure := ProjectFiles.dependency_closure([scene_path])
		check(closure.has(module_root.path_join("gdscript/story_vm.gd")) and closure.has(module_root.path_join("resources/default_commands.tres")), "scene includes runtime dependency closure: " + extension)
		player.free()
		restored.free()
	var bytes := PackedByteArray([239, 187, 191]) + "Guide: 中文  \r\n\t> whitespace\r\n".to_utf8_buffer()
	var byte_file := FileAccess.open("res://bytes.en.md", FileAccess.WRITE)
	byte_file.store_buffer(bytes)
	byte_file.close()
	check(ResourceSaver.save(load("res://bytes.en.md"), "res://bytes_copy.en.story") == OK and FileAccess.get_file_as_bytes("res://bytes_copy.en.story") == bytes, "cross-format Duplicate preserves BOM, Unicode, CRLF and whitespace")
	check(module.save_all() and module.unsaved_status().is_empty(), "save-all clears all dirty documents")
	print("Editor: %d passed, %d failed" % [checks - failures, failures])
	return {"checks": checks, "failures": failures}
