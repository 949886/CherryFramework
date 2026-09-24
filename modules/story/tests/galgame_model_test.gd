extends SceneTree
## Filesystem-backed tests use their own user:// directory, never player saves.

var checks := 0
var failures := 0
var module_root := (get_script() as Script).resource_path.get_base_dir().get_base_dir()
var test_directory := "user://galgame_model_test_%d" % OS.get_process_id()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var preferences := StoryPreferences.new()
	preferences.path = test_directory.path_join("settings.cfg")
	check(preferences.values.line_height == 1.5, "approved default line height")
	check(preferences.values.font == "sans", "sans-serif default body")
	check(preferences.schema.sections.size() == 5, "five settings pages")
	check(preferences.set_value("font_size", 999), "range validated")
	check(preferences.values.font_size == 36, "range clamped")
	check(not preferences.set_value("font_size", NAN), "nonfinite rejected")
	check(not preferences.set_value("glass", "false"), "checkbox type checked")
	check(not preferences.set_value("palette", "missing"), "unknown palette rejected")
	check(preferences.set_value("glass", true), "enable glass")
	check(preferences.field_visible(preferences.definition("glass_blur")), "glass details appear")
	preferences.set_value("glass_blur", 31)
	preferences.set_value("glass", false)
	check(not preferences.field_visible(preferences.definition("glass_blur")), "glass details hidden")
	check(preferences.values.glass_blur == 31, "disabled glass retains values")
	var restored := StoryPreferences.new()
	restored.path = preferences.path
	check(restored.load_settings() == OK and restored.values.glass_blur == 31, "settings persist")
	check(restored.reset_section("display") == OK and restored.values.glass_blur == 22, "reset only selected page")
	check(restored.values.font_size == 36, "other settings survive reset")
	var entry := MarkdownStory.from_file(module_root.path_join("examples/stories/mahiro.zh-cn.md"))
	var library := StoryLibrary.new()
	library.build(entry, "zh-cn")
	check(library.errors.is_empty(), "real script graph compiles")
	check(library.nodes.size() == 2 and library.edges.size() == 1, "one graph node per file, not dialogue or translation")
	var view: StoryPresenter = load(module_root.path_join("scenes/story_presenter.tscn")).instantiate()
	root.add_child(view)
	var player := StoryPlayer.new()
	player.autoplay = false
	player.presenter = view
	player.story = entry
	root.add_child(player)
	check(player.play(entry, "", {}, "zh-cn") == OK, "native player starts")
	await process_frame
	player.pause()
	var archive := StoryArchive.new()
	archive.configure(player, test_directory)
	check(archive.slot_count == 24, "24 independent slots")
	check(archive.save_slot(-1) == ERR_INVALID_PARAMETER, "negative slot rejected")
	check(archive.save_slot(24) == ERR_INVALID_PARAMETER, "out-of-range slot rejected")
	check(archive.read_slot(0).status == "empty", "missing slot empty")
	check(archive.save_slot(0) == OK, "real snapshot saved")
	check(archive.save_slot(23) == OK, "last slot saved separately")
	check(archive.read_slot(0).status == "ready" and archive.read_slot(23).status == "ready", "slots survive serialization")
	check(archive.read_slot(1).status == "empty", "other slot unchanged")
	var corrupt := FileAccess.open(archive.slot_path(1), FileAccess.WRITE)
	corrupt.store_string("{broken")
	corrupt.close()
	check(archive.read_slot(1).status == "corrupt", "corrupt slot distinct from empty")
	var generation := player._generation
	check(archive.load_slot(1) != OK and player._generation == generation, "corrupt load preserves playback")
	check(archive.load_slot(0) == OK, "saved snapshot restored through player")
	archive.toggle_bookmark(entry.get_identity())
	var archive_reload := StoryArchive.new()
	archive_reload.configure(player, test_directory)
	check(archive_reload.bookmarks.has(entry.get_identity()), "bookmarks persist")
	check(archive.replay_file("unvisited") == ERR_UNAVAILABLE, "unread file cannot replay")
	# A real multi-file fixture exercises cycle termination and a shared join.
	var fixture_files := {
		"entry.md": "- Left\n\t>>[left](left.md)\n- Right\n\t>>[right](right.md)\n",
		"left.md": "Guide: Left\n>>[join](join.md)\n",
		"right.md": "Guide: Right\n>>[join](join.md)\n",
		"join.md": "Guide: Shared ending\n>>[cycle](entry.md)\n",
	}
	for name in fixture_files:
		var file := FileAccess.open(test_directory.path_join(name), FileAccess.WRITE)
		file.store_string(fixture_files[name])
		file.close()
	var fixture := MarkdownStory.from_file(test_directory.path_join("entry.md"))
	library.build(fixture, "")
	check(library.errors.is_empty() and library.nodes.size() == 4, "joins and cycles do not duplicate files")
	check(library.edges.size() == 5, "all branch/join/cycle edges retained")
	# Replay checkpoints and read progress survive a new archive instance.
	var checkpoint: Dictionary = archive.read_slot(0).snapshot
	archive.progress[entry.get_identity()] = {"read": {"seen": true}, "entry": checkpoint, "visited": true}
	archive.save_profile()
	archive_reload.load_profile()
	check(archive_reload.is_read(entry.get_identity(), "seen"), "lifetime read progress persists")
	check(not archive_reload.is_read(entry.get_identity(), "new-text"), "unread text remains unread")
	check(archive_reload.replay_file(entry.get_identity()) == OK, "visited file replays a validated checkpoint")
	player.stop()
	player.queue_free()
	view.queue_free()
	await process_frame
	print("Galgame model: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
