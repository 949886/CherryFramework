extends Control
## Demo UI only. StoryPlayer owns playback and all persistence operations.

@export var player: StoryPlayer
@export var debug_actions: Dictionary = {
	"Favor95": {"variable": "mahiro_favorability", "value": 95},
	"Tire90": {"variable": "tire", "value": 90},
}

@onready var status_label: Label = $TopBar/Status
@onready var locale_button: Button = $TopBar/Locale
@onready var debug_label: Label = $DebugBar/Variables

func _ready() -> void:
	$TopBar/Save.pressed.connect(func(): player.save_game())
	$TopBar/Load.pressed.connect(func(): player.load_game())
	$TopBar/Restart.pressed.connect(func(): player.restart())
	locale_button.pressed.connect(_toggle_locale)
	for button_name in debug_actions:
		var button := get_node_or_null("DebugBar/" + String(button_name)) as Button
		if button != null:
			button.pressed.connect(_debug_set.bind(debug_actions[button_name]))
	player.story_failed.connect(_set_status)
	player.story_finished.connect(func(_id): _set_status("剧情 END。点击 Restart 可重新体验。"))
	player.story_started.connect(func(_id): _update_locale_button())
	player.instruction_changed.connect(func(_instruction): _refresh_debug_label())
	player.saved.connect(func(automatic): _set_status("自动存档完成。" if automatic else "已保存当前剧情位置。"))
	player.restored.connect(func(_quality): _set_status("恢复：%s" % player.save_manager.restore_quality_text()))
	_update_locale_button()

func _next_locale() -> String:
	var locales := player.library.locale_labels.keys()
	if locales.is_empty():
		return player.locale
	return String(locales[(locales.find(player.locale) + 1) % locales.size()])

func _toggle_locale() -> void:
	player.switch_locale(_next_locale())

func _update_locale_button() -> void:
	var next := _next_locale()
	locale_button.text = String(player.library.locale_labels.get(next, next))

func _debug_set(action: Dictionary) -> void:
	if player.vm.program == null:
		return
	var key := StringName(action.get("variable", ""))
	if key in player.vm.program.save_variables:
		player.vm.program.runtime.set(key, action.get("value"))
		_refresh_debug_label()

func _refresh_debug_label() -> void:
	var pairs: Array[String] = []
	for key in player.vm.program.save_variables:
		pairs.append("%s=%s" % [key, player.vm.program.runtime.get(key)])
	debug_label.text = "%s.%s   %s" % [player.current_story_id, player.locale, "  ".join(pairs)]

func _set_status(message: String) -> void:
	status_label.text = message
