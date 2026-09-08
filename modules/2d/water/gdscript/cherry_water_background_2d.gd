@tool
class_name CherryWaterBackground2D
extends Node

## Optional adapter for artwork containing a baked, fixed waterline.
## Regions and source_surface_y use the linked water's local coordinates.
## 目标水体的相对场景路径；也可以在入树前直接赋值 water。
@export var water_path: NodePath
## 需要修正固定水位的完整 Sprite2D；材质由适配器接管。
@export var sprite_path: NodePath
## 最多 8 个水体局部坐标矩形，应覆盖完整波动范围；区域外保留原图。
@export var correction_regions: Array[Rect2] = []
## 原图中已浸水的采样行，使用水体局部 Y，须位于修正区底部之前。
@export var source_surface_y := 7.5
## 退水后暴露区域的填充色，应与原图水面上方背景相匹配。
@export var air_color := Color(0,.004,.008,1)
var water: CherryWater2D
var sprite: Sprite2D
var _material := ShaderMaterial.new()
var _previous: Material

## 优先使用代码指定的节点引用，否则解析场景中配置的 NodePath。
## 只适配完整单帧 Sprite2D；保存原材质，并让背景与水体共享高度纹理。
func _ready() -> void:
    if water==null:
        water=get_node_or_null(water_path) as CherryWater2D
    if sprite==null:
        sprite=get_node_or_null(sprite_path) as Sprite2D
    if water==null or sprite==null or sprite.texture==null:
        push_warning("CherryWaterBackground2D requires a water body and textured Sprite2D.")
        return
    if sprite.region_enabled or sprite.hframes!=1 or sprite.vframes!=1:
        push_warning("CherryWaterBackground2D requires an unframed, full-texture Sprite2D.")
        return
    _previous=sprite.material
    _material.shader=preload("../shaders/background.gdshader")
    sprite.material=_material
    _process(0)

## 仅当 Sprite 仍在使用本适配器材质时恢复旧材质，避免覆盖其他系统后来设置的材质。
func _exit_tree() -> void:
    if is_instance_valid(sprite) and sprite.material==_material:
        sprite.material=_previous

## 依次组合“纹理 UV → Sprite 局部 → 世界 → 水体局部”变换。
## 反变换用于把修正后的水下取样点送回纹理 UV；包含居中、offset、翻转和节点变换。
func _process(_delta: float) -> void:
    if not is_instance_valid(water) or not is_instance_valid(sprite) or sprite.material!=_material:
        return
    var size:=sprite.texture.get_size()
    var origin:=sprite.offset-size*.5 if sprite.centered else sprite.offset
    var axes:=size
    if sprite.flip_h:
        origin.x+=size.x
        axes.x=-axes.x
    if sprite.flip_v:
        origin.y+=size.y
        axes.y=-axes.y
    # 矩阵从右向左作用：UV 缩放/偏移 → Sprite 世界变换 → 水体逆世界变换。
    var mapping:=water.global_transform.affine_inverse()*sprite.global_transform*Transform2D(Vector2(axes.x,0),Vector2(0,axes.y),origin)
    var inverse:=mapping.affine_inverse()
    _material.set_shader_parameter("uv_to_water_x",Vector3(mapping.x.x,mapping.y.x,mapping.origin.x))
    _material.set_shader_parameter("uv_to_water_y",Vector3(mapping.x.y,mapping.y.y,mapping.origin.y))
    _material.set_shader_parameter("water_to_uv_x",Vector3(inverse.x.x,inverse.y.x,inverse.origin.x))
    _material.set_shader_parameter("water_to_uv_y",Vector3(inverse.x.y,inverse.y.y,inverse.origin.y))
    _material.set_shader_parameter("surface_profile",water.surface_texture)
    _material.set_shader_parameter("surface_width",water.width)
    _material.set_shader_parameter("source_surface_y",source_surface_y)
    _material.set_shader_parameter("air_color",air_color)
    # 将 Rect2 转成 (左, 上, 右, 下)，并补齐着色器固定长度数组；只处理前 8 个区域。
    var regions: Array[Vector4]=[]
    for i in range(8):
        var r:=correction_regions[i] if i<correction_regions.size() else Rect2()
        regions.append(Vector4(r.position.x,r.position.y,r.end.x,r.end.y))
    _material.set_shader_parameter("regions",regions)
    _material.set_shader_parameter("region_count",mini(8,correction_regions.size()))
