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
	var source := "```gdscript\nvar count: int = 1\nvar ratio: float = 0.5\nvar inventory: Array[int] = [1]\nvar flags: Dictionary[String, bool] = {\"seen\": false}\nvar nested = {\"items\": [1]}\n```\n<!-- @sid:a -->\nGuide: A\n> Between\n<!-- @sid:b -->\nGuide: B"
	var vm := StoryVM.new()
	vm.setup(parser.compile_source(source, "save"))
	var saves := StorySaveManager.new()
	var snapshot := saves.create_snapshot(vm, "en")
	vm.program.runtime.get("inventory").append(2)
	vm.program.runtime.get("nested").items.append(2)
	check(snapshot.variables.inventory == [1] and snapshot.variables.nested.items == [1], "snapshot owns nested copies")
	check(saves.restore_snapshot(vm, snapshot) == OK, "restore typed collection snapshot")
	vm.program.runtime.get("inventory").append(3)
	check(snapshot.variables.inventory == [1], "restored runtime cannot mutate snapshot")
	for invalid in [
		{"format_version": 99}, {"format_version": "2"}, {"story_id": 7},
		{"variables": []}, {"sid": []}, {"instruction_index": -1},
		{"instruction_index": 1.5}, {"instruction_index": true}, {"op": 77},
	]:
		var damaged := snapshot.duplicate(true)
		damaged.merge(invalid, true)
		check(saves.restore_snapshot(vm, damaged) == ERR_INVALID_DATA, "reject malformed fields: " + str(invalid))
	var mismatched := snapshot.duplicate(true)
	mismatched.story_id = "another"
	check(saves.restore_snapshot(vm, mismatched) == ERR_INVALID_DATA, "reject different story")
	var before_inventory: Array = vm.program.runtime.get("inventory").duplicate()
	var bad_types := snapshot.duplicate(true)
	bad_types.variables.count = 90
	bad_types.variables.inventory = ["invalid"]
	check(saves.restore_snapshot(vm, bad_types) == ERR_INVALID_DATA, "reject typed array mismatch")
	check(vm.ip == 0 and vm.program.runtime.get("count") == 1 and vm.program.runtime.get("inventory") == before_inventory, "failed restoration is transactional")
	bad_types = snapshot.duplicate(true)
	bad_types.variables.flags = {"seen": "not a bool"}
	check(saves.restore_snapshot(vm, bad_types) == ERR_INVALID_DATA, "reject typed dictionary mismatch")
	bad_types = snapshot.duplicate(true)
	bad_types.variables.count = 1.5
	check(saves.restore_snapshot(vm, bad_types) == ERR_INVALID_DATA, "reject fractional integer")
	var huge := snapshot.duplicate(true)
	huge.sid = "gone"
	huge.instruction_index = 1000000000000
	huge.exact_signature = "gone"
	var begin := Time.get_ticks_msec()
	check(saves.restore_snapshot(vm, huge) == OK and vm.ip == 2, "large position selects nearest actual dialogue")
	check(Time.get_ticks_msec() - begin < 100, "search bound depends on program size")
	huge.instruction_index = 1
	check(saves.restore_snapshot(vm, huge) == OK and vm.ip == 2, "forward wins equal distance")
	var legacy := {"story_id": "save", "sid": "a", "variables": {"count": 8}}
	check(saves.restore_snapshot(vm, legacy) == OK and vm.program.runtime.get("count") == 8, "legacy v1 SID remains supported")
	var path := "user://save_test_%d/slot.json" % OS.get_process_id()
	check(saves.write_snapshot(path, snapshot) == OK, "create save and parent directory")
	var next := snapshot.duplicate(true)
	next.variables.count = 19
	check(saves.write_snapshot(path, next) == OK, "atomically replace existing save")
	var loaded := saves.load_from_file(path)
	check(saves.restore_snapshot(vm, loaded) == OK and vm.program.runtime.get("count") == 19, "JSON numbers restore declared integer types")
	check(vm.program.runtime.get("inventory").is_typed() and vm.program.runtime.get("flags").is_typed(), "JSON preserves declared collection types")
	var previous_bytes := FileAccess.get_file_as_bytes(path)
	var invalid_object := snapshot.duplicate(true)
	invalid_object.variables.object = RefCounted.new()
	check(saves.write_snapshot(path, invalid_object) == ERR_INVALID_DATA, "reject object serialization")
	check(FileAccess.get_file_as_bytes(path) == previous_bytes, "rejected write preserves original file")
	var cycle: Array = []
	cycle.append(cycle)
	invalid_object.variables = {"cycle": cycle}
	check(saves.write_snapshot(path, invalid_object) == ERR_INVALID_DATA, "reject cyclic values without recursion overflow")
	cycle.clear()
	saves.max_file_bytes = 2
	check(saves.load_from_file(path).is_empty(), "limit incoming file size")
	check(saves.write_snapshot(path, snapshot) == ERR_OUT_OF_MEMORY and FileAccess.get_file_as_bytes(path) == previous_bytes, "size-limited write preserves old file")
	saves.max_file_bytes = 16 * 1024 * 1024
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{broken")
	file.close()
	check(saves.load_from_file(path).is_empty() and not saves.last_file_error.is_empty(), "corrupt JSON produces actionable error")
	DirAccess.remove_absolute(path)
	check(DirAccess.get_files_at(path.get_base_dir()).is_empty(), "successful and failed writes leave no temp files")
	DirAccess.remove_absolute(path.get_base_dir())
	print("Save: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
