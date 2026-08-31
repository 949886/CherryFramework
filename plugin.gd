@tool
extends EditorPlugin

var _plugin_root := ""
var _modules: Array[PluginModule] = []
var _modules_by_id: Dictionary = {}

func _enter_tree() -> void:
    _plugin_root = (get_script() as Script).resource_path.get_base_dir()
    _register_modules()
    for module: PluginModule in _modules:
        module.on_plugin_enter_tree()
    set_process(true)
    set_physics_process(true)

func _ready() -> void:
    for module: PluginModule in _modules:
        module.on_plugin_ready()

func _process(delta: float) -> void:
    for module: PluginModule in _modules:
        module.on_plugin_process(delta)

func _physics_process(delta: float) -> void:
    for module: PluginModule in _modules:
        module.on_plugin_physics_process(delta)

func _exit_tree() -> void:
    for index: int in range(_modules.size() - 1, -1, -1):
        _modules[index].on_plugin_exit_tree()
    _modules.clear()
    _modules_by_id.clear()

func _register_modules() -> void:
    _register_module(NavigationModule.new())
    _register_module(JoystickModule.new())

func _register_module(module: PluginModule) -> void:
    module._attach(self, _plugin_root)
    var module_id := module.get_module_id()
    if module_id == &"":
        push_error("Cherry: module id cannot be empty.")
        return
    if _modules_by_id.has(module_id):
        push_error("Cherry: duplicate module id '%s'." % String(module_id))
        return
    _modules.append(module)
    _modules_by_id[module_id] = module
    module.on_plugin_registered()

## Returns the registered module with [param module_id], or [code]null[/code] if
## Cherry has no module with that id.
func get_module(module_id: StringName) -> PluginModule:
    return _modules_by_id.get(module_id) as PluginModule

## Returns [code]true[/code] when a module with [param module_id] is registered.
func has_module(module_id: StringName) -> bool:
    return _modules_by_id.has(module_id)

## Returns a copy of the currently registered module list in registration order.
func get_modules() -> Array[PluginModule]:
    return _modules.duplicate()
