@tool
class_name VirtualProgressButton
extends Control

signal pressed
signal button_down
signal button_up

var _button_radius := 40.0
var _cooldown_progress := 0.0
var _charge_count := 1
var _max_charge_count := 1

@export_group("Appearance")
@export var action := ""
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

@export_group("Skill Mechanics")
@export_range(0.0, 1.0, 0.01) var cooldown_progress := 0.0:
	set(value):
		_cooldown_progress = clampf(value, 0.0, 1.0)
		queue_redraw()
	get:
		return _cooldown_progress

@export var cooldown_color := Color(0.1, 0.1, 0.1, 0.8)
@export var cooldown_ring_width := 6.0

@export var charge_count := 1:
	set(value):
		_charge_count = maxi(value, 0)
		queue_redraw()
	get:
		return _charge_count

@export var max_charge_count := 1:
	set(value):
		_max_charge_count = maxi(value, 1)
		queue_redraw()
	get:
		return _max_charge_count

@export var charge_dot_color := Color(0.9, 0.9, 0.2, 1.0)
@export var charge_dot_radius := 4.0
@export var charge_dot_spacing := 12.0
@export var charge_dot_offset := Vector2(0, -15.0)

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
	if event is not InputEventScreenTouch:
		return

	var touch := event as InputEventScreenTouch
	if touch.pressed:
		if _is_pressed or charge_count == 0:
			return
		var local_pos := touch.position - global_position
		if local_pos.distance_to(size / 2.0) <= effective_radius:
			_touch_index = touch.index
			_is_pressed = true
			if not Engine.is_editor_hint() and not action.is_empty() and InputMap.has_action(action):
				Input.action_press(action)
			button_down.emit()
			queue_redraw()
	else:
		if touch.index != _touch_index:
			return
		_is_pressed = false
		_touch_index = -1
		if not Engine.is_editor_hint() and not action.is_empty() and InputMap.has_action(action):
			Input.action_release(action)
		button_up.emit()
		pressed.emit()
		queue_redraw()

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

	if not label.is_empty():
		_draw_label(center)

	if cooldown_progress > 0.0 and charge_count == 0:
		var start_angle := -PI / 2.0
		var end_angle := start_angle + TAU * cooldown_progress
		draw_circle(center, radius, Color(0, 0, 0, 0.4), true)
		var arc_radius := radius * 0.9
		var progress_color := Color(current_color.r + 0.2, current_color.g + 0.2, current_color.b + 0.2, 1.0)
		if cooldown_progress >= 0.999:
			draw_arc(center, arc_radius, 0.0, TAU, 64, cooldown_color, cooldown_ring_width, true)
		else:
			draw_arc(center, arc_radius, start_angle, end_angle, maxi(8, int(64 * cooldown_progress)), progress_color, cooldown_ring_width, true)

	if max_charge_count >= 2:
		_draw_charge_dots(center)

func _draw_charge_dots(center: Vector2) -> void:
	var base_pos := center + Vector2(0, -button_radius) + charge_dot_offset
	var total_width := float(max_charge_count - 1) * charge_dot_spacing
	var start_x := base_pos.x - total_width / 2.0
	for i in range(max_charge_count):
		var dot_pos := Vector2(start_x + float(i) * charge_dot_spacing, base_pos.y)
		if i < charge_count:
			draw_circle(dot_pos, charge_dot_radius, charge_dot_color, true)
		else:
			draw_arc(dot_pos, charge_dot_radius, 0.0, TAU, 16, charge_dot_color, 1.5, true)

func _get_minimum_size() -> Vector2:
	return Vector2(button_radius * 2.0, button_radius * 2.0)

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
