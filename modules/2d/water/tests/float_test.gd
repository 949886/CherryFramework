extends SceneTree

var failures: Array[String]=[]
func _initialize() -> void:
    _run.call_deferred()

func check(value: bool, message: String) -> void:
    if not value:
        failures.append(message)
        push_error(message)

func frames(count: int) -> void:
    for i in range(count):
        await physics_frame

func _run() -> void:
    var path: String=get_script().resource_path.get_base_dir().path_join("../examples/two_pools.tscn")
    var scene: Node2D=load(path).instantiate()
    root.add_child(scene)
    var body: CherryFloatingObject2D=scene.drop_object(Vector2(190,70))
    await frames(10)
    check(body.global_position.y>70,"Object falls under gravity")
    await frames(180)
    check(body.water_entries>0,"Entry triggers water interaction")
    var water: CherryWater2D=scene.pools[0]
    var surface:=water.to_global(water.surface_point(water.to_local(body.global_position).x)).y
    check(absf(body.global_position.y-surface)<20,"Object floats near moving surface")
    var before:=body.linear_velocity.y
    body.kick()
    await frames(1)
    check(body.linear_velocity.y<before-50,"Click kick launches the object")
    var key:=InputEventKey.new()
    key.keycode=KEY_SPACE
    key.pressed=true
    scene._unhandled_input(key)
    var point:=body.global_position
    await frames(10)
    check(body.global_position==point,"Pause freezes objects")
    key.keycode=KEY_R
    scene._unhandled_input(key)
    await process_frame
    check(scene.objects.get_child_count()==0,"Reset clears objects")
    for kind in range(1,8):
        var shaped: CherryFloatingObject2D=scene.object_scene.instantiate()
        shaped.shape_kind=kind
        shaped.pools=scene.pools
        scene.objects.add_child(shaped)
        shaped.global_position=Vector2(190,70)
        var collision: ConvexPolygonShape2D=shaped.get_node("CollisionShape2D").shape
        check(collision.points==shaped.get_node("Body").polygon,"Shape %d collision matches visible outline"%kind)
        await frames(180)
        var water_level:=water.to_global(water.surface_point(water.to_local(shaped.global_position).x)).y
        check(shaped.water_entries>0 and absf(shaped.global_position.y-water_level)<20,"Shape %d enters water and floats"%kind)
        shaped.free()
    print("WATER FLOAT TEST ",JSON.stringify({"checks":20,"failures":failures}))
    scene.free()
    quit(0 if failures.is_empty() else 1)
