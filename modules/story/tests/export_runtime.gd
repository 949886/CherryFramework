extends Node
## Run from a PCK in an empty project directory: no loose-file fallback.

const Demo = preload("../examples/story_demo.tscn")
const GalgameDemo = preload("../examples/galgame_demo.tscn")
var failures: Array[String] = []
var checks := 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures.append(message)
		printerr("FAIL: " + message)

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := Demo.instantiate()
	var player := scene.get_node("StoryPlayer") as StoryPlayer
	player.autoplay = false
	add_child(scene)
	var entry := player.story
	for id in ["mahiro", "mahiro_h"]:
		var variant := entry.resolve_story(id)
		check(variant != null, "exported jump target: " + id)
		for locale in ["ja", "zh-cn"]:
			check(variant.get_source_path(locale).ends_with(".%s.md" % locale) and locale in variant.get_available_locales(), "exported exact translation: %s/%s" % [id, locale])
	var story_format := get_meta("story_format") as MarkdownStory
	check(story_format != null and story_format.compile("ja") != null, "native .story reference compiles from PCK")
	var root_path := (get_script() as Script).resource_path.get_base_dir().get_base_dir()
	for asset in ["room.svg", "omelette.svg", "mahiro_voice.wav"]:
		check(load(root_path.path_join("examples/assets/" + asset)) != null, "exported imported asset: " + asset)
	check(FileAccess.file_exists("res://runtime_config.json"), "explicit extra file exported")
	check(not FileAccess.file_exists("res://unused.md"), "unselected invalid story excluded")
	var presenter := player.presenter as StoryPresenter
	presenter.character_delay = 0.0
	presenter.background_fade_duration = 0.0
	for locale in ["ja", "zh-cn"]:
		check(player.play(null, "", {}, locale) == OK, "exported story starts: " + locale)
		player.vm.program.runtime.set("mahiro_favorability", 95)
		var deadline := Time.get_ticks_msec() + 15000
		while player.is_playing and Time.get_ticks_msec() < deadline:
			presenter.advance()
			if presenter.choices_panel.visible and presenter.choices_panel.get_child_count() > 2:
				(presenter.choices_panel.get_child(2) as Button).pressed.emit()
			await get_tree().process_frame
		check(not player.is_playing and player.current_story_id == "mahiro_h", "exported UI reaches cross-file END: " + locale)
		check(player.vm.program.source_path.ends_with(".%s.md" % locale), "cross-file playback keeps requested language: " + locale)
	scene.queue_free()
	await get_tree().process_frame
	# The polished scene must work from a selected-scene PCK too: its JSON schema,
	# catalog, eight scripts and imported sprites cannot depend on loose files.
	var galgame := GalgameDemo.instantiate()
	var native := galgame.get_node("Presenter") as StoryGalgamePresenter
	native.save_directory = "user://galgame_export_test_%d" % OS.get_process_id()
	add_child(galgame)
	await get_tree().process_frame
	check(native.preferences.schema.get("sections", []).size() == 5, "galgame settings schema exported")
	check(native.library.nodes.size() == 8 and native.library.errors.is_empty(), "galgame file graph exported")
	check(native.backdrop != null and native.characters[0].states[1].portrait != null, "galgame supplied images exported")
	# Texture references must survive selected-scene packing without the source
	# directory, system icon fonts, or a developer's import cache as fallbacks.
	for identity in StorySkin.ICONS.get_meta("icons"):
		var texture := native.skin.icon(identity)
		check(texture != null and texture.get_width() > 0, "exported native SVG icon: " + identity)
		check(texture is DPITexture and not texture.get_source().is_empty(), "export preserves scalable SVG source: " + identity)
	native.preferences.set_value("instant", true)
	native.preferences.set_value("motion", "reduced")
	for step in range(20):
		if native._state.mode == "choice": break
		native.advance_time(5)
		native.advance()
		native.advance_time(0)
		await get_tree().process_frame
	check(native.choices_panel.get_child_count() == 3, "exported galgame reaches choice")
	native.open_menu("settings")
	check(native.menu.preview != null, "exported shared preview opens")
	native.close_menu()
	native.archive.player.stop()
	galgame.queue_free()
	# Menu preview layout and resource releases are deferred by Controls. Drain
	# their queued work before ending the engine, as a normal scene change does.
	for frame in range(4): await get_tree().process_frame
	print("Export PCK: %d passed, %d failed" % [checks - failures.size(), failures.size()])
	get_tree().quit(0 if failures.is_empty() else 1)
