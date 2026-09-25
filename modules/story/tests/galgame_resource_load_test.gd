extends SceneTree
## This entry point must not reference any Story class or preload a fixture.
## Each process begins with an empty resource cache, just like opening a leaf
## scene before the presenter. Typed test suites can otherwise hide cycles by
## resolving the menu scripts/catalog before the scene under test is loaded.

func _initialize() -> void:
	var module_root := (get_script() as Script).resource_path.get_base_dir().get_base_dir()
	var target := "gdscript/story_galgame_menus.gd"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--resource="): target = argument.trim_prefix("--resource=")
	var path := module_root.path_join(target)
	var catalog_path := module_root.path_join("resources/galgame_pages.tres")
	var checks := 1
	var failures := 0
	if ResourceLoader.has_cached(catalog_path):
		failures += 1
		printerr("FAIL: cold load fixture unexpectedly warmed the page catalog")
	var resource := ResourceLoader.load(path)
	checks += 1
	if resource == null:
		failures += 1
		printerr("FAIL: cold resource load: " + target)
	# Only the composed menus/presenter and the catalog itself should load all
	# routes. A leaf component or script must not pull its parent scenes in.
	if target.begins_with("gdscript/") or target in [
		"scenes/galgame/slot_card.tscn", "scenes/galgame/confirm.tscn", "scenes/galgame/menu_page.tscn"]:
		checks += 1
		if ResourceLoader.has_cached(catalog_path):
			failures += 1
			printerr("FAIL: leaf resource recursively loaded the page catalog: " + target)
	print("Cold galgame load (%s): %d passed, %d failed" % [target, checks - failures, failures])
	quit(0 if failures == 0 else 1)
