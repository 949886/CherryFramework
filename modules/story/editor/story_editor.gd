@tool
extends VBoxContainer
## Each open story owns a native CodeEdit and its undo history.
const ProjectFiles = preload("story_project_files.gd")
var files := ItemList.new()
var filter := LineEdit.new()
var title := Label.new()
var summary := Label.new()
var diagnostics := ItemList.new()
var editors := VBoxContainer.new()
var search_bar := HBoxContainer.new()
var query := LineEdit.new()
var caret_position := Label.new()
var empty := Label.new()
var documents: Dictionary = {}
var paths := PackedStringArray()
var current_path := ""
var _recovery_timer := Timer.new()
var _reload_dialog := ConfirmationDialog.new()
var _reload_path := ""

func _init() -> void:
	name = "StoryEditor"
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var menu := HBoxContainer.new()
	add_child(menu)
	_add_menu(menu, "File", ["Save", "Save All", "Reload from Disk", "Show in FileSystem", "Refresh Stories"], _file_action)
	_add_menu(menu, "Edit", ["Undo", "Redo", "Cut", "Copy", "Paste", "Select All"], _edit_action)
	_add_menu(menu, "Search", ["Find", "Find Next", "Find Previous"], _search_action)
	_add_menu(menu, "Story", ["Save All and Check Current", "Save All and Check Project"], _check_action)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	menu.add_child(title)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	var sidebar := VBoxContainer.new()
	sidebar.custom_minimum_size.x = 220 * EditorInterface.get_editor_scale()
	split.add_child(sidebar)
	filter.placeholder_text = "Filter Stories"
	filter.clear_button_enabled = true
	filter.text_changed.connect(func(_text): _update_list())
	sidebar.add_child(filter)
	files.size_flags_vertical = Control.SIZE_EXPAND_FILL
	files.item_selected.connect(func(index): open_path(files.get_item_metadata(index)))
	sidebar.add_child(files)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(body)
	body.add_child(search_bar)
	query.placeholder_text = "Find in current story"
	query.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	query.text_submitted.connect(func(_text): find_text(false))
	search_bar.add_child(query)
	for caption in ["Previous", "Next", "Close"]:
		var button := Button.new()
		button.text = caption
		button.pressed.connect(func():
			if caption == "Close": search_bar.hide()
			else: find_text(caption == "Previous"))
		search_bar.add_child(button)
	search_bar.hide()
	editors.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(editors)
	empty.text = "Select a story on the left to edit.\n.md and .story files are discovered throughout the project; README.md is excluded."
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editors.add_child(empty)
	diagnostics.custom_minimum_size.y = 120 * EditorInterface.get_editor_scale()
	diagnostics.item_selected.connect(_select_diagnostic)
	body.add_child(diagnostics)
	diagnostics.hide()
	summary.text = "Select a story to begin."
	summary.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.add_child(summary)
	caret_position.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	body.add_child(caret_position)
	add_child(_reload_dialog)
	_reload_dialog.dialog_text = "Discard this story's unsaved changes and reload the file from disk?"
	_reload_dialog.confirmed.connect(func(): _reload(_reload_path))
	_recovery_timer.one_shot = true
	_recovery_timer.wait_time = 1.0
	_recovery_timer.timeout.connect(store_recovery)
	add_child(_recovery_timer)

func _ready() -> void:
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(refresh_files)
	refresh_files()
	_restore_recovery()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_IN and is_node_ready():
		refresh_files()
		for path in documents:
			if not is_dirty(path) and FileAccess.file_exists(path):
				if FileAccess.get_file_as_string(path) != documents[path].saved: _reload(path)

func _add_menu(bar: HBoxContainer, caption: String, entries: Array, callback: Callable) -> void:
	var button := MenuButton.new()
	button.text = caption
	bar.add_child(button)
	for entry in entries: button.get_popup().add_item(entry)
	button.get_popup().id_pressed.connect(callback)

func refresh_files() -> void:
	paths = ProjectFiles.source_paths()
	_update_list()

func _update_list() -> void:
	var scroll := files.get_v_scroll_bar().value
	files.clear()
	var all_paths := paths.duplicate()
	for path in documents:
		if path not in all_paths: all_paths.append(path)
	all_paths.sort()
	for path in all_paths:
		if not filter.text.is_empty() and not path.containsn(filter.text): continue
		var index := files.add_item(path.get_file() + (" (*)" if is_dirty(path) else ""))
		files.set_item_metadata(index, path)
		files.set_item_tooltip(index, path)
		if path == current_path: files.select(index)
	files.get_v_scroll_bar().set_deferred("value", scroll)
	_update_labels()

func _update_labels() -> void:
	for index in files.item_count:
		var path: String = files.get_item_metadata(index)
		files.set_item_text(index, path.get_file() + (" (*)" if is_dirty(path) else ""))
	title.text = current_path.trim_prefix("res://") + (" (*)" if is_dirty(current_path) else "")
	_update_position()

func open_path(path: String, line: int = -1) -> void:
	if not MarkdownStory.supports_path(path): return
	if not documents.has(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			summary.text = "Cannot read: " + path
			return
		_create_document(path, file.get_as_text())
	current_path = path
	empty.hide()
	for key in documents: documents[key].editor.visible = key == path
	var editor := active_editor()
	if line >= 0:
		editor.set_caret_line(clampi(line, 0, editor.get_line_count() - 1))
		editor.center_viewport_to_caret()
	editor.grab_focus()
	_update_list()

func _create_document(path: String, text: String) -> void:
	var editor := CodeEdit.new()
	editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.gutters_draw_line_numbers = true
	editor.draw_tabs = true
	editor.minimap_draw = true
	editor.highlight_current_line = true
	editor.auto_brace_completion_enabled = true
	var settings := EditorInterface.get_editor_settings()
	var theme := EditorInterface.get_editor_theme()
	editor.add_theme_font_override("font", theme.get_font("source", "EditorFonts"))
	if settings.has_setting("interface/editor/code_font_size"):
		editor.add_theme_font_size_override("font_size", roundi(float(settings.get_setting("interface/editor/code_font_size")) * EditorInterface.get_editor_scale()))
	var highlighter := CodeHighlighter.new()
	highlighter.symbol_color = settings.get_setting("text_editor/theme/highlighting/symbol_color")
	highlighter.number_color = settings.get_setting("text_editor/theme/highlighting/number_color")
	highlighter.function_color = settings.get_setting("text_editor/theme/highlighting/function_color")
	highlighter.member_variable_color = settings.get_setting("text_editor/theme/highlighting/member_variable_color")
	highlighter.add_color_region("<!--", "-->", settings.get_setting("text_editor/theme/highlighting/comment_color"))
	highlighter.add_color_region("`", "`", settings.get_setting("text_editor/theme/highlighting/string_color"))
	highlighter.add_color_region("[", "]", settings.get_setting("text_editor/theme/highlighting/symbol_color"))
	editor.syntax_highlighter = highlighter
	editor.text = text
	editor.clear_undo_history()
	editor.hide()
	editors.add_child(editor)
	documents[path] = {"editor": editor, "saved": text}
	editor.text_changed.connect(func():
		_update_labels()
		_recovery_timer.start())
	editor.caret_changed.connect(_update_position)
	editor.gui_input.connect(_editor_input)

func active_editor() -> CodeEdit:
	return documents[current_path].editor if documents.has(current_path) else null

func is_dirty(path: String) -> bool:
	return documents.has(path) and documents[path].editor.text != String(documents[path].saved).replace("\r\n", "\n")

func unsaved_files() -> PackedStringArray:
	var result := PackedStringArray()
	for path in documents:
		if is_dirty(path): result.append(path)
	return result

func save_path(path: String) -> bool:
	if not is_dirty(path): return true
	# Never silently overwrite another editor's changes or a deleted source.
	if not FileAccess.file_exists(path) or FileAccess.get_file_as_string(path) != documents[path].saved:
		summary.text = "File changed outside Story: %s. Copy your edits or use File > Reload from Disk before saving." % path
		store_recovery()
		return false
	var temporary := path + ".cherry-saving-" + str(Time.get_ticks_usec())
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		summary.text = "Cannot write: " + path
		return false
	var content: String = documents[path].editor.text
	if String(documents[path].saved).contains("\r\n"):
		content = content.replace("\n", "\r\n")
	file.store_string(content)
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
		summary.text = "Save failed (%s): %s" % [error_string(error), path]
		return false
	documents[path].saved = content
	EditorInterface.get_resource_filesystem().update_file(path)
	summary.text = "Saved: " + path
	_update_list()
	store_recovery()
	return true

func save_all() -> bool:
	var ok := true
	for path in documents:
		if not save_path(path): ok = false
	return ok

func _reload(path: String) -> void:
	if not documents.has(path) or not FileAccess.file_exists(path): return
	var editor: CodeEdit = documents[path].editor
	documents[path].saved = FileAccess.get_file_as_string(path)
	var line := editor.get_caret_line()
	editor.text = documents[path].saved
	editor.clear_undo_history()
	editor.set_caret_line(mini(line, editor.get_line_count() - 1))
	_update_list()
	store_recovery()

func _file_action(id: int) -> void:
	match id:
		0: save_path(current_path)
		1: save_all()
		2:
			if is_dirty(current_path):
				_reload_path = current_path
				_reload_dialog.popup_centered()
			else: _reload(current_path)
		3:
			if not current_path.is_empty(): EditorInterface.get_file_system_dock().navigate_to_path(current_path)
		4: refresh_files()

func _edit_action(id: int) -> void:
	var editor := active_editor()
	if editor == null: return
	var actions := [TextEdit.MENU_UNDO, TextEdit.MENU_REDO, TextEdit.MENU_CUT, TextEdit.MENU_COPY, TextEdit.MENU_PASTE, TextEdit.MENU_SELECT_ALL]
	editor.menu_option(actions[id])
	editor.grab_focus()

func _search_action(id: int) -> void:
	search_bar.show()
	if id == 0: query.grab_focus()
	else: find_text(id == 2)

func find_text(backwards: bool) -> void:
	var editor := active_editor()
	if editor == null or query.text.is_empty(): return
	var flags := TextEdit.SEARCH_BACKWARDS if backwards else 0
	var line := editor.get_caret_line()
	var column := editor.get_caret_column()
	if backwards:
		column -= 1
		if column < 0:
			line = posmod(line - 1, editor.get_line_count())
			column = editor.get_line(line).length()
	var found := editor.search(query.text, flags, line, column)
	if found.x < 0:
		summary.text = "No match: " + query.text
		return
	editor.select(found.y, found.x, found.y, found.x + query.text.length())
	editor.set_caret_line(found.y)
	editor.set_caret_column(found.x if backwards else found.x + query.text.length())
	editor.center_viewport_to_caret()

func _editor_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	if event.is_command_or_control_pressed() and event.keycode == KEY_S:
		if event.shift_pressed: save_all()
		else: save_path(current_path)
	elif event.is_command_or_control_pressed() and event.keycode == KEY_F: _search_action(0)
	elif event.keycode == KEY_F3: find_text(event.shift_pressed)
	else: return
	get_viewport().set_input_as_handled()

func _update_position() -> void:
	var editor := active_editor()
	caret_position.text = "%d : %d  |  UTF-8" % [editor.get_caret_line() + 1, editor.get_caret_column() + 1] if editor else ""

func _check_action(id: int) -> void:
	if id == 1: check_all()
	elif not current_path.is_empty(): check_story(MarkdownStory.from_file(current_path))

func check_all() -> void:
	var stories := ProjectFiles.stories()
	var configured := {}
	for story in stories:
		configured[story.get_identity()] = true
	for path in ProjectFiles.source_paths():
		var story := MarkdownStory.from_file(path)
		if story != null and not configured.has(story.get_identity()): stories.append(story)
	check_stories(stories)

func check_story(story: Story) -> void:
	check_stories([story])

func check_stories(stories: Array[Story]) -> void:
	if not save_all(): return
	diagnostics.clear()
	var seen := {}
	var checked := {}
	var errors := 0
	for story in stories:
		if story == null: continue
		var entry_key := "%s:%s:%s:%s" % [story.get_identity(), story.get_source_path().get_extension(), story.commands.get_instance_id() if story.commands != null else 0, str(story.extra_files)]
		if checked.has(entry_key): continue
		checked[entry_key] = true
		var report := StoryValidator.new().validate(story)
		for diagnostic in report.diagnostics:
			var key := str(diagnostic)
			if seen.has(key): continue
			seen[key] = true
			if diagnostic.severity == "error": errors += 1
			var index := diagnostics.add_item("%s:%d [%s] %s" % [diagnostic.path, diagnostic.line, diagnostic.severity, diagnostic.message])
			diagnostics.set_item_metadata(index, diagnostic)
	diagnostics.visible = diagnostics.item_count > 0
	summary.text = "%d story entries — %d errors, %d warnings" % [checked.size(), errors, diagnostics.item_count - errors]

func _select_diagnostic(index: int) -> void:
	var diagnostic: Dictionary = diagnostics.get_item_metadata(index)
	open_path(diagnostic.path, int(diagnostic.line) - 1)

func _recovery_path() -> String:
	return EditorInterface.get_editor_paths().get_project_settings_dir().path_join("story_editor_recovery.cfg")

func store_recovery() -> void:
	var config := ConfigFile.new()
	for path in unsaved_files():
		config.set_value(path, "text", documents[path].editor.text)
		config.set_value(path, "saved", documents[path].saved)
	config.save(_recovery_path())

func _restore_recovery() -> void:
	var config := ConfigFile.new()
	if config.load(_recovery_path()) != OK: return
	for path in config.get_sections():
		if not MarkdownStory.supports_path(path): continue
		_create_document(path, config.get_value(path, "saved", ""))
		documents[path].editor.text = config.get_value(path, "text", "")
		open_path(path)
	if not config.get_sections().is_empty(): summary.text = "Recovered unsaved Story edits. Review and save when ready."
