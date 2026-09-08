@tool
class_name WaterModule
extends PluginModule

## Scene-local 2D water. The GDScript runtime works in both standard and .NET
## projects; no autoload, language switching or project settings are required.
const MODULE_ID := &"2d.water"

func get_module_id() -> StringName:
    return MODULE_ID

func get_runtime_root() -> String:
    return module_root.path_join("gdscript")

var selected: CherryWater2D
var _drag := -1
var _before_size := Vector2.ZERO
var _before_points := PackedVector2Array()

func edit_water(object: Object) -> void:
    _cancel_drag()
    selected=object as CherryWater2D
    plugin.update_overlays()

func on_plugin_exit_tree() -> void:
    _cancel_drag()
    selected=null

func on_plugin_process(_delta: float) -> void:
    if is_instance_valid(selected):
        plugin.update_overlays()

func _valid() -> bool:
    return is_instance_valid(selected) and selected.is_inside_tree()

func canvas_transform() -> Transform2D:
    return EditorInterface.get_editor_viewport_2d().global_canvas_transform*selected.global_transform

func _handles_local() -> PackedVector2Array:
    return PackedVector2Array([Vector2(selected.width,selected.depth*.5),Vector2(selected.width*.5,selected.depth),Vector2(selected.width,selected.depth)])

func draw_handles(overlay: Control) -> void:
    if not _valid():
        return
    var transform:=canvas_transform()
    var corners:=PackedVector2Array([Vector2.ZERO,Vector2(selected.width,0),Vector2(selected.width,selected.depth),Vector2(0,selected.depth),Vector2.ZERO])
    overlay.draw_polyline(transform*corners,Color(.3,.85,1,.8),1)
    for point in _handles_local():
        overlay.draw_rect(Rect2(transform*point-Vector2(5,5),Vector2(10,10)),Color(.3,.9,1))

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
                undo.commit_action(false)
            return true
    if event is InputEventMouseMotion and _drag>=0:
        var motion: InputEventMouseMotion = event as InputEventMouseMotion
        var inverse_transform: Transform2D = canvas_transform().affine_inverse()
        var local_position: Vector2 = inverse_transform * motion.position
        var size:=_before_size
        if _drag!=1:
            size.x=maxf(1,roundf(local_position.x))
        if _drag!=0:
            size.y=maxf(1,roundf(local_position.y))
        var points:=_before_points.duplicate()
        for i in range(points.size()):
            points[i]*=size/_before_size
        selected.apply_shape(size,points)
        plugin.update_overlays()
        return true
    return false

func _cancel_drag() -> void:
    if _drag>=0 and _valid():
        selected.apply_shape(_before_size,_before_points)
    _drag=-1
