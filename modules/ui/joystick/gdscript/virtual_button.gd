@tool
class_name VirtualButton
extends Control

signal button_down
signal button_up

var _button_radius := 40.0

@export_group("Input")
@export var action := ""

@export_group("Appearance")
@export var normal_texture: Texture2D
@export var pressed_texture: Texture2D

@export var button_radius := 40.0:
	set(value):
		_button_radius = maxf(value, 10.0)
		_update_minimum_size()
		queue_redraw()
	get:
		return _button_radius

@export var normal_color := Color(0.2, 0.2, 0.2, 0.6)
@export var pressed_color := Color(0.5, 0.5, 0.5, 0.9)
@export var icon_color := Color.WHITE
@export var label := ""
@export var label_font_size := 20
@export_range(0.0, 1.0, 0.01) var pressed_scale := 0.9

var _is_pressed := false
var _touch_index := -1

var is_pressed: bool:
	get:
		return _is_pressed

var effective_radius: float:
	get:
		return minf(size.x, size.y) / 2.0

func _ready() -> void:
	_update_minimum_size()

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)

func _draw() -> void:
	var center := size / 2.0
	var radius := effective_radius * (pressed_scale if _is_pressed else 1.0)
	var current_color := pressed_color if _is_pressed else normal_color

	if _is_pressed and pressed_texture:
		_draw_texture(pressed_texture, center, radius, current_color)
	elif normal_texture:
		_draw_texture(normal_texture, center, radius, current_color)
	else:
		draw_circle(center, radius, current_color, true)
		var ring_color := Color(current_color.r + 0.15, current_color.g + 0.15, current_color.b + 0.15, current_color.a)
		draw_arc(center, radius, 0.0, TAU, 128, ring_color, 2.0, true)
		if _is_pressed:
			draw_circle(center, radius * 0.7, Color(1.0, 1.0, 1.0, 0.15), true)

	if not label.is_empty():
		_draw_label(center)

func _get_minimum_size() -> Vector2:
	return Vector2(button_radius * 2.0, button_radius * 2.0)

func _handle_touch(touch: InputEventScreenTouch) -> void:
	if touch.pressed:
		if _is_pressed:
			return
		var local_pos := touch.position - global_position
		if local_pos.distance_to(size / 2.0) <= effective_radius:
			_press(touch.index)
	else:
		if touch.index == _touch_index:
			_release()

func _handle_drag(drag: InputEventScreenDrag) -> void:
	if drag.index != _touch_index:
		return
	var local_pos := drag.position - global_position
	if local_pos.distance_to(size / 2.0) > effective_radius * 1.5:
		_release()

func _press(index: int) -> void:
	_touch_index = index
	_is_pressed = true
	if not Engine.is_editor_hint() and not action.is_empty() and InputMap.has_action(action):
		Input.action_press(action)
	button_down.emit()
	queue_redraw()

func _release() -> void:
	_is_pressed = false
	_touch_index = -1
	if not Engine.is_editor_hint() and not action.is_empty() and InputMap.has_action(action):
		Input.action_release(action)
	button_up.emit()
	queue_redraw()

func _draw_texture(texture_2d: Texture2D, center: Vector2, radius: float, tint: Color) -> void:
	var tex_size := texture_2d.get_size()
	var scale := (radius * 2.0) / maxf(tex_size.x, tex_size.y)
	var draw_pos := center - tex_size * scale / 2.0
	draw_texture_rect(texture_2d, Rect2(draw_pos, tex_size * scale), false, tint)

func _draw_label(center: Vector2) -> void:
	var font := ThemeDB.fallback_font
	if font == null:
		return
	var scaled_font_size := label_font_size
	if button_radius > 0.0:
		scaled_font_size = maxi(int(label_font_size * (effective_radius / button_radius)), 8)
	var text_size := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, scaled_font_size)
	var text_pos := center - Vector2(text_size.x / 2.0, -text_size.y / 4.0)
	draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1, scaled_font_size, icon_color)

func _update_minimum_size() -> void:
	custom_minimum_size = _get_minimum_size()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and not Engine.is_editor_hint():
		if not action.is_empty() and InputMap.has_action(action) and Input.is_action_pressed(action):
			Input.action_release(action)
	elif what == NOTIFICATION_RESIZED:
		queue_redraw()
