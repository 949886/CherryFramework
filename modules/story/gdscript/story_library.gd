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
		for instruction in program.instructions:
			if is_readable(instruction):
				total += 1
		nodes[identity] = {
			"identity": identity, "story": story, "source": program.source_path,
			"title": description.get("title", story.get_story_id()),
			"chapter": description.get("chapter", "故事"),
			"summary": description.get("summary", ""),
			"ending": description.get("ending", false),
			"column": rank, "row": int(rank_rows.get(rank, 0)), "total": total,
		}
		rank_rows[rank] = int(rank_rows.get(rank, 0)) + 1
		for instruction in program.instructions:
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
				edges.append({"from": identity, "to": target_id, "label": String(address.get("label", ""))})
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
