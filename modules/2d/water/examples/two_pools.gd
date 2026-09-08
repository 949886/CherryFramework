extends Node2D

@export var pools: Array[CherryWater2D] = []
@export var waterfalls: Array[CherryWaterfall2D] = []
@export var object_scene: PackedScene
@export var objects: Node2D
@export_range(1,100,1) var maximum_objects := 24
var paused := false

func drop_object(point: Vector2) -> CherryWaterDemoFloat:
	if object_scene==null or objects==null:
		return null
	if objects.get_child_count()>=maximum_objects:
		var oldest:=objects.get_child(0)
		objects.remove_child(oldest)
		oldest.queue_free()
	var body:=object_scene.instantiate() as CherryWaterDemoFloat
	body.pools=pools
	body.freeze=paused
	objects.add_child(body)
	body.global_position=point
	body.angular_velocity=1.5
	return body

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var point:=get_global_mouse_position()
		for body in objects.get_children():
			if body is CherryWaterDemoFloat and body.contains_global_point(point):
				body.kick()
				return
		drop_object(point)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_SPACE:
			paused=not paused
			for child in pools + waterfalls:
				if child is CherryWater2D or child is CherryWaterfall2D:
					child.auto_simulate=not child.auto_simulate
			for body in objects.get_children():
				body.freeze=paused
		elif event.keycode==KEY_R:
			for body in objects.get_children():
				body.queue_free()
			for child in pools + waterfalls:
				if child is CherryWater2D or child is CherryWaterfall2D:
					child.reset()
