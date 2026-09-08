extends SceneTree

var failures: Array[String]=[]
var checks:=0

func _initialize() -> void:
    _run.call_deferred()

func check(value: bool, message: String) -> void:
    checks+=1
    if not value:
        failures.append(message)
        push_error(message)

func _run() -> void:
    var path: String=get_script().resource_path.get_base_dir().path_join("../examples/two_pools.tscn")
    var packed:=load(path) as PackedScene
    var scene:=packed.instantiate()
    var left:=scene.get_node("LeftPool") as CherryWater2D
    var right:=scene.get_node("RightPool") as CherryWater2D
    check(left!=null and right!=null and scene.get_node("UI/Instructions") is Label,"Scene contains water and UI before ready")
    root.add_child(scene)
    check(scene.pools==[left,right] and scene.waterfalls.size()==1,"Exported node lists resolve")
    check(scene.get_node("Waterfall").water==left,"Serialized waterfall link resolves")
    var key:=InputEventKey.new()
    key.keycode=KEY_SPACE
    key.pressed=true
    scene._unhandled_input(key)
    check(not left.auto_simulate and not right.auto_simulate and not scene.waterfalls[0].auto_simulate,"Pause reaches serialized nodes")
    var original:=Vector2(left.width,left.depth)
    left.resize(Vector2(320,190))
    check(left.mesh.polygon[left.sample_count]==Vector2(320,190),"Resize rebuilds basin geometry")
    var saved:=PackedScene.new()
    check(saved.pack(scene)==OK,"Scene packs with resized water")
    var copy:=saved.instantiate()
    check(copy.get_node("LeftPool").width==320 and copy.get_node("LeftPool").depth==190,"Resize survives serialization")
    copy.free()
    left.bottom_points=PackedVector2Array([Vector2(320,190),Vector2(0,190)])
    left.resize(Vector2(160,95))
    check(left.bottom_points[0]==Vector2(160,95),"Custom basin scales with dimensions")
    left.resize(original)
    scene.free()
    print("WATER SCENE TEST ",JSON.stringify({"checks":checks,"failures":failures}))
    quit(0 if failures.is_empty() else 1)
