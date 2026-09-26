@tool
extends RefCounted
## Test-only editor code. Production UI scenes are passive, editable templates:
## no generated nodes, sample data, save hooks or page builders run in the editor.

const UI_SCRIPTS = [
	preload("../gdscript/story_galgame_presenter.gd"),
	preload("../gdscript/story_galgame_menus.gd"),
	preload("../gdscript/story_menu_page.gd"),
	preload("../gdscript/story_dialogue_box.gd"),
	preload("../gdscript/story_choice_button.gd"),
	preload("../gdscript/story_flow_view.gd"),
	preload("../gdscript/story_flow_canvas.gd"),
	preload("../gdscript/story_flow_card.gd"),
	preload("../gdscript/story_flow_minimap.gd"),
	preload("../gdscript/story_skin.gd"),
	preload("../gdscript/story_preferences.gd"),
]

var checks := 0
var failures := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func run(host: EditorPlugin) -> Dictionary:
	var module_root: String = host.module.module_root
	var bus_count := AudioServer.bus_count
	for script in UI_SCRIPTS:
		check(not script.is_tool(), "UI logic is runtime-only: " + script.resource_path)
	var scenes: Array[String] = ["scenes/galgame_presenter.tscn", "examples/galgame_demo.tscn"]
	for file in DirAccess.get_files_at(module_root.path_join("scenes/galgame")):
		if file.ends_with(".tscn"): scenes.append("scenes/galgame/" + file)
	for file in scenes:
		var resource := load(module_root.path_join(file)) as PackedScene
		var view := resource.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		var authored := _state(view)
		var container := Control.new()
		container.size = Vector2(1280, 720)
		host.add_child(container)
		container.add_child(view)
		for i in range(6): await host.get_tree().process_frame
		check(_state(view) == authored, "opening keeps authored nodes and content: " + file)
		check(_passive(view, module_root), "UI template has no editor generator or tool script: " + file)
		if view.has_node("Sheet/Margin/Layout/Header/Heading"):
			check(view.get_node("Sheet/Margin/Layout/Header/Heading").text == view.get("title"),
				"page heading is authored in the template: " + file)
		# Edit a real authored label, then verify neither save notifications nor
		# scene switching replace the designer's text with sample data.
		var label := view.find_children("*", "Label", true, false)
		for candidate in label:
			# Nested scene internals are edited in their own template, not by
			# changing a read-only child of the demo's presenter instance.
			if candidate.owner == view:
				candidate.text = "Authored edit"
				break
		var edited := _state(view)
		view.propagate_notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
		var saved := PackedScene.new()
		check(saved.pack(view) == OK, "template saves normally: " + file)
		view.propagate_notification(Node.NOTIFICATION_EDITOR_POST_SAVE)
		var restored := saved.instantiate()
		check(_state(restored) == edited, "template reload preserves authored edits: " + file)
		restored.free()
		for cycle in range(2):
			container.remove_child(view)
			for i in range(2): await host.get_tree().process_frame
			container.add_child(view)
			for i in range(6): await host.get_tree().process_frame
			check(_state(view) == edited, "switching scene keeps template unchanged: " + file)
		container.queue_free()
		for i in range(3): await host.get_tree().process_frame
	await _check_editor_tabs(host, module_root)
	check(AudioServer.bus_count == bus_count, "opening templates never changes audio buses")
	check(not FileAccess.file_exists("user://cherry_galgame/settings.cfg"), "opening templates never writes player settings")
	print("Galgame editor templates: %d passed, %d failed" % [checks - failures, failures])
	return {"checks": checks, "failures": failures}

func _state(node: Node) -> Array:
	# Container-computed rectangles are intentionally excluded: Godot's layout
	# engine still runs normally. Content and node structure must remain static.
	var result: Array = [node.name, node.get_class()]
	if node is Label or node is RichTextLabel or node is Button: result.append(node.text)
	if node is Button: result.append(node.icon.resource_path if node.icon != null else "")
	if node is TextureRect: result.append(node.texture.resource_path if node.texture != null else "")
	for child in node.get_children(): result.append(_state(child))
	return result

func _passive(node: Node, module_root: String) -> bool:
	if node.name == "EditorPreview": return false
	var script := node.get_script() as Script
	# StoryPlayer's existing @tool declaration registers export dependencies;
	# it is not a UI renderer and must remain available to the export pipeline.
	if script != null and script.resource_path.begins_with(module_root.path_join("gdscript/")):
		if not script.resource_path.ends_with("/story_player.gd") and script.is_tool(): return false
	for child in node.get_children():
		if child.owner == null or not _passive(child, module_root): return false
	return true

func _check_editor_tabs(host: EditorPlugin, module_root: String) -> void:
	var snapshots := {}
	for page in ["settings", "save", "backlog", "settings", "flow", "save", "backlog", "settings"]:
		var path := module_root.path_join("scenes/galgame/%s.tscn" % page)
		EditorInterface.open_scene_from_path(path)
		for i in range(8): await host.get_tree().process_frame
		var root := EditorInterface.get_edited_scene_root()
		check(root != null and root.scene_file_path == path, "editor activates template tab: " + page)
		if root == null or root.scene_file_path != path: continue
		check(_passive(root, module_root), "editor tab only contains authored controls: " + page)
		if snapshots.has(page):
			check(root == snapshots[page].root and _state(root) == snapshots[page].state,
				"editor tab preserves template content: " + page)
		else:
			snapshots[page] = {"root": root, "state": _state(root)}
