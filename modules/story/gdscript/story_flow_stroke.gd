class_name StoryFlowStroke
extends Resource
## Shared native vector stroke settings. Geometry is rasterized at viewport
## pixel density; no bitmap scaling, whole-viewport MSAA or blur is required.

@export_group("Connections")
@export var width := 1.5
@export var traveled_width := 2.0
@export var selected_width := 2.5
@export_range(0, 1) var opacity := 0.38
@export_range(0, 1) var traveled_opacity := 0.7
@export var dash_length := 5.0
@export var gap_length := 5.0
@export var curve_step := 2.0
@export var minimum_dash_pixels := 2.0
@export_group("Node outline")
@export var outline_width := 1.0
@export var outline_dash := 3.0
@export var outline_gap := 3.0

static func pixel_transform(item: CanvasItem) -> Transform2D:
	# Match the actual viewport texture, including canvas_items window stretch
	# and the presenter's 16:9 letterbox transform. OS window position is irrelevant.
	return item.get_viewport().get_stretch_transform() * item.get_global_transform_with_canvas()

func bezier(start: Vector2, end: Vector2, bend: float, density: float) -> PackedVector2Array:
	var curve := Curve2D.new()
	curve.add_point(start, Vector2.ZERO, Vector2(bend, 0))
	curve.add_point(end, Vector2(-bend, 0), Vector2.ZERO)
	return curve.tessellate_even_length(10, curve_step / maxf(density, 0.01))

static func dashes(points: PackedVector2Array, dash: float, gap: float) -> Array[PackedVector2Array]:
	# Walk cumulative arc length, carrying the remainder over every curve vertex.
	# Each dash is one polyline: AA is not restarted at each tessellation segment.
	var result: Array[PackedVector2Array] = []
	if points.size() < 2 or dash <= 0 or gap <= 0: return result
	var drawing := true
	var remaining := dash
	var path := PackedVector2Array([points[0]])
	for index in range(1, points.size()):
		var cursor := points[index - 1]
		var end := points[index]
		var distance := cursor.distance_to(end)
		while distance > 0.0001:
			var step := minf(remaining, distance)
			cursor = cursor.move_toward(end, step)
			if drawing: path.append(cursor)
			remaining -= step
			distance -= step
			if remaining <= 0.0001:
				if drawing and path.size() > 1: result.append(path)
				drawing = not drawing
				remaining = dash if drawing else gap
				path = PackedVector2Array([cursor]) if drawing else PackedVector2Array()
	if drawing and path.size() > 1: result.append(path)
	return result

func draw_path(item: CanvasItem, points: PackedVector2Array, color: Color, logical_width: float, dash := 0.0, gap := 0.0) -> void:
	if points.size() < 2: return
	var transform := pixel_transform(item)
	var density := transform.x.length()
	var pixel_width := maxf(1.0, roundf(logical_width * density))
	var pixels := transform * points
	# Odd widths straddle pixel centers, even widths pixel boundaries. Straight
	# connectors become crisp fills; curved paths keep native edge antialiasing.
	var horizontal := true
	var vertical := true
	for point in pixels:
		horizontal = horizontal and is_equal_approx(point.y, pixels[0].y)
		vertical = vertical and is_equal_approx(point.x, pixels[0].x)
	var center := fmod(pixel_width, 2.0) * 0.5
	for index in pixels.size():
		if horizontal: pixels[index].y = floorf(pixels[0].y) + center
		if vertical: pixels[index].x = floorf(pixels[0].x) + center
	var paths: Array[PackedVector2Array] = []
	# At small overview zooms a subpixel dash/gap would blend into a fuzzy
	# dotted line. Preserve distinct marks in physical pixels at every scale.
	if dash > 0 and gap > 0: paths = dashes(pixels, maxf(minimum_dash_pixels, dash * density), maxf(minimum_dash_pixels, gap * density))
	else: paths.append(pixels)
	item.draw_set_transform_matrix(transform.affine_inverse())
	for path in paths:
		item.draw_polyline(path, color, pixel_width, not (horizontal or vertical))
	item.draw_set_transform_matrix(Transform2D.IDENTITY)

static func rounded_outline(rect: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	radius = minf(radius, minf(rect.size.x, rect.size.y) / 2.0)
	var corners := [rect.position + Vector2(radius, radius), Vector2(rect.end.x - radius, rect.position.y + radius), rect.end - Vector2.ONE * radius, Vector2(rect.position.x + radius, rect.end.y - radius)]
	for corner in 4:
		for step in 13:
			var angle := PI + (corner + step / 12.0) * PI / 2.0
			points.append(corners[corner] + Vector2.from_angle(angle) * radius)
	points.append(points[0])
	return points
