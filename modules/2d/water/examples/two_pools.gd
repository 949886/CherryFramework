extends Node2D

@export var pools: Array[CherryWater2D] = []
@export var waterfalls: Array[CherryWaterfall2D] = []

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var point:=get_global_mouse_position()
		for pool in pools:
			if pool.contains_point(point):
				pool.impact(point,12)
				pool.emit_bubbles(point,15)
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_SPACE:
			for child in pools + waterfalls:
				if child is CherryWater2D or child is CherryWaterfall2D:
					child.auto_simulate=not child.auto_simulate
		elif event.keycode==KEY_R:
			for child in pools + waterfalls:
				if child is CherryWater2D or child is CherryWaterfall2D:
					child.reset()
