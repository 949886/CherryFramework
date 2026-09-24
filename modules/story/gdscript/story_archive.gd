class_name StoryArchive
extends RefCounted
## Persistent UI state around a StoryPlayer. VM snapshots remain owned/validated
## by StorySaveManager. Settings and lifetime read progress are not rolled back
## when the player loads an older slot.

signal changed
signal failed(message: String)

const PROFILE_VERSION := 1
const HISTORY_LIMIT := 500
var directory := "user://cherry_galgame"
var slot_count := 24
var player: StoryPlayer
var history: Array[Dictionary] = []
var progress: Dictionary = {}
var bookmarks: Dictionary = {}
var last_error := ""
var _active_identity := ""
var _active_key := ""
var _restoring := false

func configure(host: StoryPlayer, save_directory: String = "") -> void:
	player = host
	if not save_directory.is_empty():
		directory = save_directory
	load_profile()

func slot_path(index: int) -> String:
	if index < 0 or index >= slot_count:
		return ""
	return directory.path_join("slot_%02d.json" % (index + 1))

func read_slot(index: int) -> Dictionary:
	var path := slot_path(index)
	if path.is_empty() or not FileAccess.file_exists(path):
		return {"status": "empty", "index": index}
	var manager := StorySaveManager.new()
	var snapshot := manager.load_from_file(path)
	if snapshot.is_empty():
		return {"status": "corrupt", "index": index, "error": manager.last_file_error}
	return {"status": "ready", "index": index, "snapshot": snapshot, "metadata": snapshot.get("galgame", {})}

func save_slot(index: int, thumbnail: PackedByteArray = PackedByteArray()) -> Error:
	var path := slot_path(index)
	if path.is_empty():
		return _error("无效的存档栏位。", ERR_INVALID_PARAMETER)
	return _save(path, thumbnail)

func save_automatic() -> Error:
	return _save(directory.path_join("automatic.json"), PackedByteArray())

func _save(path: String, thumbnail: PackedByteArray) -> Error:
	if player == null or player.vm.program == null or not player.is_playing:
		return _error("当前没有可保存的剧情位置。", ERR_UNCONFIGURED)
	var snapshot := player.create_snapshot()
	if snapshot.is_empty():
		return _error("无法保存当前剧情。", ERR_INVALID_DATA)
	var presentation := player.presenter.capture_state()
	snapshot["galgame"] = {
		"version": PROFILE_VERSION,
		"time": Time.get_datetime_string_from_system(false, true),
		"speaker": presentation.speaker,
		"text": presentation.dialogue_text if presentation.dialogue_shown else presentation.article_text,
		"thumbnail": "" if thumbnail.is_empty() else Marshalls.raw_to_base64(thumbnail),
		"history": history.duplicate(true),
	}
	var error := player.save_manager.write_snapshot(path, snapshot)
	if error != OK:
		return _error("无法保存存档：" + player.save_manager.last_file_error, error)
	last_error = ""
	changed.emit()
	return OK

func load_slot(index: int) -> Error:
	var slot := read_slot(index)
	if slot.status != "ready":
		return _error("存档为空或已损坏，无法读取。", ERR_FILE_CORRUPT)
	return restore_snapshot(slot.snapshot)

func load_automatic() -> Error:
	var snapshot := StorySaveManager.new().load_from_file(directory.path_join("automatic.json"))
	if snapshot.is_empty():
		return _error("没有可读取的自动存档。", ERR_FILE_NOT_FOUND)
	return restore_snapshot(snapshot)

func restore_snapshot(snapshot: Dictionary) -> Error:
	if player == null or player.story == null:
		return _error("剧情播放器尚未准备好。", ERR_UNCONFIGURED)
	var target := player.story.resolve_story(String(snapshot.get("story_source", "")))
	if target == null:
		return _error("存档对应的剧本文件已不存在。", ERR_FILE_NOT_FOUND)
	# play() prepares the new VM transactionally before canceling the old one.
	var error := player.play(target, "", snapshot, String(snapshot.get("locale", player.locale)))
	if error != OK:
		return _error("读取存档失败，当前进度已保留。", error)
	var saved_history: Variant = snapshot.get("galgame", {}).get("history", [])
	history.clear()
	if saved_history is Array:
		for row in saved_history.slice(-HISTORY_LIMIT):
			if _valid_history(row):
				history.append(row.duplicate(true))
	_restoring = true
	last_error = ""
	changed.emit()
	return OK

func begin_presentation(payload: Dictionary) -> bool:
	if player == null or player.current_story == null:
		return false
	var instruction := player.vm.current_instruction()
	if not StoryLibrary.is_readable(instruction):
		return false
	_active_identity = player.current_story.get_identity()
	_active_key = StoryLibrary.reading_key(instruction)
	var already_read := is_read(_active_identity, _active_key)
	if not progress.has(_active_identity):
		progress[_active_identity] = {"read": {}, "entry": player.create_snapshot(), "visited": true}
	if not _restoring and int(instruction.op) != StoryProgram.Op.CHO:
		var text := ""
		var voice := ""
		for token in StoryInlineParser.new().parse(String(payload.get("content", ""))):
			if token.type == "text":
				text += String(token.bbcode)
			elif token.get("name", "") == "audio":
				var argument := String(token.get("argument", ""))
				voice = argument if argument.is_absolute_path() else player.vm.program.source_path.get_base_dir().path_join(argument).simplify_path()
		history.append({"kind": "dialogue" if instruction.op == StoryProgram.Op.DIA else "narration", "speaker": String(payload.get("speaker", "旁白")), "text": text, "voice": voice, "file": _active_identity})
		_trim_history()
	_restoring = false
	save_profile()
	changed.emit()
	return already_read

func complete_presentation() -> void:
	if progress.has(_active_identity) and not _active_key.is_empty():
		progress[_active_identity].read[_active_key] = true
		save_profile()
		changed.emit()

func record_choice(text: String) -> void:
	history.append({"kind": "choice", "speaker": "你的选择", "text": text, "voice": "", "file": _active_identity})
	_trim_history()

func _trim_history() -> void:
	if history.size() > HISTORY_LIMIT:
		history = history.slice(-HISTORY_LIMIT)

func is_read(identity: String, key: String) -> bool:
	return bool(progress.get(identity, {}).get("read", {}).get(key, false))

func status(identity: String, library: StoryLibrary) -> String:
	if player != null and player.current_story != null and player.current_story.get_identity() == identity:
		return "current"
	if progress.has(identity):
		return "read"
	for edge in library.edges:
		if edge.to == identity and progress.has(edge.from):
			return "unread"
	return "locked"

func toggle_bookmark(identity: String) -> void:
	if bookmarks.has(identity):
		bookmarks.erase(identity)
	else:
		bookmarks[identity] = true
	save_profile()
	changed.emit()

func replay_file(identity: String) -> Error:
	var snapshot: Dictionary = progress.get(identity, {}).get("entry", {})
	if snapshot.is_empty():
		return _error("这份剧本尚未阅读。", ERR_UNAVAILABLE)
	return restore_snapshot(snapshot)

func save_profile() -> Error:
	var config := ConfigFile.new()
	config.set_value("profile", "version", PROFILE_VERSION)
	config.set_value("profile", "progress", progress)
	config.set_value("profile", "bookmarks", bookmarks)
	var path := directory.path_join("profile.cfg")
	var error := DirAccess.make_dir_recursive_absolute(directory)
	if error == OK:
		error = config.save(path + ".tmp")
	if error == OK:
		error = DirAccess.rename_absolute(path + ".tmp", path)
	if error != OK:
		return _error("无法保存已读记录（%d）。" % error, error)
	return OK

func load_profile() -> Error:
	var path := directory.path_join("profile.cfg")
	if not FileAccess.file_exists(path):
		return OK
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > 16 * 1024 * 1024:
		return _error("已读记录文件无法读取或过大。", ERR_FILE_CORRUPT)
	file.close()
	var config := ConfigFile.new()
	var error := config.load(path)
	if error != OK or config.get_value("profile", "version", 0) != PROFILE_VERSION:
		return _error("已读记录格式不受支持。", ERR_FILE_CORRUPT)
	var saved: Variant = config.get_value("profile", "progress", {})
	var marked: Variant = config.get_value("profile", "bookmarks", {})
	progress.clear()
	bookmarks.clear()
	if saved is Dictionary:
		for identity in saved:
			var record: Variant = saved[identity]
			if not identity is String or not record is Dictionary or not record.get("read", {}) is Dictionary:
				continue
			var entry: Variant = record.get("entry", {})
			if not entry is Dictionary or not StorySaveManager.new().validate_snapshot(entry).is_empty():
				continue
			progress[identity] = record.duplicate(true)
	if marked is Dictionary:
		for identity in marked:
			if identity is String and marked[identity] is bool and marked[identity]:
				bookmarks[identity] = true
	return OK

func _valid_history(row: Variant) -> bool:
	if not row is Dictionary:
		return false
	for key in ["kind", "speaker", "text", "voice", "file"]:
		if not row.get(key) is String:
			return false
	return row.kind in ["dialogue", "narration", "choice"]

func _error(message: String, code: Error) -> Error:
	last_error = message
	failed.emit(message)
	return code
