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
    var a:=CherryWater2D.new()
    var b:=CherryWater2D.new()
    for water in [a,b]:
        water.auto_simulate=false
        water.ambient_amplitudes=Vector2.ZERO
        root.add_child(water)
    b.position=Vector2(321,93)
    b.rotation=.3
    b.scale=Vector2(1.4,.7)
    check(a.surface_texture!=b.surface_texture and a.water_material!=b.water_material,"Instances own their GPU resources")
    a.impulse(128,12)
    for i in range(20):
        a.advance(1.0/60)
    check(absf(a.get_displacements()[69])>.001,"Impulse propagates")
    check(b.get_displacements().count(0.0)==b.sample_count,"Other pool stays undisturbed")
    check(b.contains_point(b.to_global(Vector2(100,30))),"Transformed wet point")
    check(not b.contains_point(b.to_global(Vector2(100,-20))),"Transformed dry point")
    a.reset()
    b.reset()
    a.impulse(100,8)
    b.impulse(100,8)
    for i in range(60):
        a.advance(1.0/60)
    for i in range(120):
        b.advance(1.0/120)
    check(a.get_displacements()==b.get_displacements(),"Fixed steps agree at 60 and 120 Hz")
    var synchronized:=true
    for i in range(b.sample_count):
        synchronized=synchronized and absf(b.surface_at(b.mesh.polygon[i].x)-b.mesh.polygon[i].y)<.0001
    check(synchronized,"Surface queries equal geometry")
    if DisplayServer.get_name()!="headless":
        var profile:=b.surface_texture.get_image()
        synchronized=true
        for i in range(b.sample_count):
            synchronized=synchronized and absf(profile.get_pixel(i,0).r-b.mesh.polygon[i].y)<.0001
        check(synchronized,"GPU profile equals geometry")
        RenderingServer.set_default_clear_color(Color.BLACK)
        root.content_scale_size=Vector2i(800,480)
        a.position=Vector2(20,120)
        var camera:=Camera2D.new()
        camera.position=Vector2(370,210)
        camera.zoom=Vector2(1.1,1.1)
        root.add_child(camera)
        await process_frame
        await RenderingServer.frame_post_draw
        var image:=root.get_texture().get_image()
        var aligned:=true
        for water in [a,b]:
            for x in range(30,220,15):
                var surface: Vector2=water.surface_point(x)
                var dry: Vector2=water.get_global_transform_with_canvas()*(surface-Vector2(0,6))
                var wet: Vector2=water.get_global_transform_with_canvas()*(surface+Vector2(0,8))
                aligned=aligned and image.get_pixelv(Vector2i(dry)).b<.02 and image.get_pixelv(Vector2i(wet)).b>.04
        check(aligned,"Rendered water follows transformed surfaces with camera zoom and an 800x480 viewport")
        camera.free()
    b.bubble_limit=4
    b.emit_bubbles(b.to_global(Vector2(100,40)),100)
    check(b.bubbles.size()==4,"Bubble budget")
    b.reset()
    check(b.bubbles.is_empty() and b.get_displacements().count(0.0)==b.sample_count,"Reset clears simulation and effects")
    a.free()
    b.free()
    print("CHERRY WATER TEST ",JSON.stringify({"checks":checks,"failures":failures}))
    quit(0 if failures.is_empty() else 1)
