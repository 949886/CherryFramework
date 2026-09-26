class_name StoryFlowCanvas
extends Control
## The graph world moves; chrome stays in the authored overlay. Pointer capture
## is handled here so dragging can start on cards and finish outside the canvas.

@export var min_zoom := 0.3
@export var max_zoom := 1.75
@export var grid_spacing := 22.0
@export var drag_threshold := 5.0
@onready var world: Control = $World
var view: Control
var pan := Vector2.ZERO
var zoom := 1.0
var dragging := false
var suppress_click := false
var _armed := false
var _last_pointer := Vector2.ZERO
var _origin := Vector2.ZERO
var _old_size := Vector2.ZERO

func _ready() -> void:
	resized.connect(_resize)

func _resize() -> void:
	if view == null: return
	if _old_size != Vector2.ZERO: pan += (size - _old_size) / 2.0
	_old_size = size
	refresh()

func refresh() -> void:
	if view == null: return
	var bounds: Rect2 = view.graph_bounds()
	pan.x = clampf(pan.x, size.x * 0.35 - bounds.end.x * zoom, size.x * 0.65 - bounds.position.x * zoom)
	pan.y = clampf(pan.y, size.y * 0.35 - bounds.end.y * zoom, size.y * 0.65 - bounds.position.y * zoom)
	world.position = pan
	world.scale = Vector2.ONE * zoom
	for card in view.cards.values(): card.update_zoom(zoom)
	view.zoom_label.text = "%d%%" % roundi(zoom * 100)
	queue_redraw()
	view.minimap.queue_redraw()

func center_on(identity: String) -> void:
	if not view.positions.has(identity): return
	pan = size / 2.0 - (view.positions[identity] + view.card_size / 2.0) * zoom
	refresh()

func zoom_at(point: Vector2, next: float) -> void:
	next = clampf(next, min_zoom, max_zoom)
	pan = point - (point - pan) * next / zoom
	zoom = next
	refresh()

func card_input(event: InputEvent, card: Control) -> void:
	if event is InputEventMouseButton:
		var point: Vector2 = get_global_transform().affine_inverse() * (card.get_global_transform() * event.position)
		_pointer_button(event, point)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton: _pointer_button(event, event.position)

func _pointer_button(event: InputEventMouseButton, point: Vector2) -> void:
	if view == null or view.no_results: return
	if event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
		_armed = true
		_origin = point
		_last_pointer = point
		suppress_click = false
	if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		zoom_at(point, zoom * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15))
		accept_event()

func _input(event: InputEvent) -> void:
	if not _armed: return
	if not is_visible_in_tree():
		_armed = false
		dragging = false
		return
	if event is InputEventMouseMotion:
		var point: Vector2 = get_global_transform().affine_inverse() * event.position
		if point.distance_to(_origin) >= drag_threshold: dragging = true
		if dragging:
			suppress_click = true
			pan += point - _last_pointer
			refresh()
			get_viewport().set_input_as_handled()
		_last_pointer = point
	elif event is InputEventMouseButton and not event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
		_armed = false
		dragging = false
		# Native Button.pressed fires later in this input dispatch. Keep the drag
		# suppression flag until that dispatch finishes, without rebuilding nodes.
		_clear_suppression.call_deferred()

func pointer_armed() -> bool:
	return _armed

func _clear_suppression() -> void:
	suppress_click = false

func _draw() -> void:
	if view == null: return
	var colors: Dictionary = view.skin.colors
	draw_rect(Rect2(Vector2.ZERO, size), colors.soft)
	for x in range(0, int(size.x), int(grid_spacing)):
		for y in range(0, int(size.y), int(grid_spacing)): draw_circle(Vector2(x, y), 0.8, colors.line)
	if view.no_results: return
	for edge in view.presenter.library.edges:
		var points: PackedVector2Array = edge_points(edge)
		var selected_edge: bool = edge.from == view.selected or edge.to == view.selected
		var traveled: bool = view.presenter.archive.progress.has(edge.from) and view.presenter.archive.progress.has(edge.to)
		var color: Color = colors.accent if selected_edge or traveled else colors.muted
		color.a = 1.0 if selected_edge else (0.7 if traveled else 0.38)
		var width := 2.5 if selected_edge else (2.0 if traveled else 1.5)
		if view.status(edge.to) == "locked":
			for i in range(points.size() - 1):
				if i % 4 < 2: draw_line(points[i], points[i + 1], color, width, true)
		else: draw_polyline(points, color, width, true)

func edge_points(edge: Dictionary) -> PackedVector2Array:
	var start: Vector2 = pan + (view.positions[edge.from] + Vector2(view.card_size.x, view.card_size.y / 2.0)) * zoom
	var end: Vector2 = pan + (view.positions[edge.to] + Vector2(0, view.card_size.y / 2.0)) * zoom
	var bend := maxf(absf(end.x - start.x) * 0.5, 48.0 * zoom)
	var points := PackedVector2Array()
	for step in range(49):
		points.append(start.bezier_interpolate(start + Vector2(bend, 0), end - Vector2(bend, 0), end, float(step) / 48.0))
	return points
