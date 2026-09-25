@tool
extends Node
## Read-only 2D editor previews. Reuse the real page builders with a detached,
## in-memory presenter; never configure a player, navigator, audio or archive.
## Generated nodes have no owner and authored properties are restored before
## saving, so opening a scene cannot bake preview content into the game.

@export_enum("presenter", "menu", "dialogue", "choice", "slot", "confirm") var kind := "dialogue"
@export_group("Preview data (editor only)")
@export_multiline var dialogue_text := "欢迎回来！今天也有许多想和你分享的事情。\n让我们从这一页，继续书写故事吧。"
@export var speaker := "角色"
@export var roman := "CHARACTER"
@export var options := PackedStringArray(["听听今天的故事", "说说自己的心情", "再一起待一会儿"])
@export_enum("text", "reading", "sound", "display", "system") var settings_section := "text"
@export var background: Texture2D
@export var portrait: Texture2D
## Keys/values use galgame_settings.json, e.g. {"palette": "mint", "glass": true}.
@export var settings: Dictionary = {}

var _saved: Array[Dictionary] = []
var _generated: Array[Node] = []
var _context: StoryGalgamePresenter
var _menus: StoryGalgameMenus
var _context_nodes: Array[Node] = []
var _signature := 0
var _clock := 0.0
var _saving := false
var _queued := false
var _built := false
var _enabled := false
var _signals: Array[Dictionary] = []

func _ready() -> void:
	if not Engine.is_editor_hint():
		set_process(false)
		return
	# The outer preview owns nested components as a unit. Otherwise a dialogue
	# helper could overwrite the presenter's character or snapshot it twice.
	var ancestor := get_parent().get_parent()
	while ancestor != null:
		if ancestor.has_node("EditorPreview"):
			set_process(false)
			return
		ancestor = ancestor.get_parent()
	_enabled = true
	_queue_refresh()

func _notification(what: int) -> void:
	if not _enabled: return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		_saving = true
		_restore()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_saving = false
		_queue_refresh()

func _process(delta: float) -> void:
	if not Engine.is_editor_hint() or _saving: return
	_clock += delta
	if _clock < 0.25: return
	_clock = 0
	var signature := _current_signature()
	if signature != _signature:
		_signature = signature
		_queue_refresh()
	if kind == "presenter" and _built: _layout_options()

func _current_signature() -> int:
	var values: Array = [kind, dialogue_text, speaker, roman, options, settings_section, background, portrait, settings]
	if kind == "presenter":
		var host := get_parent() as StoryGalgamePresenter
		values.append_array([host.backdrop, host.game_title, host.footer_caption, host.choice_scene])
		for character in host.characters:
			if character == null: continue
			values.append_array([character.id, character.display_name, character.default_state])
			for state in character.states:
				if state != null: values.append_array([state.id, state.portrait])
	return hash(values)

func _queue_refresh() -> void:
	if not _enabled or _queued or not is_inside_tree() or _saving: return
	_queued = true
	_refresh.call_deferred()

func _remember(node: Object, property: String, value: Variant) -> void:
	_saved.append({"node": node, "property": property, "before": node.get(property), "after": value})
	node.set(property, value)

func _snapshot(root: Node) -> void:
	# Capture just presentation properties. Runtime containers may calculate
	# their child rectangles normally; those rectangles are not preview data.
	if root is Control:
		for property in root.get_property_list():
			var key := String(property.name)
			if key in ["theme", "material", "text", "icon", "texture", "visible", "self_modulate", "disabled"] or key.begins_with("theme_override_"):
				_saved.append({"node": root, "property": key, "before": root.get(key)})
	for child in root.get_children(): _snapshot(child)

func _finish_snapshot() -> void:
	for item in _saved:
		if not item.has("after"): item.after = item.node.get(item.property)
		if item.after is StyleBox or item.after is ShaderMaterial:
			item.resource_values = _resource_values(item.after)

func _resource_values(resource: Resource) -> Dictionary:
	var values := {}
	for property in resource.get_property_list():
		if property.usage & PROPERTY_USAGE_STORAGE and property.name != "shader_parameter/panel_size":
			values[property.name] = resource.get(property.name)
	return values

func _restore() -> void:
	_built = false
	for connection in _signals:
		if is_instance_valid(connection.signal.get_object()) and connection.signal.is_connected(connection.callable):
			connection.signal.disconnect(connection.callable)
	_signals.clear()
	for node in _generated:
		if is_instance_valid(node):
			node.get_parent().remove_child(node)
			node.queue_free()
	_generated.clear()
	# Do not undo a designer's edit made since the preview was applied.
	_saved.reverse()
	for item in _saved:
		if is_instance_valid(item.node) and item.node.get(item.property) == item.get("after"):
			var restored: Variant = item.before
			if item.has("resource_values"):
				var changes := {}
				for key in item.resource_values:
					if item.after.get(key) != item.resource_values[key]: changes[key] = item.after.get(key)
				if not changes.is_empty():
					# The Inspector can edit a StyleBox in place without changing its
					# identity. Carry those edits back to the authored resource only.
					restored = (item.before if item.before is Resource else item.after).duplicate()
					for key in changes: restored.set(key, changes[key])
			item.node.set(item.property, restored)
	_saved.clear()
	if _context != null:
		_context.free()
		_context = null
	if _menus != null:
		_menus.free()
		_menus = null
	for node in _context_nodes:
		if is_instance_valid(node): node.free()
	_context_nodes.clear()

func _exit_tree() -> void:
	if Engine.is_editor_hint(): _restore()

func _refresh() -> void:
	_queued = false
	if not is_inside_tree() or _saving: return
	_restore()
	var host: Variant = get_parent()
	if not host is Control: return
	var preferences := StoryPreferences.new()
	preferences.persistence_enabled = false
	for key in settings: preferences.set_value(key, settings[key], false)
	var skin := StorySkin.new(preferences)
	_snapshot(host)
	# Keep the authored Theme resource directly inspectable in the default
	# preview. Only simulated player settings need a temporary recolored copy.
	if settings.is_empty() and host.theme != null:
		skin.theme = host.theme
	else:
		host.theme = skin.theme
	skin.refresh_labels(host)
	match kind:
		"presenter": _presenter(host as StoryGalgamePresenter, skin)
		"menu": _menu(host as StoryMenuPage, skin)
		"dialogue": _dialogue(host as StoryDialogueBox, skin)
		"choice":
			var choice := host as StoryChoiceButton
			choice.configure(skin)
			choice.reveal = 1.0
			choice.advance_visuals(0)
			choice.icon = skin.icon("chevron-right")
			if choice.text == "选项": choice.text = "01    选择想要继续的故事"
		"slot":
			host.get_node("Content/Title").text = "SLOT 01"
			host.get_node("Content/Text").text = "故事的一页"
			host.get_node("Content/Stamp").text = "编辑预览 · 示例记录"
			host.get_node("Content/Image").texture = background
		"confirm":
			host.get_node("Card/Content/Message").text = "继续这个操作吗？这里将显示具体的确认内容。"
			host.get_node("Card/Content/Buttons/Cancel").icon = skin.icon("close")
			host.get_node("Card/Content/Buttons/Confirm").icon = skin.icon("check")
	if kind in ["menu", "confirm"]:
		# Menus live in a 1280x720 game canvas, not the project window's size.
		for key in ["anchor_left", "anchor_top", "anchor_right", "anchor_bottom", "offset_left", "offset_top", "offset_right", "offset_bottom"]:
			_remember(host, key, 1280.0 if key == "offset_right" else (720.0 if key == "offset_bottom" else 0.0))
	_finish_snapshot()
	_signature = _current_signature()
	_built = true

func _dialogue(box: StoryDialogueBox, skin: StorySkin) -> void:
	if box.text.text.is_empty(): box.text.text = dialogue_text
	box.speaker.text = speaker
	box.roman.text = roman
	box.voice.text = roman
	box.apply_skin(skin)

func _presenter(host: StoryGalgamePresenter, skin: StorySkin) -> void:
	host.stage.theme = skin.theme
	host.brand_label.text = host.game_title
	host.caption_label.text = host.footer_caption
	var brand_icon: TextureRect = host.brand_label.get_parent().get_node("Icon")
	brand_icon.texture = skin.icon("cherry", int(brand_icon.custom_minimum_size.x))
	host.background.texture = background if background != null else host.backdrop
	if portrait != null: host.portrait.texture = portrait
	elif not host.characters.is_empty():
		var character := host.characters[0]
		for state in character.states:
			if state.id == character.default_state:
				host.portrait.texture = state.portrait
				break
		if speaker == "角色": host.dialogue.speaker.text = character.display_name
		if roman == "CHARACTER": host.dialogue.roman.text = String(character.id).to_upper()
	host.dialogue.text.text = dialogue_text
	host.dialogue.voice.text = host.dialogue.roman.text
	host.dialogue.apply_skin(skin)
	for box in [host.dialogue, host.narration]:
		_remember(box, "offset_top", box.offset_bottom - box.fitted_height(skin.preferences.values, box.size.y))
	host.location_label.text = "章节 / 场景预览"
	for i in options.size():
		var button := host.choice_scene.instantiate() as StoryChoiceButton
		host.choices_panel.add_child(button)
		_generated.append(button)
		button.text = "%02d    %s" % [i + 1, options[i]]
		button.icon = skin.icon("chevron-right")
		button.configure(skin)
		button.reveal = 1
		button.advance_visuals(0)
	host.choices_panel.visible = not options.is_empty()
	host.choice_scroll.visible = not options.is_empty()
	# Keep the user's horizontal anchors; only preview the dynamic vertical fit.
	_remember(host.choice_scroll, "offset_top", host.choice_scroll.offset_top)
	_remember(host.choice_scroll, "offset_bottom", host.choice_scroll.offset_bottom)
	_layout_options()

func _layout_options() -> void:
	var host := get_parent() as StoryGalgamePresenter
	if host == null: return
	var bottom := host.dialogue.position.y - host.choice_gap
	host.choice_scroll.offset_bottom = bottom
	host.choice_scroll.offset_top = bottom - minf(host.choices_panel.get_combined_minimum_size().y, maxf(0, bottom - host.choice_top_margin))
	for item in _saved:
		if item.node == host.choice_scroll and item.property in ["offset_top", "offset_bottom"]:
			item.after = host.choice_scroll.get(item.property)

func _menu(page: StoryMenuPage, skin: StorySkin) -> void:
	_context = StoryGalgamePresenter.new()
	_context.skin = skin
	_context.preferences = skin.preferences
	_context.stage = Control.new()
	_context.stage.size = Vector2(1280, 720)
	_context.background = TextureRect.new()
	_context.background.texture = background
	_context.portrait = TextureRect.new()
	_context.portrait.texture = portrait
	_context.portrait.position = Vector2(12, 36)
	_context.portrait.size = Vector2(614, 1044)
	_context.dialogue = load(get_script().resource_path.get_base_dir().path_join("../scenes/galgame/dialogue_box.tscn")).instantiate()
	_context.dialogue.position = Vector2(42, 481)
	_context.dialogue.size = Vector2(1196, 185)
	_context.dialogue.size.y = _context.dialogue.fitted_height(skin.preferences.values, 185)
	_context.dialogue.position.y = 720 - 54 - _context.dialogue.size.y
	_context.dialogue.text.text = dialogue_text
	_context.dialogue.speaker.text = speaker
	_context.dialogue.roman.text = roman
	_context.narration = _context.dialogue
	_context_nodes.assign([_context.stage, _context.background, _context.portrait, _context.dialogue])
	# Deliberately synthetic data: never open the user's profile, save slots or
	# compile a story merely because a scene is opened in the editor.
	_context.archive.history.assign([
		{"kind": "dialogue", "speaker": speaker, "text": dialogue_text, "voice": ""},
		{"kind": "choice", "speaker": "你的选择", "text": options[0] if not options.is_empty() else "继续故事", "voice": ""},
	])
	for index in 3:
		var identity := "preview_%d" % index
		_context.library.nodes[identity] = {"title": "故事的开始" if index == 0 else "分支 %d" % index,
			"source": "chapter_%02d.story" % index, "chapter": "预览章节", "summary": dialogue_text,
			"total": 4, "column": mini(index, 1), "row": maxi(index - 1, 0)}
		if index > 0: _context.library.edges.append({"from": "preview_0", "to": identity})
	_context.archive.progress["preview_0"] = {"entry": {}, "read": {"sample": true}}
	_menus = StoryGalgameMenus.new()
	_menus.presenter = _context
	_menus.skin = skin
	_menus.section_id = settings_section
	page.configure(_menus)
	# Track newly built, ownerless roots even when they sit under authored tabs
	# or slot grids. Keep the hierarchy bounded to avoid duplicates on refresh.
	var before: Array[Node] = []
	_collect(page, before)
	var original_connections: Array[Dictionary] = []
	for node in before:
		if node is BaseButton: original_connections.append_array(node.pressed.get_connections())
	page._built_sections.clear()
	page._tab_buttons.clear()
	page._previews.clear()
	page._preview_fits.clear()
	page.rows.clear()
	page.fields.clear()
	page._controls.clear()
	page._numbers.clear()
	page._slot_cards.clear()
	page._slot_buttons.clear()
	page.build_content()
	for node in before:
		if node is BaseButton:
			for connection in node.pressed.get_connections():
				if connection not in original_connections: _signals.append(connection)
	if page.page == "flow":
		var graph := page.body.get_child(0) as StoryFlowView
		graph._select("preview_0")
		graph.fit_graph.call_deferred()
	var after: Array[Node] = []
	_collect(page, after)
	for node in after:
		if node not in before and node.get_parent() in before: _generated.append(node)

func _collect(node: Node, output: Array[Node]) -> void:
	output.append(node)
	for child in node.get_children(): _collect(child, output)
