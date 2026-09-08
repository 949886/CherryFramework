class_name CherryWaterDemoFloat
extends RigidBody2D

## Demo-specific buoyancy; the water module remains independent of rigid bodies.
## 生成几何的尺度，单位为局部像素；圆形与正多边形使用外接圆半径。
@export var radius := 9.0
## 完全浸水时浮力相对重力的倍数；默认 2 使物体约半浸水时平衡。
@export var buoyancy := 2.0
## 浸水后的线性阻力系数，按浸水比例衰减平移速度。
@export var water_drag := 3.0
## 0 随机，1～7 分别对应圆、三角、正方、长方、菱形、五边和六边。
@export_enum("Random", "Circle", "Triangle", "Square", "Rectangle", "Diamond", "Pentagon", "Hexagon") var shape_kind := 0
var chosen_shape := 0
var _outline := PackedVector2Array()
var _buoyancy_samples := PackedVector2Array()
var pools: Array[CherryWater2D] = []
var water_entries := 0
var _wet := false
var _age := 0.0
var _ripple_clock := 0.0

## 每个实例独立抽取形状；shape_kind 为 0 表示随机，其余值指定固定形状。
func _ready() -> void:
    configure_shape(randi_range(1,7) if shape_kind==0 else shape_kind)

## Visuals, collision and buoyancy all derive from the same convex outline.
## 根据同一个凸多边形轮廓生成外观、碰撞与浮力采样。
## 圆形用 24 边形近似，正方形与菱形通过初始相位区分；每实例新建碰撞资源以免互相影响。
func configure_shape(kind: int) -> void:
    chosen_shape=clampi(kind,1,7)
    _outline.clear()
    if chosen_shape==4:
        _outline=PackedVector2Array([Vector2(-1,-.55),Vector2(1,-.55),Vector2(1,.55),Vector2(-1,.55)])
        for i in range(_outline.size()):
            _outline[i]*=radius
    else:
        # Circle 实际使用 24 个边；这样碰撞与绘制共享同一组顶点，不存在圆形碰撞包住三角形的问题。
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
    # 用 9×9 网格的格心作面积采样，只保留形状内部点；每个点近似代表相同面积。
    _buoyancy_samples.clear()
    for y in range(9):
        for x in range(9):
            var sample_point:=Vector2((x+.5)/9.0*2-1,(y+.5)/9.0*2-1)*radius
            if Geometry2D.is_point_in_polygon(sample_point,_outline):
                _buoyancy_samples.append(sample_point)

## 把点击世界坐标转到物体局部空间，再测试实际轮廓；旋转后仍可准确点击，不使用包围圆。
func contains_global_point(point: Vector2) -> bool:
    return Geometry2D.is_point_in_polygon(to_local(point),_outline)

## 刚体自身负责重力与碰撞，这里只添加近似二维浮力、水阻和与水体的特效交互。
## 采样点均匀分布于形状内部，浸水样本比例近似浸水面积比例；不求解真实流体压力。
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
    # 每帧把局部采样点转到世界坐标，物体旋转后浸水比例也随之改变。
    for offset in _buoyancy_samples:
        for pool in pools:
            if is_instance_valid(pool) and pool.contains_point(to_global(offset)):
                wet_samples+=1
                active_water=pool
                break
    # 多个水池重叠时每个点只计一次；特效发送给最后命中的水体，适用于演示中的分离水池。
    var fraction:=float(wet_samples)/maxi(1,_buoyancy_samples.size())
    if active_water!=null:
        var gravity: float=ProjectSettings.get_setting("physics/2d/default_gravity",980.0)
        var direction: Vector2=ProjectSettings.get_setting("physics/2d/default_gravity_vector",Vector2.DOWN)
        # 浮力 = -重力方向 × g × gravity_scale × 质量 × 浮力倍数 × 浸水比例。
        # 水阻 = -速度 × 阻力系数 × 质量 × 浸水比例。这里施加的是力，不乘 delta，刚体引擎会积分。
        apply_central_force(-direction*gravity*gravity_scale*mass*buoyancy*fraction-linear_velocity*water_drag*mass*fraction)
        # 旋转阻尼单独抑制水中的持续翻转；浮力施加在中心，因此这是简化模型，不模拟偏心浮力力矩。
        apply_torque(-angular_velocity*mass*20*fraction)
        # 仅在从干燥变为浸水的边沿触发入水水花，避免每帧重复喷射。
        if not _wet:
            water_entries+=1
            active_water.impact(global_position,clampf(linear_velocity.length()*.035,2,14))
            active_water.emit_bubbles(global_position,12)
        _ripple_clock+=delta
        # 在水面附近运动时低频注入小波纹；完全浸水时不持续扰动表面。
        if _ripple_clock>.12 and fraction<1 and linear_velocity.length()>8:
            active_water.impulse(active_water.to_local(global_position).x,clampf(linear_velocity.y*.015,-1.5,1.5))
            _ripple_clock=0
    _wet=wet_samples>0

## 施加瞬时冲量向右上弹起并增加旋转；乘以质量使不同质量物体获得相近的线速度变化。
func kick() -> void:
    if not freeze:
        apply_central_impulse(Vector2(45,-150)*mass)
        apply_torque_impulse(20)
