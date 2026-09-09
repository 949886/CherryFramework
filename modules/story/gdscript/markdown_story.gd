@tool
class_name MarkdownStory
extends Story
## A single Markdown-syntax entry and its discovered sibling translations.

const SUPPORTED_EXTENSIONS := ["md", "story"]

@export_file("*.md", "*.story") var source_file := ""

static func supports_path(path: String) -> bool:
	return path.get_extension().to_lower() in SUPPORTED_EXTENSIONS

static func from_file(path: String) -> MarkdownStory:
	if not supports_path(path) or not FileAccess.file_exists(path):
		return null
	var result := MarkdownStory.new()
	result.source_file = path.simplify_path()
	return result

## Reserve a recognized language suffix for localization; preserve other dots.
static func describe_path(path: String) -> Dictionary:
	var stem := path.get_file().get_basename()
	var dot := stem.rfind(".")
	if dot > 0:
		var suffix := stem.substr(dot + 1)
		var language := suffix.replace("_", "-").get_slice("-", 0).to_lower()
		if language in TranslationServer.get_all_languages():
			return {"id": stem.substr(0, dot), "locale": Story.normalize_locale(suffix)}
	return {"id": stem, "locale": ""}

func get_story_id() -> String:
	return String(describe_path(source_file).id)

func get_identity() -> String:
	return source_file.get_base_dir().path_join(get_story_id())

func get_sources() -> Dictionary:
	var sources := {}
	if source_file.is_empty() or not DirAccess.dir_exists_absolute(source_file.get_base_dir()):
		return sources
	# Include raw Markdown in exports: DirAccess then works in a mounted PCK too.
	var names := DirAccess.get_files_at(source_file.get_base_dir())
	names.sort()
	for name in names:
		if not supports_path(name):
			continue
		var description := describe_path(name)
		if description.id == get_story_id():
			# Prefer the entry's extension when both formats supply a translation.
			var same_extension := name.get_extension().to_lower() == source_file.get_extension().to_lower()
			if not sources.has(description.locale) or (same_extension and String(sources[description.locale]).get_extension().to_lower() != source_file.get_extension().to_lower()):
				sources[description.locale] = source_file.get_base_dir().path_join(name)
	return sources

func get_source_path(locale: String = "") -> String:
	var sources := get_sources()
	var requested := Story.normalize_locale(locale)
	var candidates: Array[String] = [requested, requested.get_slice("-", 0), "", String(describe_path(source_file).locale)]
	for candidate in candidates:
		if sources.has(candidate):
			return sources[candidate]
	return ""

func resolve_story(target: String) -> Story:
	if target == get_story_id():
		return self
	var path := target if supports_path(target) else target + "." + source_file.get_extension()
	if not path.is_absolute_path():
		path = source_file.get_base_dir().path_join(path).simplify_path()
	var candidate := MarkdownStory.new()
	candidate.source_file = path
	var sources := candidate.get_sources()
	if sources.is_empty():
		return null
	# Prefer an actual unsuffixed file, then the entry's language, then stable order.
	if not FileAccess.file_exists(path):
		var preferred := String(describe_path(source_file).locale)
		candidate.source_file = sources.get("", sources.get(preferred, sources.values()[0]))
	# Imported resources carry optional per-file import settings.
	if ResourceLoader.exists(candidate.source_file):
		var imported := load(candidate.source_file) as MarkdownStory
		if imported != null:
			return imported
	# Raw-file use also works without the editor importer.
	candidate.commands = commands
	return candidate

func compile(locale: String, cache: StoryProgramCache = null) -> StoryProgram:
	var path := get_source_path(locale)
	if path.is_empty():
		return null
	if cache != null:
		return cache.compile_file(path, get_story_id())
	return StoryParser.new().compile_file(path, get_story_id())
