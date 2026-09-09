@tool
extends RefCounted
const Palette = preload("../editor/story_syntax_palette.gd")

var checks := 0
var failures := 0
var screen: Control
var editor: CodeEdit
var native := TextEdit.new()
var settings: EditorSettings

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1
	if not ok: printerr("FAIL: " + label)

func color_at(map: Dictionary, column: int, fallback: Color) -> Color:
	var result := fallback
	var last := -1
	for key in map:
		if int(key) <= column and int(key) > last:
			last = int(key)
			result = map[key].color
	return result

func theme_color(name: String) -> Color:
	return Palette.get_color(name)

func native_palette() -> Dictionary:
	var values := {}
	for property in settings.get_property_list():
		if String(property.name).begins_with("text_editor/theme/"):
			values[property.name] = settings.get_setting(property.name)
	return values

func check_color(line: int, token: String, expected: String, label: String) -> void:
	var column := editor.get_line(line).find(token)
	check(column >= 0 and color_at(editor.syntax_highlighter.get_line_syntax_highlighting(line), column, theme_color("text_color")) == theme_color(expected), label)

func source(text: String) -> void:
	editor.text = text

func compare_native(code: String, wrapped: String, code_first_line: int, offset: int, label: String) -> void:
	source(wrapped)
	native.text = code
	native.syntax_highlighter.clear_highlighting_cache()
	var ok := true
	var remap := Palette.native_color_map()
	# Request the last line first, as minimap/scrolling can do.
	for line in range(native.get_line_count() - 1, -1, -1):
		var actual := editor.syntax_highlighter.get_line_syntax_highlighting(line + code_first_line)
		var expected := native.syntax_highlighter.get_line_syntax_highlighting(line)
		for column in native.get_line(line).length():
			var native_color := color_at(expected, column, theme_color("text_color"))
			if color_at(actual, column + offset, theme_color("text_color")) != remap.get(native_color, native_color):
				ok = false
	check(ok, label)

func run(host: EditorPlugin) -> Dictionary:
	await host.get_tree().create_timer(1.0).timeout
	settings = EditorInterface.get_editor_settings()
	var original_settings := native_palette()
	native.add_theme_color_override("font_color", theme_color("text_color"))
	native.syntax_highlighter = GDScriptSyntaxHighlighter.new()
	screen = host.module._panel
	screen.open_path("res://original.ja.md")
	editor = screen.active_editor()
	var original := editor.text
	check(is_equal_approx(theme_color("text_color").a, 1.0) and theme_color("text_color").get_luminance() > 0.85, "body text stays bright and opaque")
	check(editor.get_theme_color("font_color") == theme_color("text_color"), "uncolored prose uses the same palette text color")
	var roles := ["keyword", "function", "type", "speaker", "state", "string", "number"]
	var distinct := true
	for i in roles.size():
		for j in range(i + 1, roles.size()):
			var a := Palette.THEME.get_color(roles[i], &"StorySyntax")
			var b := Palette.THEME.get_color(roles[j], &"StorySyntax")
			var distance := absf(a.h - b.h)
			if minf(distance, 1.0 - distance) < 0.04: distinct = false
	check(distinct, "major syntax roles retain distinct hues")
	var code := "# Code comment, not a heading\nvar score: int = 50\nconst words = [\"[wait:3s]\", \"<!-- not a comment -->\"]\nfunc ready() -> bool:\n\treturn score > 0 and not words.is_empty()"
	compare_native(code, "```gdscript\n" + code + "\n```\n> Plain text 123", 1, 0, "fenced GDScript matches native colors at every character")
	check_color(7, "123", "text_color", "prose numbers are not GDScript numbers")
	compare_native("if score >= 80:", "\t`if score >= 80:`", 0, 2, "indented control flow matches native colors")
	compare_native("print(\"[save] # text\", Vector2.ZERO)", "`print(\"[save] # text\", Vector2.ZERO)`", 0, 1, "inline strings, functions and types match native colors")
	compare_native("var message = \"\"\"line one\n# [wait:3s]\nline three\"\"\"", "```gdscript\nvar message = \"\"\"line one\n# [wait:3s]\nline three\"\"\"\n```", 1, 0, "multiline GDScript strings stay native inside one fence")
	source("# Opening\n真尋@happy：Hello 123 [wait:3s]**world**.\n> Narration [audio:voice.wav|bus=Voice]\n- Choose a route\n>>[Continue](chapter2.story#Opening)\n![transition: fadein](../assets/room.svg)\n<!-- @sid:greeting -->")
	check_color(0, "Opening", "keyword_color", "Story heading highlighted")
	check_color(1, "真尋", "user_type_color", "Unicode speaker highlighted")
	check_color(1, "happy", "gdscript/annotation_color", "speaker state highlighted")
	check_color(1, "Hello", "text_color", "dialogue body uses editor text color")
	check_color(1, "123", "text_color", "dialogue numbers remain prose")
	check_color(1, "wait", "function_color", "command name highlighted")
	check_color(1, "3s", "string_color", "command argument highlighted")
	check_color(1, "world", "keyword_color", "bold content highlighted")
	check_color(1, ".", "text_color", "bold color ends at closing marker")
	check_color(2, "audio", "function_color", "narration command highlighted")
	check_color(2, "bus", "gdscript/annotation_color", "command attribute highlighted")
	check_color(2, "Voice", "string_color", "command attribute value highlighted")
	check_color(3, "Choose", "text_color", "choice caption remains readable prose")
	check_color(4, "Continue", "text_color", "jump caption is not a command")
	check_color(4, "chapter2", "string_color", "story jump destination highlighted")
	check_color(5, "transition", "function_color", "image command highlighted")
	check_color(5, "../assets", "string_color", "image path highlighted")
	check_color(6, "@sid", "comment_color", "stable ID metadata is a comment")
	source("<!-- comment\n# Not a heading\n- Not a choice\n-->\n# Title [save]\n- Caption [save]\n> [wait: <!-- still a comment -->]\n>>[Continue](path<!-- comment -->\n> [save](plain parentheses)")
	check_color(1, "Not", "comment_color", "heading markers inside comments stay comments")
	check_color(2, "Not", "comment_color", "choice markers inside comments stay comments")
	check_color(4, "save", "keyword_color", "heading text does not execute inline commands")
	check_color(5, "save", "text_color", "choice captions do not execute inline commands")
	check_color(6, "still", "comment_color", "comments take precedence over unfinished brackets")
	check_color(7, "comment", "comment_color", "comments take precedence over unfinished destinations")
	check_color(8, "save", "function_color", "parentheses in prose do not turn commands into links")
	source("[custom_command:anything][save]\n> After incomplete [wait:\n真尋: New line\n`if score > 1:\n> Still prose\n**unfinished\n普通文本")
	check_color(0, "custom_command", "function_color", "custom commands need no hardcoded keyword list")
	check_color(0, "save", "function_color", "adjacent command highlighted")
	check_color(2, "New", "text_color", "unclosed brackets do not color later lines")
	check_color(3, "if", "control_flow_keyword_color", "unfinished inline code still highlights")
	check_color(4, "Still", "text_color", "unfinished backticks do not color later lines")
	check_color(6, "普通", "text_color", "unfinished bold does not color later lines")
	source("<!-- comment\n```gdscript\nvar ignored = 2\n-->\n# Heading\n```gdscript\nvar broken = \"\"\"unfinished\n```\n> Prose\n```gdscript\nvar valid = 3\n```")
	check_color(2, "var", "comment_color", "fence text inside HTML comment does not open code")
	check_color(4, "Heading", "keyword_color", "multiline comment closes correctly")
	check_color(8, "Prose", "text_color", "malformed string cannot escape its code fence")
	check_color(10, "var", "keyword_color", "next fence starts with clean native lexer state")
	var sentinel := "user://highlight_must_not_execute.txt"
	source("```gdscript\nfunc _init():\n\tFileAccess.open(\"%s\", FileAccess.WRITE).store_string(\"executed\")\n```" % sentinel)
	editor.syntax_highlighter.get_line_syntax_highlighting(2)
	check(not FileAccess.file_exists(sentinel), "highlighting never instantiates author code")
	source("```gdscript\nvar score = 2\n```\n> End")
	check_color(1, "var", "keyword_color", "initial fence color cached")
	editor.set_line(0, "> Removed fence")
	check_color(1, "var", "text_color", "editing fence invalidates cached states")
	editor.undo()
	check_color(1, "var", "keyword_color", "undo restores fence highlighting")
	editor.insert_line_at(0, "<!-- @sid:test -->")
	check_color(2, "var", "keyword_color", "inserting lines preserves code mapping")
	editor.remove_line_at(0)
	check_color(1, "var", "keyword_color", "removing lines preserves code mapping")
	source("<!-- open\ncommand [save]\n-->\n> End")
	check_color(1, "save", "comment_color", "comment state cached")
	editor.set_line(0, "> Closed")
	check_color(1, "save", "function_color", "editing comment opener clears multiline cache")
	var text_before := editor.text
	var undo_before := editor.get_version()
	var old_color: Color = settings.get_setting("text_editor/theme/highlighting/function_color")
	settings.set_setting("text_editor/theme/highlighting/function_color", Color("e6a35a"))
	screen._refresh_editor_theme()
	check_color(1, "save", "function_color", "Story palette stays stable when native settings change")
	compare_native("print(42)", "`print(42)`", 0, 1, "native GDScript colors also refresh with settings")
	settings.set_setting("text_editor/theme/highlighting/function_color", old_color)
	screen._refresh_editor_theme()
	var old_palette_color := Palette.THEME.get_color(&"function", &"StorySyntax")
	Palette.THEME.set_color(&"function", &"StorySyntax", Color("ad92c4"))
	await host.get_tree().process_frame
	source("[save]")
	check_color(0, "save", "function_color", "editing palette resource updates open document")
	Palette.THEME.set_color(&"function", &"StorySyntax", old_palette_color)
	await host.get_tree().process_frame
	editor.text = text_before
	editor.clear_undo_history()
	undo_before = editor.get_version()
	screen._refresh_editor_theme()
	check(editor.text == text_before and editor.get_version() == undo_before, "theme refresh leaves text and undo history unchanged")
	screen.open_path("res://copy.ja.story")
	var second: CodeEdit = screen.active_editor()
	second.text = "[save]"
	check(second.syntax_highlighter != editor.syntax_highlighter, "each document owns its highlighter")
	check(color_at(second.syntax_highlighter.get_line_syntax_highlighting(0), 1, theme_color("text_color")) == theme_color("function_color"), ".story files use the same highlighting")
	screen.open_path("res://original.ja.md")
	check(screen.active_editor() == editor, "switching documents preserves the editor buffer")
	var long_story := PackedStringArray()
	for index in 2000:
		long_story.append("真尋@happy: 欢迎回来。[wait:3s]今天过得**怎么样**？")
	source("\n".join(long_story))
	var begin := Time.get_ticks_usec()
	editor.syntax_highlighter.get_line_syntax_highlighting(1999)
	print("PERF 2000-line state scan and last-line highlight: ", (Time.get_ticks_usec() - begin) / 1000.0, " ms")
	check_color(1999, "wait", "function_color", "scrolling to end of long story resolves syntax")
	settings.set_setting("text_editor/theme/color_theme", original_settings["text_editor/theme/color_theme"])
	check(native_palette() == original_settings, "Story palette does not modify global Godot colors")
	editor.text = original
	second.text = screen.documents["res://copy.ja.story"].saved
	native.free()
	print("Syntax: %d passed, %d failed" % [checks - failures, failures])
	return {"checks": checks, "failures": failures}
