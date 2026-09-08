@tool
class_name WaterModule
extends PluginModule

## Scene-local 2D water. The GDScript runtime works in both standard and .NET
## projects; no autoload, language switching or project settings are required.
const MODULE_ID := &"2d.water"

## 返回 Cherry 注册表中的稳定模块标识，不依赖插件安装目录。
func get_module_id() -> StringName:
    return MODULE_ID

## 从 PluginModule 注入的模块目录推导运行时目录，支持整个插件迁移。
func get_runtime_root() -> String:
    return module_root.path_join("gdscript")

var selected: CherryWater2D
# -1 空闲；0 只改宽度；1 只改深度；2 同时改宽深。
var _drag := -1
var _before_size := Vector2.ZERO
var _before_points := PackedVector2Array()

## 切换选中对象前取消未完成拖拽，防止将旧节点的尺寸快照应用到新节点。
func edit_water(object: Object) -> void:
    _cancel_drag()
    selected=object as CherryWater2D
    plugin.update_overlays()

## 插件卸载时回滚未完成拖拽并释放选择引用。
func on_plugin_exit_tree() -> void:
    _cancel_drag()
    selected=null

## 请求编辑器覆盖层重绘，让手柄跟随视图缩放和节点变换。
func on_plugin_process(_delta: float) -> void:
    if is_instance_valid(selected):
        plugin.update_overlays()

## 节点可能在编辑器中被删除或移出场景树；访问前同时检查实例有效性与入树状态。
func _valid() -> bool:
    return is_instance_valid(selected) and selected.is_inside_tree()

## 编辑器覆盖层坐标 = 编辑器画布变换 × 节点世界变换。
## 不能直接套用游戏视口的转换，否则编辑器缩放后手柄会偏离水体。
func canvas_transform() -> Transform2D:
    return EditorInterface.get_editor_viewport_2d().global_canvas_transform*selected.global_transform

## 依次返回宽度、深度、宽高手柄位置；下标 0/1/2 同时作为拖拽状态标识。
func _handles_local() -> PackedVector2Array:
    return PackedVector2Array([Vector2(selected.width,selected.depth*.5),Vector2(selected.width*.5,selected.depth),Vector2(selected.width,selected.depth)])

## 先将局部边框转到覆盖层坐标，再以固定屏幕尺寸绘制手柄，缩放后仍便于点击。
func draw_handles(overlay: Control) -> void:
    if not _valid():
        return
    var transform:=canvas_transform()
    var corners:=PackedVector2Array([Vector2.ZERO,Vector2(selected.width,0),Vector2(selected.width,selected.depth),Vector2(0,selected.depth),Vector2.ZERO])
    overlay.draw_polyline(transform*corners,Color(.3,.85,1,.8),1)
    for point in _handles_local():
        overlay.draw_rect(Rect2(transform*point-Vector2(5,5),Vector2(10,10)),Color(.3,.9,1))

## 处理按下、拖动、松开和 Esc 取消；返回 true 表示消费事件，阻止编辑器同时移动节点。
## 拖动期间实时预览，松开时只提交一条撤销记录，不把每次鼠标移动写入历史。
func handle_input(event: InputEvent) -> bool:
    if not _valid():
        return false
    if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE and _drag>=0:
        _cancel_drag()
        return true
    if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
        if event.pressed:
            var transform:=canvas_transform()
            var handles:=_handles_local()
            # 逆序检测使右下角手柄在小尺寸、热点重叠时优先命中。命中半径使用屏幕像素。
            for i in range(handles.size()-1,-1,-1):
                if event.position.distance_to(transform*handles[i])<=9:
                    _drag=i
                    _before_size=Vector2(selected.width,selected.depth)
                    _before_points=selected.bottom_points.duplicate()
                    return true
        elif _drag>=0:
            _drag=-1
            var after:=Vector2(selected.width,selected.depth)
            if after!=_before_size:
                var undo:=plugin.get_undo_redo()
                undo.create_action("Resize Water 2D",UndoRedo.MERGE_DISABLE,selected)
                undo.add_do_method(selected,"apply_shape",after,selected.bottom_points.duplicate())
                undo.add_undo_method(selected,"apply_shape",_before_size,_before_points)
                # 拖动时已应用最终几何，因此提交时不再次执行 do；撤销仍恢复完整旧快照。
                undo.commit_action(false)
            return true
    if event is InputEventMouseMotion and _drag>=0:
        # 显式声明事件、变换和位置类型，避免 InputEvent 属性参与表达式时 GDScript 推断失败。
        var motion: InputEventMouseMotion = event as InputEventMouseMotion
        var inverse_transform: Transform2D = canvas_transform().affine_inverse()
        var local_position: Vector2 = inverse_transform * motion.position
        var size:=_before_size
        if _drag!=1:
            size.x=maxf(1,roundf(local_position.x))
        if _drag!=0:
            size.y=maxf(1,roundf(local_position.y))
        # 始终从拖动起点的原始水底缩放，避免连续鼠标事件反复缩放产生累计误差。
        var points:=_before_points.duplicate()
        for i in range(points.size()):
            points[i]*=size/_before_size
        selected.apply_shape(size,points)
        plugin.update_overlays()
        return true
    return false

## 恢复拖拽开始时的尺寸和水底快照，不产生撤销动作；-1 表示当前未拖拽。
func _cancel_drag() -> void:
    if _drag>=0 and _valid():
        selected.apply_shape(_before_size,_before_points)
    _drag=-1
