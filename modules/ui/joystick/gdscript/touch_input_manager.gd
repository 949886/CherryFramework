class_name TouchInputManager
extends CanvasLayer

const VIRTUAL_JOYSTICK_SCRIPT = preload("./cherry_virtual_joystick.gd")
const VIRTUAL_BUTTON_SCRIPT = preload("./virtual_button.gd")

signal joystick_input_changed(output: Vector2)

@export_group("General")
@export var auto_hide_on_desktop := true
@export_range(0.5, 3.0, 0.1) var control_scale := 1.0

@export_group("Joystick Settings")
@export var joystick_mode: int = VIRTUAL_JOYSTICK_SCRIPT.JoystickMode.FIXED
@export var joystick_visibility: int = VIRTUAL_JOYSTICK_SCRIPT.VisibilityMode.ALWAYS
@export var move_left_action := "move_left"
@export var move_right_action := "move_right"
@export var move_up_action := "jump"
@export var move_down_action := "move_down"

@export_group("Button Settings")
@export var show_jump_button := true
@export var jump_action := "jump"
@export var show_attack_button := true
@export var attack_action := "attack"
@export var show_dash_button := false
@export var dash_action := "dash"

var _joystick
var _jump_button
var _attack_button
var _dash_button
var _container: Control

var joystick:
	get:
		return _joystick

var joystick_output: Vector2:
	get:
		return _joystick.output if _joystick else Vector2.ZERO

func _ready() -> void:
	_create_layout()

func set_controls_visible(is_visible: bool) -> void:
	if _container:
		_container.visible = is_visible

func _create_layout() -> void:
	_container = Control.new()
	_container.name = "TouchControls"
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_container)

	_create_joystick()
	_create_action_buttons()

	if auto_hide_on_desktop and not _is_mobile_platform():
		_container.visible = false

func _create_joystick() -> void:
	var joystick_area := Control.new()
	joystick_area.name = "JoystickArea"
	joystick_area.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	joystick_area.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var local_base_radius := 75.0 * control_scale
	var area_size := local_base_radius * 4.0
	joystick_area.size = Vector2(area_size, area_size)
	joystick_area.position = Vector2(30.0 * control_scale, -area_size - 30.0 * control_scale)
	_container.add_child(joystick_area)

	_joystick = VIRTUAL_JOYSTICK_SCRIPT.new()
	_joystick.name = "CherryVirtualJoystick"
	_joystick.mode = joystick_mode
	_joystick.visibility_mode = joystick_visibility
	_joystick.base_radius = local_base_radius
	_joystick.handle_radius = 35.0 * control_scale
	_joystick.dead_zone = 0.2
	_joystick.clamp_zone = 1.0
	_joystick.action_left = move_left_action
	_joystick.action_right = move_right_action
	_joystick.action_up = move_up_action
	_joystick.action_down = move_down_action
	_joystick.position = Vector2((area_size - local_base_radius * 2.0) / 2.0, (area_size - local_base_radius * 2.0) / 2.0)
	_joystick.size = Vector2(local_base_radius * 2.0, local_base_radius * 2.0)
	_joystick.joystick_input.connect(func(output: Vector2): joystick_input_changed.emit(output))
	joystick_area.add_child(_joystick)

func _create_action_buttons() -> void:
	var button_radius := 40.0 * control_scale
	var spacing := 20.0 * control_scale
	var right_margin := 30.0 * control_scale
	var bottom_margin := 30.0 * control_scale

	var button_area := Control.new()
	button_area.name = "ButtonArea"
	button_area.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	button_area.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var area_width := button_radius * 4.0 + spacing
	var area_height := button_radius * 4.0 + spacing
	button_area.size = Vector2(area_width, area_height)
	button_area.position = Vector2(-area_width - right_margin, -area_height - bottom_margin)
	_container.add_child(button_area)

	var center_x := area_width / 2.0
	var center_y := area_height / 2.0

	if show_attack_button:
		_attack_button = _create_button("AttackButton", attack_action, "A", button_radius)
		_attack_button.pressed_color = Color(0.8, 0.3, 0.3, 0.9)
		_attack_button.position = Vector2(area_width - button_radius * 2.0, center_y - button_radius)
		button_area.add_child(_attack_button)

	if show_jump_button:
		_jump_button = _create_button("JumpButton", jump_action, "B", button_radius)
		_jump_button.pressed_color = Color(0.3, 0.6, 0.8, 0.9)
		_jump_button.position = Vector2(center_x - button_radius, 0.0)
		button_area.add_child(_jump_button)

	if show_dash_button:
		_dash_button = _create_button("DashButton", dash_action, "X", button_radius)
		_dash_button.pressed_color = Color(0.3, 0.8, 0.3, 0.9)
		_dash_button.position = Vector2(0.0, center_y - button_radius)
		button_area.add_child(_dash_button)

func _create_button(name: String, action_name: String, button_label: String, radius: float):
	var button = VIRTUAL_BUTTON_SCRIPT.new()
	button.name = name
	button.action = action_name
	button.label = button_label
	button.button_radius = radius
	button.size = Vector2(radius * 2.0, radius * 2.0)
	return button

func _is_mobile_platform() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")
