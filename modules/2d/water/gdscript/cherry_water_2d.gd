@tool
class_name CherryWater2D
extends Node2D

## A scene-local spring surface, refractive water polygon and optional effects.
## The node origin is the left end of the resting surface. X runs along the
## surface; Y runs down into the water. Queries accepting global points work
## through translated, rotated and scaled parents.
signal surface_impacted(global_point: Vector2, strength: float)

const WATER_SHADER = preload("../shaders/water.gdshader")
const FIXED_STEP := 1.0 / 60.0

@export_group("Shape")
@export_range(1,8192,1) var width := 256.0
@export_range(1,8192,1) var depth := 120.0
@export_range(3,1025,1) var sample_count := 129
## Right shore -> bottom -> left shore, in local coordinates; omit surface.
## Empty uses a rectangular basin. Do not cross or intersect the moving surface.
@export var bottom_points := PackedVector2Array()
@export_group("Simulation")
@export var auto_simulate := true
@export var simulation_enabled := true
@export var preview_animation := false
@export_range(0,.4,.005) var propagation := .20
@export_range(0,.2,.005) var spring_strength := .025
@export_range(0,.5,.005) var damping := .065
@export_range(0,128,.5) var maximum_displacement := 12.0
@export var ambient_amplitudes := Vector2(2.2,.9)
@export var ambient_frequencies := Vector2(.055,.14)
@export var ambient_speeds := Vector2(2.0,-1.7)
@export var wave_phase_offset := 0.0
@export var random_seed := 198527
@export_group("Appearance")
@export var shallow_color := Color(.018,.25,.70)
@export var deep_color := Color(.006,.014,.25)
@export var surface_color := Color(.38,1,.90)
@export_range(0,1,.01) var tint_strength := .16
@export_range(.1,16,.1) var surface_thickness := 1.8
@export_range(1,2048,1) var depth_range := 170.0
@export_range(0,4,.1) var caustic_strength := 1.0
@export var refraction_pixels := Vector2(.768,.432)
@export var pattern_offset := Vector2.ZERO
@export var light_shafts := PackedFloat32Array()
@export_group("Effects")
@export var effects_enabled := true
@export var splash_color := Color("b6ffff")
@export var bubble_color := Color(.48,.86,1,.65)
@export_range(0,4000,1) var particle_limit := 1000
@export_range(0,2000,1) var bubble_limit := 400

var simulation_time := 0.0
var surface_texture := ImageTexture.new()
var water_material := ShaderMaterial.new()
var mesh: Polygon2D
var bubbles: Array[Dictionary] = []
var _heights := PackedFloat32Array()
var _speeds := PackedFloat32Array()
var _levels := PackedFloat32Array()
var _particles: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _underlay: Node2D
var _overlay: Node2D
var _accumulator := 0.0
var _configuration_hash := 0
var _light_global := Vector2.ZERO
var _light_enabled := false

func _ready() -> void:
    initialize()

func _process(_delta: float) -> void:
    if _settings_hash()!=_configuration_hash:
        initialize()
    _sync_shader()
    if Engine.is_editor_hint():
        # Editor canvases do not provide the same screen copy as game viewports.
        # Use an opaque preview so water stays visible on an empty scene.
        mesh.material=null
        mesh.color=shallow_color
        queue_redraw()

func _draw() -> void:
    if Engine.is_editor_hint() and mesh!=null:
        draw_polyline(mesh.polygon.slice(0,sample_count),surface_color,surface_thickness)

## Resize geometry rather than its Node2D transform; custom basins scale too.
func resize(new_size: Vector2) -> void:
    var bounded:=new_size.max(Vector2.ONE)
    var ratio:=bounded/Vector2(width,depth)
    var points:=bottom_points.duplicate()
    for i in range(points.size()):
        points[i]*=ratio
    apply_shape(bounded,points)

## Atomic shape change, also used by editor undo/redo.
func apply_shape(new_size: Vector2, points: PackedVector2Array) -> void:
    width=maxf(1,new_size.x)
    depth=maxf(1,new_size.y)
    bottom_points=points.duplicate()
    if is_inside_tree():
        initialize()

func _physics_process(delta: float) -> void:
    if auto_simulate and simulation_enabled and (not Engine.is_editor_hint() or preview_animation):
        advance(delta)

## Initialize after configuring a new instance. Reconfiguration resets waves.
func initialize() -> void:
    width=maxf(width,1)
    depth=maxf(depth,1)
    sample_count=clampi(sample_count,3,1025)
    if mesh==null:
        mesh=Polygon2D.new()
        mesh.name="WaterMesh"
        water_material.shader=WATER_SHADER
        mesh.material=water_material
        add_child(mesh)
        _underlay=Node2D.new()
        _underlay.name="Bubbles"
        _underlay.z_index=-1
        _underlay.draw.connect(_draw_bubbles)
        add_child(_underlay)
        _overlay=Node2D.new()
        _overlay.name="Splashes"
        _overlay.z_index=2
        _overlay.draw.connect(_draw_splashes)
        add_child(_overlay)
    _rng.seed=random_seed
    _heights.resize(sample_count)
    _speeds.resize(sample_count)
    _levels.resize(sample_count)
    reset()
    _configuration_hash=_settings_hash()
    _sync_shader()

func _settings_hash() -> int:
    return hash([width,depth,sample_count,bottom_points,shallow_color,deep_color,
        surface_color,tint_strength,surface_thickness,depth_range,caustic_strength,
        refraction_pixels,pattern_offset,light_shafts,random_seed,
        ambient_amplitudes,ambient_frequencies,ambient_speeds,wave_phase_offset])

## Advances using fixed 60 Hz spring steps, independently of caller tick rate.
## Set auto_simulate=false when a scene owns stepping or pausing.
func advance(delta: float) -> void:
    if not simulation_enabled or not is_finite(delta) or delta<0:
        return
    if mesh==null:
        initialize()
    simulation_time+=delta
    _accumulator+=minf(delta,.25)
    while _accumulator+0.0000001>=FIXED_STEP:
        _step_springs()
        _accumulator-=FIXED_STEP
    _rebuild_surface()
    _update_effects(delta)
    _sync_shader()

func _step_springs() -> void:
    for i in range(1,sample_count-1):
        var laplace:=_heights[i-1]+_heights[i+1]-2*_heights[i]
        _speeds[i]+=laplace*propagation-_heights[i]*spring_strength-_speeds[i]*damping
    for i in range(sample_count):
        _heights[i]=clampf(_heights[i]+_speeds[i],-maximum_displacement,maximum_displacement)
    _heights[0]=0
    _heights[sample_count-1]=0
    _speeds[0]=0
    _speeds[sample_count-1]=0

func _rebuild_surface() -> void:
    var points:=PackedVector2Array()
    var data:=PackedByteArray()
    data.resize(sample_count*4)
    for i in range(sample_count):
        var x:=width*float(i)/(sample_count-1)
        var phase_x:=x+wave_phase_offset
        var y:=_heights[i]+sin(phase_x*ambient_frequencies.x+simulation_time*ambient_speeds.x)*ambient_amplitudes.x+sin(phase_x*ambient_frequencies.y+simulation_time*ambient_speeds.y)*ambient_amplitudes.y
        _levels[i]=y
        points.append(Vector2(x,y))
        data.encode_float(i*4,y)
    if bottom_points.is_empty():
        points.append(Vector2(width,depth))
        points.append(Vector2(0,depth))
    else:
        points.append_array(bottom_points)
    mesh.polygon=points
    var image:=Image.create_from_data(sample_count,1,false,Image.FORMAT_RF,data)
    if surface_texture.get_width()!=sample_count:
        surface_texture.set_image(image)
    else:
        surface_texture.update(image)

## Height in water-local coordinates, clamped to the two shore endpoints.
func surface_at(local_x: float) -> float:
    if _levels.is_empty():
        return 0
    var sample_x:=clampf(local_x/width*(sample_count-1),0,sample_count-1)
    var i:=int(sample_x)
    return lerpf(_levels[i],_levels[mini(i+1,sample_count-1)],sample_x-i)

func surface_point(local_x: float) -> Vector2:
    return Vector2(clampf(local_x,0,width),surface_at(local_x))

func contains_point(global_point: Vector2) -> bool:
    return mesh!=null and Geometry2D.is_point_in_polygon(to_local(global_point),mesh.polygon)

## Push the spring surface at a local X. Positive strength pushes down.
func impulse(local_x: float, strength: float) -> void:
    if not is_finite(strength) or local_x<0 or local_x>width:
        return
    if mesh==null:
        initialize()
    var center:=int(local_x/width*(sample_count-1))
    for k in range(-4,5):
        var i:=center+k
        if i>0 and i<sample_count-1:
            _speeds[i]+=strength*exp(-float(k*k)*.22)*.22

## Spring impulse plus splash and ripple. Global position is projected onto
## the surface. Signals let gameplay provide audio without asset dependencies.
func impact(global_point: Vector2, strength: float=6.0) -> bool:
    var local:=to_local(global_point)
    if local.x<0 or local.x>width or not is_finite(strength):
        return false
    strength=clampf(strength,0,40)
    impulse(local.x,strength)
    var point:=surface_point(local.x)
    if effects_enabled:
        for i in range(int(strength*4)):
            emit_spray(point,Vector2(_rng.randf_range(-50,50),_rng.randf_range(-95,-20))*strength*.14,_rng.randf_range(.3,.65),splash_color,_rng.randf_range(1,2))
        _rings.append({"p":point,"life":.6})
    surface_impacted.emit(to_global(point),strength)
    return true

func emit_spray(local_point: Vector2, velocity: Vector2, lifetime: float, color: Color, size: float) -> void:
    if effects_enabled and _particles.size()<particle_limit:
        _particles.append({"p":local_point,"v":velocity,"life":lifetime,"max":maxf(lifetime,.001),"c":color,"size":size})

func emit_bubbles(global_point: Vector2, count: int=1) -> void:
    if not effects_enabled:
        return
    var local:=to_local(global_point)
    for i in range(mini(maxi(count,0),maxi(0,bubble_limit-bubbles.size()))):
        bubbles.append({"p":local+Vector2(_rng.randf_range(-8,8),_rng.randf_range(-6,6)),"v":Vector2(_rng.randf_range(-12,12),_rng.randf_range(-23,-8)),"life":_rng.randf_range(.5,2),"r":_rng.randf_range(.7,2.6),"phase":_rng.randf()*TAU})

func set_underwater_light(global_point: Vector2, enabled: bool=true) -> void:
    _light_global=global_point
    _light_enabled=enabled

## Deterministic initial disturbance for tooling/tests. Copies caller data.
func set_displacements(values: PackedFloat32Array, at_time: float=0.0) -> void:
    if mesh==null:
        initialize()
    if values.size()!=sample_count:
        push_error("CherryWater2D: displacement count must equal sample_count.")
        return
    simulation_time=at_time
    _accumulator=0
    for i in range(sample_count):
        _heights[i]=clampf(values[i],-maximum_displacement,maximum_displacement) if is_finite(values[i]) else 0.0
        _speeds[i]=0
    _rebuild_surface()
    _sync_shader()

func get_displacements() -> PackedFloat32Array:
    return _heights.duplicate()

func reset() -> void:
    simulation_time=0
    _accumulator=0
    _heights.fill(0)
    _speeds.fill(0)
    bubbles.clear()
    _particles.clear()
    _rings.clear()
    if mesh!=null:
        _rebuild_surface()
        _underlay.queue_redraw()
        _overlay.queue_redraw()

func _sync_shader() -> void:
    if mesh==null or not is_inside_tree():
        return
    var forward:=get_global_transform_with_canvas()
    var inverse:=forward.affine_inverse()
    water_material.set_shader_parameter("surface_profile",surface_texture)
    water_material.set_shader_parameter("surface_width",width)
    water_material.set_shader_parameter("clock",simulation_time)
    water_material.set_shader_parameter("screen_to_water_x",Vector3(inverse.x.x,inverse.y.x,inverse.origin.x))
    water_material.set_shader_parameter("screen_to_water_y",Vector3(inverse.x.y,inverse.y.y,inverse.origin.y))
    water_material.set_shader_parameter("water_y_axis_screen",forward.y)
    water_material.set_shader_parameter("light_position",to_local(_light_global))
    water_material.set_shader_parameter("light_strength",1.0 if _light_enabled else 0.0)
    for parameter in ["shallow_color","deep_color","surface_color","tint_strength","surface_thickness","depth_range","caustic_strength","refraction_pixels","pattern_offset"]:
        water_material.set_shader_parameter(parameter,get(parameter))
    var shafts:=PackedFloat32Array()
    shafts.resize(8)
    for i in range(mini(8,light_shafts.size())):
        shafts[i]=light_shafts[i]
    water_material.set_shader_parameter("shaft_positions",shafts)
    water_material.set_shader_parameter("shaft_count",mini(8,light_shafts.size()))

func _update_effects(delta: float) -> void:
    for i in range(_particles.size()-1,-1,-1):
        var p: Dictionary=_particles[i]
        p.life-=delta
        p.v.y+=155*delta
        p.p+=p.v*delta
        if p.life<=0 or p.p.y>surface_at(p.p.x)+22:
            _particles.remove_at(i)
    for i in range(bubbles.size()-1,-1,-1):
        var b: Dictionary=bubbles[i]
        b.life-=delta
        b.p+=(b.v+Vector2(sin(simulation_time*4+b.phase)*4,0))*delta
        if b.life<=0 or not Geometry2D.is_point_in_polygon(b.p,mesh.polygon):
            bubbles.remove_at(i)
    for i in range(_rings.size()-1,-1,-1):
        _rings[i].life-=delta
        if _rings[i].life<=0:
            _rings.remove_at(i)
    _underlay.visible=effects_enabled
    _overlay.visible=effects_enabled
    _underlay.queue_redraw()
    _overlay.queue_redraw()

func _draw_bubbles() -> void:
    if not effects_enabled:
        return
    for b in bubbles:
        var color:=bubble_color
        color.a=minf(b.life,color.a)
        _underlay.draw_arc(b.p.round(),b.r,0,TAU,12,color,1)

func _draw_splashes() -> void:
    if not effects_enabled:
        return
    for p in _particles:
        var color: Color=p.c
        color.a=clampf(p.life/p.max*1.8,0,1)
        _overlay.draw_rect(Rect2(p.p.round(),Vector2.ONE*ceilf(p.size)),color)
    for ring in _rings:
        var radius: float=(.6-ring.life)*42
        var point:=Vector2(ring.p.x,surface_at(ring.p.x))
        _overlay.draw_line(point-Vector2(radius,0),point+Vector2(radius,0),Color(.6,1,1,ring.life),1)
