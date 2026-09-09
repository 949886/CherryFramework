@tool
class_name StoryValidator
extends RefCounted
## Validate one story entry, all sibling translations and reachable file jumps.

var _diagnostics: Array[Dictionary] = []
var _dependencies: Dictionary = {}

func validate(entry: Story) -> Dictionary:
	_diagnostics.clear()
	_dependencies.clear()
	if entry == null:
		_add("", 1, "story_missing", "No Story resource was provided.")
		return _result()
	var pending: Array[Story] = [entry]
	var visited := {}
	var programs := {}
	var jumps: Array[Dictionary] = []
	while not pending.is_empty():
		var story: Story = pending.pop_back()
		if visited.has(story.get_identity()):
			continue
		visited[story.get_identity()] = true
		var source_path := story.get_source_path()
		if story.commands == null:
			_add(source_path, 1, "registry_missing", "No command registry was configured.")
			continue
		for message in story.commands.validate():
			_add(source_path, 1, "command_registry", message)
		var sources := story.get_sources()
		if sources.is_empty():
			_add(story.get_identity(), 1, "story_file_missing", "No story source files were found.")
		var variants := {}
		for locale in sources:
			var path := String(sources[locale])
			if not FileAccess.file_exists(path):
				_add(path, 1, "story_file_missing", "Story source is missing.")
				continue
			_dependencies[path] = true
			var parser := StoryParser.new()
			parser.report_errors = false
			var program := parser.compile_source(FileAccess.get_file_as_string(path), story.get_story_id(), path, false)
			if program == null:
				_diagnostics.append_array(parser.diagnostics)
				continue
			programs[path] = program
			variants[locale] = program
			_check_commands(program, story.commands)
			for instruction in program.instructions:
				if instruction.op != StoryProgram.Op.JMP or not instruction.data is Dictionary:
					continue
				var target := story.resolve_story(String(instruction.data.story))
				var line := int(instruction.get("source_line", 1))
				if target == null or target.get_source_path(locale).is_empty():
					_add(path, line, "jump_story_missing", "Cannot resolve jump target: %s" % instruction.data.story)
					continue
				pending.append(target)
				jumps.append({"path": path, "line": line, "target": target.get_source_path(locale), "label": instruction.data.label})
		_check_translations(variants)
		for file in story.extra_files:
			var path := file if file.is_absolute_path() else source_path.get_base_dir().path_join(file).simplify_path()
			if FileAccess.file_exists(path) or ResourceLoader.exists(path):
				_dependencies[path] = true
			else:
				_add(path, 1, "extra_dependency_missing", "Missing explicitly declared dependency.")
	for jump in jumps:
		var target: StoryProgram = programs.get(jump.target)
		if target != null and not String(jump.label).is_empty() and target.resolve_label(jump.label) < 0:
			_add(jump.path, jump.line, "jump_heading_missing", "Unknown heading '%s' in '%s'." % [jump.label, jump.target])
	return _result()

func _check_commands(program: StoryProgram, registry: StoryCommandRegistry) -> void:
	for instruction in program.instructions:
		if instruction.op not in [StoryProgram.Op.DIA, StoryProgram.Op.NAR]:
			continue
		for command in StoryInlineParser.new().parse(String(instruction.data.get("content", ""))):
			if command.type != "command":
				continue
			var line := int(instruction.get("source_line", 1))
			var handler := registry.find(StringName(command.name))
			if handler == null:
				_add(program.source_path, line, "unknown_command", "Unknown inline command: %s" % command.name)
				continue
			var message := handler.validate_argument(command)
			if not message.is_empty():
				_add(program.source_path, line, "command_argument", message)
				continue
			if handler.asset_type.is_empty():
				continue
			var path: String = command.argument if String(command.argument).is_absolute_path() else program.source_path.get_base_dir().path_join(command.argument).simplify_path()
			if not ResourceLoader.exists(path):
				_add(program.source_path, line, "asset_missing", "Missing asset: %s" % path)
				continue
			var asset := load(path)
			if asset == null or not asset.is_class(handler.asset_type):
				_add(program.source_path, line, "asset_type", "Expected %s: %s" % [handler.asset_type, path])
				continue
			_dependencies[path] = true

func _check_translations(variants: Dictionary) -> void:
	var reference: Array[String] = []
	var reference_locale := ""
	var has_reference := false
	for locale in variants:
		var program: StoryProgram = variants[locale]
		var ids: Array[String] = []
		for instruction in program.instructions:
			if instruction.sid_explicit:
				ids.append("%s:%s" % [instruction.sid, instruction.op])
		if not has_reference:
			has_reference = true
			reference_locale = locale
			reference = ids
		elif ids != reference:
			_add(program.source_path, 1, "translation_sid_mismatch", "Explicit SID order/types differ from locale '%s'." % reference_locale, "warning")

func _add(path: String, line: int, code: String, message: String, severity: String = "error") -> void:
	_diagnostics.append({"path": path, "line": line, "column": 1, "code": code, "message": message, "severity": severity})

func _result() -> Dictionary:
	var dependencies := PackedStringArray(_dependencies.keys())
	dependencies.sort()
	var errors := 0
	for diagnostic in _diagnostics:
		if diagnostic.severity == "error":
			errors += 1
	return {"diagnostics": _diagnostics.duplicate(true), "dependencies": dependencies, "errors": errors, "ok": errors == 0}
