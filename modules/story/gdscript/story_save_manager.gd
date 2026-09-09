class_name StorySaveManager
extends RefCounted
## Owns all persistence and save-position recovery for StoryVM.
##
## Design boundary:
## - StoryVM executes story control flow only.
## - StorySaveManager knows how a VM snapshot is serialized, restored and migrated.
## - Main/UI decides when to save/load and how to present diagnostics.
##
## Position recovery policy (save format v2):
## 1. If a saved SID still exists, SID wins immediately.
## 2. Otherwise verify instruction_index + op + exact_signature strictly.
## 3. Search +/- MAX_EXACT_SEARCH_RANGE for the exact same instruction.
## 4. If exact identity is lost, fall back to the nearest same resumable op.
## 5. If that does not exist, fall back to the nearest DIA.
##
## There is deliberately no fuzzy/fingerprint matching in this version.

const SAVE_FORMAT_VERSION := 2
const MAX_EXACT_SEARCH_RANGE := 32
const MAX_JSON_INTEGER := 9007199254740991
const MAX_VALUE_DEPTH := 64

var max_file_bytes := 16 * 1024 * 1024
var _file_sequence := 0

## Only presentation instructions are safe generic resume points. Internal
## control-flow instructions may execute author GDScript and must not be used as
## fallback positions because doing so can repeat side effects.
const RESUMABLE_OPS := [
	StoryProgram.Op.DIA,
	StoryProgram.Op.NAR,
	StoryProgram.Op.CHO,
]

enum RestoreQuality {
	NONE,
	SID,
	EXACT_POSITION,
	EXACT_NEARBY,
	FALLBACK_SAME_TYPE,
	FALLBACK_DIALOGUE,
	FAILED,
}

## Diagnostics for the most recent restore_snapshot() call.
var last_restore_quality: int = RestoreQuality.NONE
var last_restore_from_ip: int = -1
var last_restore_to_ip: int = -1
var last_restore_message: String = ""

## Human-readable file error. UI code can show a localized message of its own;
## this field is mainly useful when debugging persistence failures.
var last_file_error: String = ""


func create_snapshot(vm: StoryVM, locale: String = "") -> Dictionary:
	## Captures story position and saveable author-GDScript member variables.
	##
	## The source line is intentionally a debugging hint only. Restoration never
	## uses Markdown line numbers.
	last_file_error = ""
	if vm == null or vm.program == null or vm.program.runtime == null:
		last_file_error = "Cannot save an unconfigured StoryVM."
		return {}

	var instruction := vm.current_instruction()
	var variables := _capture_script_variables(vm.program)
	if not _is_json_value(variables):
		last_file_error = "Story variables must be finite JSON data with string keys, safe integers and no cycles."
		return {}

	return {
		"format_version": SAVE_FORMAT_VERSION,
		"story_id": vm.program.story_id,
		"locale": locale,
		"sid": String(instruction.get("sid", "")),
		"sid_explicit": bool(instruction.get("sid_explicit", false)),
		"instruction_index": vm.ip,
		"op": int(instruction.get("op", StoryProgram.Op.END)),
		"exact_signature": String(instruction.get("exact_signature", "")),
		"source_line_hint": int(instruction.get("source_line", 0)),
		"variables": variables.duplicate(true),
	}


func save_to_file(path: String, vm: StoryVM, locale: String = "") -> Error:
	## Serializes one complete snapshot as JSON.
	last_file_error = ""
	var snapshot := create_snapshot(vm, locale)
	if snapshot.is_empty():
		return ERR_INVALID_DATA
	return write_snapshot(path, snapshot)


## Writes beside the destination, flushes, then renames over the old file.
## A write/rename failure preserves the previous save; no delete-then-write gap.
func write_snapshot(path: String, snapshot: Dictionary) -> Error:
	last_file_error = validate_snapshot(snapshot)
	if not last_file_error.is_empty():
		return ERR_INVALID_DATA
	var content := JSON.stringify(snapshot, "  ", true, true)
	if content.to_utf8_buffer().size() > max_file_bytes:
		last_file_error = "Save exceeds the configured file size limit."
		return ERR_OUT_OF_MEMORY
	var directory := path.get_base_dir()
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		last_file_error = "Cannot create save directory: %s" % directory
		return error
	_file_sequence += 1
	var temporary := "%s.tmp.%d.%d.%d" % [path, OS.get_process_id(), Time.get_ticks_usec(), _file_sequence]

	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_file_error = "Could not open save file for writing: %s" % path
		return FileAccess.get_open_error()

	file.store_string(content)
	file.flush()
	error = file.get_error()
	file.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		last_file_error = "Could not replace save file (error %d): %s" % [error, path]
		DirAccess.remove_absolute(temporary)
	return error


func load_from_file(path: String) -> Dictionary:
	## Reads and parses the save file only. Applying it to a VM is a separate
	## operation because the caller must first compile/load the target StoryProgram.
	last_file_error = ""
	if not FileAccess.file_exists(path):
		last_file_error = "Save file does not exist: %s" % path
		return {}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_file_error = "Could not open save file for reading: %s" % path
		return {}
	if file.get_length() > max_file_bytes:
		file.close()
		last_file_error = "Save exceeds the configured file size limit."
		return {}

	var text := file.get_as_text()
	file.close()
	var json := JSON.new()
	var parse_error := json.parse(text)
	if parse_error != OK:
		last_file_error = "Save JSON line %d: %s" % [json.get_error_line(), json.get_error_message()]
		return {}
	var parsed: Variant = json.data
	if not parsed is Dictionary:
		last_file_error = "Save JSON must be a dictionary."
		return {}

	# Keep the typed return explicit for Godot's static GDScript checker.
	var data: Dictionary = parsed
	last_file_error = validate_snapshot(data)
	if not last_file_error.is_empty():
		return {}
	return data


func restore_snapshot(vm: StoryVM, snapshot: Dictionary) -> Error:
	## Restores a snapshot into an already compiled/configured StoryVM.
	##
	## Position is resolved first. Variables are written only after a valid resume
	## point is found, so a failed migration cannot partially mutate story state.
	_reset_restore_diagnostics()
	if vm == null or vm.program == null or vm.program.runtime == null:
		return _restore_failure("StoryVM is not configured.", ERR_UNCONFIGURED)
	var invalid := validate_snapshot(snapshot)
	if not invalid.is_empty():
		return _restore_failure(invalid, ERR_INVALID_DATA)
	if String(snapshot.story_id) != vm.program.story_id:
		return _restore_failure("Save belongs to a different story.", ERR_INVALID_DATA)
	var prepared := _prepare_variables(vm.program, snapshot.get("variables", {}))
	if not prepared.ok:
		return _restore_failure(prepared.error, ERR_INVALID_DATA)

	var restored_ip := _resolve_snapshot_position(vm.program, snapshot)
	if restored_ip < 0:
		return _restore_failure("Could not resolve a safe save position.", ERR_DOES_NOT_EXIST)

	for key in prepared["values"]:
		vm.program.runtime.set(key, prepared["values"][key])
	vm.jump_to_ip(restored_ip)
	last_restore_to_ip = restored_ip
	return OK


func restore_quality_text() -> String:
	match last_restore_quality:
		RestoreQuality.SID:
			return "SID"
		RestoreQuality.EXACT_POSITION:
			return "EXACT_POSITION"
		RestoreQuality.EXACT_NEARBY:
			return "EXACT_NEARBY"
		RestoreQuality.FALLBACK_SAME_TYPE:
			return "FALLBACK_SAME_TYPE"
		RestoreQuality.FALLBACK_DIALOGUE:
			return "FALLBACK_DIALOGUE"
		RestoreQuality.FAILED:
			return "FAILED"
		_:
			return "NONE"


func _capture_script_variables(program: StoryProgram) -> Dictionary:
	var variables := {}
	if program.runtime == null:
		return variables

	for variable_name in program.save_variables:
		variables[String(variable_name)] = program.runtime.get(variable_name)
	return variables


func _prepare_variables(program: StoryProgram, values: Dictionary) -> Dictionary:
	var properties := {}
	for property in program.runtime_script.get_script_property_list():
		properties[String(property.name)] = property
	var prepared := {}
	for key in values:
		if StringName(key) not in program.save_variables:
			continue # Removed fields are allowed when migrating an old save.
		var expected_type := int(properties.get(key, {}).get("type", TYPE_NIL))
		var converted := _convert_value(values[key], expected_type, program.runtime.get(key))
		if not converted.ok:
			return {"ok": false, "error": "Save variable '%s' has an incompatible type." % key}
		prepared[key] = converted.value
	return {"ok": true, "values": prepared}


func _convert_value(value: Variant, expected_type: int, template: Variant = null) -> Dictionary:
	var value_type := typeof(value)
	if expected_type == TYPE_NIL:
		return {"ok": true, "value": value.duplicate(true) if value is Array or value is Dictionary else value}
	if expected_type == TYPE_INT and _is_integer(value):
		return {"ok": true, "value": int(value)}
	if expected_type == TYPE_FLOAT and value_type in [TYPE_INT, TYPE_FLOAT]:
		return {"ok": true, "value": float(value)}
	if expected_type != value_type:
		return {"ok": false}
	if value is Array:
		var result: Array = template.duplicate() if template is Array else []
		result.clear()
		for item in value:
			var converted := _convert_value(item, result.get_typed_builtin())
			if not converted.ok:
				return {"ok": false}
			result.append(converted.value)
		return {"ok": true, "value": result}
	if value is Dictionary:
		var result: Dictionary = template.duplicate() if template is Dictionary else {}
		result.clear()
		for key in value:
			var converted_key := _convert_value(key, result.get_typed_key_builtin())
			var converted_value := _convert_value(value[key], result.get_typed_value_builtin())
			if not converted_key.ok or not converted_value.ok:
				return {"ok": false}
			result[converted_key.value] = converted_value.value
		return {"ok": true, "value": result}
	return {"ok": true, "value": value}


func _restore_failure(message: String, error: Error) -> Error:
	last_restore_quality = RestoreQuality.FAILED
	last_restore_message = message
	return error


func validate_snapshot(snapshot: Dictionary) -> String:
	if not _is_json_value(snapshot):
		return "Save contains unsupported JSON values or excessive nesting."
	var version: Variant = snapshot.get("format_version", 1)
	if not _is_integer(version) or int(version) not in [1, SAVE_FORMAT_VERSION]:
		return "Unsupported save format version."
	if int(version) == SAVE_FORMAT_VERSION:
		for key in ["instruction_index", "op", "exact_signature", "variables"]:
			if not snapshot.has(key):
				return "Save v2 is missing '%s'." % key
	if not snapshot.get("story_id") is String or String(snapshot.story_id).is_empty():
		return "Save requires a non-empty story_id."
	if not snapshot.get("variables", {}) is Dictionary:
		return "Save variables must be a dictionary."
	for key in ["locale", "sid", "exact_signature", "story_source"]:
		if snapshot.has(key) and not snapshot[key] is String:
			return "Save field '%s' must be a string." % key
	for key in ["instruction_index", "op"]:
		if snapshot.has(key) and (not _is_integer(snapshot[key]) or snapshot[key] < 0):
			return "Save field '%s' must be a non-negative integer." % key
	if snapshot.has("op") and snapshot.op >= StoryProgram.Op.size():
		return "Save opcode is out of range."
	if String(snapshot.get("sid", "")).is_empty() and not snapshot.has("instruction_index"):
		return "Save has no position anchor."
	return ""


func _is_integer(value: Variant) -> bool:
	if value is int:
		return value >= -MAX_JSON_INTEGER and value <= MAX_JSON_INTEGER
	return value is float and is_finite(value) and value >= -MAX_JSON_INTEGER and value <= MAX_JSON_INTEGER and floor(value) == value


func _is_json_value(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_VALUE_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT:
			return _is_integer(value)
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_ARRAY:
			for item in value:
				if not _is_json_value(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key in value:
				if not key is String or not _is_json_value(value[key], depth + 1):
					return false
			return true
	return false


func _resolve_snapshot_position(program: StoryProgram, snapshot: Dictionary) -> int:
	## Stage 1: legacy/optional SID always wins while it remains valid.
	var saved_sid := String(snapshot.get("sid", ""))
	if not saved_sid.is_empty():
		var sid_ip := program.resolve_sid(saved_sid)
		if sid_ip >= 0:
			last_restore_quality = RestoreQuality.SID
			last_restore_from_ip = int(snapshot.get("instruction_index", sid_ip))
			last_restore_message = "Restored by SID '%s'." % saved_sid
			return sid_ip

	## Format-v1 saves may contain only SID + variables. If that SID disappeared,
	## there is no numeric anchor from which the v2 resolver can recover.
	if not snapshot.has("instruction_index"):
		last_restore_message = "Legacy save SID no longer exists and no instruction_index is available."
		return -1

	var saved_ip := int(snapshot.get("instruction_index", -1))
	var saved_op := int(snapshot.get("op", -1))
	var saved_exact := String(snapshot.get("exact_signature", ""))
	last_restore_from_ip = saved_ip

	## Stage 2: exact source at the original numeric instruction position.
	if _instruction_exactly_matches(program, saved_ip, saved_op, saved_exact):
		last_restore_quality = RestoreQuality.EXACT_POSITION
		last_restore_message = "Saved instruction still exists at ip %d." % saved_ip
		return saved_ip

	## Stage 3: limited exact search around the original position. Forward wins on
	## equal distance: old+1, old-1, old+2, old-2, ...
	if not saved_exact.is_empty() and saved_op >= 0:
		var exact_nearby := _find_exact_nearby(program, saved_ip, saved_op, saved_exact)
		if exact_nearby >= 0:
			last_restore_quality = RestoreQuality.EXACT_NEARBY
			last_restore_message = "Exact instruction moved from ip %d to %d." % [saved_ip, exact_nearby]
			return exact_nearby

	## Stage 4: exact identity is gone. Resume at nearest same-type presentation
	## point. This is a fallback, not a claim that the instruction is identical.
	if saved_op in RESUMABLE_OPS:
		var same_type := _find_nearest_op(program, saved_ip, saved_op)
		if same_type >= 0:
			last_restore_quality = RestoreQuality.FALLBACK_SAME_TYPE
			last_restore_message = "Exact instruction was lost; resumed at nearest same-type instruction %d." % same_type
			return same_type

	## Stage 5: DIA is the universal final presentation fallback.
	var nearest_dialogue := _find_nearest_op(program, saved_ip, StoryProgram.Op.DIA)
	if nearest_dialogue >= 0:
		last_restore_quality = RestoreQuality.FALLBACK_DIALOGUE
		last_restore_message = "No same-type resume point exists; resumed at nearest DIA %d." % nearest_dialogue
		return nearest_dialogue

	return -1


func _instruction_exactly_matches(
	program: StoryProgram,
	candidate_ip: int,
	saved_op: int,
	saved_exact: String
) -> bool:
	if candidate_ip < 0 or candidate_ip >= program.instructions.size():
		return false
	if saved_op < 0 or saved_exact.is_empty():
		return false

	var candidate: Dictionary = program.instructions[candidate_ip]
	return (
		int(candidate.get("op", -1)) == saved_op
		and String(candidate.get("exact_signature", "")) == saved_exact
	)


func _find_exact_nearby(
	program: StoryProgram,
	center_ip: int,
	saved_op: int,
	saved_exact: String
) -> int:
	for distance in range(1, MAX_EXACT_SEARCH_RANGE + 1):
		var forward := center_ip + distance
		if _instruction_exactly_matches(program, forward, saved_op, saved_exact):
			return forward

		var backward := center_ip - distance
		if _instruction_exactly_matches(program, backward, saved_op, saved_exact):
			return backward

	return -1


func _find_nearest_op(program: StoryProgram, center_ip: int, wanted_op: int) -> int:
	## Full-story fallback is used only after strict matching fails. Forward is
	## checked before backward at equal distance to reduce the chance of replaying
	## already-executed GDScript side effects.
	if program.instructions.is_empty():
		return -1

	var last_ip := program.instructions.size() - 1
	var nearest := -1
	var nearest_distance := MAX_JSON_INTEGER + 1
	for candidate in range(last_ip + 1):
		if not _instruction_has_op(program, candidate, wanted_op):
			continue
		var distance := absi(candidate - center_ip)
		# Ascending traversal plus <= preserves the forward tie-break.
		if distance <= nearest_distance:
			nearest = candidate
			nearest_distance = distance
	return nearest


func _instruction_has_op(program: StoryProgram, candidate_ip: int, wanted_op: int) -> bool:
	if candidate_ip < 0 or candidate_ip >= program.instructions.size():
		return false
	return int(program.instructions[candidate_ip].get("op", -1)) == wanted_op


func _reset_restore_diagnostics() -> void:
	last_restore_quality = RestoreQuality.NONE
	last_restore_from_ip = -1
	last_restore_to_ip = -1
	last_restore_message = ""
