class_name StoryVM
extends RefCounted
## Executes the seven-op StoryProgram control-flow IR.
##
## StoryVM has one responsibility: execute story control flow.
##
## It intentionally knows nothing about:
## - save-file formats or JSON,
## - save/load migration,
## - SID recovery policy,
## - persistence of GDScript member variables,
## - presentation of dialogue/narration.
##
## Persistence belongs to StorySaveManager; rendering belongs to StoryPresenter.

var program: StoryProgram
var ip: int = 0


func setup(new_program: StoryProgram, start_ip: int = 0) -> void:
	program = new_program
	ip = clampi(start_ip, 0, maxi(0, program.instructions.size() - 1))


func current_instruction() -> Dictionary:
	if program == null or ip < 0 or ip >= program.instructions.size():
		return {
			"op": StoryProgram.Op.END,
			"sid": "",
			"sid_explicit": false,
			"exact_signature": "",
			"data": null,
		}
	return program.instructions[ip]


func advance() -> void:
	ip += 1


func jump_to_ip(target_ip: int) -> void:
	ip = target_ip


func execute_internal(instruction: Dictionary) -> Dictionary:
	## Executes an instruction that should not block on presentation.
	## Returns a small result dictionary. Cross-file JMP is deliberately returned
	## to the orchestration layer because loading another StoryProgram is not a VM
	## instruction-execution concern.
	var op: int = int(instruction["op"])
	var data: Variant = instruction.get("data")

	match op:
		StoryProgram.Op.JIF:
			var method_name := StringName(data["method"])
			# Object.call() returns Variant. Convert explicitly at the control-flow
			# boundary so the VM always works with a strict boolean.
			var result := bool(program.runtime.call(method_name))
			if result:
				ip += 1
			else:
				ip = int(data["target"])
			return {"ok": true}

		StoryProgram.Op.JMP:
			# Compiler-generated local control-flow jumps use an integer target.
			if data is int:
				ip = int(data)
				return {"ok": true}

			# Narrative jumps use a StoryAddress dictionary. The VM can resolve a
			# local label; an external story load is reported to the orchestrator.
			if data is Dictionary:
				var target_story := String(data.get("story", program.story_id))
				var target_label := String(data.get("label", ""))
				if target_story == program.story_id:
					var local_ip := 0 if target_label.is_empty() else program.resolve_label(target_label)
					if local_ip < 0:
						push_error("Unknown local story label: %s" % target_label)
						return {"ok": false}
					ip = local_ip
					return {"ok": true}
				return {
					"ok": true,
					"external_jump": true,
					"story": target_story,
					"label": target_label,
				}

			return {
				"ok": false,
				"error": "JMP expects an int target or StoryAddress Dictionary",
			}

		StoryProgram.Op.EXE:
			program.runtime.call(StringName(data["method"]))
			ip += 1
			return {"ok": true}

		StoryProgram.Op.END:
			return {"ok": true, "finished": true}

		_:
			return {"ok": false, "error": "execute_internal called for a presentation opcode"}

	# Defensive fallback for Godot's typed-return control-flow checker.
	return {"ok": false, "error": "Unhandled internal VM instruction"}
