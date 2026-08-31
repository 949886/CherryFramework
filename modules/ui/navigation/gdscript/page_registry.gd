@tool
class_name PageRegistry
extends Resource

static var _instance: PageRegistry = null

## Process-local singleton used by every [Navigator].
##
## The instance loads Cherry's generated registry resource on first access.
static var instance: PageRegistry:
    get:
        if _instance == null:
            _instance = _load_or_create_instance()
        return _instance

## Generated static page definitions.
@export var pages: Array[PageDefinition] = []

var _by_path: Dictionary = {}
var _index_valid := false

## Returns the generated registry resource path.
##
## The Navigation module publishes the preferred path in Project Settings under
## [code]cherry/navigation/page_registry_path[/code]. If that setting is absent,
## Cherry derives its root from the globally registered [PluginModule] class.
static func get_registry_path() -> String:
    var configured_path := str(ProjectSettings.get_setting("cherry/navigation/page_registry_path", ""))
    if not configured_path.is_empty():
        return configured_path
    var cherry_root: String = _find_cherry_root()
    if cherry_root.is_empty():
        push_error("Cherry Navigation: unable to locate Cherry root.")
        return ""
    return cherry_root.path_join("generated/page_registry.tres")

static func _find_cherry_root() -> String:
    for class_info: Dictionary in ProjectSettings.get_global_class_list():
        if str(class_info.get("class", "")) != "PluginModule":
            continue
        var script_path := str(class_info.get("path", ""))
        if script_path.is_empty():
            return ""
        return script_path.get_base_dir().get_base_dir()
    return ""

static func _load_or_create_instance() -> PageRegistry:
    var registry_path: String = get_registry_path()
    if not registry_path.is_empty() and ResourceLoader.exists(registry_path):
        var loaded := ResourceLoader.load(registry_path, "", ResourceLoader.CACHE_MODE_IGNORE) as PageRegistry
        if loaded != null:
            return loaded
    return PageRegistry.new()

## Converts a public navigation path into Cherry's canonical [code]ui://...[/code]
## representation.
##
## Accepted inputs are [code]/settings[/code], [code]ui://settings[/code],
## [code]/[/code], and [code]ui://[/code]. Bare names and other URI schemes
## return an empty string.
static func normalize_path(path: String) -> String:
    var raw: String = path.strip_edges()
    if raw == "/" or raw == "ui://":
        return "ui://"
    var suffix: String = ""
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

## Rebuilds the runtime path lookup table from [member pages].
func rebuild_index() -> void:
    _by_path.clear()
    for page: PageDefinition in pages:
        if page == null:
            continue
        var normalized: String = PageRegistry.normalize_path(page.path)
        if not normalized.is_empty():
            _by_path[normalized] = page
    _index_valid = true

## Replaces all generated definitions and immediately rebuilds runtime indexes.
##
## This is primarily used by the editor-side [NavigationModule] generator.
func replace_pages(new_pages: Array[PageDefinition]) -> void:
    pages.clear()
    pages.append_array(new_pages)
    _index_valid = false
    rebuild_index()

## Returns whether [param other_pages] contains the same ordered Path and Scene
## entries as the loaded registry.
func content_equals(other_pages: Array[PageDefinition]) -> bool:
    if pages.size() != other_pages.size():
        return false
    for i: int in pages.size():
        var current: PageDefinition = pages[i]
        var other: PageDefinition = other_pages[i]
        if current == null or other == null or current.path != other.path:
            return false
        if current.scene == null or other.scene == null or current.scene.resource_path != other.scene.resource_path:
            return false
    return true

## Resolves [param path] to a [PageDefinition].
##
## Returns [code]null[/code] and reports an error when no definition exists.
func resolve(path: String) -> PageDefinition:
    var definition: PageDefinition = try_resolve(path)
    if definition == null:
        push_error("Navigation page not found: %s" % path)
    return definition

## Attempts to resolve [param path] without reporting an error.
##
## Returns [code]null[/code] for invalid or unregistered paths.
func try_resolve(path: String) -> PageDefinition:
    if not _index_valid:
        rebuild_index()
    var normalized: String = PageRegistry.normalize_path(path)
    if normalized.is_empty():
        return null
    return _by_path.get(normalized) as PageDefinition

## Returns whether [param path] is currently registered.
func contains(path: String) -> bool:
    return try_resolve(path) != null

## Returns a shallow copy of all generated page definitions.
func get_pages() -> Array[PageDefinition]:
    return pages.duplicate()
