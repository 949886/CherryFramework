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
    # Water remains a canvas tool when Cherry also provides a main screen.
    set_input_event_forwarding_always_enabled()
    set_force_draw_over_forwarding_enabled()
    EditorInterface.get_selection().selection_changed.connect(_water_selection_changed)

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
    EditorInterface.get_selection().selection_changed.disconnect(_water_selection_changed)
    for index: int in range(_modules.size() - 1, -1, -1):
        _modules[index].on_plugin_exit_tree()
    _modules.clear()
    _modules_by_id.clear()

func _register_modules() -> void:
    _register_module(NavigationModule.new())
    _register_module(JoystickModule.new())
    _register_module(WaterModule.new())
    _register_module(StoryModule.new())

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

func _handles(object: Object) -> bool:
    return object is Story

func _edit(object: Object) -> void:
    if object is Story:
        var story_module := get_module(StoryModule.MODULE_ID) as StoryModule
        if story_module != null:
            story_module.edit_story(object)

func _make_visible(visible: bool) -> void:
    var story_module := get_module(StoryModule.MODULE_ID) as StoryModule
    if story_module != null:
        story_module.make_visible(visible)

func _has_main_screen() -> bool:
    return true

func _get_plugin_name() -> String:
    return "Story"

func _get_plugin_icon() -> Texture2D:
    return preload("modules/story/icons/story.svg")

func _save_external_data() -> void:
    var story_module := get_module(StoryModule.MODULE_ID) as StoryModule
    if story_module != null:
        story_module.save_all()

func _get_unsaved_status(for_scene: String) -> String:
    var story_module := get_module(StoryModule.MODULE_ID) as StoryModule
    return story_module.unsaved_status() if for_scene.is_empty() and story_module != null else ""

func _build() -> bool:
    var story_module := get_module(StoryModule.MODULE_ID) as StoryModule
    return story_module.save_all() if story_module != null else true

func _water_selection_changed() -> void:
    var water_module := get_module(WaterModule.MODULE_ID) as WaterModule
    if water_module != null:
        var nodes := EditorInterface.get_selection().get_selected_nodes()
        water_module.edit_water(nodes[0] if nodes.size() == 1 else null)

func _forward_canvas_gui_input(event: InputEvent) -> bool:
    var water_module:=get_module(&"2d.water") as WaterModule
    return water_module.handle_input(event) if water_module!=null else false

func _forward_canvas_force_draw_over_viewport(overlay: Control) -> void:
    var water_module:=get_module(&"2d.water") as WaterModule
    if water_module!=null:
        water_module.draw_handles(overlay)
