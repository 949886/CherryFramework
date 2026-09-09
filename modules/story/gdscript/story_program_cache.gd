@tool
class_name StoryProgramCache
extends RefCounted
## Bounded in-memory cache of compiled templates, never running story instances.

var capacity := 64
var compiler_version := StoryParser.COMPILER_VERSION
var hits := 0
var misses := 0
var compilations := 0
var diagnostics: Array[Dictionary] = []
var _templates: Dictionary = {}
var _lru: Array[String] = []

func clear() -> void:
	_templates.clear()
	_lru.clear()
	diagnostics.clear()

func size() -> int:
	return _templates.size()

func compile_file(path: String, story_id: String, enabled: bool = true, report_errors: bool = true) -> StoryProgram:
	diagnostics.clear()
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		diagnostics.append({"path": path, "line": 1, "column": 1, "severity": "error", "code": "story_file_missing", "message": "Cannot open story file."})
		return null
	var source := file.get_as_text()
	file.close()
	var key := JSON.stringify([compiler_version, story_id, path, source.sha256_text()]).sha256_text()
	_trim_to_capacity()
	if enabled and capacity > 0 and _templates.has(key):
		hits += 1
		_lru.erase(key)
		_lru.append(key)
		return (_templates[key] as StoryProgram).instantiate_program()
	misses += 1
	var parser := StoryParser.new()
	parser.report_errors = report_errors
	compilations += 1
	var template := parser.compile_source(source, story_id, path, false)
	diagnostics.assign(parser.diagnostics)
	if template == null:
		return null
	if enabled and capacity > 0:
		_templates[key] = template
		_lru.append(key)
		_trim_to_capacity()
	return template.instantiate_program()

func _trim_to_capacity() -> void:
	while _lru.size() > maxi(0, capacity):
		_templates.erase(_lru.pop_front())
