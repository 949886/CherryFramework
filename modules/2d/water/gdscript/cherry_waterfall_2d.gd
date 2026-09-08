@tool
class_name CherryWaterfall2D
extends Node2D

## A local +Y stream. Keep its axes aligned with the target water's axes.
## 目标水体的相对节点路径，编辑器改动后会重新解析。
@export var water_path: NodePath
## 瀑布条带宽度，单位为瀑布局部像素。
@export var width := 36.0
## 未连接水体时的显示高度，单位为瀑布局部像素。
@export var fallback_height := 184.0
@export var auto_simulate := true
@export var preview_animation := true
## 条带噪声的相位偏移，用于区分多个瀑布。
@export var phase := 0.0
@export var random_seed := 216
## 两次水面扰动间隔，单位为秒；运行时至少使用 0.01 秒。
@export var impact_interval := .05
## 随机弹簧扰动的绝对值上限，正负方向交替形成持续波纹。
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

## 解析目标水体，建立瀑布条带材质与程序生成的径向光晕，无需外部图片。
## 条带放在父节点绘制内容后方，使水面泡沫显示在落水条带之前。
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

## 游戏中的自动推进入口；外部管理暂停时关闭 auto_simulate 并手动调用 advance。
func _physics_process(delta: float) -> void:
	if auto_simulate and not Engine.is_editor_hint():
		advance(delta)

## 先更新瀑布末端，再按固定时间间隔向水体施加正负随机扰动。
## 冲击和气泡使用独立计时器，避免不同物理帧率改变喷射频率；水花参数使用目标水体局部坐标。
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

## 重置动画时间、喷射计时和计数，同时恢复随机种子，使瀑布可重复播放。
func reset() -> void:
	_time=0
	_accumulator=0
	_bubble_clock=0
	impacts=0
	_rng.seed=random_seed
	_sync()

## 持续刷新几何；编辑器预览只有在目标水体也允许预览时才注入扰动，避免停止的水池累积冲击。
func _process(delta: float) -> void:
	_sync()
	if Engine.is_editor_hint() and preview_animation:
		if not is_instance_valid(water) or (water.preview_animation and water.simulation_enabled):
			advance(delta)

## 将瀑布上端中心投影到水体局部 X，查询动态水面，再转换回瀑布局部位置。
## 条带高度随水面变化；未绑定水体时使用 fallback_height。两者坐标轴应保持对齐。
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

## 绘制落点光晕与分散的像素泡沫。黄金角近似值 2.399 用来打散角度，
## 半径取平方根使点在椭圆区域内更均匀，避免全部拥挤在中心。
func _draw() -> void:
	if _glow==null:
		return
	draw_texture_rect(_glow,Rect2(_tip-Vector2(26,20),Vector2(52,40)),false,Color("8efcff"))
	for i in range(26):
		var angle:=float(i)*2.399+_time*.2
		var radius:=sqrt(fposmod(sin(float(i)*73.13)*4375.5,1))
		var foam:=_tip+Vector2(cos(angle)*radius*width*.42,sin(angle)*radius*5+sin(_time*12+i)*1.5)
		draw_rect(Rect2(foam.round(),Vector2(2,2)),Color("d6ffff") if i%3 else Color("89f5f0"))
