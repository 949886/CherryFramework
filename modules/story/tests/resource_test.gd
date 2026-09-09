extends SceneTree
## Resource semantics and automatic localization, without an editor or library map.

var checks := 0
var failures := 0
var directory := "user://resource_test_%d" % OS.get_process_id()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + label)

func write(name: String, content: String = "Guide: Hello") -> String:
	var path := directory.path_join(name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(content)
	file.close()
	return path

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	check(not MarkdownStory.supports_path("README.md") and not MarkdownStory.supports_path("docs/ReAdMe.MD"), "README excluded regardless of case")
	check(MarkdownStory.supports_path("chapter.STORY") and not MarkdownStory.supports_path("chapter.txt"), "supported extensions are case insensitive")
	check(MarkdownStory.describe_path("chapter.one.zh_CN.md") == {"id": "chapter.one", "locale": "zh-cn"}, "regional locale normalized without losing dotted ID")
	check(MarkdownStory.describe_path("chapter.one.story") == {"id": "chapter.one", "locale": ""}, "nonlanguage suffix belongs to story ID")
	check(MarkdownStory.from_file(directory.path_join("missing.md")) == null, "missing entry rejected")
	var japanese := write("chapter.one.ja.md")
	var chinese := write("chapter.one.zh-cn.story", "Guide: 中文")
	var english := write("chapter.one.en.md")
	write("unrelated.en.md")
	var story := load(japanese) as MarkdownStory
	check(story != null and story.resource_path == japanese and story.source_file == japanese, "native Markdown load retains external source identity")
	check(load(chinese) is MarkdownStory, "native .story load uses the same resource class")
	check(story.get_sources().size() == 3, "sibling discovery includes both formats and excludes other IDs")
	check(story.get_available_locales() == PackedStringArray(["en", "ja", "zh-cn"]), "available locales have deterministic order")
	check(story.get_source_path("ZH_CN") == chinese, "exact normalized locale wins")
	check(story.get_source_path("en-GB") == english, "region falls back to primary language")
	check(story.get_source_path("fr") == japanese, "missing translation falls back to entry language")
	var neutral := write("chapter.one.md")
	check(story.get_source_path("fr") == neutral, "unsuffixed source takes precedence over entry fallback")
	var chinese_md := write("chapter.one.zh-cn.md")
	check(story.get_source_path("zh-cn") == chinese_md, "same-locale collision prefers entry extension")
	check((load(chinese) as Story).get_source_path("zh-cn") == chinese, ".story entry keeps its extension preference")
	DirAccess.remove_absolute(chinese_md)
	check(story.get_source_path("zh-cn") == chinese, "removed translation is detected without stale map")
	check(story.resolve_story("chapter.one") == story, "self jump reuses entry")
	var destination := write("next.ja.story", "# ending\nGuide: Next")
	var next := story.resolve_story("next.story")
	check(next != null and next.get_source_path("ja") == destination, "cross-format jump finds localized destination without an unsuffixed file")
	check(story.resolve_story("missing") == null, "unresolved jump returns null")
	var cache := StoryProgramCache.new()
	check(story.compile("zh-cn", cache) != null and story.compile("zh-cn", cache) != null and cache.hits == 1, "resource compiles through shared program cache")
	var player := StoryPlayer.new()
	player.autoplay = false
	player.story = story
	var packed := PackedScene.new()
	check(packed.pack(player) == OK and ResourceSaver.save(packed, directory.path_join("entry.tscn")) == OK, "Story property serializes in a scene")
	var text := FileAccess.get_file_as_string(directory.path_join("entry.tscn"))
	check(text.contains(japanese) and not text.contains('source_file ='), "scene stores external Markdown reference instead of inline wrapper")
	var restored := (load(directory.path_join("entry.tscn")) as PackedScene).instantiate() as StoryPlayer
	check(restored.story is MarkdownStory and restored.story.source_file == japanese, "scene reload restores native Story resource")
	player.free()
	restored.free()
	for file in DirAccess.get_files_at(directory):
		DirAccess.remove_absolute(directory.path_join(file))
	DirAccess.remove_absolute(directory)
	print("Resource: %d passed, %d failed" % [checks - failures, failures])
	quit(0 if failures == 0 else 1)
