@tool
extends SyntaxHighlighter
## Story structure is highlighted here; GDScript tokens use Godot's own lexer.

const THEME_ROLES := {
	"text": "text_color",
	"marker": "symbol_color",
	"comment": "comment_color",
	"heading": "keyword_color",
	"speaker": "user_type_color",
	"state": "gdscript/annotation_color",
	"command": "function_color",
	"argument": "string_color",
	"emphasis": "keyword_color",
}

var _palette: Dictionary = {}
var _lines: Array[Dictionary] = []
var _blocks: Array[String] = []
var _active_block := -1
var _code_buffer := TextEdit.new()
var _gdscript := GDScriptSyntaxHighlighter.new()

func _init() -> void:
	_code_buffer.syntax_highlighter = _gdscript

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		_code_buffer.free()

func _update_cache() -> void:
	var editor := get_text_edit()
	if editor == null:
		return
	# SyntaxHighlighter's built-in edit callback only clears its own line cache.
	# Our fence/comment state must also be invalidated after insertions and undo.
	if not editor.lines_edited_from.is_connected(_source_changed):
		editor.lines_edited_from.connect(_source_changed)
	var settings := EditorInterface.get_editor_settings()
	for role in THEME_ROLES:
		_palette[role] = settings.get_setting("text_editor/theme/highlighting/" + THEME_ROLES[role])
	_code_buffer.add_theme_color_override("font_color", _palette.text)
	_gdscript.update_cache()

func _source_changed(_from: int, _to: int) -> void:
	clear_highlighting_cache()

func _clear_highlighting_cache() -> void:
	_lines.clear()
	_blocks.clear()
	_active_block = -1

func _ensure_lines() -> void:
	if not _lines.is_empty():
		return
	var editor := get_text_edit()
	var block := -1
	var code_lines := PackedStringArray()
	var in_comment := false
	for line in editor.get_line_count():
		var text := editor.get_line(line)
		var stripped := text.strip_edges()
		if block >= 0:
			if stripped == "```":
				_blocks[block] = "\n".join(code_lines)
				block = -1
				_lines.append({"kind": "fence"})
			else:
				_lines.append({"kind": "code", "block": block, "row": code_lines.size()})
				code_lines.append(text)
			continue
		if not in_comment and stripped.begins_with("```gdscript"):
			block = _blocks.size()
			_blocks.append("")
			code_lines.clear()
			_lines.append({"kind": "fence"})
			continue
		if not in_comment and stripped.begins_with("`") and not stripped.begins_with("``"):
			var start := text.length() - text.strip_edges(true, false).length()
			var end := start + stripped.length()
			var closed := stripped.length() > 1 and stripped.ends_with("`")
			var code_end := end - 1 if closed else end
			_lines.append({"kind": "inline", "block": _blocks.size(), "row": 0, "start": start + 1, "end": code_end})
			_blocks.append(text.substr(start + 1, code_end - start - 1))
			continue
		var comments: Array[Vector2i] = []
		var cursor := 0
		while cursor < text.length():
			var start := cursor if in_comment else text.find("<!--", cursor)
			if start < 0:
				break
			var close := text.find("-->", start if in_comment else start + 4)
			in_comment = close < 0
			cursor = text.length() if in_comment else close + 3
			comments.append(Vector2i(start, cursor))
		_lines.append({"kind": "prose", "comments": comments})
	if block >= 0:
		_blocks[block] = "\n".join(code_lines)

func _get_line_syntax_highlighting(line: int) -> Dictionary:
	_ensure_lines()
	var info := _lines[line]
	if info.kind == "code":
		return _code_colors(info)
	var text := get_text_edit().get_line(line)
	var colors := PackedColorArray()
	colors.resize(text.length())
	colors.fill(_palette.text)
	match info.kind:
		"fence":
			_paint(colors, 0, text.length(), "marker")
		"inline":
			_paint(colors, int(info.start) - 1, int(info.start), "marker")
			var code_colors := _code_colors(info)
			var current: Color = _palette.text
			for column in range(int(info.start), int(info.end)):
				if code_colors.has(column - int(info.start)):
					current = code_colors[column - int(info.start)].color
				colors[column] = current
			_paint(colors, int(info.end), text.length(), "marker")
		"prose":
			_highlight_prose(text, colors, info.comments)
	var result := {}
	for column in colors.size():
		if column == 0 or colors[column] != colors[column - 1]:
			result[column] = {"color": colors[column]}
	return result

func _code_colors(info: Dictionary) -> Dictionary:
	if _active_block != int(info.block):
		_active_block = int(info.block)
		_code_buffer.text = _blocks[_active_block]
		_code_buffer.clear_undo_history()
		# Reset even for identical blocks: unfinished strings must not cross fences.
		_gdscript.clear_highlighting_cache()
	return _gdscript.get_line_syntax_highlighting(int(info.row))

func _highlight_prose(text: String, colors: PackedColorArray, comments: Array) -> void:
	var stripped := text.strip_edges(true, false)
	var start := text.length() - stripped.length()
	if stripped.begins_with("# "):
		_paint(colors, start, text.length(), "heading")
		for span: Vector2i in comments:
			_paint(colors, span.x, span.y, "comment")
		return
	elif stripped.begins_with("- "):
		_paint(colors, start, start + 1, "marker")
		for span: Vector2i in comments:
			_paint(colors, span.x, span.y, "comment")
		return
	elif stripped.begins_with(">>"):
		_paint(colors, start, start + 2, "marker")
	elif stripped.begins_with(">") or stripped.begins_with("!["):
		_paint(colors, start, start + 1, "marker")
	elif not stripped.begins_with("[") and not stripped.begins_with("<!--"):
		var colon := text.find(":", start)
		var wide_colon := text.find("：", start)
		if colon < 0 or (wide_colon >= 0 and wide_colon < colon):
			colon = wide_colon
		var bracket := text.find("[", start)
		if colon > start and (bracket < 0 or colon < bracket):
			_paint(colors, start, colon, "speaker")
			var state := text.find("@", start)
			if state >= 0 and state < colon:
				_paint(colors, state, colon, "state")
			_paint(colors, colon, colon + 1, "marker")
	var cursor := start
	var comment_index := 0
	var bold := false
	while cursor < text.length():
		if comment_index < comments.size() and cursor >= comments[comment_index].x:
			var span: Vector2i = comments[comment_index]
			_paint(colors, span.x, span.y, "comment")
			cursor = span.y
			comment_index += 1
			continue
		if text.substr(cursor, 2) == "**":
			_paint(colors, cursor, cursor + 2, "marker")
			bold = not bold
			cursor += 2
			continue
		if text[cursor] == "[":
			var close := text.find("]", cursor + 1)
			var segment_end: int = comments[comment_index].x if comment_index < comments.size() else text.length()
			if close >= 0 and close < segment_end:
				var is_link := text.substr(close + 1, 1) == "(" and (
					(stripped.begins_with(">>[") and cursor == start + 2)
					or (stripped.begins_with("![") and cursor == start + 1))
				if not is_link or (cursor > 0 and text[cursor - 1] == "!"):
					_highlight_command(text, colors, cursor + 1, close)
				_paint(colors, cursor, cursor + 1, "marker")
				_paint(colors, close, close + 1, "marker")
				cursor = close + 1
				if is_link:
					var end := text.find(")", cursor + 1)
					if end < 0 or end >= segment_end:
						end = segment_end
					_paint(colors, cursor, cursor + 1, "marker")
					_paint(colors, cursor + 1, end, "argument")
					if end < segment_end:
						_paint(colors, end, end + 1, "marker")
					cursor = end + 1 if end < segment_end else end
				continue
		if bold:
			_paint(colors, cursor, cursor + 1, "emphasis")
		cursor += 1

func _highlight_command(text: String, colors: PackedColorArray, start: int, end: int) -> void:
	var colon := text.find(":", start)
	if colon < 0 or colon >= end:
		_paint(colors, start, end, "command")
		return
	_paint(colors, start, colon, "command")
	_paint(colors, colon, colon + 1, "marker")
	_paint(colors, colon + 1, end, "argument")
	var separator := text.find("|", colon + 1)
	while separator >= 0 and separator < end:
		_paint(colors, separator, separator + 1, "marker")
		var next := text.find("|", separator + 1)
		var attribute_end := end if next < 0 else mini(next, end)
		var equals := text.find("=", separator + 1)
		if equals >= 0 and equals < attribute_end:
			_paint(colors, separator + 1, equals, "state")
			_paint(colors, equals, equals + 1, "marker")
		separator = next

func _paint(colors: PackedColorArray, start: int, end: int, role: String) -> void:
	for column in range(maxi(start, 0), mini(end, colors.size())):
		colors[column] = _palette[role]
