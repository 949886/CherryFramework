@tool
class_name MarkdownStoryFormatSaver
extends ResourceFormatSaver
## Godot's FileSystem Duplicate loads UID resources and saves them at a new path.
## The source remains plain text; Resource fields belong in a .tres wrapper.

func _recognize(resource: Resource) -> bool:
	return resource is MarkdownStory

func _get_recognized_extensions(resource: Resource) -> PackedStringArray:
	return PackedStringArray(MarkdownStory.SUPPORTED_EXTENSIONS) if _recognize(resource) else PackedStringArray()

func _recognize_path(resource: Resource, path: String) -> bool:
	return _recognize(resource) and MarkdownStory.supports_path(path)

func _save(resource: Resource, path: String, _flags: int) -> Error:
	if not _recognize_path(resource, path):
		return ERR_FILE_UNRECOGNIZED
	var source := FileAccess.open((resource as MarkdownStory).source_file, FileAccess.READ)
	if source == null:
		return FileAccess.get_open_error()
	# Copy bytes, preserving BOM, line endings, whitespace and Markdown syntax.
	var content := source.get_buffer(source.get_length())
	var error := source.get_error()
	source.close()
	if error != OK:
		return error
	var temporary := path + ".cherry-saving-" + str(Time.get_ticks_usec())
	var output := FileAccess.open(temporary, FileAccess.WRITE)
	if output == null:
		return FileAccess.get_open_error()
	output.store_buffer(content)
	output.flush()
	error = output.get_error()
	output.close()
	if error == OK:
		error = DirAccess.rename_absolute(temporary, path)
	if error != OK:
		DirAccess.remove_absolute(temporary)
	# Do not copy the source .uid: the editor assigns the destination its own UID.
	return error

func _set_uid(path: String, uid: int) -> Error:
	if not MarkdownStory.supports_path(path):
		return ERR_FILE_UNRECOGNIZED
	var file := FileAccess.open(path + ".uid", FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_line(ResourceUID.id_to_text(uid))
	file.flush()
	var error := file.get_error()
	file.close()
	return error
