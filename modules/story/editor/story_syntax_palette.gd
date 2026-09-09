@tool
extends RefCounted
## A local color scheme. Tokenization remains Godot's native GDScript lexer.

const THEME = preload("story_syntax_palette.tres")
const SETTINGS_PREFIX := "text_editor/theme/highlighting/"
const SETTING_ROLES := {
	"text_color": &"text",
	"keyword_color": &"keyword",
	"control_flow_keyword_color": &"keyword",
	"function_color": &"function",
	"gdscript/function_definition_color": &"function",
	"gdscript/global_function_color": &"keyword",
	"base_type_color": &"type",
	"engine_type_color": &"type",
	"user_type_color": &"speaker",
	"member_variable_color": &"speaker",
	"gdscript/annotation_color": &"state",
	"string_color": &"string",
	"gdscript/string_name_color": &"string",
	"string_placeholder_color": &"state",
	"number_color": &"number",
	"gdscript/node_path_color": &"number",
	"gdscript/node_reference_color": &"number",
	"symbol_color": &"symbol",
	"comment_color": &"comment",
	"doc_comment_color": &"doc_comment",
	"comment_markers/critical_color": &"critical",
	"comment_markers/warning_color": &"warning",
	"comment_markers/notice_color": &"number",
}

static func get_color(setting: String) -> Color:
	if SETTING_ROLES.has(setting):
		return THEME.get_color(SETTING_ROLES[setting], &"StorySyntax")
	return EditorInterface.get_editor_settings().get_setting(SETTINGS_PREFIX + setting)

static func native_color_map() -> Dictionary:
	var settings := EditorInterface.get_editor_settings()
	var result := {}
	# Read the current native palette, never change global editor settings.
	# Equal native colors remain equal after recoloring; first role takes priority.
	var text_color: Color = settings.get_setting(SETTINGS_PREFIX + "text_color")
	for setting in SETTING_ROLES:
		var original: Variant = settings.get_setting(SETTINGS_PREFIX + setting)
		if original is Color and original != text_color and not result.has(original):
			result[original] = get_color(setting)
	return result
