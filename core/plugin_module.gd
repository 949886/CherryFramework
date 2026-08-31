@tool
class_name PluginModule
extends RefCounted

## Base class for every Cherry editor module.
##
## A module is instantiated by Cherry's root [EditorPlugin], attached through
## [_attach], and then receives the plugin lifecycle through the public
## [code]on_plugin_*[/code] callbacks.
var plugin: EditorPlugin

## Absolute Godot resource path to the Cherry plugin root, for example
## [code]res://addons/cherry[/code]. Modules should use this instead of
## hard-coding an installation directory.
var plugin_root: String

## Absolute Godot resource path to this module's own directory.
var module_root: String

## Internal attachment hook used by Cherry before any module lifecycle callback.
func _attach(host_plugin: EditorPlugin, host_plugin_root: String) -> void:
    plugin = host_plugin
    plugin_root = host_plugin_root
    var script := get_script() as Script
    module_root = script.resource_path.get_base_dir() if script != null else ""

## Returns the unique id used to identify this module inside Cherry.
##
## Implementations must return a non-empty value. Navigation uses
## [code]ui.navigation[/code].
func get_module_id() -> StringName:
    return &""

## Called once immediately after the module has been registered by Cherry.
##
## Use this callback to derive module paths and initialize state that does not
## require the editor plugin to have entered its tree yet.
func on_plugin_registered() -> void:
    pass

## Mirrors [method Node._enter_tree] for the Cherry root plugin.
##
## Modules should connect editor signals and begin editor-side services here.
func on_plugin_enter_tree() -> void:
    pass

## Mirrors [method Node._ready] for the Cherry root plugin.
func on_plugin_ready() -> void:
    pass

## Mirrors [method Node._process] for the Cherry root plugin.
func on_plugin_process(_delta: float) -> void:
    pass

## Mirrors [method Node._physics_process] for the Cherry root plugin.
func on_plugin_physics_process(_delta: float) -> void:
    pass

## Mirrors [method Node._exit_tree] for the Cherry root plugin.
##
## Modules should disconnect signals and release editor-side state here.
func on_plugin_exit_tree() -> void:
    pass
