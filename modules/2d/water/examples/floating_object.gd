class_name CherryWaterDemoFloat
extends RigidBody2D

## Demo-specific buoyancy; the water module remains independent of rigid bodies.
@export var radius := 9.0
@export var buoyancy := 2.0
@export var water_drag := 3.0
@export_enum("Random", "Circle", "Triangle", "Square", "Rectangle", "Diamond", "Pentagon", "Hexagon") var shape_kind := 0
var chosen_shape := 0
var _outline := PackedVector2Array()
var _buoyancy_samples := PackedVector2Array()
var pools: Array[CherryWater2D] = []
var water_entries := 0
var _wet := false
var _age := 0.0
var _ripple_clock := 0.0

func _ready() -> void:
    configure_shape(randi_range(1,7) if shape_kind==0 else shape_kind)

## Visuals, collision and buoyancy all derive from the same convex outline.
func configure_shape(kind: int) -> void:
    chosen_shape=clampi(kind,1,7)
    _outline.clear()
    if chosen_shape==4:
        _outline=PackedVector2Array([Vector2(-1,-.55),Vector2(1,-.55),Vector2(1,.55),Vector2(-1,.55)])
        for i in range(_outline.size()):
            _outline[i]*=radius
    else:
        var sides: int=[24,3,4,4,4,5,6][chosen_shape-1]
        var phase:=PI*.25 if chosen_shape==3 else -PI*.5
        for i in range(sides):
            _outline.append(Vector2.from_angle(phase+TAU*float(i)/sides)*radius)
    $Body.polygon=_outline
    var highlight:=PackedVector2Array()
    for point in _outline:
        highlight.append(point*.45)
    $Highlight.polygon=highlight
    var collision:=ConvexPolygonShape2D.new()
    collision.points=_outline
    $CollisionShape2D.shape=collision
    _buoyancy_samples.clear()
    for y in range(9):
        for x in range(9):
            var sample_point:=Vector2((x+.5)/9.0*2-1,(y+.5)/9.0*2-1)*radius
            if Geometry2D.is_point_in_polygon(sample_point,_outline):
                _buoyancy_samples.append(sample_point)

func contains_global_point(point: Vector2) -> bool:
    return Geometry2D.is_point_in_polygon(to_local(point),_outline)

func _physics_process(delta: float) -> void:
    if freeze:
        return
    _age+=delta
    if _age>60 or global_position.y>2000:
        queue_free()
        return
    var wet_samples:=0
    var active_water: CherryWater2D
    # Distributed samples avoid a sudden force jump at the surface.
    for offset in _buoyancy_samples:
        for pool in pools:
            if is_instance_valid(pool) and pool.contains_point(to_global(offset)):
                wet_samples+=1
                active_water=pool
                break
    var fraction:=float(wet_samples)/maxi(1,_buoyancy_samples.size())
    if active_water!=null:
        var gravity: float=ProjectSettings.get_setting("physics/2d/default_gravity",980.0)
        var direction: Vector2=ProjectSettings.get_setting("physics/2d/default_gravity_vector",Vector2.DOWN)
        apply_central_force(-direction*gravity*gravity_scale*mass*buoyancy*fraction-linear_velocity*water_drag*mass*fraction)
        apply_torque(-angular_velocity*mass*20*fraction)
        if not _wet:
            water_entries+=1
            active_water.impact(global_position,clampf(linear_velocity.length()*.035,2,14))
            active_water.emit_bubbles(global_position,12)
        _ripple_clock+=delta
        if _ripple_clock>.12 and fraction<1 and linear_velocity.length()>8:
            active_water.impulse(active_water.to_local(global_position).x,clampf(linear_velocity.y*.015,-1.5,1.5))
            _ripple_clock=0
    _wet=wet_samples>0

func kick() -> void:
    if not freeze:
        apply_central_impulse(Vector2(45,-150)*mass)
        apply_torque_impulse(20)
