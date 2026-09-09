extends Node2D

## 场景中已有的水体节点，直接拖入 Inspector 配置，演示不负责创建水池。
@export var pools: Array[CherryWater2D] = []
## 与暂停和重置联动的瀑布节点列表。
@export var waterfalls: Array[CherryWaterfall2D] = []
## 投放物体的 PackedScene 数据引用；根节点应使用 CherryFloatingObject2D。
@export var object_scene: PackedScene
## 运行时物体的容器节点，保存在示例场景中便于查看实例。
@export var objects: Node2D
## 同时存在的物体上限；超过时回收最早投放的物体。
@export_range(1,100,1) var maximum_objects := 24
var paused := false

## 在世界坐标 point 投放导出 PackedScene 指定的物体。水池引用在入树前传入。
## 达到数量上限先移除最旧实例；新物体继承暂停状态，防止暂停期间点击生成仍运动的物体。
func drop_object(point: Vector2) -> CherryFloatingObject2D:
	if object_scene==null or objects==null:
		return null
	if objects.get_child_count()>=maximum_objects:
		var oldest:=objects.get_child(0)
		objects.remove_child(oldest)
		oldest.queue_free()
	var body:=object_scene.instantiate() as CherryFloatingObject2D
	body.pools=pools
	body.freeze=paused
	objects.add_child(body)
	body.global_position=point
	body.angular_velocity=1.5
	return body

## 左键优先检测已有几何轮廓并弹起，未命中才投放新物体。
## Space 同步切换水体/瀑布自动推进与刚体冻结；R 清理物体并重置水体，保留当前暂停状态。
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT:
		var point:=get_global_mouse_position()
		for body in objects.get_children():
			if body is CherryFloatingObject2D and body.contains_global_point(point):
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
