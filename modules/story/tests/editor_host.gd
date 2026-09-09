@tool
extends EditorPlugin
## Enabled only in the temporary project created by run_tests.py.

const SyntaxSuite = preload("syntax_suite.gd")
const EditorSuite = preload("editor_suite.gd")
const IconSuite = preload("icon_suite.gd")
var module: StoryModule

func _enter_tree() -> void:
	module = StoryModule.new()
	module._attach(self, "res://shared/cherry_core")
	module.on_plugin_enter_tree()
	if "--story-editor-check" in OS.get_cmdline_user_args():
		_probe.call_deferred()
	elif "--story-icon-check" in OS.get_cmdline_user_args():
		_icon_probe.call_deferred()

func _has_main_screen() -> bool:
	return true

func _get_plugin_name() -> String:
	return "Story"

func _get_plugin_icon() -> Texture2D:
	return preload("../icons/story.svg")

func _make_visible(visible: bool) -> void:
	if module != null: module.make_visible(visible)

func _probe() -> void:
	await get_tree().process_frame
	var editor_result: Dictionary = await EditorSuite.new().run(self)
	var syntax_result: Dictionary = await SyntaxSuite.new().run(self)
	var failures: int = editor_result.failures + syntax_result.failures
	print("Editor total: checks=%d failures=%d" % [editor_result.checks + syntax_result.checks, failures])
	get_tree().quit(0 if failures == 0 else 1)

func _icon_probe() -> void:
	var result: Dictionary = await IconSuite.new().run(self)
	get_tree().quit(0 if result.failures == 0 else 1)

func _exit_tree() -> void:
	if module != null:
		module.on_plugin_exit_tree()
		module = null
