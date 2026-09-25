class_name StorySkin
extends RefCounted
## Shared native drawing tokens. Dialogue and settings preview deliberately use
## the same component and fonts rather than separately approximated styles.

const ICONS = preload("../resources/galgame_icons.tres")

var preferences: StoryPreferences
var colors: Dictionary = {}
var ui_font: SystemFont
var body_font: FontVariation
var theme: Theme
var _sized_icons: Dictionary = {}

func _init(settings: StoryPreferences) -> void:
	preferences = settings
	rebuild()

func rebuild() -> void:
	colors.clear()
	var palette := preferences.palette()
	for key in ["paper", "ink", "muted", "accent", "line", "soft", "name", "name_ink"]:
		colors[key] = Color(String(palette[key]))
	ui_font = SystemFont.new()
	ui_font.font_names = PackedStringArray(["Noto Serif SC", "Source Han Serif SC", "SimSun", "serif"])
	var sans := SystemFont.new()
	var families := {
		"sans": ["Noto Sans SC", "Microsoft YaHei", "PingFang SC", "sans-serif"],
		"rounded": ["YouYuan", "幼圆", "Hiragino Maru Gothic ProN", "Microsoft YaHei", "sans-serif"],
		"serif": ["Noto Serif SC", "SimSun", "serif"],
	}
	sans.font_names = PackedStringArray(families[preferences.values.font])
	sans.font_weight = {"regular": 400, "medium": 500, "bold": 700}[preferences.values.weight]
	body_font = FontVariation.new()
	body_font.base_font = sans
	body_font.spacing_glyph = roundi(preferences.values.letter_spacing)
	theme = Theme.new()
	theme.default_font = ui_font
	theme.default_font_size = 16
	for type in ["Label", "Button", "CheckButton", "OptionButton", "LineEdit", "PopupMenu"]:
		theme.set_color("font_color", type, colors.ink)
		theme.set_color("font_hover_color", type, colors.accent)
		theme.set_color("font_pressed_color", type, colors.accent)
		theme.set_color("font_focus_color", type, colors.accent)
		theme.set_color("font_hover_pressed_color", type, colors.accent)
		theme.set_color("font_disabled_color", type, colors.muted)
	# White SVG artwork is tinted by the native button state, independently of
	# the selected text font. Keep disabled and keyboard-focus states legible.
	for type in ["Button", "OptionButton"]:
		for state in ["normal", "hover", "pressed", "focus", "hover_pressed", "disabled"]:
			theme.set_color("icon_" + state + "_color", type, colors.ink if state == "normal" else (colors.muted if state == "disabled" else colors.accent))
		theme.set_constant("h_separation", type, 7)
	theme.set_icon("arrow", "OptionButton", icon("chevron-down"))
	theme.set_constant("modulate_arrow", "OptionButton", 1)
	for type in ["Button", "OptionButton", "LineEdit"]:
		theme.set_stylebox("normal", type, box(colors.paper, colors.line, 8, 12))
		theme.set_stylebox("hover", type, box(colors.soft, colors.line, 8, 12))
		theme.set_stylebox("pressed", type, box(colors.soft, colors.accent, 8, 12))
		theme.set_stylebox("disabled", type, box(colors.soft, colors.line, 8, 12))
		theme.set_stylebox("focus", type, box(Color.TRANSPARENT, colors.accent, 8, 0))
	theme.set_stylebox("panel", "PopupMenu", box(colors.paper, colors.line, 8, 12))
	theme.set_color("default_color", "RichTextLabel", colors.ink)
	theme.set_color("font_placeholder_color", "LineEdit", colors.muted)
	for key in ["slider", "grabber_area", "grabber_area_highlight"]:
		var track := box(colors.line if key == "slider" else colors.accent, Color.TRANSPARENT, 3, 0)
		track.content_margin_top = 3
		track.content_margin_bottom = 3
		theme.set_stylebox(key, "HSlider", track)
	for key in ["grabber", "grabber_highlight"]:
		var grabber := DPITexture.create_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="18" height="18"><circle cx="9" cy="9" r="7" fill="#%s" stroke="#%s" stroke-width="2"/></svg>' % [colors.paper.to_html(false), colors.accent.to_html(false)])
		theme.set_icon(key, "HSlider", grabber)
	theme.set_stylebox("background", "ProgressBar", box(colors.line, Color.TRANSPARENT, 4))
	theme.set_stylebox("fill", "ProgressBar", box(colors.accent, Color.TRANSPARENT, 4))
	var separator := StyleBoxLine.new()
	separator.color = colors.line
	separator.thickness = 1
	theme.set_stylebox("separator", "HSeparator", separator)

static func box(fill: Color, border := Color.TRANSPARENT, radius := 8, padding := 0) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(1 if border.a > 0 else 0)
	style.set_corner_radius_all(radius)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = padding
	style.content_margin_bottom = padding
	return style

func label(text: String, font_size := 16, color_key := "ink") -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", colors[color_key])
	result.set_meta("palette_color", color_key)
	return result

func refresh_labels(node: Node) -> void:
	if node is Label and node.has_meta("palette_color"):
		node.add_theme_color_override("font_color", colors[node.get_meta("palette_color")])
	elif node is TextureRect and node.has_meta("palette_color"):
		node.self_modulate = colors[node.get_meta("palette_color")]
	for child in node.get_children(): refresh_labels(child)

func icon(identity: String, extent := 0) -> Texture2D:
	var source := ICONS.get_meta("icons").get(identity) as Texture2D
	if not source is DPITexture or extent <= 0 or extent == source.get_width():
		return source
	# Viewport oversampling handles window/HiDPI scaling. A TextureRect's own
	# size (e.g. the larger brand mark) also needs matching logical SVG density.
	# Cache these variants without mutating the shared button texture resource.
	var key := "%s:%d" % [identity, extent]
	if not _sized_icons.has(key):
		var sized := source.duplicate() as DPITexture
		sized.base_scale *= float(extent) / source.get_width()
		_sized_icons[key] = sized
	return _sized_icons[key]

func icon_view(identity: String, extent := 18, color_key := "ink") -> TextureRect:
	var result := TextureRect.new()
	result.texture = icon(identity, extent)
	result.custom_minimum_size = Vector2.ONE * extent
	result.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	result.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	result.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result.self_modulate = colors[color_key]
	result.set_meta("palette_color", color_key)
	return result

func icon_label(identity: String, text: String, font_size := 16, color_key := "ink") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	row.add_child(icon_view(identity, font_size, color_key))
	row.add_child(label(text, font_size, color_key))
	return row

func button(text: String, callback: Callable, minimum := Vector2.ZERO, icon_id := "") -> Button:
	var result := Button.new()
	result.text = text
	if not icon_id.is_empty(): result.icon = icon(icon_id)
	result.custom_minimum_size = minimum
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if callback.is_valid():
		result.pressed.connect(callback)
	return result

func style_body(label_node: RichTextLabel) -> void:
	var settings := preferences.values
	var font_size := int(settings.font_size)
	for key in ["normal_font", "bold_font", "italics_font", "bold_italics_font"]:
		label_node.add_theme_font_override(key, body_font)
	for key in ["normal_font_size", "bold_font_size", "italics_font_size", "bold_italics_font_size"]:
		label_node.add_theme_font_size_override(key, font_size)
	label_node.add_theme_color_override("default_color", colors.ink if settings.theme_text else Color(settings.text_color))
	# RichTextLabel adds pixels to the font's line height; do not confuse the
	# desired CSS-like multiplier with a raw extra pixel amount.
	label_node.add_theme_constant_override("line_separation", roundi(font_size * float(settings.line_height) - body_font.get_height(font_size)))
	label_node.add_theme_constant_override("paragraph_separation", 0)
	label_node.add_theme_constant_override("outline_size", 2 if settings.text_effect == "outline" else 0)
	label_node.add_theme_color_override("font_outline_color", colors.paper)
	label_node.add_theme_color_override("font_shadow_color", Color(colors.accent, 0.3) if settings.text_effect == "shadow" else Color.TRANSPARENT)
	label_node.add_theme_constant_override("shadow_offset_x", 1)
	label_node.add_theme_constant_override("shadow_offset_y", 2)

func style_glass(material: ShaderMaterial, tint: Color, panel_size: Vector2, radius: float) -> void:
	# Dialogue, preview and choices share the same surface settings. Each keeps
	# its own material so resizing or highlighting one cannot affect another.
	var settings := preferences.values
	material.set_shader_parameter("tint", Color(tint, float(settings.glass_tint) / 100.0))
	material.set_shader_parameter("blur_pixels", settings.glass_blur)
	material.set_shader_parameter("saturation", float(settings.glass_saturation) / 100.0)
	material.set_shader_parameter("panel_size", panel_size)
	material.set_shader_parameter("radius", radius)
