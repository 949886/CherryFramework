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
## 静止水面长度，单位为水体局部像素。
@export_range(1,8192,1) var width := 256.0
## 默认矩形水底深度；自定义水底存在时，也作为 resize() 的纵向缩放基准。
@export_range(1,8192,1) var depth := 120.0
## 水面弹簧样本数；越多轮廓越细，但 CPU 积分、网格与纹理更新开销也越高。
@export_range(3,1025,1) var sample_count := 129
## Right shore -> bottom -> left shore, in local coordinates; omit surface.
## Empty uses a rectangular basin. Do not cross or intersect the moving surface.
@export var bottom_points := PackedVector2Array()
@export_group("Simulation")
## 游戏运行时自动推进；宿主手动调用 advance() 时关闭。
@export var auto_simulate := true
## 模拟总开关；关闭后手动 advance() 也不推进。
@export var simulation_enabled := true
## 在编辑器中播放波浪预览，不改变运行时自动推进设置。
@export var preview_animation := true
## 每个固定步的邻点耦合系数，控制扰动向左右传播。
@export_range(0,.4,.005) var propagation := .20
## 每个固定步回到静止位置的回复系数。
@export_range(0,.2,.005) var spring_strength := .025
## 每个固定步的速度衰减系数，越大波浪越快消失。
@export_range(0,.5,.005) var damping := .065
## 限制弹簧位移绝对值；最终表面还包含环境波，因此可超过此高度。
@export_range(0,128,.5) var maximum_displacement := 12.0
## 两层环境正弦波的振幅，单位为局部像素。
@export var ambient_amplitudes := Vector2(2.2,.9)
## 两层环境波的空间角频率，单位为弧度/局部像素。
@export var ambient_frequencies := Vector2(.055,.14)
## 两层环境波的时间角速度，单位为弧度/秒，符号影响传播方向。
@export var ambient_speeds := Vector2(2.0,-1.7)
## 只偏移环境波的横向相位，便于复现已有场景的波形。
@export var wave_phase_offset := 0.0
## 本水体特效的独立随机种子，多实例互不消耗对方随机序列。
@export var random_seed := 198527
@export_group("Appearance")
@export var shallow_color := Color(.018,.25,.70)
@export var deep_color := Color(.006,.014,.25)
@export var surface_color := Color(.38,1,.90)
## 在折射背景上叠加水色的强度，不等同于透明度。
@export_range(0,1,.01) var tint_strength := .16
## 水面高亮带在局部 Y 方向的厚度。
@export_range(.1,16,.1) var surface_thickness := 1.8
## 浅色到深色及背景衰减的过渡深度，单位为局部像素。
@export_range(1,2048,1) var depth_range := 170.0
@export_range(0,4,.1) var caustic_strength := 1.0
## 屏幕 X/Y 方向折射偏移的最大幅度，单位为渲染视口像素。
@export var refraction_pixels := Vector2(.768,.432)
## 焦散和光束图案的局部坐标偏移，不改变水面几何。
@export var pattern_offset := Vector2.ZERO
## 最多 8 个光柱的局部 X 坐标，着色器中向深处倾斜并衰减。
@export var light_shafts := PackedFloat32Array()
@export_group("Effects")
@export var effects_enabled := true
@export var splash_color := Color("b6ffff")
@export var bubble_color := Color(.48,.86,1,.65)
## 水花数量硬上限，达到后忽略新增粒子。
@export_range(0,4000,1) var particle_limit := 1000
## 气泡数量硬上限，避免持续入水导致实例内存增长。
@export_range(0,2000,1) var bubble_limit := 400

var simulation_time := 0.0
var surface_texture := ImageTexture.new()
var water_material := ShaderMaterial.new()
var mesh: Polygon2D
var bubbles: Array[Dictionary] = []
# 弹簧相对静止水面的位移；_speeds 为每个固定积分步的速度状态。
var _heights := PackedFloat32Array()
var _speeds := PackedFloat32Array()
# 最终绝对局部高度（弹簧 + 环境波），CPU 查询与 GPU 顶边共同使用。
var _levels := PackedFloat32Array()
var _particles: Array[Dictionary] = []
var _rings: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _underlay: Node2D
var _overlay: Node2D
# 尚未消耗的秒数；只用于弹簧固定步积分，不能替代 simulation_time。
var _accumulator := 0.0
var _configuration_hash := 0
var _light_global := Vector2.ZERO
var _light_enabled := false

## 节点入树后建立本实例独有的网格、材质和高度纹理，避免多水池共享模拟状态。
func _ready() -> void:
    initialize()

## 监听 Inspector 参数变化并重建几何。编辑器在此推进预览；游戏运行时只同步渲染参数，
## 实际模拟由物理帧或外部 advance() 驱动，避免一帧计算两次。
func _process(delta: float) -> void:
    if _settings_hash()!=_configuration_hash:
        initialize()
    if Engine.is_editor_hint() and preview_animation and simulation_enabled:
        advance(delta)
    else:
        _sync_shader()

## Resize geometry rather than its Node2D transform; custom basins scale too.
## new_size 为水体局部坐标下的宽、深，单位为局部像素。
## 按新旧尺寸比例缩放自定义水底，不修改 Node2D.scale；调用会重置波浪。
func resize(new_size: Vector2) -> void:
    var bounded:=new_size.max(Vector2.ONE)
    var ratio:=bounded/Vector2(width,depth)
    var points:=bottom_points.duplicate()
    for i in range(points.size()):
        points[i]*=ratio
    apply_shape(bounded,points)

## Atomic shape change, also used by editor undo/redo.
## 一次性应用尺寸与水底点数组，供拖拽预览及撤销/重做共用。
## 复制传入数组，防止后续修改污染编辑器保存的历史快照。
func apply_shape(new_size: Vector2, points: PackedVector2Array) -> void:
    width=maxf(1,new_size.x)
    depth=maxf(1,new_size.y)
    bottom_points=points.duplicate()
    if is_inside_tree():
        initialize()

## 仅在游戏运行且启用自动模拟时推进；宿主手动调用 advance() 时应关闭 auto_simulate。
func _physics_process(delta: float) -> void:
    if not Engine.is_editor_hint() and auto_simulate and simulation_enabled:
        advance(delta)

## Initialize after configuring a new instance. Reconfiguration resets waves.
## 校验尺寸与采样数，首次创建渲染子节点，之后复用节点并重新初始化数组。
## 水体和气泡、水花使用相对 Z 层级：气泡在水体后方，水花在水体前方。
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

## 将影响几何及外观的参数组成指纹；Inspector 改动这些值会触发重建与状态重置。
func _settings_hash() -> int:
    return hash([width,depth,sample_count,bottom_points,shallow_color,deep_color,
        surface_color,tint_strength,surface_thickness,depth_range,caustic_strength,
        refraction_pixels,pattern_offset,light_shafts,random_seed,
        ambient_amplitudes,ambient_frequencies,ambient_speeds,wave_phase_offset])

## Advances using fixed 60 Hz spring steps, independently of caller tick rate.
## Set auto_simulate=false when a scene owns stepping or pausing.
## delta 单位为秒。累计时间达到 1/60 秒才积分弹簧，保证 60/120 Hz 调用结果一致。
## 弹簧单次最多补算 0.25 秒，避免卡顿后无界追帧；动画时钟及特效仍使用原始 delta。
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

## 离散弹簧链：邻点高度差推动波浪传播，回复力拉向静止水位，阻尼消耗能量。
## 先算所有速度再更新位移，避免从左向右更新导致方向偏差。两端固定的是弹簧位移，
## 最终表面仍会叠加环境正弦波，因此端点不保证绝对高度为零。
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

## 唯一的水面数据生成入口：弹簧位移与两层环境波相加得到局部高度。
## 同一份高度同时写入多边形顶边、CPU 查询数组和 GPU 单通道 32 位浮点纹理，
## 保证水面曲线、蓝色水体及背景遮罩一致，避免波峰空隙和波谷溢色。
func _rebuild_surface() -> void:
    var points:=PackedVector2Array()
    var data:=PackedByteArray()
    # 每个 RF 纹素占 4 字节；用浮点保存负高度与小数，避免 8 位归一化量化误差。
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
    # 纹理仅一行；尺寸不变时 update() 复用 GPU 资源，尺寸改变才重新上传布局。
    var image:=Image.create_from_data(sample_count,1,false,Image.FORMAT_RF,data)
    if surface_texture.get_width()!=sample_count:
        surface_texture.set_image(image)
    else:
        surface_texture.update(image)

## Height in water-local coordinates, clamped to the two shore endpoints.
## 将局部横坐标映射到相邻采样点，线性插值得到局部 Y；超出范围时夹到岸端。
## 此插值必须与 surface.gdshaderinc 的纹理采样规则一致。
func surface_at(local_x: float) -> float:
    if _levels.is_empty():
        return 0
    var sample_x:=clampf(local_x/width*(sample_count-1),0,sample_count-1)
    var i:=int(sample_x)
    return lerpf(_levels[i],_levels[mini(i+1,sample_count-1)],sample_x-i)

## 返回水体局部坐标下的水面点；需要世界坐标时使用 to_global(surface_point(x))。
func surface_point(local_x: float) -> Vector2:
    return Vector2(clampf(local_x,0,width),surface_at(local_x))

## 输入世界坐标，转换到水体局部坐标后查询完整水体多边形。
## 支持凹形水底与节点变换；这是几何查询，不会创建物理碰撞体或自动施加浮力。
func contains_point(global_point: Vector2) -> bool:
    return mesh!=null and Geometry2D.is_point_in_polygon(to_local(global_point),mesh.polygon)

## Push the spring surface at a local X. Positive strength pushes down.
## 输入局部 X 和弹簧速度扰动强度，正数向下、负数向上。
## 向中心两侧各 4 个样本施加高斯衰减扰动，避免单点尖峰；不生成水花或声音。
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
## 输入世界坐标，将该点沿局部 Y 投影到水面，再施加向下扰动、水花与波纹。
## 只验证横坐标范围，不要求输入点已经浸水；有效时发出世界坐标信号并返回 true。
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

## 生成局部坐标水花；velocity 单位为局部像素/秒，lifetime 单位为秒。
## 粒子字典 p/v/life/max/c/size 分别记录位置、速度、剩余寿命、总寿命、颜色和边长。
func emit_spray(local_point: Vector2, velocity: Vector2, lifetime: float, color: Color, size: float) -> void:
    if effects_enabled and _particles.size()<particle_limit:
        _particles.append({"p":local_point,"v":velocity,"life":lifetime,"max":maxf(lifetime,.001),"c":color,"size":size})

## 输入世界坐标，在附近散布气泡；受 bubble_limit 限制，避免持续喷射无限分配。
## 气泡后续按水体局部方向上浮，离开真实水体轮廓后删除。
func emit_bubbles(global_point: Vector2, count: int=1) -> void:
    if not effects_enabled:
        return
    var local:=to_local(global_point)
    for i in range(mini(maxi(count,0),maxi(0,bubble_limit-bubbles.size()))):
        bubbles.append({"p":local+Vector2(_rng.randf_range(-8,8),_rng.randf_range(-6,6)),"v":Vector2(_rng.randf_range(-12,12),_rng.randf_range(-23,-8)),"life":_rng.randf_range(.5,2),"r":_rng.randf_range(.7,2.6),"phase":_rng.randf()*TAU})

## 保存世界坐标光源；同步着色器时再转为局部坐标，水体变换后仍定位正确。
func set_underwater_light(global_point: Vector2, enabled: bool=true) -> void:
    _light_global=global_point
    _light_enabled=enabled

## Deterministic initial disturbance for tooling/tests. Copies caller data.
## 为回放或测试注入确定性弹簧位移，长度必须等于 sample_count。
## 清空速度与积分余量；最终水面仍叠加 at_time 时刻的环境波。
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

## 返回弹簧位移的副本，不含环境波；调用者修改返回值不会改写正在运行的模拟。
func get_displacements() -> PackedFloat32Array:
    return _heights.duplicate()

## 清空弹簧和瞬态特效并将时间归零。尺寸、颜色与其他配置保留，环境波重新从零时刻开始。
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

## 把 CPU 参数传给本实例材质。屏幕像素到水体局部坐标的逆矩阵按两行 vec3 上传，
## 供折射采样越过水面时纠正取样位置。编辑器使用专用画布变换，包含编辑器平移与缩放。
func _sync_shader() -> void:
    if mesh==null or not is_inside_tree():
        return
    var forward:=get_global_transform_with_canvas()
    if Engine.is_editor_hint():
        forward=EditorInterface.get_editor_viewport_2d().global_canvas_transform*global_transform
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
    # 着色器数组长度固定为 8，未使用项填零，并用 shaft_count 限制有效项。
    var shafts:=PackedFloat32Array()
    shafts.resize(8)
    for i in range(mini(8,light_shafts.size())):
        shafts[i]=light_shafts[i]
    water_material.set_shader_parameter("shaft_positions",shafts)
    water_material.set_shader_parameter("shaft_count",mini(8,light_shafts.size()))

## 反向遍历并移除过期元素，避免删除后跳过下一个元素。
## 水花受局部重力下落；气泡有横向摆动；波纹只更新剩余寿命。
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

## 在水体后方绘制环形气泡，经过水体折射与染色；剩余寿命控制消隐。
func _draw_bubbles() -> void:
    if not effects_enabled:
        return
    for b in bubbles:
        var color:=bubble_color
        color.a=minf(b.life,color.a)
        _underlay.draw_arc(b.p.round(),b.r,0,TAU,12,color,1)

## 水花位置取整、边长向上取整以保持像素风；波纹绘制时重新查询水面，随波浪移动。
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
