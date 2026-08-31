@tool
class_name JoystickModule
extends PluginModule

## Cherry editor module responsible for selecting the Joystick runtime language.
##
## Both implementations are shipped together:
##
## [code]joystick/gdscript[/code]
## [code]joystick/csharp[/code]
##
## A root-level .csproj selects C#; otherwise GDScript is selected. The unused
## implementation receives a runtime-created .gdignore and the editor filesystem
## is rescanned so only the matching set of global classes is exposed.

const MODULE_ID := &"ui.joystick"
const LANGUAGE_GDSCRIPT := &"gdscript"
const LANGUAGE_CSHARP := &"csharp"

var _gdscript_runtime_root := ""
var _csharp_runtime_root := ""
var _runtime_root := ""
var _runtime_language: StringName = LANGUAGE_GDSCRIPT
var _is_dotnet := false

var _runtime_ready := false
var _runtime_rescan_needed := false
var _runtime_rescan_started := false
var _runtime_rescan_settle_frames := 0

## Returns Cherry's stable module id for Joystick.
func get_module_id() -> StringName:
    return MODULE_ID

## Returns the currently selected implementation language.
func get_runtime_language() -> StringName:
    return _runtime_language

## Returns the currently selected runtime directory.
func get_runtime_root() -> String:
    return _runtime_root

## Returns true when Cherry selected the C# implementation.
func is_dotnet_runtime() -> bool:
    return _is_dotnet

## Detects the project language and configures which runtime directory Godot sees.
func on_plugin_registered() -> void:
    _gdscript_runtime_root = module_root.path_join("gdscript")
    _csharp_runtime_root = module_root.path_join("csharp")

    _is_dotnet = _is_dotnet_project()
    _runtime_language = LANGUAGE_CSHARP if _is_dotnet else LANGUAGE_GDSCRIPT
    _runtime_root = _csharp_runtime_root if _is_dotnet else _gdscript_runtime_root
    _runtime_rescan_needed = _configure_runtime_directories()

    print(
        "Cherry Joystick: selected %s runtime (%s)"
        % ["C#/.NET" if _is_dotnet else "GDScript", _runtime_root]
    )

func on_plugin_enter_tree() -> void:
    if not _runtime_rescan_needed:
        _runtime_ready = true

func on_plugin_process(_delta: float) -> void:
    if _runtime_ready:
        return
    _process_runtime_rescan(EditorInterface.get_resource_filesystem())

## Applies the .gdignore state for the current project type.
func _configure_runtime_directories() -> bool:
    var changed := false
    changed = _set_directory_ignored(_gdscript_runtime_root, _is_dotnet) or changed
    changed = _set_directory_ignored(_csharp_runtime_root, not _is_dotnet) or changed
    return changed

## Detects an actual C# project by looking for a root-level .csproj next to project.godot.
func _is_dotnet_project() -> bool:
    var root_directory := DirAccess.open("res://")
    if root_directory == null:
        return false
    for file_name: String in root_directory.get_files():
        if file_name.get_extension().to_lower() == "csproj":
            return true
    return false

## Creates/removes .gdignore through the physical filesystem so ignored folders
## remain manageable after they disappear from Godot's resource filesystem.
func _set_directory_ignored(directory_res_path: String, ignored: bool) -> bool:
    var directory_abs_path := ProjectSettings.globalize_path(directory_res_path)
    var directory := DirAccess.open(directory_abs_path)
    if directory == null:
        push_error("Cherry Joystick: runtime directory does not exist: " + directory_res_path)
        return false

    var ignore_exists := directory.file_exists(".gdignore")
    if ignored:
        if ignore_exists:
            return false
        var ignore_path := directory_abs_path.path_join(".gdignore")
        var file := FileAccess.open(ignore_path, FileAccess.WRITE)
        if file == null:
            push_error("Cherry Joystick: cannot create: " + ignore_path)
            return false
        file.close()
        print("Cherry Joystick: ignoring unused runtime: " + directory_res_path)
        return true

    if not ignore_exists:
        return false

    var remove_error := directory.remove(".gdignore")
    if remove_error != OK:
        push_error("Cherry Joystick: cannot remove .gdignore from: " + directory_res_path)
        return false

    print("Cherry Joystick: exposing selected runtime: " + directory_res_path)
    return true

## Rescans after language selection. This intentionally mirrors Navigation's
## bootstrap behavior so global classes are refreshed before the module is used.
func _process_runtime_rescan(file_system: EditorFileSystem) -> void:
    if _runtime_rescan_needed:
        if file_system.is_scanning():
            return
        file_system.scan()
        _runtime_rescan_needed = false
        _runtime_rescan_started = true
        _runtime_rescan_settle_frames = 1
        return

    if not _runtime_rescan_started:
        _runtime_ready = true
        return

    if file_system.is_scanning():
        return
    if _runtime_rescan_settle_frames > 0:
        _runtime_rescan_settle_frames -= 1
        return

    _runtime_rescan_started = false
    _runtime_ready = true
