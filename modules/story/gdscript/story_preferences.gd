@tool
class_name StoryPreferences
extends RefCounted
## Settings are described once in a JSON schema. Both the editor-facing model
## and the native settings page validate against that schema, never UI labels.

signal changed(key: String)

const SCHEMA_PATH := "../resources/galgame_settings.json"
var schema: Dictionary
var values: Dictionary = {}
var path := "user://cherry_galgame/settings.cfg"
var last_error := ""
## Editor preview contexts explicitly opt out of every persistence path,
## including reset_section(), which calls save_settings() directly.
var persistence_enabled := true

func _init() -> void:
	var source := (get_script() as Script).resource_path.get_base_dir().path_join(SCHEMA_PATH)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(source))
	schema = parsed if parsed is Dictionary else {}
	for field in fields():
		values[field.key] = field.default

func fields() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for section in schema.get("sections", []):
		for field in section.fields:
			result.append(field)
	return result

func definition(key: String) -> Dictionary:
	for field in fields():
		if field.key == key:
			return field
	return {}

func set_value(key: String, value: Variant, persist := true) -> bool:
	var field := definition(key)
	if field.is_empty():
		return false
	var normalized: Variant = _normalize(field, value)
	if normalized == null:
		return false
	values[key] = normalized
	if persist:
		save_settings()
	changed.emit(key)
	return true

func _normalize(field: Dictionary, value: Variant) -> Variant:
	match String(field.type):
		"check":
			return value if value is bool else null
		"range":
			if not (value is float or value is int) or not is_finite(float(value)):
				return null
			return clampf(snappedf(float(value), float(field.step)), float(field.min), float(field.max))
		"select":
			return value if value is String and field.options.has(value) else null
		"palette":
			return value if value is String and schema.palettes.has(value) else null
		"color":
			return value if value is String and value.begins_with("#") and value.length() in [7, 9] and Color.html_is_valid(value) else null
	return null

func field_visible(field: Dictionary) -> bool:
	for key in field.get("when", {}):
		if values.get(key) != field.when[key]:
			return false
	return true

func reset_section(id: String) -> Error:
	for section in schema.get("sections", []):
		if section.id == id:
			for field in section.fields:
				values[field.key] = field.default
			changed.emit("")
			return save_settings()
	return ERR_DOES_NOT_EXIST

func load_settings() -> Error:
	last_error = ""
	if not FileAccess.file_exists(path):
		return OK
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK:
		last_error = "设置文件无法读取，已使用默认设置。"
		return error
	for field in fields():
		var normalized: Variant = _normalize(field, config.get_value("settings", field.key, field.default))
		if normalized != null:
			values[field.key] = normalized
	return OK

func save_settings() -> Error:
	if not persistence_enabled: return OK
	var config := ConfigFile.new()
	for key in values:
		config.set_value("settings", key, values[key])
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error == OK:
		error = config.save(path + ".tmp")
	if error == OK:
		error = DirAccess.rename_absolute(path + ".tmp", path)
	last_error = "" if error == OK else "无法保存设置（%d）。" % error
	return error

func palette() -> Dictionary:
	var name := String(values.get("palette", "peach"))
	if name == "adaptive":
		name = "night" if DisplayServer.is_dark_mode() else "cream"
	return schema.palettes[name]
