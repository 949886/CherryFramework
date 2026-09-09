class_name StoryParser
extends RefCounted
## Markdown-like galgame script -> StoryProgram compiler.
##
## This is intentionally an MVP parser, but it already demonstrates the key
## architecture:
##   author text -> tiny 7-op IR + generated real GDScript.
##
## Supported surface syntax in this demo:
## - Initial ```gdscript fenced block: story-local fields/functions.
## - Later ```gdscript fenced blocks: executable code at that story position.
## - `if expression:` / `elif expression:` / `else:` using indentation.
## - Other `code` lines: executable GDScript statement(s).
## - Name@state: dialogue   (ASCII or Chinese colon is accepted).
## - > narration/article
## - - choice, with the choice body indented beneath the option.
## - # heading
## - >>[caption](file.md) and >>[caption](##heading)
## - ![transition: fadein](path) and ![popup](path)
## - [save] or other command-only lines (desugared into silent NAR content).
## - <!-- @sid:stable_name --> optionally assigns a stable ID to the next emitted event.
##
## Intentional first-version restrictions:
## - Story indentation accepts spaces or tabs. Tabs are normalized to 4-column
##   tab stops, because Godot's text editor may save indentation as tabs.
## - A single [ ... ] block is exactly one inline command.  `[wait:3s save]`
##   is invalid; write `[wait:3s][save]`.
## - The initial author GDScript block must not contain extends/class_name.

var _program: StoryProgram
var _lines: Array[Dictionary] = []
var _top_code: String = ""
var _generated_methods: Array[String] = []
var _fenced_exec_blocks: Dictionary = {}
var _condition_counter: int = 0
var _exec_counter: int = 0
var _auto_sid_occurrences: Dictionary = {}
var _pending_sid: String = ""
var _errors: Array[String] = []
var _current_source_line: int = 0

const STORY_TAB_WIDTH := 4


func compile_file(path: String, story_id: String) -> StoryProgram:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("Cannot open story: %s" % path)
		return null
	var source := file.get_as_text()
	file.close()
	return compile_source(source, story_id, path)


## Compiles in-memory source using the same pipeline as Markdown files.
func compile_source(source: String, story_id: String, path: String = "") -> StoryProgram:
	_reset()
	_program = StoryProgram.new()
	_program.story_id = story_id
	_program.source_path = path

	_preprocess(source)
	if not _errors.is_empty():
		_print_errors(path)
		return null

	_parse_sequence(0, 0)

	# A program always ends explicitly.  END also makes malformed fall-through
	# easier to inspect in a debugger.
	_emit(StoryProgram.Op.END, null, "end")

	_resolve_heading_jumps()
	_build_generated_gdscript()

	if not _errors.is_empty():
		_print_errors(path)
		return null

	var err := _program.create_runtime(null)
	if err != OK:
		return null
	return _program


func _reset() -> void:
	_program = null
	_lines.clear()
	_top_code = ""
	_generated_methods.clear()
	_fenced_exec_blocks.clear()
	_condition_counter = 0
	_exec_counter = 0
	_auto_sid_occurrences.clear()
	_pending_sid = ""
	_errors.clear()
	_current_source_line = 0


func _preprocess(source: String) -> void:
	## Separates fenced GDScript before tokenizing indentation.
	## The first fenced GDScript block before story content becomes the body of
	## the generated RefCounted class.  Later fenced blocks become EXE thunks.
	var raw_lines := source.replace("\r\n", "\n").replace("\r", "\n").split("\n")
	var story_started := false
	var i := 0

	while i < raw_lines.size():
		var raw := String(raw_lines[i])

		var stripped := raw.strip_edges()
		if stripped.begins_with("```gdscript"):
			# Markdown/story indentation is normalized to visual columns. This makes
			# a file stable whether the editor stores one indent level as four spaces
			# or as one tab. GDScript inside the fence is *not* normalized; after the
			# structural prefix is removed, its original whitespace is preserved.
			var fence_indent := _story_indent_columns(raw)
			var block_start_line := i + 1
			var code_lines: Array[String] = []
			i += 1
			while i < raw_lines.size() and String(raw_lines[i]).strip_edges() != "```":
				var code_raw := String(raw_lines[i])
				# Remove only the story/Markdown indentation that belongs to the fence.
				# Any remaining spaces/tabs belong to the author's GDScript and must
				# reach Godot's own GDScript parser unchanged.
				code_raw = _strip_story_indent_prefix(code_raw, fence_indent)
				code_lines.append(code_raw)
				i += 1
			if i >= raw_lines.size():
				_errors.append("line %d: unclosed ```gdscript fence" % block_start_line)
				break

			var code := "\n".join(code_lines)
			if not story_started and _top_code.is_empty() and fence_indent == 0:
				_top_code = code
			else:
				var token := "__GAL_FENCED_EXEC_%d__" % _fenced_exec_blocks.size()
				_fenced_exec_blocks[token] = code
				_lines.append({
					"indent": fence_indent,
					"text": "`%s`" % token,
					"line": block_start_line,
				})
				story_started = true
			i += 1
			continue

		# Blank lines do not carry structural information in this DSL.
		if stripped.is_empty():
			i += 1
			continue

		# Store indentation as visual columns, but slice the source using the actual
		# number of whitespace characters. Example: one leading tab has 4 columns
		# but occupies only one String character.
		var indent := _story_indent_columns(raw)
		var indent_chars := _leading_whitespace_length(raw)
		var text := raw.substr(indent_chars).strip_edges(false, true)
		_lines.append({"indent": indent, "text": text, "line": i + 1})

		# SID comments are metadata, not story content by themselves.
		if not _is_sid_comment(text):
			story_started = true
		i += 1

	_scan_save_variables()


func _parse_sequence(start_index: int, indent: int) -> int:
	## Compiles a sequence until indentation returns to a parent level or an
	## elif/else token must be handled by the parent `_parse_if` call.
	var i := start_index
	while i < _lines.size():
		var line := _lines[i]
		var line_indent := int(line["indent"])
		var text := String(line["text"])
		_current_source_line = int(line["line"])

		if line_indent < indent:
			break
		if line_indent > indent:
			_errors.append("line %d: unexpected indentation (expected column %d, got %d)" % [_current_source_line, indent, line_indent])
			i += 1
			continue

		if _is_sid_comment(text):
			_pending_sid = _parse_sid_comment(text)
			i += 1
			continue

		if text.begins_with("# "):
			var label := text.substr(2).strip_edges()
			if label.is_empty():
				_errors.append("line %d: empty heading" % _current_source_line)
			else:
				_program.labels[label] = _program.instructions.size()
			i += 1
			continue

		if _is_control_code(text, "elif") or _is_else_code(text):
			break

		if _is_control_code(text, "if"):
			i = _parse_if(i, indent)
			continue

		if text.begins_with("- "):
			i = _parse_choice_group(i, indent)
			continue

		_compile_simple_line(text)
		i += 1

	return i


func _parse_if(start_index: int, parent_indent: int) -> int:
	## Lowers an if/elif/else chain to only JIF + JMP.
	var i := start_index
	var end_jumps: Array[int] = []
	var first := true

	while i < _lines.size():
		var line := _lines[i]
		_current_source_line = int(line["line"])
		var code := _unwrap_backticks(String(line["text"]))
		var condition := ""

		if first:
			condition = _condition_from_control(code, "if")
			first = false
		else:
			condition = _condition_from_control(code, "elif")

		if condition.is_empty():
			_errors.append("line %d: invalid if/elif syntax" % _current_source_line)
			return i + 1

		var method_name := _new_condition_method(condition)
		var jif_ip := _emit(StoryProgram.Op.JIF, {"method": method_name, "target": -1}, "jif|%s" % condition)
		i += 1

		# An empty branch is allowed, but a non-empty branch must be indented.
		if i < _lines.size() and int(_lines[i]["indent"]) > parent_indent:
			var child_indent := int(_lines[i]["indent"])
			i = _parse_sequence(i, child_indent)

		# If an elif/else follows at the same indentation, the successful branch
		# needs to jump over the remaining chain.
		if i < _lines.size() and int(_lines[i]["indent"]) == parent_indent:
			var next_text := String(_lines[i]["text"])
			if _is_control_code(next_text, "elif"):
				end_jumps.append(_emit(StoryProgram.Op.JMP, -1, "if_end_jump"))
				_patch_target(jif_ip, _program.instructions.size())
				continue

			if _is_else_code(next_text):
				end_jumps.append(_emit(StoryProgram.Op.JMP, -1, "if_end_jump"))
				_patch_target(jif_ip, _program.instructions.size())
				i += 1
				if i < _lines.size() and int(_lines[i]["indent"]) > parent_indent:
					var else_indent := int(_lines[i]["indent"])
					i = _parse_sequence(i, else_indent)
				break

		_patch_target(jif_ip, _program.instructions.size())
		break

	var end_ip := _program.instructions.size()
	for jump_ip in end_jumps:
		_patch_target(jump_ip, end_ip)
	return i


func _parse_choice_group(start_index: int, indent: int) -> int:
	## CHO is emitted once; each option body is compiled linearly and gets a
	## destination index.  A compiler-generated JMP skips the other option bodies.
	var choice_ip := _emit(StoryProgram.Op.CHO, {"options": []}, "choice")
	var options: Array[Dictionary] = []
	var end_jumps: Array[int] = []
	var i := start_index

	while i < _lines.size():
		var line := _lines[i]
		if int(line["indent"]) != indent:
			break
		var text := String(line["text"])
		if not text.begins_with("- "):
			break

		_current_source_line = int(line["line"])
		var label := text.substr(2).strip_edges()
		if label.is_empty():
			_errors.append("line %d: empty choice label" % _current_source_line)

		i += 1
		var target_ip := _program.instructions.size()
		options.append({"text": label, "target": target_ip})

		if i < _lines.size() and int(_lines[i]["indent"]) > indent:
			var child_indent := int(_lines[i]["indent"])
			i = _parse_sequence(i, child_indent)

		# Even an empty option body receives a jump.  That makes each option's
		# destination unambiguous and keeps the lowering algorithm simple.
		end_jumps.append(_emit(StoryProgram.Op.JMP, -1, "choice_end_jump"))

	var end_ip := _program.instructions.size()
	for jump_ip in end_jumps:
		_patch_target(jump_ip, end_ip)

	var inst := _program.instructions[choice_ip]
	inst["data"] = {"options": options}

	# CHO is emitted before its option labels are known. Update its strict source
	# signature now that the complete choice header is available. Only the option
	# labels belong to the CHO itself; option bodies are separate instructions.
	var option_labels: Array[String] = []
	for option in options:
		option_labels.append(String(option.get("text", "")))
	var choice_signature := "choice|%s" % "\u001f".join(option_labels)
	inst["exact_signature"] = _make_exact_signature(StoryProgram.Op.CHO, choice_signature)

	# The old automatic CHO SID was based only on the word "choice", which made
	# it occurrence-order dependent. Once labels are known, retag only automatic
	# choices with a content-derived SID. Explicit @sid values are never changed.
	if not bool(inst.get("sid_explicit", false)):
		var old_sid := String(inst.get("sid", ""))
		# Keep the old occurrence-based SID as a lookup alias so format-v1 saves
		# that contain only that SID can still load. New snapshots store final_sid.
		# (A legacy SID without a position anchor cannot be made perfectly robust.)
		var final_sid := _auto_sid(StoryProgram.Op.CHO, choice_signature)
		inst["sid"] = final_sid
		_program.sid_to_ip[final_sid] = choice_ip

	_program.instructions[choice_ip] = inst
	return i


func _compile_simple_line(text: String) -> void:
	# Narrative jump must be checked before narration (`>`).
	if text.begins_with(">>"):
		_compile_story_jump(text)
		return

	if text.begins_with("!["):
		_compile_image(text)
		return

	if text.begins_with("`") and text.ends_with("`"):
		var code := _unwrap_backticks(text)
		if _fenced_exec_blocks.has(code):
			code = String(_fenced_exec_blocks[code])
		var method_name := _new_exec_method(code)
		_emit(StoryProgram.Op.EXE, {"method": method_name}, "exe|%s" % code)
		return

	if text.begins_with(">"):
		var content := text.substr(1).strip_edges()
		_validate_inline_commands(content)
		_emit(StoryProgram.Op.NAR, {"content": content, "silent": false}, "nar|%s" % content)
		return

	# A line made only from command brackets is a silent presentation event.
	# This keeps [save] and image/audio-only effects out of the story opcode set.
	if text.begins_with("[") and text.ends_with("]"):
		_validate_inline_commands(text)
		_emit(StoryProgram.Op.NAR, {"content": text, "silent": true}, "silent|%s" % text)
		return

	var colon_index := _find_dialogue_colon(text)
	if colon_index > 0:
		var head := text.substr(0, colon_index).strip_edges()
		var content := text.substr(colon_index + 1).strip_edges()
		var speaker := head
		var state := "default"
		var at_index := head.find("@")
		if at_index >= 0:
			speaker = head.substr(0, at_index).strip_edges()
			state = head.substr(at_index + 1).strip_edges()
		_validate_inline_commands(content)
		_emit(StoryProgram.Op.DIA, {
			"speaker": speaker,
			"state": state,
			"content": content,
		}, "dia|%s|%s|%s" % [speaker, state, content])
		return

	# Plain text is treated as article/narration.  This is a friendly fallback
	# for prose-heavy scripts and makes the parser less brittle while drafting.
	_validate_inline_commands(text)
	_emit(StoryProgram.Op.NAR, {"content": text, "silent": false}, "nar|%s" % text)


func _compile_story_jump(text: String) -> void:
	var link_start := text.find("](")
	if not text.begins_with(">>[") or link_start < 0 or not text.ends_with(")"):
		_errors.append("line %d: invalid story jump syntax" % _current_source_line)
		return

	var destination := text.substr(link_start + 2, text.length() - (link_start + 3)).strip_edges()
	var address := {"story": _program.story_id, "label": ""}

	if destination.begins_with("##"):
		address["label"] = destination.substr(2)
	elif destination.begins_with("#"):
		address["label"] = destination.substr(1)
	elif destination.ends_with(".md"):
		address["story"] = _story_id_from_filename(destination.get_file())
	else:
		_errors.append("line %d: jump target must be ##heading or *.md" % _current_source_line)
		return

	_emit(StoryProgram.Op.JMP, address, "jump|%s" % destination)


func _compile_image(text: String) -> void:
	var close_alt := text.find("](")
	if not text.begins_with("![") or close_alt < 0 or not text.ends_with(")"):
		_errors.append("line %d: invalid image syntax" % _current_source_line)
		return

	var alt := text.substr(2, close_alt - 2).strip_edges()
	var path := text.substr(close_alt + 2, text.length() - (close_alt + 3)).strip_edges()
	var content := ""

	if "popup" in alt.to_lower():
		content = "[popup:%s]" % path
	else:
		var transition := "none"
		if alt.to_lower().begins_with("transition:"):
			transition = alt.substr(alt.find(":") + 1).strip_edges()
		content = "[bg:%s|transition=%s]" % [path, transition]

	_emit(StoryProgram.Op.NAR, {"content": content, "silent": true}, "image|%s|%s" % [alt, path])


func _emit(op: int, data: Variant, signature: String) -> int:
	## Every emitted instruction keeps both the legacy SID and a strict source
	## signature. The SID is attempted first during load. If it no longer exists,
	## StorySaveManager falls back to instruction position + exact_signature recovery.
	var sid := _pending_sid
	var sid_explicit := not sid.is_empty()
	_pending_sid = ""
	if sid.is_empty():
		sid = _auto_sid(op, signature)
	elif _program.sid_to_ip.has(sid):
		_errors.append("line %d: duplicate SID '%s'" % [_current_source_line, sid])
		sid = _auto_sid(op, signature)
		sid_explicit = false

	var exact_signature := _make_exact_signature(op, signature)
	var ip := _program.add_instruction(op, sid, data, exact_signature, sid_explicit)
	var inst := _program.instructions[ip]
	inst["source_line"] = _current_source_line
	_program.instructions[ip] = inst
	return ip


func _make_exact_signature(op: int, source_signature: String) -> String:
	## This is intentionally strict rather than fuzzy. A punctuation change,
	## speaker/state change, inline-command change, or choice-label change makes
	## the signature different. It is stored directly in the save file so v1 of
	## the resolver can perform an unambiguous equality check with no heuristic.
	return "%d|%s" % [op, source_signature]


func _auto_sid(op: int, signature: String) -> String:
	## Content-derived automatic SID retained for backwards compatibility and
	## convenient identity when unchanged content moves. Explicit @sid remains a
	## stronger author-controlled identity, but is no longer required for saves.
	var base := "%s:%s:%s" % [_program.story_id, op, str(hash(signature))]
	var count := int(_auto_sid_occurrences.get(base, 0))
	_auto_sid_occurrences[base] = count + 1
	return base if count == 0 else "%s:%d" % [base, count]


func _patch_target(instruction_ip: int, target_ip: int) -> void:
	var inst := _program.instructions[instruction_ip]
	if inst["op"] == StoryProgram.Op.JIF:
		var data: Dictionary = inst["data"]
		data["target"] = target_ip
		inst["data"] = data
	else:
		inst["data"] = target_ip
	_program.instructions[instruction_ip] = inst


func _resolve_heading_jumps() -> void:
	# Local narrative jumps keep the heading name in the IR.  Resolution is done
	# by StoryVM at runtime so headings remain inspectable in debug output.
	for inst in _program.instructions:
		if int(inst["op"]) != StoryProgram.Op.JMP or not (inst.get("data") is Dictionary):
			continue
		var data: Dictionary = inst["data"]
		if String(data.get("story", "")) == _program.story_id:
			var label := String(data.get("label", ""))
			if not label.is_empty() and not _program.labels.has(label):
				_errors.append("line %d: unknown heading '%s'" % [int(inst.get("source_line", 0)), label])


func _new_condition_method(expression: String) -> StringName:
	var method_name := "__gal_cond_%04d" % _condition_counter
	_condition_counter += 1
	_generated_methods.append("func %s() -> bool:\n\treturn (%s)\n" % [method_name, expression])
	return StringName(method_name)


func _new_exec_method(code: String) -> StringName:
	var method_name := "__gal_exec_%04d" % _exec_counter
	_exec_counter += 1
	var body_lines := code.split("\n")
	var indented: Array[String] = []
	for line in body_lines:
		indented.append("\t" + String(line))
	if indented.is_empty() or code.strip_edges().is_empty():
		indented = ["\tpass"]
	_generated_methods.append("func %s() -> void:\n%s\n" % [method_name, "\n".join(indented)])
	return StringName(method_name)


func _build_generated_gdscript() -> void:
	if _top_code.contains("extends ") or _top_code.contains("class_name "):
		_errors.append("initial GDScript block must not declare extends/class_name; the engine wraps it in a RefCounted class")

	var pieces: Array[String] = [
		"extends RefCounted",
		"",
		"# Reserved bridge back to StoryPlayer. Trusted author GDScript may use it.",
		"var __gal_host: Object = null",
		"",
	]
	if not _top_code.strip_edges().is_empty():
		pieces.append(_top_code)
		pieces.append("")
	for method_source in _generated_methods:
		pieces.append(method_source)
	_program.generated_gdscript_source = "\n".join(pieces)


func _scan_save_variables() -> void:
	var regex := RegEx.new()
	# Only script members are persistent; indented function locals are not fields.
	regex.compile("^var\\s+([A-Za-z_][A-Za-z0-9_]*)")
	for code_line in _top_code.split("\n"):
		var result := regex.search(String(code_line))
		if result != null:
			var variable_name := StringName(result.get_string(1))
			if variable_name != &"__gal_host" and variable_name not in _program.save_variables:
				_program.save_variables.append(variable_name)


func _validate_inline_commands(content: String) -> void:
	## Only validates bracket-command shape. Markdown **bold** is intentionally
	## left untouched for StoryPresenter.
	var cursor := 0
	while cursor < content.length():
		var open := content.find("[", cursor)
		if open < 0:
			break
		var close := content.find("]", open + 1)
		if close < 0:
			_errors.append("line %d: unclosed inline command '['" % _current_source_line)
			return
		var body := content.substr(open + 1, close - open - 1)
		# Markdown links are not expected inside dialogue text in this MVP.
		# A whitespace inside the command body almost always means the forbidden
		# `[wait:3s save]` form. Paths with spaces should be renamed/escaped later.
		if " " in body or "\t" in body:
			_errors.append("line %d: one [...] block may contain only one command; use adjacent blocks like [wait:3s][save]" % _current_source_line)
			return
		cursor = close + 1


func _is_control_code(text: String, keyword: String) -> bool:
	if not text.begins_with("`") or not text.ends_with("`"):
		return false
	var code := _unwrap_backticks(text)
	return code.begins_with(keyword + " ") and code.ends_with(":")


func _is_else_code(text: String) -> bool:
	return text == "`else:`"


func _condition_from_control(code: String, keyword: String) -> String:
	if not code.begins_with(keyword + " ") or not code.ends_with(":"):
		return ""
	return code.substr(keyword.length() + 1, code.length() - keyword.length() - 2).strip_edges()


func _unwrap_backticks(text: String) -> String:
	return text.substr(1, text.length() - 2).strip_edges() if text.length() >= 2 else ""


func _find_dialogue_colon(text: String) -> int:
	var ascii := text.find(":")
	var full_width := text.find("：")
	if ascii < 0:
		return full_width
	if full_width < 0:
		return ascii
	return mini(ascii, full_width)


func _is_sid_comment(text: String) -> bool:
	return text.begins_with("<!-- @sid:") and text.ends_with("-->")


func _parse_sid_comment(text: String) -> String:
	var value := text.trim_prefix("<!-- @sid:").trim_suffix("-->").strip_edges()
	if value.is_empty():
		_errors.append("line %d: empty @sid" % _current_source_line)
	return value


func _story_id_from_filename(filename: String) -> String:
	var base := filename.trim_suffix(".md")
	var parts := base.split(".")
	# `mahiro_h.ja.md` or `mahiro_h.zh-cn.md` -> `mahiro_h`.
	if parts.size() >= 2:
		return String(parts[0])
	return base


func _story_indent_columns(text: String) -> int:
	## Converts leading story whitespace to visual columns. A tab advances to the
	## next 4-column tab stop, matching the common Godot editor configuration.
	## Only Markdown/story structure uses this value; fenced GDScript keeps its
	## own original indentation after `_strip_story_indent_prefix()`.
	var columns := 0
	var index := 0
	while index < text.length():
		var ch := text.substr(index, 1)
		if ch == " ":
			columns += 1
		elif ch == "\t":
			columns += STORY_TAB_WIDTH - (columns % STORY_TAB_WIDTH)
		else:
			break
		index += 1
	return columns


func _strip_story_indent_prefix(text: String, target_columns: int) -> String:
	## Removes at most `target_columns` worth of *leading* story whitespace.
	## This is used for nested fenced GDScript blocks: the common Markdown prefix
	## is removed, while extra indentation belonging to GDScript remains intact.
	if target_columns <= 0:
		return text

	var columns := 0
	var index := 0
	while index < text.length() and columns < target_columns:
		var ch := text.substr(index, 1)
		if ch == " ":
			columns += 1
			index += 1
		elif ch == "\t":
			var next_columns := columns + STORY_TAB_WIDTH - (columns % STORY_TAB_WIDTH)
			# Do not consume a tab if doing so would remove indentation that belongs
			# to the GDScript block itself rather than the Markdown fence.
			if next_columns > target_columns:
				break
			columns = next_columns
			index += 1
		else:
			break
	return text.substr(index)


func _leading_whitespace_length(text: String) -> int:
	var count := 0
	while count < text.length():
		var ch := text.substr(count, 1)
		if ch != " " and ch != "\t":
			break
		count += 1
	return count


func _print_errors(path: String) -> void:
	for error_message in _errors:
		push_error("%s: %s" % [path, error_message])
