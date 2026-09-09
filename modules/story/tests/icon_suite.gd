@tool
extends RefCounted
var checks := 0
var failures := 0
var events := 0
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1
	if not ok: printerr("FAIL: " + label)
func run(host: EditorPlugin) -> Dictionary:
	await host.get_tree().create_timer(2.0).timeout
	var fs := EditorInterface.get_resource_filesystem()
	var on_changed := func(): events += 1
	fs.filesystem_changed.connect(on_changed)
	var dock := EditorInterface.get_file_system_dock()
	for path in ["res://original.ja.md", "res://copy.ja.md", "res://original.ja.story", "res://copy.ja.story"]:
		check(fs.get_file_type(path) == "Resource", path + " indexed as Resource")
		dock.navigate_to_path(path)
		for i in 3: await host.get_tree().process_frame
		var tree: Tree = dock.find_children("*", "Tree", true, false)[0]
		var icon := tree.get_selected().get_icon(0)
		check(icon != null and icon.resource_path.ends_with("/icons/story.svg"), path + " has unified Story icon")
	check(FileAccess.file_exists("res://README.md") and fs.get_file_type("res://README.md") in ["", "TextFile"], "README is not indexed as a Story resource")
	check(not MarkdownStoryFormatLoader.new()._recognize_path("res://README.md", &"Resource"), "Story loader leaves README to Godot's text handling")
	var cached: Resource = load("res://original.ja.md")
	check(cached.is_class("TextFile"), "Script editor text resource is preserved")
	var editor := EditorInterface.get_script_editor()
	var code := editor.get_current_editor().get_base_editor() as CodeEdit
	var before := code.text
	code.insert_text_at_caret("unsaved ")
	await host.get_tree().process_frame
	var uid := ResourceLoader.get_resource_uid("res://original.ja.md")
	host.module._queue_source_refresh()
	for i in 4: await host.get_tree().process_frame
	check(code.text.contains("unsaved") and not editor.get_unsaved_files().is_empty(), "refresh preserves unsaved Script buffer")
	check(ResourceLoader.get_resource_uid("res://original.ja.md") == uid, "refresh preserves UID")
	code.undo()
	check(code.text == before and editor.get_unsaved_files().is_empty(), "test leaves restored Script tab clean")
	var before_events := events
	host.module._queue_source_refresh()
	await host.get_tree().create_timer(1.0).timeout
	check(events == before_events, "refresh is idempotent and does not cause scan loops")
	check(ResourceSaver.save(cached, "res://duplicate.ja.md") == OK, "cached text still duplicates")
	await host.get_tree().process_frame
	check(load("res://duplicate.ja.md") is MarkdownStory, "duplicate still loads as Story")
	fs.filesystem_changed.disconnect(on_changed)
	print("Icons: %d passed, %d failed" % [checks - failures, failures])
	return {"checks": checks, "failures": failures}
