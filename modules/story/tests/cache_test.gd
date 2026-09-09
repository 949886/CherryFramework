extends SceneTree

var checks := 0
var failures := 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func write(path: String, content: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()

func _initialize() -> void:
	var path := "user://cache_test_%d.md" % OS.get_process_id()
	var init_file := "user://cache_init_%d.txt" % OS.get_process_id()
	var source := "```gdscript\nvar count = 1\nvar items = [1]\nfunc _init():\n\tvar path = \"%s\"\n\tvar count = FileAccess.get_file_as_string(path).to_int() if FileAccess.file_exists(path) else 0\n\tvar file = FileAccess.open(path, FileAccess.WRITE)\n\tfile.store_string(str(count + 1))\n\tfile.close()\n```\nGuide: Original\n>>[next](chapter.one.en.md)" % init_file
	write(path, source)
	var cache := StoryProgramCache.new()
	var first := cache.compile_file(path, "start")
	first.runtime.set("count", 99)
	first.runtime.get("items").append(2)
	first.instructions[0].data.content = "Mutated"
	var second := cache.compile_file(path, "start")
	check(cache.compilations == 1 and cache.hits == 1, "cache hit avoids parsing and script compilation")
	check(first.runtime_script == second.runtime_script and first.runtime != second.runtime, "compiled script shared, runtime independent")
	check(second.runtime.get("count") == 1 and second.runtime.get("items") == [1], "fresh scalar and collection defaults")
	check(second.instructions[0].data.content == "Original", "mutable IR cannot corrupt template")
	check(FileAccess.get_file_as_string(init_file) == "2", "author initializer executes once per playback, never for template")
	write(path, source.replace("Original", "Changed"))
	var changed := cache.compile_file(path, "start")
	check(changed.instructions[0].data.content == "Changed" and cache.compilations == 2, "content hash invalidates without relying on timestamp")
	var mapped := cache.compile_file(path, "renamed")
	check(mapped.story_id == "renamed" and cache.compilations == 3, "different story IDs have distinct cached programs")
	cache.compiler_version = "future-test-version"
	var recompiled := cache.compile_file(path, "renamed")
	check(cache.compilations == 4 and recompiled.runtime_script != mapped.runtime_script, "compiler version invalidates")
	cache.capacity = 1
	cache.compile_file(path, "another")
	check(cache.size() == 1, "cache shrinks to bounded capacity")
	var before := cache.compilations
	cache.compile_file(path, "start")
	check(cache.compilations == before + 1, "evicted program recompiles")
	cache.clear()
	check(cache.size() == 0 and first.runtime.get("count") == 99, "clear does not disturb active runtimes")
	cache.compile_file(path, "start", false)
	cache.compile_file(path, "start", false)
	check(cache.size() == 0, "disabled cache never retains templates")
	write(path, "`else:`\nGuide: Invalid")
	check(cache.compile_file(path, "bad", true, false) == null and cache.size() == 0, "failed compilations are never cached")
	check(not cache.diagnostics.is_empty(), "cache forwards compiler diagnostics")
	write(path, "Guide: Repaired")
	check(cache.compile_file(path, "bad") != null and cache.diagnostics.is_empty(), "fixed source recovers after error")
	DirAccess.remove_absolute(path)
	check(cache.compile_file(path, "bad") == null, "deleted source cannot reuse stale cache")
	DirAccess.remove_absolute(init_file)
	print("Cache: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
