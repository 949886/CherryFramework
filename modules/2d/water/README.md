# Cherry Water 2D

可复用的 Godot 4.7 二维水体，包含弹簧波浪、同步水体轮廓、折射、焦散、光柱、水花、气泡与瀑布。无需 Autoload、角色脚本或外部美术资源；标准版与 .NET 版共用 GDScript 实现。

## 快速使用

在编辑器创建 `CherryWater2D` 节点，设置位置、`width`、`depth` 即可运行。也可以通过代码创建：

```gdscript
var water := CherryWater2D.new()
water.position = Vector2(100,180)
water.width = 320
water.depth = 140
add_child(water)

# 世界坐标查询与交互
if water.contains_point(player.global_position):
    water.emit_bubbles(player.global_position, 8)
water.impact(player.global_position, 10)
water.set_underwater_light(player.global_position, true)
```

模块目录整体可移动，内部资源均使用相对路径。未启用 Cherry 编辑器插件也能直接使用这些全局类；插件启用时注册模块 ID `2d.water`。

## 编辑器工作流

`examples/two_pools.tscn` 已保存 Background、PoolBackdrop、Camera2D、LeftPool、RightPool、Waterfall、UI/Instructions 节点；打开场景即可看到并编辑，示例脚本只处理交互。水池与瀑布列表通过 Inspector 中的节点引用配置，代码直接使用 `CherryWater2D` / `CherryWaterfall2D` 全局类，不通过 `preload` 绑定脚本文件。

选中水体，在 Inspector 的 Shape 中修改 Width、Depth、Sample Count、Bottom Points；颜色和波浪参数分别位于 Appearance、Simulation。编辑器与游戏使用同一水体材质，实时显示折射、焦散、光柱和水面高光。Preview Animation 默认开启，波浪、瀑布、泡沫、水花与气泡自动运动；关闭水体的该选项会冻结水体和关联瀑布，关闭瀑布自身的该选项则仅冻结瀑布。编辑器预览独立于游戏的 Auto Simulate，运行游戏时仍按原有自动或手动推进方式模拟。

启用 Cherry 插件后，选中的水体显示右侧、底部、右下角三个青色手柄，分别调整宽度、深度、宽高。拖拽按局部像素取整，支持旋转和缩放后的节点；Esc 取消拖拽，Ctrl+Z / Ctrl+Shift+Z 撤销和重做。修改保存到场景中。自定义水底会随手柄等比例缩放到新宽高；Inspector 的 Bottom Points 仍可逐点编辑。`resize(Vector2)` 提供相同的几何缩放接口。

当前宿主项目已启用 Cherry。单独复制模块且不启用插件时，Inspector 编辑和预览仍可用，拖拽手柄需要 Cherry 编辑器插件。

## 坐标与接口

- 原点是静止水面的左端，局部 X 沿水面，局部 Y 向水底；水体支持父节点平移、旋转与缩放。
- `surface_at(local_x)` 返回局部高度；`to_global(surface_point(local_x))` 返回世界坐标水面点。
- `contains_point(global_point)` 查询实际水体多边形，不含岸边岩石；它不创建实体碰撞，也不自动改变角色重力。
- `impulse(local_x, strength)` 只扰动波浪，正值向下；`impact(global_point, strength)` 另加水花、波纹并发出 `surface_impacted` 信号，可在游戏端绑定声音。
- `emit_bubbles(global_point, count)`、`set_underwater_light(global_point, enabled)` 接受世界坐标。
- 默认自动模拟。游戏自行管理暂停时设置 `auto_simulate=false`，每帧调用 `advance(delta)`；不要同时自动与手动推进。弹簧以固定 60 Hz 积分，单次最多补算 0.25 秒。
- `reset()` 清空波浪和特效；`set_displacements(values, time)` 可注入确定性波形，数组长度须等于 `sample_count`。

`bottom_points` 可自定义凹形水底：从右岸沿水底走到左岸，不包含动态水面顶点。应保持简单、不自交，岸边低于最大波峰/波谷范围。留空生成矩形。几何与静态外观参数变化会重建实例并重置模拟。

## 瀑布与背景

`CherryWaterfall2D` 通过 `water_path` 或 `water` 连接水体，自动跟随水面并产生扰动、泡沫、水花与气泡。瀑布沿自身 +Y 下落，须与水体坐标轴对齐；同一水体可绑定多个瀑布。`width`、`impact_interval`、`impact_strength` 可配置。

普通背景不需要额外处理。若美术图片已经画有固定蓝色水位，可添加 `CherryWaterBackground2D`，设置 `water_path`、`sprite_path`，再配置最多 8 个水体局部坐标 `correction_regions` 和水下取样行 `source_surface_y`。适配器共享同一浮点水面纹理，将干燥部分替换为 `air_color`，并把水下图片延展到波峰。修正区域必须覆盖完整波动范围，取样行须是实际水下图像。更深的背景保持原样。

适配器支持完整单帧 Sprite2D（含居中、偏移、翻转、变换），不支持 region 或图集帧；一个 Sprite2D 使用一个适配器，它占用该 Sprite 的材质并在移除时恢复原材质。多个池子需要分别提供对应的背景 Sprite。

## 示例与验证

打开 `examples/two_pools.tscn` 运行：两个不同尺寸、位置、颜色与变换的池子。点击屏幕投放浮动物体，落水时产生波浪、水花和气泡；点击已有物体将它弹起。Space 暂停，R 清空物体并重置水体。例子不依赖宿主项目素材或 InputMap。

在项目根目录执行：

```shell
godot --headless --path . --script res://addons/cherry/modules/2d/water/tests/water_test.gd
godot --headless --path . --script res://addons/cherry/modules/2d/water/tests/scene_test.gd
```

覆盖 9 项多实例隔离、坐标变换、波浪传播、60/120 Hz 一致性、查询与网格一致性及重置检查。移除 `--headless` 使用真实渲染器后额外验证 GPU 高度、旋转缩放水体、相机缩放与 800×480 分辨率，共 11 项。原水洞另有真实渲染器像素回归 `tests/water_surface_render.gd`。

`scene_test.gd` 另验证 8 项场景节点、导出引用、暂停、尺寸调整和序列化。宿主的 `tests/water_editor_probe` 是可选编辑器验证插件：仅临时启用该插件并以 `--editor -- --water-editor-test` 启动时运行 11 项材质预览、动画与暂停、拖拽、撤销/重做与序列化检查，完成后退出测试编辑器；日常使用无需启用。

折射使用 Godot 屏幕纹理，水体应绘制在需要折射的场景之后。互不重叠的水体可共享屏幕拷贝；叠放水体需要自行安排 BackBufferCopy。水花与气泡使用水体局部重力方向。本模块不包含宿主的角色控制、音效或全屏 bloom。

演示物体使用独立的 `examples/floating_object.tscn`，由示例根节点的 Object Scene 导出属性引用。可编辑外观、碰撞、质量、重力、浮力与水阻参数；Objects 节点收纳运行时实例，默认最多 24 个，60 秒后自动回收。浮力属于演示脚本，不耦合到水体核心。运行 `tests/float_test.gd` 可验证下落、入水、漂浮、弹起、暂停及清空。
