extends SceneTree

var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func _initialize() -> void:
	var parser := StoryParser.new()
	parser.report_errors = false
	for fixture in [
		["Guide: Before\n`else:`\nGuide: After", 2, "orphan"],
		["`elif true:`\n    Guide: No", 1, "orphan"],
		["`if true:`\n    `else:`\n        Guide: No", 2, "orphan"],
		["# repeated\nGuide: One\n# repeated\nGuide: Two", 3, "duplicate heading"],
		["<!-- @sid:a -->\n<!-- @sid:b -->\nGuide: Hi", 2, "no following event"],
		["Guide: Hi\n    Guide: Unexpected", 2, "indentation"],
		[">>[jump](##missing)", 1, "unknown heading"],
		[">>[jump](next.md#)", 1, "empty"],
	]:
		check(parser.compile_source(fixture[0], "bad", "res://bad.md") == null, "reject: " + fixture[2])
		check(not parser.diagnostics.is_empty() and parser.diagnostics[0].line == fixture[1] and parser.diagnostics[0].path == "res://bad.md", "source diagnostic: " + fixture[2])
	var valid := parser.compile_source("```gdscript\nvar n = 1\n```\n`if n == 1:`\n    `if false:`\n        Guide: Wrong\n    `elif true:`\n        Guide: Inner\n    `else:`\n        Guide: Wrong\n`else:`\n    Guide: Wrong\nGuide: After", "nested")
	check(valid != null and parser.diagnostics.is_empty(), "nested conditional remains valid and clears errors")
	var vm := StoryVM.new()
	vm.setup(valid)
	var lines: Array[String] = []
	for step in range(100):
		var instruction := vm.current_instruction()
		if instruction.op == StoryProgram.Op.DIA:
			lines.append(instruction.data.content)
			vm.advance()
		else:
			var result := vm.execute_internal(instruction)
			if result.get("finished", false):
				break
	check(lines == ["Inner", "After"], "nested branches consume all trailing content")
	var dotted := parser.compile_source(">>[next](chapter.one.md#scene.2)", "start")
	check(dotted.instructions[0].data == {"story": "chapter.one", "label": "scene.2"}, "dotted logical ID and cross-file heading")
	parser.story_aliases = {"res://stories/chapter.one.zh-cn.md": "chapter.one"}
	var localized := parser.compile_source(">>[next](chapter.one.zh-cn.md)", "start", "res://stories/start.md")
	check(localized.instructions[0].data.story == "chapter.one", "localized file resolves only by explicit library mapping")
	print("Parser: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
