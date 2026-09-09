@tool
extends VBoxContainer

const ProjectFiles = preload("story_project_files.gd")
var summary: Label
var items: ItemList
var source: CodeEdit
var diagnostics: Array[Dictionary] = []

func _init() -> void:
	custom_minimum_size.y = 260
	var button := Button.new()
	button.text = "Check all Story libraries"
	button.pressed.connect(check_all)
	add_child(button)
	summary = Label.new()
	summary.text = "Check syntax, commands, assets, jumps and translation SIDs."
	add_child(summary)
	var split := HSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)
	items = ItemList.new()
	items.custom_minimum_size.x = 480
	items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	items.item_selected.connect(_show_source)
	split.add_child(items)
	source = CodeEdit.new()
	source.editable = false
	source.gutters_draw_line_numbers = true
	source.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(source)

func check_all() -> void:
	check_libraries(ProjectFiles.libraries())

func check_library(library: StoryLibrary) -> void:
	check_libraries([library])

func check_libraries(libraries: Array[StoryLibrary]) -> void:
	diagnostics.clear()
	items.clear()
	source.text = ""
	var errors := 0
	for library in libraries:
		var report := StoryLibraryValidator.new().validate(library)
		errors += report.errors
		diagnostics.append_array(report.diagnostics)
	for diagnostic in diagnostics:
		items.add_item("%s:%d  [%s / %s] %s" % [String(diagnostic.path).trim_prefix("res://"), diagnostic.line, diagnostic.severity, diagnostic.code, diagnostic.message])
	summary.text = "%d libraries — %d errors, %d warnings" % [libraries.size(), errors, diagnostics.size() - errors]
	if not diagnostics.is_empty():
		items.select(0)
		_show_source(0)

func _show_source(index: int) -> void:
	var diagnostic := diagnostics[index]
	source.text = FileAccess.get_file_as_string(diagnostic.path) if FileAccess.file_exists(diagnostic.path) else "Source file is unavailable."
	source.set_caret_line(clampi(int(diagnostic.line) - 1, 0, source.get_line_count() - 1))
	source.center_viewport_to_caret()
