@tool
class_name NavigationModule
extends PluginModule

## Cherry editor module responsible for selecting the Navigation runtime language
## and regenerating the shared PageRegistry resource.
##
## The addon always ships both implementations:
##
## [code]navigation/gdscript[/code]
## [code]navigation/csharp[/code]
##
## A root-level .csproj selects C#; otherwise GDScript is selected. The unused
## implementation receives a runtime-created .gdignore and the editor filesystem
## is rescanned before registry generation starts. This mirrors Cherry's
## dual-language packaging rule without requiring separate addon distributions.

const MODULE_ID := &"ui.navigation"
const PAGE_REGISTRY_PATH_SETTING := "cherry/navigation/page_registry_path"

const LANGUAGE_GDSCRIPT := &"gdscript"
const LANGUAGE_CSHARP := &"csharp"

var _registry_path := ""
var _gdscript_runtime_root := ""
var _csharp_runtime_root := ""
var _runtime_root := ""
var _registry_script_path := ""
var _definition_script_path := ""
var _runtime_language: StringName = LANGUAGE_GDSCRIPT
var _is_dotnet := false

var _runtime_ready := false
var _runtime_rescan_needed := false
var _runtime_rescan_started := false
var _runtime_rescan_settle_frames := 0

var _pending_rebuild := false
var _settle_frames := 2

## Returns Cherry's stable module id for Navigation.
func get_module_id() -> StringName:
    return MODULE_ID

## Detects the project language, chooses the matching runtime directory, and
## updates the generated-registry project setting.
func on_plugin_registered() -> void:
    _registry_path = plugin_root.path_join("generated/page_registry.tres")
    _gdscript_runtime_root = module_root.path_join("gdscript")
    _csharp_runtime_root = module_root.path_join("csharp")

    _is_dotnet = _is_dotnet_project()
    _runtime_language = LANGUAGE_CSHARP if _is_dotnet else LANGUAGE_GDSCRIPT
    _runtime_root = _csharp_runtime_root if _is_dotnet else _gdscript_runtime_root

    _registry_script_path = _runtime_root.path_join("PageRegistry.cs" if _is_dotnet else "page_registry.gd")
    _definition_script_path = _runtime_root.path_join("PageDefinition.cs" if _is_dotnet else "page_definition.gd")

    _runtime_rescan_needed = _configure_runtime_directories()
    _register_project_setting()

    print(
        "Cherry Navigation: selected %s runtime (%s)"
        % ["C#/.NET" if _is_dotnet else "GDScript", _runtime_root]
    )

func _register_project_setting() -> void:
    ## ProjectSettings.add_property_info() requires the setting to already exist.
    ## Create/update the value first so a fresh project does not hit Godot's
    ## missing-property assertion during plugin startup.
    var current_value := str(ProjectSettings.get_setting(PAGE_REGISTRY_PATH_SETTING, ""))
    var setting_changed := current_value != _registry_path
    if setting_changed:
        ProjectSettings.set_setting(PAGE_REGISTRY_PATH_SETTING, _registry_path)

    ProjectSettings.add_property_info({
        "name": PAGE_REGISTRY_PATH_SETTING,
        "type": TYPE_STRING,
        "hint": PROPERTY_HINT_FILE,
        "hint_string": "*.tres",
    })

    if not setting_changed:
        return

    var save_error: Error = ProjectSettings.save()
    if save_error != OK:
        push_error(
            "Cherry Navigation: failed to save project setting '%s': %s"
            % [PAGE_REGISTRY_PATH_SETTING, error_string(save_error)]
        )

func on_plugin_enter_tree() -> void:
    var file_system: EditorFileSystem = EditorInterface.get_resource_filesystem()
    if not file_system.filesystem_changed.is_connected(_on_filesystem_changed):
        file_system.filesystem_changed.connect(_on_filesystem_changed)

    if not _runtime_rescan_needed:
        _runtime_ready = true
        _request_rebuild()

func on_plugin_process(_delta: float) -> void:
    var file_system: EditorFileSystem = EditorInterface.get_resource_filesystem()

    if not _runtime_ready:
        _process_runtime_rescan(file_system)
        return

    if not _pending_rebuild:
        return
    if file_system.is_scanning():
        return
    if _settle_frames > 0:
        _settle_frames -= 1
        return

    _pending_rebuild = false
    _rebuild_registry(file_system)

func on_plugin_exit_tree() -> void:
    var file_system: EditorFileSystem = EditorInterface.get_resource_filesystem()
    if file_system.filesystem_changed.is_connected(_on_filesystem_changed):
        file_system.filesystem_changed.disconnect(_on_filesystem_changed)

func _on_filesystem_changed() -> void:
    ## Ignore filesystem-change notifications produced by language selection.
    ## Registry generation begins only after the selected runtime rescan settles.
    if _runtime_ready:
        _request_rebuild()

func _request_rebuild() -> void:
    _pending_rebuild = true
    _settle_frames = 2

## Applies the .gdignore state for the current project type.
##
## A C# project hides navigation/gdscript and exposes navigation/csharp.
## A GDScript project does the reverse. Both source trees remain physically
## present, so the same addon directory can be copied into either project.
func _configure_runtime_directories() -> bool:
    var changed := false
    changed = _set_directory_ignored(_gdscript_runtime_root, _is_dotnet) or changed
    changed = _set_directory_ignored(_csharp_runtime_root, not _is_dotnet) or changed
    return changed

## Detects an actual C# project rather than merely a .NET-capable Godot editor.
##
## Godot C# projects keep their main .csproj next to project.godot.
func _is_dotnet_project() -> bool:
    var root_directory := DirAccess.open("res://")
    if root_directory == null:
        return false
    for file_name: String in root_directory.get_files():
        if file_name.get_extension().to_lower() == "csproj":
            return true
    return false

## Creates or removes an empty .gdignore using the physical filesystem.
##
## Absolute paths are intentional: after .gdignore takes effect, the ignored
## directory disappears from Godot's resource filesystem but still exists on
## disk and must remain manageable when the project type changes.
func _set_directory_ignored(directory_res_path: String, ignored: bool) -> bool:
    var directory_abs_path := ProjectSettings.globalize_path(directory_res_path)
    var directory := DirAccess.open(directory_abs_path)
    if directory == null:
        push_error("Cherry Navigation: runtime directory does not exist: " + directory_res_path)
        return false

    var ignore_exists := directory.file_exists(".gdignore")
    if ignored:
        if ignore_exists:
            return false
        var ignore_path := directory_abs_path.path_join(".gdignore")
        var file := FileAccess.open(ignore_path, FileAccess.WRITE)
        if file == null:
            push_error("Cherry Navigation: cannot create: " + ignore_path)
            return false
        file.close()
        print("Cherry Navigation: ignoring unused runtime: " + directory_res_path)
        return true

    if not ignore_exists:
        return false

    var remove_error := directory.remove(".gdignore")
    if remove_error != OK:
        push_error("Cherry Navigation: cannot remove .gdignore from: " + directory_res_path)
        return false

    print("Cherry Navigation: exposing selected runtime: " + directory_res_path)
    return true

## Rescans the editor filesystem after changing .gdignore state.
##
## EditorFileSystem.scan() must not run while another scan is active. A settle
## frame after completion lets global classes/resource visibility reflect the
## new language selection before PageRegistry generation starts.
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
        _request_rebuild()
        return

    if file_system.is_scanning():
        return
    if _runtime_rescan_settle_frames > 0:
        _runtime_rescan_settle_frames -= 1
        return

    _runtime_rescan_started = false
    _runtime_ready = true
    _request_rebuild()

## Rebuilds the registry without statically referencing either runtime language.
##
## The module scans scene source text, then writes the .tres using the selected
## PageRegistry/PageDefinition script paths. This keeps C# editor bootstrap
## independent from an already-built C# assembly while using the same generator
## implementation in GDScript projects.
func _rebuild_registry(file_system: EditorFileSystem) -> void:
    var scene_paths: Array[String] = []
    _scan_directory("res://", scene_paths)
    scene_paths.sort()

    var path_to_scene: Dictionary = {}
    var entries: Array[Dictionary] = []

    for scene_path: String in scene_paths:
        var source := FileAccess.get_file_as_string(scene_path)
        if source.is_empty():
            continue

        var normalized_path := _normalize_path(_read_navigation_path(source))
        if normalized_path.is_empty():
            continue

        if path_to_scene.has(normalized_path):
            push_error(
                "Cherry Navigation: duplicate path '%s' in %s and %s"
                % [normalized_path, str(path_to_scene[normalized_path]), scene_path]
            )
            continue

        path_to_scene[normalized_path] = scene_path
        entries.append({"path": normalized_path, "scene": scene_path})

    entries.sort_custom(
        func(a: Dictionary, b: Dictionary) -> bool:
            return str(a["path"]) < str(b["path"])
    )

    var paths: Array[String] = []
    var scenes: Array[String] = []
    for entry: Dictionary in entries:
        paths.append(str(entry["path"]))
        scenes.append(str(entry["scene"]))

    var generated := _build_registry_text(paths, scenes)
    if FileAccess.file_exists(_registry_path) and FileAccess.get_file_as_string(_registry_path) == generated:
        return

    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_registry_path.get_base_dir()))
    var file := FileAccess.open(_registry_path, FileAccess.WRITE)
    if file == null:
        push_error("Cherry Navigation: unable to create generated registry: " + _registry_path)
        return

    file.store_string(generated)
    file.close()

    _refresh_registry_resource(file_system)
    print(
        "Cherry Navigation: rebuilt %s (%d pages, %s runtime)"
        % [_registry_path, paths.size(), String(_runtime_language)]
    )

## Updates EditorFileSystem metadata and refreshes an already cached generated
## registry in place.
##
## CACHE_MODE_REPLACE_DEEP is required because PageDefinition entries are
## embedded subresources. The load is conditional so a C# project can generate
## its registry before the C# assembly has been built.
func _refresh_registry_resource(file_system: EditorFileSystem) -> void:
    file_system.update_file(_registry_path)
    if ResourceLoader.has_cached(_registry_path):
        ResourceLoader.load(_registry_path, "", ResourceLoader.CACHE_MODE_REPLACE_DEEP)

## Reads only the root NavigationPage path property without instantiating scenes.
##
## The GDScript runtime serializes [code]navigation_path[/code], while C# scenes
## serialize [code]NavigationPath[/code]. Supporting both lets one universal
## scanner serve both project types.
func _read_navigation_path(scene_source: String) -> String:
    var seen_root_node := false
    for line: String in scene_source.split("\n"):
        var stripped := line.strip_edges()
        if stripped.begins_with("[node "):
            if seen_root_node:
                break
            seen_root_node = true
            continue
        if not seen_root_node:
            continue
        if stripped.begins_with("["):
            break

        var equals_index := stripped.find("=")
        if equals_index < 0:
            continue

        var property_name := stripped.substr(0, equals_index).strip_edges()
        if property_name != "NavigationPath" and property_name != "navigation_path":
            continue

        return _parse_quoted_string(stripped.substr(equals_index + 1).strip_edges())

    return ""

func _parse_quoted_string(value: String) -> String:
    if value.length() < 2 or not value.begins_with("\"") or not value.ends_with("\""):
        return ""
    return value.substr(1, value.length() - 2)

## Normalizes static PageDefinition identity only. Query/Fragment parsing remains
## a Navigator/Uri concern and is intentionally absent from registry generation.
func _normalize_path(path: String) -> String:
    var raw := path.strip_edges()
    if raw == "/" or raw == "ui://":
        return "ui://"

    var suffix := ""
    if raw.begins_with("ui://"):
        suffix = raw.substr(5)
    elif raw.begins_with("/"):
        suffix = raw.substr(1)
    else:
        return ""

    while suffix.begins_with("/"):
        suffix = suffix.substr(1)
    while suffix.ends_with("/") and not suffix.is_empty():
        suffix = suffix.left(-1)

    if suffix.is_empty():
        return "ui://"
    if "://" in suffix:
        return ""

    return "ui://" + suffix

## Dispatches generated PageRegistry text to the selected runtime writer.
##
## The two writers deliberately remain separate. C# keeps the text writer shape
## used by Cherry before the dual-language addon merge; GDScript owns its
## lowercase resource-property format independently instead of sharing
## conditional property-name variables with C#.
func _build_registry_text(paths: Array[String], scenes: Array[String]) -> String:
    if _is_dotnet:
        return _build_registry_text_csharp(paths, scenes)
    return _build_registry_text_gdscript(paths, scenes)

## Builds the C# PageRegistry resource text.
##
## This intentionally follows the original C# NavigationModule writer: C#
## exported properties are serialized as Path, Scene, and Pages.
func _build_registry_text_csharp(paths: Array[String], scenes: Array[String]) -> String:
    var output: PackedStringArray = ["[gd_resource type=\"Resource\" load_steps=%d format=3]" % (2 + paths.size() * 2), ""]
    output.append("[ext_resource type=\"Script\" path=\"%s\" id=\"1_registry\"]" % _registry_script_path)
    output.append("[ext_resource type=\"Script\" path=\"%s\" id=\"2_definition\"]" % _definition_script_path)
    for index: int in paths.size():
        output.append("[ext_resource type=\"PackedScene\" path=\"%s\" id=\"scene_%d\"]" % [scenes[index], index])
    output.append("")
    for index: int in paths.size():
        output.append("[sub_resource type=\"Resource\" id=\"Page_%d\"]" % index)
        output.append("script = ExtResource(\"2_definition\")")
        output.append("Path = \"%s\"" % _escape_tres_string(paths[index]))
        output.append("Scene = ExtResource(\"scene_%d\")" % index)
        output.append("")
    output.append("[resource]")
    output.append("script = ExtResource(\"1_registry\")")
    var page_refs: PackedStringArray = []
    for index: int in paths.size():
        page_refs.append("SubResource(\"Page_%d\")" % index)
    output.append("Pages = Array[ExtResource(\"2_definition\")]([%s])" % ", ".join(page_refs))
    output.append("")
    return "\n".join(output)

## Builds the GDScript PageRegistry resource text.
##
## GDScript PageDefinition/PageRegistry export lowercase property names, so its
## generated resource stays independent from C# serialization details.
func _build_registry_text_gdscript(paths: Array[String], scenes: Array[String]) -> String:
    var output: PackedStringArray = ["[gd_resource type=\"Resource\" load_steps=%d format=3]" % (2 + paths.size() * 2), ""]
    output.append("[ext_resource type=\"Script\" path=\"%s\" id=\"1_registry\"]" % _registry_script_path)
    output.append("[ext_resource type=\"Script\" path=\"%s\" id=\"2_definition\"]" % _definition_script_path)
    for index: int in paths.size():
        output.append("[ext_resource type=\"PackedScene\" path=\"%s\" id=\"scene_%d\"]" % [scenes[index], index])
    output.append("")
    for index: int in paths.size():
        output.append("[sub_resource type=\"Resource\" id=\"Page_%d\"]" % index)
        output.append("script = ExtResource(\"2_definition\")")
        output.append("path = \"%s\"" % _escape_tres_string(paths[index]))
        output.append("scene = ExtResource(\"scene_%d\")" % index)
        output.append("")
    output.append("[resource]")
    output.append("script = ExtResource(\"1_registry\")")
    var page_refs: PackedStringArray = []
    for index: int in paths.size():
        page_refs.append("SubResource(\"Page_%d\")" % index)
    output.append("pages = Array[ExtResource(\"2_definition\")]([%s])" % ", ".join(page_refs))
    output.append("")
    return "\n".join(output)

func _escape_tres_string(value: String) -> String:
    return value.replace("\\", "\\\\").replace("\"", "\\\"")

func _scan_directory(path: String, output: Array[String]) -> void:
    var directory := DirAccess.open(path)
    if directory == null:
        return

    directory.list_dir_begin()
    var name := directory.get_next()

    while not name.is_empty():
        if name == "." or name == ".." or name.begins_with("."):
            name = directory.get_next()
            continue

        var child_path := path.path_join(name)
        if directory.current_is_dir():
            _scan_directory(child_path, output)
        elif name.get_extension().to_lower() == "tscn":
            output.append(child_path)

        name = directory.get_next()

    directory.list_dir_end()
