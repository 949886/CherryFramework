class_name StoryPresentationState
extends Resource
## Serializable visual context and cursor of one presentation event.

const FIELDS := {
	"mode": TYPE_STRING, "payload": TYPE_DICTIONARY, "phase": TYPE_STRING,
	"token_index": TYPE_INT, "visible_characters": TYPE_INT,
	"remaining": TYPE_FLOAT, "text_time": TYPE_FLOAT,
	"background_path": TYPE_STRING, "background_alpha": TYPE_FLOAT,
	"portrait_path": TYPE_STRING, "popup_path": TYPE_STRING,
	"audio_path": TYPE_STRING, "audio_position": TYPE_FLOAT, "audio_playing": TYPE_BOOL,
	"dialogue_text": TYPE_STRING, "dialogue_characters": TYPE_INT, "speaker": TYPE_STRING,
	"article_text": TYPE_STRING, "article_characters": TYPE_INT,
	"dialogue_shown": TYPE_BOOL, "article_shown": TYPE_BOOL,
}
const PHASES := ["idle", "next", "text", "wait", "input", "end", "choice", "popup", "fade"]
const MODES := ["idle", "dialogue", "narration", "silent", "choice"]

var mode := "idle"
var payload: Dictionary = {}
var phase := "idle"
var token_index := 0
var visible_characters := 0
var remaining := 0.0
var text_time := 0.0
var background_path := ""
var background_alpha := 1.0
var portrait_path := ""
var popup_path := ""
var audio_path := ""
var audio_position := 0.0
var audio_playing := false
var dialogue_text := ""
var dialogue_characters := 0
var speaker := ""
var article_text := ""
var article_characters := 0
var dialogue_shown := false
var article_shown := false

func to_dict() -> Dictionary:
	var data := {"version": 1}
	for key in FIELDS:
		data[key] = get(key)
	return data.duplicate(true)

func copy() -> StoryPresentationState:
	return from_dict(to_dict())

static func from_dict(data: Dictionary) -> StoryPresentationState:
	if data.get("version") != 1:
		return null
	var state := StoryPresentationState.new()
	for key in FIELDS:
		if not data.has(key):
			return null
		var value: Variant = data[key]
		var expected: int = FIELDS[key]
		if expected in [TYPE_INT, TYPE_FLOAT]:
			if not (value is int or value is float) or not is_finite(float(value)):
				return null
			if expected == TYPE_INT and (value < 0 or value > 2147483647 or floor(value) != value):
				return null
			value = int(value) if expected == TYPE_INT else float(value)
		elif typeof(value) != expected:
			return null
		state.set(key, value.duplicate(true) if value is Dictionary else value)
	if state.mode not in MODES or state.phase not in PHASES:
		return null
	if state.remaining < 0 or state.text_time < 0 or state.audio_position < 0 or state.background_alpha < 0 or state.background_alpha > 1:
		return null
	if state.mode == "choice":
		if state.phase != "choice" or not state.payload.get("options") is Array:
			return null
		for option in state.payload.options:
			if not option is Dictionary or not option.get("text") is String or not (option.get("target") is int or option.get("target") is float):
				return null
	elif state.mode != "idle":
		if not state.payload.get("content") is String:
			return null
		var tokens := StoryInlineParser.new().parse(state.payload.content)
		if state.token_index > tokens.size():
			return null
		if state.phase == "text" and (state.token_index == tokens.size() or tokens[state.token_index].type != "text"):
			return null
		var total := 0
		for token in tokens:
			if token.type == "text":
				total += int(token.visible_length)
		if state.visible_characters > total:
			return null
	return state
