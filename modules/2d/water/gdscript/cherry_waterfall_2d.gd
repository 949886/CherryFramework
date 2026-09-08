@tool
class_name CherryWaterfall2D
extends Node2D

## A local +Y stream. Keep its axes aligned with the target water's axes.
@export var water_path: NodePath
@export var width := 36.0
@export var fallback_height := 184.0
@export var auto_simulate := true
@export var preview_animation := true
@export var phase := 0.0
@export var random_seed := 216
@export var impact_interval := .05
@export var impact_strength := 1.8
var water: CherryWater2D
var impacts := 0
var _time := 0.0
var _accumulator := 0.0
var _bubble_clock := 0.0
var _rng := RandomNumberGenerator.new()
var _stream: ColorRect
var _material := ShaderMaterial.new()
var _tip := Vector2.ZERO
var _glow: GradientTexture2D

func _ready() -> void:
	if water==null and not water_path.is_empty():
		water=get_node_or_null(water_path) as CherryWater2D
	_rng.seed=random_seed
	_stream=ColorRect.new()
	_stream.show_behind_parent=true
	_stream.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_material.shader=preload("../shaders/fall.gdshader")
	_stream.material=_material
	add_child(_stream)
	var gradient:=Gradient.new()
	gradient.offsets=PackedFloat32Array([0,.35,1])
	gradient.colors=PackedColorArray([Color(1,1,1,.38),Color(1,1,1,.12),Color(1,1,1,0)])
	_glow=GradientTexture2D.new()
	_glow.gradient=gradient
	_glow.fill=GradientTexture2D.FILL_RADIAL
	_glow.fill_from=Vector2(.5,.5)
	_glow.fill_to=Vector2(1,.5)
	_glow.width=64
	_glow.height=64
	_sync()

func _physics_process(delta: float) -> void:
	if auto_simulate and not Engine.is_editor_hint():
		advance(delta)

func advance(delta: float) -> void:
	if not is_finite(delta) or delta<0:
		return
	_time+=delta
	_sync()
	if not is_instance_valid(water):
		return
	_accumulator+=minf(delta,.25)
	_bubble_clock+=delta
	var local:=water.to_local(to_global(_tip))
	while _accumulator>=maxf(.01,impact_interval):
		_accumulator-=maxf(.01,impact_interval)
		impacts+=1
		water.impulse(local.x,_rng.randf_range(-impact_strength,impact_strength))
		for i in range(10):
			water.emit_spray(local+Vector2(_rng.randf_range(-width*.36,width*.36),4),Vector2(_rng.randf_range(-32,32),_rng.randf_range(-82,-12)),_rng.randf_range(.22,.48),Color("d4ffff") if i%3 else Color("63e8ed"),_rng.randf_range(1,4))
	if _bubble_clock>=11.0/60:
		_bubble_clock=fmod(_bubble_clock,11.0/60)
		water.emit_bubbles(water.to_global(local+Vector2(0,7)),1)

func reset() -> void:
	_time=0
	_accumulator=0
	_bubble_clock=0
	impacts=0
	_rng.seed=random_seed
	_sync()

func _process(delta: float) -> void:
	_sync()
	if Engine.is_editor_hint() and preview_animation:
		if not is_instance_valid(water) or (water.preview_animation and water.simulation_enabled):
			advance(delta)

func _sync() -> void:
	if _stream==null:
		return
	if Engine.is_editor_hint():
		water=get_node_or_null(water_path) as CherryWater2D if not water_path.is_empty() else null
	_tip=Vector2(width*.5,fallback_height)
	if is_instance_valid(water):
		var x:=water.to_local(to_global(Vector2(width*.5,0))).x
		_tip=to_local(water.to_global(water.surface_point(x)))
	_stream.size=Vector2(maxf(1,width),maxf(1,_tip.y+1))
	_material.set_shader_parameter("pixel_size",_stream.size)
	_material.set_shader_parameter("clock",_time)
	_material.set_shader_parameter("phase",phase)
	queue_redraw()

func _draw() -> void:
	if _glow==null:
		return
	draw_texture_rect(_glow,Rect2(_tip-Vector2(26,20),Vector2(52,40)),false,Color("8efcff"))
	for i in range(26):
		var angle:=float(i)*2.399+_time*.2
		var radius:=sqrt(fposmod(sin(float(i)*73.13)*4375.5,1))
		var foam:=_tip+Vector2(cos(angle)*radius*width*.42,sin(angle)*radius*5+sin(_time*12+i)*1.5)
		draw_rect(Rect2(foam.round(),Vector2(2,2)),Color("d6ffff") if i%3 else Color("89f5f0"))
