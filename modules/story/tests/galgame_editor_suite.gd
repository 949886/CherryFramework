@tool
extends RefCounted
## Run in a real editor process, not a runtime imitation of editor_hint.

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
	# Base scenes are opened directly while authoring too. In particular the
	# shell and slot template must not run the settings-only control builder.
	for file in ["galgame/dialogue_box", "galgame/choice_button", "galgame/slot_card", "galgame/menu_page", "galgame/slots", "galgame/settings", "galgame/save", "galgame/load", "galgame/confirm", "galgame/backlog", "galgame/flow", "galgame/ending", "galgame_presenter"]:
		var resource := load(module_root.path_join("scenes/" + file + ".tscn")) as PackedScene
		var view: Variant = resource.instantiate(PackedScene.GEN_EDIT_STATE_INSTANCE)
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1280, 720)
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		host.add_child(viewport)
		var container := Control.new()
		container.size = Vector2(1280, 720)
		viewport.add_child(container)
		container.add_child(view)
		for i in range(12): await host.get_tree().process_frame
		var preview: Node = view.get_node("EditorPreview")
		check(preview._built, "editor preview builds: " + file)
		check(view.theme != null and view.theme.default_font_size == 16, "shared editor theme: " + file)
		if "--story-editor-render" in OS.get_cmdline_user_args():
			RenderingServer.force_draw(false)
			viewport.get_texture().get_image().save_png("user://editor-" + file.get_file() + ".png")
		if view is StoryMenuPage:
			check(view.heading.text == view.title and view.size == Vector2(1280, 720), "page title and virtual canvas: " + file)
			if file == "galgame/menu_page":
				check(view.page == "shell" and view.body.get_child_count() == 0, "base menu previews only its authored shell")
			if file == "galgame/slots":
				check(view.page == "slots" and view.fields.is_empty(), "base slots previews cards without settings controls")
			if view.page == "settings":
				check(view.fields.size() > 0 and view.preview != null, "settings shows real fields and dialogue preview")
				preview.settings_section = "sound"
				preview._refresh()
				for i in range(6): await host.get_tree().process_frame
				check(view.preview == null and view.fields.has("master"), "Inspector switches preview to sound category")
			elif view.page in ["slots", "save", "load"]:
				check(view._slot_cards.size() == 6, "six actual slot templates in editor")
				check(view._slot_cards[0].stamp.text.contains("编辑预览"), "slot preview uses sample data")
		elif view is StoryGalgamePresenter:
			check(not view._initialized and view.menu.navigator.get_child_count() == 0, "editor never starts runtime or Cherry navigation")
			check(view.choices_panel.get_child_count() == 3 and not view.dialogue.text.text.is_empty(), "editor shows dialogue and choice templates")
			check(view.dialogue.size.y == 185, "editor-only label padding cannot inflate the default dialogue")
			preview.settings = {"font_size": 36, "line_height": 2.2}
			preview._refresh()
			check(is_equal_approx(view.dialogue.size.y, 36 * 2.2 * 2 + 102), "editor fits large text with the same height calculation as runtime")
		elif view is StoryDialogueBox:
			check(view.text.get_theme_stylebox("normal") is StyleBoxEmpty, "editor text field background cannot leak into dialogue")
			check(view.speaker.get_theme_stylebox("normal").get_margin(SIDE_LEFT) == 0, "editor label padding cannot move the nameplate")
			preview.settings = {"palette": "mint", "glass": true}
			preview._refresh()
			check(view.glass.visible and view.text.get_theme_color("default_color") == Color("36564d"), "Inspector preview settings use actual glass and text styles")
			(view.get_theme_stylebox("panel") as StyleBoxFlat).corner_radius_top_left = 29
		var nodes_before := _count(view)
		view.propagate_notification(Node.NOTIFICATION_EDITOR_PRE_SAVE)
		check(not preview._built and preview._generated.is_empty(), "save excludes generated editor content: " + file)
		if view is StoryDialogueBox:
			check(view.get_theme_stylebox("panel").corner_radius_top_left == 29, "saving preserves Inspector edits to a previewed StyleBox")
			check(view.text.text.is_empty() and not view.glass.visible, "save restores authored text and glass visibility")
		var saved := PackedScene.new()
		check(saved.pack(view) == OK, "authored scene still serializes: " + file)
		view.propagate_notification(Node.NOTIFICATION_EDITOR_POST_SAVE)
		for i in range(8): await host.get_tree().process_frame
		check(preview._built and _count(view) == nodes_before, "preview restores once after save: " + file)
		viewport.queue_free()
		for i in range(4): await host.get_tree().process_frame
	var demo: Control = load(module_root.path_join("examples/galgame_demo.tscn")).instantiate()
	var demo_viewport := SubViewport.new()
	demo_viewport.size = Vector2i(1280, 720)
	demo_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	host.add_child(demo_viewport)
	demo_viewport.add_child(demo)
	for i in range(12): await host.get_tree().process_frame
	var presenter: StoryGalgamePresenter = demo.get_node("Presenter")
	check(presenter.background.texture == presenter.backdrop and presenter.portrait.texture != null, "Demo editor preview uses configured character and backdrop")
	check(presenter.dialogue.speaker.text == presenter.characters[0].display_name, "Demo editor preview uses configured character name")
	check(not demo.get_node("StoryPlayer").is_playing, "Demo editor preview does not start the story")
	if "--story-editor-render" in OS.get_cmdline_user_args():
		RenderingServer.force_draw(false)
		demo_viewport.get_texture().get_image().save_png("user://editor-demo.png")
	demo_viewport.queue_free()
	for i in range(4): await host.get_tree().process_frame
	check(AudioServer.bus_count == bus_count, "preview never changes game audio buses")
	check(not FileAccess.file_exists("user://cherry_galgame/settings.cfg"), "preview never writes player settings")
	print("Galgame editor preview: %d passed, %d failed" % [checks - failures, failures])
	return {"checks": checks, "failures": failures}

func _count(node: Node) -> int:
	var count := 1
	for child in node.get_children(): count += _count(child)
	return count
