@tool
class_name CherryVirtualJoystick
extends Control

enum JoystickMode {
	FIXED,
	DYNAMIC,
	FOLLOWING,
	DYNAMIC_FOLLOWING,
}

enum VisibilityMode {
	ALWAYS,
	TOUCH_ONLY,
	FADE_IN_OUT,
}

signal joystick_input(output: Vector2)
signal joystick_pressed
signal joystick_released

var _mode: JoystickMode = JoystickMode.FIXED
var _visibility_mode: VisibilityMode = VisibilityMode.ALWAYS
var _base_radius := 75.0
var _handle_radius := 35.0

@export_group("Joystick")
@export var mode: JoystickMode = JoystickMode.FIXED:
	set(value):
		_mode = value
		queue_redraw()
	get:
		return _mode

@export var visibility_mode: VisibilityMode = VisibilityMode.ALWAYS:
	set(value):
		_visibility_mode = value
		_update_visibility()
		queue_redraw()
	get:
		return _visibility_mode

@export_range(0.0, 1.0, 0.01) var dead_zone := 0.2
@export_range(-1.0, 1.0, 0.01) var clamp_zone := 1.0
@export_range(0.0, 1000.0, 1.0) var touch_area_margin := 100.0

@export_group("Input Actions")
@export var action_left := ""
@export var action_right := ""
@export var action_up := ""
@export var action_down := ""

@export_group("Appearance")
@export var base_texture: Texture2D
@export var handle_texture: Texture2D

@export var base_radius := 75.0:
	set(value):
		_base_radius = maxf(value, 10.0)
		_update_minimum_size()
		queue_redraw()
	get:
		return _base_radius

@export var handle_radius := 35.0:
	set(value):
		_handle_radius = maxf(value, 5.0)
		queue_redraw()
	get:
		return _handle_radius

@export var base_color := Color(0.15, 0.15, 0.15, 0.6)
@export var handle_color := Color(0.8, 0.8, 0.8, 0.8)
@export var handle_pressed_color := Color(1.0, 1.0, 1.0, 1.0)
@export_range(0.0, 1.0, 0.01) var inactive_opacity := 0.5
@export_range(0.0, 1.0, 0.01) var active_opacity := 1.0

var _is_pressed := false
var _touch_index := -1
var _output := Vector2.ZERO
var _base_center := Vector2.ZERO
var _handle_position := Vector2.ZERO

var output: Vector2:
	get:
		return _output

var is_pressed: bool:
	get:
		return _is_pressed

var strength: float:
	get:
		return _output.length()

var angle: float:
	get:
		return _output.angle()

var effective_base_radius: float:
	get:
		return minf(size.x, size.y) / 2.0

var effective_handle_radius: float:
	get:
		if base_radius <= 0.0:
			return effective_base_radius * 0.47
		return effective_base_radius * (handle_radius / base_radius)

func _ready() -> void:
	_base_center = size / 2.0
	_handle_position = _base_center
	_update_visibility()
	_update_minimum_size()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch_event(event)
	elif event is InputEventScreenDrag:
		_handle_drag_event(event)

func _draw() -> void:
	_draw_base()
	_draw_handle()

func _get_minimum_size() -> Vector2:
	return Vector2(base_radius * 2.0, base_radius * 2.0)

func _handle_touch_event(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		if _is_pressed:
			return

		if mode == JoystickMode.FIXED:
			var local_pos := _screen_to_local(touch.position)
			if local_pos.distance_to(_base_center) <= effective_base_radius:
				_start_touch(touch.index, local_pos)
		else:
			var expanded_rect := get_global_rect().grow(touch_area_margin)
			if expanded_rect.has_point(touch.position):
				var local_pos := _screen_to_local(touch.position)
				_base_center = local_pos
				_handle_position = local_pos
				_start_touch(touch.index, local_pos)
	else:
		if touch.index == _touch_index:
			_end_touch()

func _handle_drag_event(drag: InputEventScreenDrag) -> void:
	if drag.index != _touch_index:
		return
	_update_handle_position(_screen_to_local(drag.position))

func _start_touch(index: int, local_pos: Vector2) -> void:
	_touch_index = index
	_is_pressed = true
	_update_handle_position(local_pos)
	_update_visibility()
	joystick_pressed.emit()
	queue_redraw()

func _end_touch() -> void:
	_is_pressed = false
	_touch_index = -1
	_output = Vector2.ZERO

	if mode != JoystickMode.FIXED:
		_base_center = size / 2.0

	_handle_position = _base_center
	_update_input_actions(Vector2.ZERO)
	_update_visibility()
	joystick_input.emit(Vector2.ZERO)
	joystick_released.emit()
	queue_redraw()

func _update_handle_position(local_pos: Vector2) -> void:
	var diff := local_pos - _base_center
	var dist := diff.length()
	var max_dist := effective_base_radius * clamp_zone

	if mode in [JoystickMode.FOLLOWING, JoystickMode.DYNAMIC_FOLLOWING] and dist > max_dist and max_dist > 0.0:
		_base_center += diff.normalized() * (dist - max_dist)
		diff = local_pos - _base_center
		dist = diff.length()

	if max_dist > 0.0 and dist > max_dist:
		_handle_position = _base_center + diff.normalized() * max_dist
	else:
		_handle_position = local_pos

	if max_dist > 0.0:
		var raw_output := (_handle_position - _base_center) / max_dist
		var current_strength := raw_output.length()
		if current_strength < dead_zone:
			_output = Vector2.ZERO
		else:
			var remapped_strength := (current_strength - dead_zone) / maxf(1.0 - dead_zone, 0.0001)
			_output = raw_output.normalized() * minf(remapped_strength, 1.0)
	else:
		_output = Vector2.ZERO

	_update_input_actions(_output)
	joystick_input.emit(_output)
	queue_redraw()

func _update_input_actions(current_output: Vector2) -> void:
	if Engine.is_editor_hint():
		return

	_update_single_action(action_left, -current_output.x)
	_update_single_action(action_right, current_output.x)
	_update_single_action(action_up, -current_output.y)
	_update_single_action(action_down, current_output.y)

func _update_single_action(action: String, action_strength: float) -> void:
	if action.is_empty() or not InputMap.has_action(action):
		return

	if action_strength > 0.0:
		if Input.is_action_pressed(action):
			Input.action_release(action)
		Input.action_press(action, action_strength)
	elif Input.is_action_pressed(action):
		Input.action_release(action)

func _draw_base() -> void:
	var radius := effective_base_radius
	if base_texture:
		var tex_size := base_texture.get_size()
		var scale := (radius * 2.0) / maxf(tex_size.x, tex_size.y)
		var draw_pos := _base_center - tex_size * scale / 2.0
		draw_texture_rect(base_texture, Rect2(draw_pos, tex_size * scale), false, base_color)
		return

	draw_circle(_base_center, radius, base_color, true)
	if dead_zone > 0.0:
		var dz_color := Color(base_color.r, base_color.g, base_color.b, base_color.a * 0.3)
		draw_arc(_base_center, radius * dead_zone, 0.0, TAU, 128, dz_color, 1.5, true)
	var ring_color := Color(base_color.r + 0.1, base_color.g + 0.1, base_color.b + 0.1, base_color.a * 0.8)
	draw_arc(_base_center, radius, 0.0, TAU, 128, ring_color, 2.0, true)

func _draw_handle() -> void:
	var color := handle_pressed_color if _is_pressed else handle_color
	var radius := effective_handle_radius
	if handle_texture:
		var tex_size := handle_texture.get_size()
		var scale := (radius * 2.0) / maxf(tex_size.x, tex_size.y)
		var draw_pos := _handle_position - tex_size * scale / 2.0
		draw_texture_rect(handle_texture, Rect2(draw_pos, tex_size * scale), false, color)
		return

	draw_circle(_handle_position, radius, color, true)
	var border_color := Color(color.r * 0.8, color.g * 0.8, color.b * 0.8, color.a)
	draw_arc(_handle_position, radius, 0.0, TAU, 128, border_color, 2.0, true)
	draw_circle(_handle_position, radius * 0.4, Color(1.0, 1.0, 1.0, color.a * 0.3), true)

func _update_visibility() -> void:
	match visibility_mode:
		VisibilityMode.ALWAYS:
			modulate.a = 1.0
			visible = true
		VisibilityMode.TOUCH_ONLY:
			visible = _is_pressed
		VisibilityMode.FADE_IN_OUT:
			visible = true
			var tween := create_tween()
			tween.tween_property(self, "modulate:a", active_opacity if _is_pressed else inactive_opacity, 0.15)

func _screen_to_local(screen_pos: Vector2) -> Vector2:
	return screen_pos - global_position

func _update_minimum_size() -> void:
	custom_minimum_size = _get_minimum_size()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if not Engine.is_editor_hint():
			_release_all_actions()
	elif what == NOTIFICATION_RESIZED:
		_base_center = size / 2.0
		if not _is_pressed:
			_handle_position = _base_center
		queue_redraw()

func _release_all_actions() -> void:
	_release_action(action_left)
	_release_action(action_right)
	_release_action(action_up)
	_release_action(action_down)

func _release_action(action: String) -> void:
	if action.is_empty() or not InputMap.has_action(action):
		return
	if Input.is_action_pressed(action):
		Input.action_release(action)
