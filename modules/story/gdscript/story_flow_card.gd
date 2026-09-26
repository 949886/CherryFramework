class_name StoryFlowCard
extends Button
## An authored native Button: keyboard focus/clicks stay native, while graph
## data only fills labels and colors. Cards remain mounted across filtering.

@export var overview_threshold := 0.55
@export var minimum_title_pixels := 12.0
@export var minimum_status_pixels := 10.0
@export var stroke: StoryFlowStroke
@onready var title_label: Label = %Title
@onready var file_label: Label = %File
@onready var status_label: Label = %Status
@onready var state_icon: TextureRect = %StateIcon
@onready var bookmark_mark: TextureRect = %BookmarkMark
@onready var margin: MarginContainer = %Margin
var skin: StorySkin
var state := "unread"
var selected := false
var matched := true
var _title_size := 19
var _status_size := 13
var _file_size := 12

func _ready() -> void:
	get_viewport().size_changed.connect(queue_redraw)
	_title_size = title_label.get_theme_font_size("font_size")
	_status_size = status_label.get_theme_font_size("font_size")
	_file_size = file_label.get_theme_font_size("font_size")

func bind_data(theme_skin: StorySkin, data: Dictionary) -> void:
	skin = theme_skin
	theme = skin.theme
	state = data.state
	selected = data.selected
	title_label.text = data.title
	file_label.text = data.file
	status_label.text = data.status_label
	state_icon.texture = skin.icon(state)
	bookmark_mark.visible = data.bookmarked
	var ink: Color = skin.colors.name_ink if state == "current" else skin.colors.ink
	for label in [title_label, status_label]: label.add_theme_color_override("font_color", ink if state == "current" else (skin.colors.accent if label == status_label else ink))
	state_icon.self_modulate = ink if state == "current" else skin.colors.accent
	bookmark_mark.self_modulate = state_icon.self_modulate
	file_label.add_theme_color_override("font_color", ink if state == "current" else skin.colors.muted)
	for item in ["normal", "hover", "pressed", "focus"]:
		var style := skin.theme.get_stylebox(item, "StoryFlowCard").duplicate() as StyleBoxFlat
		style.bg_color = skin.colors.name if state == "current" else (skin.colors.soft if state == "locked" or item in ["hover", "pressed"] else skin.colors.paper)
		style.border_color = skin.colors.accent if selected or item != "normal" else skin.colors.line
		style.shadow_color = Color(skin.colors.accent if selected else skin.colors.ink, 0.14 if selected else 0.04)
		if item == "focus": style.draw_center = false
		# The vector outline below owns the border. Keep native fills, focus and
		# shadows, without a second subpixel border beneath the crisp stroke.
		style.set_border_width_all(0)
		if state == "locked": style.shadow_size = 0
		add_theme_stylebox_override(item, style)
	tooltip_text = "%s · %s\n%s" % [data.title, data.status_label, data.file]
	queue_redraw()

func set_match(value: bool) -> void:
	matched = value
	modulate.a = 1.0 if value else 0.26

func update_zoom(zoom: float) -> void:
	# Keep titles readable in the fitted overview without inflating the cards.
	var overview := zoom < overview_threshold
	file_label.visible = not overview
	title_label.add_theme_font_size_override("font_size", maxi(_title_size, roundi(minimum_title_pixels / zoom)))
	status_label.add_theme_font_size_override("font_size", maxi(_status_size, roundi(minimum_status_pixels / zoom)))
	file_label.add_theme_font_size_override("font_size", maxi(_file_size, roundi(minimum_status_pixels / zoom)))
	margin.offset_left = 9.0 if overview else 16.0
	margin.offset_right = -margin.offset_left
	margin.offset_top = 9.0 if overview else 13.0
	margin.offset_bottom = -margin.offset_top
	queue_redraw()

func _draw() -> void:
	if skin == null: return
	var style := get_theme_stylebox("normal") as StyleBoxFlat
	var outline := stroke.rounded_outline(Rect2(Vector2.ZERO, size), style.corner_radius_top_left)
	var border: Color = skin.colors.accent if selected or is_hovered() or has_focus() else skin.colors.line
	# Dash phase continues around the corners, matching a rounded CSS/SVG
	# outline. Locked cards no longer have four disconnected, fuzzy sides.
	stroke.draw_path(self, outline, border, stroke.outline_width, stroke.outline_dash if state == "locked" else 0.0, stroke.outline_gap if state == "locked" else 0.0)
	for point in [Vector2(0, size.y / 2), Vector2(size.x, size.y / 2)]:
		draw_circle(point, 4.0, skin.colors.paper)
		draw_arc(point, 4.0, 0, TAU, 20, skin.colors.accent, 1.3, true)
