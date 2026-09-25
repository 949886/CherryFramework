class_name StoryChoiceButton
extends Button
## A single interpolated style covers mouse, keyboard and confirmation states.
## The presenter drives the clock so menu pauses and choice cancellation cannot
## leave independent tweens running behind the UI or commit stale callbacks.

var reveal := 0.0
var emphasis := Vector2.ZERO # hover/focus, press/selection
var selected := false
var settling := false
var _skin: StorySkin
var _motion: Dictionary
var _reduced := false
var _elapsed := 0.0
var _duration := 0.0
var _from := Vector2.ZERO
var _target := Vector2.ZERO
var _box: StyleBoxFlat
var _settle_elapsed := 0.0
var glass: ColorRect
var _capture: BackBufferCopy

func _init() -> void:
	# Both children draw BEFORE the Button. Its native glyphs remain sharp and
	# keep native wrapping/input behavior; the shader only paints the backdrop.
	_capture = BackBufferCopy.new()
	_capture.show_behind_parent = true
	_capture.copy_mode = BackBufferCopy.COPY_MODE_DISABLED
	add_child(_capture)
	glass = ColorRect.new()
	glass.show_behind_parent = true
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glass.material = ShaderMaterial.new()
	(glass.material as ShaderMaterial).shader = preload("../resources/dialogue_glass.gdshader")
	glass.hide()
	add_child(glass)
	resized.connect(func():
		(glass.material as ShaderMaterial).set_shader_parameter("panel_size", size))

func configure(skin: StorySkin) -> void:
	_skin = skin
	_motion = skin.preferences.schema.choice_motion
	_reduced = skin.preferences.values.motion == "reduced"
	glass.visible = bool(skin.preferences.values.glass)
	_capture.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT if glass.visible else BackBufferCopy.COPY_MODE_DISABLED
	skin.style_glass(glass.material as ShaderMaterial, skin.colors.paper, size, 8.0)
	if _box == null:
		_box = StorySkin.box(skin.colors.paper, skin.colors.line, 8, 12)
		# Sharing one instance across states avoids the engine replacing the
		# animated style with an instantaneous hover/pressed/disabled style.
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			add_theme_stylebox_override(state, _box)
		add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	if _reduced:
		reveal = 1.0
		emphasis = _target
	_draw_state()

func set_interaction(highlighted: bool, down: bool) -> void:
	var target := Vector2(float(highlighted), float(down))
	if settling: target = Vector2.ONE if selected else Vector2.ZERO
	if target == _target: return
	_from = emphasis
	_target = target
	_elapsed = 0.0
	_duration = float(_motion.press_duration if down or settling else _motion.hover_duration)
	if _reduced or _duration <= 0.0:
		emphasis = target
		_draw_state()

func confirm_choice(is_selected: bool) -> void:
	selected = is_selected
	settling = true
	disabled = true
	set_interaction(is_selected, is_selected)
	_draw_state()

func advance_visuals(delta: float) -> void:
	if delta < 0.0: return
	if settling: _settle_elapsed += delta
	reveal = 1.0 if _reduced else minf(1.0, reveal + delta / maxf(0.001, float(_motion.enter_duration)))
	_elapsed = minf(_duration, _elapsed + delta)
	var fraction := 1.0 if _duration <= 0.0 or _reduced else _elapsed / _duration
	# Cubic ease-out starts from the current value on each reversal: rapid
	# pointer movement never jumps back to the beginning of an old animation.
	emphasis = _from.lerp(_target, 1.0 - pow(1.0 - fraction, 3.0))
	_draw_state()

func _draw_state() -> void:
	var highlight := maxf(emphasis.x, emphasis.y)
	var fill: Color = _skin.colors.paper.lerp(_skin.colors.soft, highlight).lerp(_skin.colors.name, emphasis.y * 0.45)
	_box.bg_color = Color.TRANSPARENT if glass.visible else fill
	_box.border_color = Color.TRANSPARENT if glass.visible else _skin.colors.line.lerp(_skin.colors.accent, highlight)
	if glass.visible:
		(glass.material as ShaderMaterial).set_shader_parameter("tint", Color(fill, float(_skin.preferences.values.glass_tint) / 100.0))
	var shift := 0.0 if _reduced else float(_motion.content_shift) * emphasis.x
	# Equal/opposite inset changes keep the minimum width and hit area fixed.
	_box.content_margin_left = 12.0 + shift
	_box.content_margin_right = 12.0 - shift
	var ink: Color = _skin.colors.ink.lerp(_skin.colors.accent, highlight)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_focus_color", "font_disabled_color"]:
		add_theme_color_override(state, ink)
	var progress := 1.0 if _reduced else clampf(_settle_elapsed / maxf(0.001, float(_motion.commit_duration)), 0.0, 1.0)
	var opacity := lerpf(1.0, float(_motion.muted_alpha), 1.0 - pow(1.0 - progress, 3.0)) if settling and not selected else 1.0
	modulate.a = opacity * (1.0 - pow(1.0 - reveal, 3.0))
