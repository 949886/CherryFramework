class_name StoryProgram
extends RefCounted
## StoryProgram is the compact IR consumed by StoryVM.
##
## The instruction set deliberately stays tiny. Presentation details such as
## [wait], [audio], [save], background changes and popup images are *not*
## opcodes. They remain inside DIA/NAR content and are interpreted by the
## presentation layer.
##
## Save-position identity has two independent layers:
## 1. `sid` keeps the old stable-ID system and is always the strongest locator.
## 2. `exact_signature` is a strict compiler-generated source signature used by
##    the position-based save resolver when a SID no longer resolves.

enum Op {
	DIA, # Dialogue: speaker + state + inline-rich text.
	NAR, # Narration/article, also used for silent presentation-only content.
	CHO, # Choice: an array of labels and destination instruction indices.

	JIF, # Jump if a generated GDScript condition returns false.
	JMP, # Unconditional jump, either local or to another story file.

	EXE, # Execute a generated GDScript method.
	END, # End the current story.
}

## Human-readable logical story key, e.g. "mahiro".
var story_id: String = ""

## Source markdown file used to build this program.
var source_path: String = ""

## Array[Dictionary]. Each dictionary has at least:
## {
##     "op": Op.*,
##     "sid": String,
##     "sid_explicit": bool,
##     "exact_signature": String,
##     "data": Variant,
## }
var instructions: Array[Dictionary] = []

## Stable story id -> runtime instruction index.
##
## The old SID system intentionally remains supported. Explicit @sid comments
## are useful for important compatibility points and for the current
## cross-language demo. Instructions without explicit SIDs still receive the
## existing content-derived automatic SID.
var sid_to_ip: Dictionary = {}

## Heading label -> runtime instruction index.
## Headings are jump targets, but they are not used as the save position.
var labels: Dictionary = {}

## Source for the dynamically generated GDScript class.
var generated_gdscript_source: String = ""

## Names of top-level `var` declarations found in the author GDScript block.
## These are the story-local fields captured by save/load.
var save_variables: Array[StringName] = []

## Compiled dynamic script and the current per-story runtime instance.
var runtime_script: GDScript
var runtime: Object


func add_instruction(
	op: Op,
	sid: String,
	data: Variant = null,
	exact_signature: String = "",
	sid_explicit: bool = false
) -> int:
	## Adds an instruction and returns its numeric runtime address.
	## Numeric addresses are deliberately valid only for the currently compiled
	## StoryProgram; save files verify them before trusting them.
	var ip := instructions.size()
	instructions.append({
		"op": op,
		"sid": sid,
		"sid_explicit": sid_explicit,
		"exact_signature": exact_signature,
		"data": data,
	})
	if not sid.is_empty():
		sid_to_ip[sid] = ip
	return ip


func resolve_sid(sid: String) -> int:
	return int(sid_to_ip.get(sid, -1))


func resolve_label(label: String) -> int:
	return int(labels.get(label, -1))


func create_runtime(host: Object = null) -> Error:
	## Compile and instantiate the generated GDScript.
	##
	## This is real GDScript: Godot parses/compiles generated_gdscript_source.
	## A single runtime object is kept for the whole story file, so top-level
	## fields such as `tire` and `mahiro_favorability` are shared by every JIF
	## and EXE thunk generated from that story.
	runtime_script = GDScript.new()
	runtime_script.source_code = generated_gdscript_source
	var err := runtime_script.reload()
	if err != OK:
		push_error("Generated GDScript failed to compile for %s (error %s).\n%s" % [story_id, err, generated_gdscript_source])
		return err

	if not runtime_script.can_instantiate():
		push_error("Generated GDScript cannot be instantiated for story: %s" % story_id)
		return ERR_CANT_CREATE

	runtime = runtime_script.new()
	if runtime == null:
		return ERR_CANT_CREATE

	# __gal_host is a reserved bridge to the engine host. Story authors can
	# call __gal_host.some_method() from trusted GDScript when needed.
	if runtime.get("__gal_host") != null or _script_has_property("__gal_host"):
		runtime.set("__gal_host", host)
	return OK


func _script_has_property(property_name: String) -> bool:
	if runtime_script == null:
		return false
	for property_info in runtime_script.get_script_property_list():
		if String(property_info.get("name", "")) == property_name:
			return true
	return false
