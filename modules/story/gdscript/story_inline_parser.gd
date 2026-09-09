class_name StoryInlineParser
extends RefCounted
## Parses presentation commands embedded in DIA/NAR content.
##
## It is intentionally separate from StoryParser: these tokens never become
## StoryProgram opcodes.  Example:
##   [audio:res://voice.wav]Hello[wait:3s]**world**[i]
## becomes text/command tokens consumed only by StoryPresenter.


func parse(content: String) -> Array[Dictionary]:
	var tokens: Array[Dictionary] = []
	var cursor := 0

	while cursor < content.length():
		var open := content.find("[", cursor)
		if open < 0:
			_append_text(tokens, content.substr(cursor))
			break

		if open > cursor:
			_append_text(tokens, content.substr(cursor, open - cursor))

		var close := content.find("]", open + 1)
		if close < 0:
			# StoryParser normally catches this.  Treat the remainder as text so a
			# runtime error does not destroy the whole UI if hot-reloaded badly.
			_append_text(tokens, content.substr(open))
			break

		var body := content.substr(open + 1, close - open - 1)
		body = body.replace("\\:", ":") # Accept Markdown-style escaped colon.
		tokens.append(_parse_command(body))
		cursor = close + 1

	return tokens


func _append_text(tokens: Array[Dictionary], text: String) -> void:
	if text.is_empty():
		return
	tokens.append({
		"type": "text",
		"source": text,
		"bbcode": markdown_to_bbcode(text),
		# `**` is formatting syntax and therefore does not count as visible
		# characters for the typewriter cursor.
		"visible_length": text.replace("**", "").length(),
	})


func _parse_command(body: String) -> Dictionary:
	var name := body
	var argument := ""
	var attributes := {}
	var colon := body.find(":")
	if colon >= 0:
		name = body.substr(0, colon)
		var tail := body.substr(colon + 1)
		var pieces := tail.split("|")
		if not pieces.is_empty():
			argument = String(pieces[0])
		for i in range(1, pieces.size()):
			var piece := String(pieces[i])
			var equals := piece.find("=")
			if equals > 0:
				attributes[piece.substr(0, equals)] = piece.substr(equals + 1)

	return {
		"type": "command",
		"name": name.to_lower(),
		"argument": argument,
		"attributes": attributes,
	}


func markdown_to_bbcode(text: String) -> String:
	## Minimal Markdown -> BBCode conversion required by the example.
	## It intentionally converts only **bold** for now; `[i]` is reserved as the
	## engine's wait-for-input command, so Markdown `*italic*` can be added later
	## without conflicting with RichTextLabel's [i] BBCode tag.
	var output := ""
	var cursor := 0
	var bold_open := false
	while cursor < text.length():
		var marker := text.find("**", cursor)
		if marker < 0:
			output += text.substr(cursor)
			break
		output += text.substr(cursor, marker - cursor)
		output += "[/b]" if bold_open else "[b]"
		bold_open = not bold_open
		cursor = marker + 2

	# If the author forgot to close **, keep RichTextLabel's tag stack valid.
	if bold_open:
		output += "[/b]"
	return output
