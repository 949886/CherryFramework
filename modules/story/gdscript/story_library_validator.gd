@tool
class_name StoryLibraryValidator
extends RefCounted
## Shared diagnostics for the editor, CI and export. Never instantiate author code.

var _diagnostics: Array[Dictionary] = []
var _dependencies: Dictionary = {}

func validate(library: StoryLibrary) -> Dictionary:
	_diagnostics.clear()
	_dependencies.clear()
	if library == null:
		_add("", 1, "library_missing", "No StoryLibrary was provided.")
		return _result()
	if library.commands == null:
		_add(library.resource_path, 1, "registry_missing", "No command registry was configured.")
		return _result()
	for message in library.commands.validate():
		_add(library.resource_path, 1, "command_registry", message)
	var programs := {}
	var paths_to_ids := {}
	var aliases := library.get_story_aliases()
	if library.stories.is_empty():
		_add(library.resource_path, 1, "library_empty", "Story library is empty.")
	for story_id in library.stories:
		if not story_id is String or story_id.is_empty() or not library.stories[story_id] is Dictionary or library.stories[story_id].is_empty():
			_add(library.resource_path, 1, "library_entry", "Each story needs a non-empty string ID and locale dictionary.")
			continue
		programs[story_id] = {}
		for locale in library.stories[story_id]:
			var configured: Variant = library.stories[story_id][locale]
			if not locale is String or locale.is_empty() or not configured is String or configured.is_empty():
				_add(library.resource_path, 1, "library_locale", "Story '%s' has an invalid locale/file entry." % story_id)
				continue
			var path := library.absolute_path(configured)
			if paths_to_ids.has(path) and paths_to_ids[path] != story_id:
				_add(path, 1, "ambiguous_story_path", "One localized file maps to multiple story IDs.")
			paths_to_ids[path] = story_id
			if not FileAccess.file_exists(path):
				_add(path, 1, "story_file_missing", "Missing story '%s' (%s)." % [story_id, locale])
				continue
			_dependencies[path] = true
			var parser := StoryParser.new()
			parser.report_errors = false
			parser.story_aliases = aliases
			var program := parser.compile_source(FileAccess.get_file_as_string(path), story_id, path, false)
			if program == null:
				_diagnostics.append_array(parser.diagnostics)
				continue
			programs[story_id][locale] = program
			_check_commands(program, library.commands)
	for story_id in programs:
		_check_translations(programs[story_id])
		for locale in programs[story_id]:
			_check_jumps(programs[story_id][locale], locale, library, programs)
	for file in library.extra_files:
		var path := library.absolute_path(file)
		if FileAccess.file_exists(path) or ResourceLoader.exists(path):
			_dependencies[path] = true
		else:
			_add(path, 1, "extra_dependency_missing", "Missing explicitly declared dependency.")
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

func _check_jumps(program: StoryProgram, locale: String, library: StoryLibrary, programs: Dictionary) -> void:
	for instruction in program.instructions:
		if instruction.op != StoryProgram.Op.JMP or not instruction.data is Dictionary:
			continue
		var target_id := String(instruction.data.story)
		var line := int(instruction.get("source_line", 1))
		var target_path := library.resolve_path(target_id, locale)
		var target: StoryProgram
		for candidate in programs.get(target_id, {}).values():
			if candidate.source_path == target_path:
				target = candidate
				break
		if target == null:
			_add(program.source_path, line, "jump_story_missing", "Cannot resolve jump target '%s' for locale '%s'." % [target_id, locale])
		elif not String(instruction.data.label).is_empty() and target.resolve_label(instruction.data.label) < 0:
			_add(program.source_path, line, "jump_heading_missing", "Unknown target heading '%s' in '%s'." % [instruction.data.label, target_id])

func _check_translations(variants: Dictionary) -> void:
	var reference: Array[String] = []
	var reference_locale := ""
	for locale in variants:
		var program: StoryProgram = variants[locale]
		var ids: Array[String] = []
		for instruction in program.instructions:
			if instruction.sid_explicit:
				ids.append("%s:%s" % [instruction.sid, instruction.op])
		if reference_locale.is_empty():
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
