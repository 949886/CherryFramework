extends Node
## Run from a PCK in an empty project directory: no loose-file fallback.

const Demo = preload("../examples/story_demo.tscn")
var failures: Array[String] = []

func check(value: bool, message: String) -> void:
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
	var library := player.library
	for id in library.stories:
		for locale in library.stories[id]:
			check(not library.resolve_path(id, locale).is_empty(), "exported Markdown: %s/%s" % [id, locale])
	var root_path := (get_script() as Script).resource_path.get_base_dir().get_base_dir()
	for asset in ["room.svg", "omelette.svg", "mahiro_voice.wav"]:
		check(load(root_path.path_join("examples/assets/" + asset)) != null, "exported imported asset: " + asset)
	check(FileAccess.file_exists("res://runtime_config.json"), "explicit extra file exported")
	check(not FileAccess.file_exists("res://unused.md"), "unselected library excluded")
	var presenter := player.presenter as StoryPresenter
	presenter.character_delay = 0.0
	presenter.background_fade_duration = 0.0
	check(player.play("mahiro") == OK, "exported story starts")
	player.vm.program.runtime.set("mahiro_favorability", 95)
	var deadline := Time.get_ticks_msec() + 15000
	while player.is_playing and Time.get_ticks_msec() < deadline:
		presenter.advance()
		if presenter.choices_panel.visible and presenter.choices_panel.get_child_count() > 2:
			(presenter.choices_panel.get_child(2) as Button).pressed.emit()
		await get_tree().process_frame
	check(not player.is_playing and player.current_story_id == "mahiro_h", "exported UI reaches cross-file END")
	scene.queue_free()
	await get_tree().process_frame
	print("Export PCK: %s" % ("passed" if failures.is_empty() else "failed"))
	get_tree().quit(0 if failures.is_empty() else 1)
