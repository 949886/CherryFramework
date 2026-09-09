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
	if vm == null or vm.program == null:
		return {}

	var instruction := vm.current_instruction()
	var variables := _capture_script_variables(vm.program)

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
		"variables": variables,
	}


func save_to_file(path: String, vm: StoryVM, locale: String = "") -> Error:
	## Serializes one complete snapshot as JSON.
	last_file_error = ""
	var snapshot := create_snapshot(vm, locale)
	if snapshot.is_empty():
		last_file_error = "Cannot save an unconfigured StoryVM."
		return ERR_UNCONFIGURED

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		last_file_error = "Could not open save file for writing: %s" % path
		return FileAccess.get_open_error()

	file.store_string(JSON.stringify(snapshot, "  "))
	file.close()
	return OK


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

	var text := file.get_as_text()
	file.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		last_file_error = "Save JSON is invalid or is not a Dictionary."
		return {}

	# Keep the typed return explicit for Godot's static GDScript checker.
	var data: Dictionary = parsed
	return data


func restore_snapshot(vm: StoryVM, snapshot: Dictionary) -> Error:
	## Restores a snapshot into an already compiled/configured StoryVM.
	##
	## Position is resolved first. Variables are written only after a valid resume
	## point is found, so a failed migration cannot partially mutate story state.
	if vm == null or vm.program == null or vm.program.runtime == null:
		return ERR_UNCONFIGURED

	_reset_restore_diagnostics()

	var restored_ip := _resolve_snapshot_position(vm.program, snapshot)
	if restored_ip < 0:
		last_restore_quality = RestoreQuality.FAILED
		last_restore_message = "Could not resolve a safe save position."
		push_error("Save position could not be restored in story %s." % vm.program.story_id)
		return ERR_DOES_NOT_EXIST

	_restore_script_variables(vm.program, snapshot.get("variables", {}))
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


func _restore_script_variables(program: StoryProgram, saved_variables: Variant) -> void:
	if not (saved_variables is Dictionary):
		return

	var values: Dictionary = saved_variables
	for key in values:
		var variable_name := StringName(key)
		if variable_name in program.save_variables:
			program.runtime.set(variable_name, values[key])


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
	var max_distance := maxi(abs(center_ip), abs(last_ip - center_ip))

	for distance in range(0, max_distance + 1):
		var forward := center_ip + distance
		if _instruction_has_op(program, forward, wanted_op):
			return forward

		if distance > 0:
			var backward := center_ip - distance
			if _instruction_has_op(program, backward, wanted_op):
				return backward

	return -1


func _instruction_has_op(program: StoryProgram, candidate_ip: int, wanted_op: int) -> bool:
	if candidate_ip < 0 or candidate_ip >= program.instructions.size():
		return false
	return int(program.instructions[candidate_ip].get("op", -1)) == wanted_op


func _reset_restore_diagnostics() -> void:
	last_restore_quality = RestoreQuality.NONE
	last_restore_from_ip = -1
	last_restore_to_ip = -1
	last_restore_message = ""
