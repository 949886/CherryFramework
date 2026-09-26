class_name StoryFlowMinimap
extends Control
## Same graph bounds as the main canvas: click, drag or keyboard recentering
## never changes the selected file or the player's current reading position.
var view: Control
var _dragging := false

func mapping() -> Transform2D:
	var bounds: Rect2 = view.graph_bounds()
	var factor := minf((size.x - 12) / bounds.size.x, (size.y - 12) / bounds.size.y)
	return Transform2D(0, Vector2.ONE * factor, 0, (size - bounds.size * factor) / 2.0 - bounds.position * factor)

func _draw() -> void:
	if view == null: return
	var colors: Dictionary = view.skin.colors
	draw_style_box(view.skin.theme.get_stylebox("panel", "StoryFlowZoom"), Rect2(Vector2.ZERO, size))
	var transform := mapping()
	for edge in view.presenter.library.edges:
		draw_line(transform * (view.positions[edge.from] + view.card_size / 2), transform * (view.positions[edge.to] + view.card_size / 2), colors.line, 1.0)
	for identity in view.positions:
		var rect := Rect2(transform * view.positions[identity], view.card_size * transform.x.x)
		draw_rect(rect, colors.accent if view.status(identity) == "current" else colors.soft)
		draw_rect(rect, colors.accent if identity == view.selected else colors.line, false, 1.0)
	var viewport := Rect2(-view.canvas.pan / view.canvas.zoom, view.canvas.size / view.canvas.zoom)
	var frame := Rect2(transform * viewport.position, viewport.size * transform.x.x).intersection(Rect2(Vector2.ONE * 3, size - Vector2.ONE * 6))
	if frame.has_area():
		draw_rect(frame, Color(colors.accent, 0.12))
		draw_rect(frame, colors.accent, false, 1.0)
	if has_focus(): draw_rect(Rect2(Vector2.ONE, size - Vector2.ONE * 2), colors.accent, false, 1.0)

func _locate(point: Vector2) -> void:
	view.canvas.pan = view.canvas.size / 2.0 - (mapping().affine_inverse() * point) * view.canvas.zoom
	view.canvas.refresh()

func _gui_input(event: InputEvent) -> void:
	if view == null: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			grab_focus()
			_locate(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_locate(event.position)
		accept_event()
	elif event.is_action_pressed("ui_accept"):
		view._locate_current()
		accept_event()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = false
