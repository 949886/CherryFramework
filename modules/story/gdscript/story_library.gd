class_name StoryLibrary
extends RefCounted
## Reachable script files form the graph. Local headings and translated files
## are not duplicate nodes. Discovery is bounded and handles joins and cycles.

var nodes: Dictionary = {}
var edges: Array[Dictionary] = []
var errors: PackedStringArray = []
var limit := 256

func build(entry: Story, locale: String, descriptions: Dictionary = {}) -> void:
	nodes.clear()
	edges.clear()
	errors.clear()
	if entry == null:
		return
	var queue: Array[Story] = [entry]
	var queued := {entry.get_identity(): true}
	var ranks := {entry.get_identity(): 0}
	var rank_rows := {}
	while not queue.is_empty() and nodes.size() < limit:
		var story: Story = queue.pop_front()
		var identity := story.get_identity()
		var program := story.compile(locale)
		if program == null:
			errors.append("无法编译剧本：" + story.get_source_path(locale))
			continue
		var rank := int(ranks.get(identity, 0))
		var description: Dictionary = descriptions.get(story.get_story_id(), {})
		var total := 0
		var reading_keys: Array[String] = []
		for instruction in program.instructions:
			if is_readable(instruction):
				total += 1
				reading_keys.append(reading_key(instruction))
		nodes[identity] = {
			"identity": identity, "story": story, "source": program.source_path,
			"title": description.get("title", story.get_story_id()),
			"chapter": description.get("chapter", "故事"),
			"lane": description.get("lane", description.get("chapter", "故事")),
			"reading_keys": reading_keys,
			"summary": description.get("summary", ""),
			"ending": description.get("ending", false),
			"column": rank, "row": int(rank_rows.get(rank, 0)), "total": total,
		}
		rank_rows[rank] = int(rank_rows.get(rank, 0)) + 1
		var choice_labels := _choice_labels(program)
		for instruction_index in program.instructions.size():
			var instruction: Dictionary = program.instructions[instruction_index]
			if instruction.op != StoryProgram.Op.JMP or not instruction.data is Dictionary:
				continue
			var address: Dictionary = instruction.data
			var destination := String(address.get("story", ""))
			if destination.is_empty() or destination == program.story_id:
				continue
			var target := story.resolve_story(destination)
			if target == null:
				errors.append("缺少目标剧本：" + destination)
				continue
			var target_id := target.get_identity()
			var duplicate := false
			for edge in edges:
				if edge.from == identity and edge.to == target_id:
					duplicate = true
			if not duplicate:
				edges.append({"from": identity, "to": target_id, "label": String(choice_labels.get(instruction_index, "继续故事"))})
			if not queued.has(target_id):
				queued[target_id] = true
				ranks[target_id] = rank + 1
				queue.append(target)
	if not queue.is_empty():
		errors.append("流程图超出文件数量上限 %d。" % limit)

static func is_readable(instruction: Dictionary) -> bool:
	return int(instruction.get("op", -1)) in [StoryProgram.Op.DIA, StoryProgram.Op.NAR, StoryProgram.Op.CHO] and not bool(instruction.get("data", {}).get("silent", false))

static func reading_key(instruction: Dictionary) -> String:
	# Exact source is included: edited text becomes unread even if its SID is stable.
	return (String(instruction.get("sid", "")) + "|" + String(instruction.get("exact_signature", ""))).sha256_text()

static func _choice_labels(program: StoryProgram) -> Dictionary:
	# Option targets and their compiler-emitted join jumps delimit branch bodies.
	# Read the compiled program rather than reparsing translated source text.
	var labels := {}
	for instruction in program.instructions:
		if instruction.op != StoryProgram.Op.CHO: continue
		var options: Array = instruction.data.options
		var join := program.instructions.size()
		if options.size() > 1:
			var end_jump: Dictionary = program.instructions[int(options[1].target) - 1]
			if end_jump.op == StoryProgram.Op.JMP and end_jump.data is int: join = end_jump.data
		for index in options.size():
			var start := int(options[index].target)
			var end := int(options[index + 1].target) if index + 1 < options.size() else join
			for ip in range(start, mini(end, program.instructions.size())):
				var step: Dictionary = program.instructions[ip]
				if step.op == StoryProgram.Op.JMP and step.data is Dictionary:
					labels[ip] = String(options[index].text)
				elif options.size() == 1 and step.op == StoryProgram.Op.JMP and step.data is int: break
	return labels
