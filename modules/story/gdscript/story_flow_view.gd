class_name StoryFlowView
extends VBoxContainer
## The .tscn owns fixed UI and the reusable card template. Runtime work binds
## real script files, reading history and graph edges; no editor code executes.

@export var node_scene: PackedScene
@export var node_gap := Vector2(92, 60)
@export var graph_margin := Vector2(34, 62)
@onready var canvas: StoryFlowCanvas = %Canvas
@onready var minimap: StoryFlowMinimap = %Minimap
@onready var details: VBoxContainer = %Details
@onready var search: LineEdit = %Search
@onready var chapter: OptionButton = %Chapter
@onready var zoom_label: Label = %ZoomLabel
@onready var progress_label: Label = %ProgressLabel
var presenter: StoryGalgamePresenter
var menus: StoryGalgameMenus
var skin: StorySkin
var only_marks := false
var selected := ""
var cards: Dictionary = {}
var positions: Dictionary = {}
var card_size := Vector2.ZERO
var no_results := false
var _lanes: Array[Label] = []
var _ending_numbers: Dictionary = {}
const STATUS_LABELS := {"current": "当前阅读", "read": "已读", "unread": "未读", "locked": "未解锁"}

func configure(host: StoryGalgamePresenter, owner_menus: StoryGalgameMenus) -> void:
	presenter = host
	menus = owner_menus
	skin = host.skin
	theme = skin.theme
	canvas.view = self
	minimap.view = self
	search.text_changed.connect(func(_text): _filter())
	chapter.item_selected.connect(func(_index): _filter())
	%Bookmarks.toggled.connect(func(value):
		only_marks = value
		%Bookmarks.icon = skin.icon("bookmark-filled" if value else "bookmark")
		_filter())
	%Locate.pressed.connect(_locate_current)
	%ClearFilters.pressed.connect(_locate_current)
	%ZoomOut.pressed.connect(func(): canvas.zoom_at(canvas.size / 2, canvas.zoom / 1.2))
	%ZoomIn.pressed.connect(func(): canvas.zoom_at(canvas.size / 2, canvas.zoom * 1.2))
	%Fit.pressed.connect(fit_graph)
	%Bookmark.pressed.connect(func():
		if not selected.is_empty() and status(selected) != "locked": presenter.archive.toggle_bookmark(selected))
	%Replay.pressed.connect(_request_replay)
	chapter.clear()
	chapter.add_item("全部章节")
	var chapters := {}
	var columns := {}
	for identity in presenter.library.nodes:
		var data: Dictionary = presenter.library.nodes[identity]
		chapters[data.chapter] = true
		if not columns.has(data.column): columns[data.column] = []
		columns[data.column].append(identity)
		if data.ending: _ending_numbers[identity] = _ending_numbers.size() + 1
		var card := node_scene.instantiate() as StoryFlowCard
		canvas.world.add_child(card)
		card_size = card.custom_minimum_size
		card.size = card_size
		card.pressed.connect(func():
			if not canvas.suppress_click: _select(identity))
		card.gui_input.connect(canvas.card_input.bind(card))
		cards[identity] = card
	for caption in chapters: chapter.add_item(caption)
	# Center each rank against the largest branch. Linear passages, splits and
	# joins share the same visual spine without hardcoding the demo's file IDs.
	var max_rows := 1
	for column in columns: max_rows = maxi(max_rows, columns[column].size())
	for column in columns:
		var identities: Array = columns[column]
		for row in identities.size():
			var identity: String = identities[row]
			positions[identity] = graph_margin + Vector2(float(column) * (card_size.x + node_gap.x), (row + (max_rows - identities.size()) / 2.0) * (card_size.y + node_gap.y))
			cards[identity].position = positions[identity]
		var lane := skin.label(String(presenter.library.nodes[identities[0]].get("lane", presenter.library.nodes[identities[0]].chapter)), 14, "muted")
		lane.position = Vector2(graph_margin.x + column * (card_size.x + node_gap.x), 24)
		lane.theme_type_variation = "StoryFlowMeta"
		lane.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.world.add_child(lane)
		_lanes.append(lane)
	presenter.archive.changed.connect(_archive_changed)
	selected = _current_identity()
	if not cards.has(selected) and not cards.is_empty(): selected = String(cards.keys()[0])
	_filter(false)
	fit_graph.call_deferred()

func status(identity: String) -> String:
	return presenter.archive.status(identity, presenter.library)

func _current_identity() -> String:
	if presenter.archive.player != null and presenter.archive.player.current_story != null:
		return presenter.archive.player.current_story.get_identity()
	return ""

func display_title(identity: String) -> String:
	if status(identity) != "locked": return String(presenter.library.nodes[identity].title)
	return "未解锁结局 %02d" % _ending_numbers[identity] if _ending_numbers.has(identity) else "未解锁剧情"

func _matches(identity: String) -> bool:
	var data: Dictionary = presenter.library.nodes[identity]
	var unlocked := status(identity) != "locked"
	var query := search.text.strip_edges()
	return (query.is_empty() or (unlocked and (String(data.title).containsn(query) or String(data.source).get_file().containsn(query)))) and (chapter.selected == 0 or data.chapter == chapter.get_item_text(chapter.selected)) and (not only_marks or presenter.archive.bookmarks.has(identity))

func _filter(center_match := true) -> void:
	var matches: Array[String] = []
	for identity in cards:
		var matches_filter := _matches(identity)
		cards[identity].set_match(matches_filter)
		if matches_filter: matches.append(identity)
	no_results = matches.is_empty()
	canvas.world.visible = not no_results
	%Empty.visible = no_results
	%EmptyText.text = "没有可显示的剧本" if cards.is_empty() else "没有匹配的剧本"
	%ZoomPanel.visible = not no_results
	minimap.visible = not no_results
	%DetailEmpty.visible = no_results
	%DetailContent.visible = not no_results
	if not no_results and not matches.has(selected): selected = matches[0]
	var visited := 0
	for identity in cards:
		if presenter.archive.progress.has(identity): visited += 1
	var filtered := not search.text.strip_edges().is_empty() or chapter.selected != 0 or only_marks
	progress_label.text = "%d / %d 份剧本" % [matches.size(), cards.size()] if filtered else "已读 %d / %d 份剧本" % [visited, cards.size()]
	_refresh()
	if not no_results:
		_show_details()
		if center_match: canvas.center_on(selected)

func _refresh() -> void:
	for identity in cards:
		var data: Dictionary = presenter.library.nodes[identity]
		var state := status(identity)
		cards[identity].bind_data(skin, {"state": state, "selected": identity == selected,
			"title": display_title(identity), "file": "剧情尚未揭晓" if state == "locked" else data.source.get_file(),
			"status_label": STATUS_LABELS[state], "bookmarked": presenter.archive.bookmarks.has(identity) and state != "locked"})
	canvas.refresh()

func update_skin() -> void:
	if presenter == null: return
	skin = presenter.skin
	theme = skin.theme
	skin.refresh_labels(self)
	_refresh()
	if not no_results: _show_details()

func _archive_changed() -> void:
	_filter(false)

func _select(identity: String) -> void:
	if not cards.has(identity): return
	selected = identity
	%DetailScroll.scroll_vertical = 0
	_refresh()
	_show_details()

func _show_details() -> void:
	if not presenter.library.nodes.has(selected): return
	var data: Dictionary = presenter.library.nodes[selected]
	var state := status(selected)
	var locked := state == "locked"
	var record: Dictionary = presenter.archive.progress.get(selected, {})
	var read_count := 0
	for key in data.reading_keys:
		if record.get("read", {}).get(key, false): read_count += 1
	%DetailStatus.text = STATUS_LABELS[state] + (" · 结局" if data.ending else "")
	%Bookmark.disabled = locked
	%Bookmark.set_pressed_no_signal(presenter.archive.bookmarks.has(selected) and not locked)
	%Bookmark.icon = skin.icon("bookmark-filled" if %Bookmark.button_pressed else "bookmark")
	%Bookmark.tooltip_text = "尚未解锁" if locked else ("移除剧本书签" if %Bookmark.button_pressed else "添加剧本书签")
	%DetailTitle.text = display_title(selected)
	%DetailFile.text = "剧本文件 · 未解锁" if locked else data.source.get_file()
	%DetailSummary.text = "继续探索故事后，这里的标题、剧本与内容将逐渐揭晓。" if locked else data.summary
	%ReadingProgress.visible = not locked
	%ReadProgress.max_value = maxi(1, data.total)
	%ReadProgress.value = read_count
	%ReadCount.text = "%d%% · %d/%d" % [roundi(100.0 * read_count / maxi(1, data.total)), read_count, data.total]
	_bind_preview(locked, record)
	_build_connections(locked)
	var visited := presenter.archive.progress.has(selected)
	%Replay.disabled = locked or (not visited and state != "current")
	%Replay.icon = skin.icon("play" if state == "current" else "restart")
	%Replay.text = "继续阅读" if state == "current" else ("尚未解锁" if locked else ("从此剧本重读" if visited else "阅读后可重访"))
	%ReplayNote.text = "回到当前对白" if state == "current" else ("从文件开头重读，保留已读记录与存档" if visited else "通过剧情中的选择到达此处")

func _bind_preview(locked: bool, record: Dictionary) -> void:
	%PreviewLock.visible = locked
	# Rasterize the SVG at its authored logical size instead of stretching the
	# smaller toolbar icon; DPITexture still handles viewport oversampling.
	%PreviewLock.texture = skin.icon("locked", roundi(%PreviewLock.size.x))
	%PreviewBackground.visible = not locked
	%PreviewPortrait.visible = false
	# Locked nodes never load or expose the asset paths in their snapshots.
	if locked:
		%PreviewBackground.texture = null
		%PreviewPortrait.texture = null
		return
	var visual: Dictionary = record.get("entry", {}).get("presentation", {})
	%PreviewBackground.texture = presenter.backdrop
	if status(selected) == "current":
		# Use the actual scene layers, not a viewport thumbnail which may have
		# been captured while another menu was still visible during navigation.
		%PreviewBackground.texture = presenter.background.texture
		%PreviewPortrait.texture = presenter.portrait.texture
		%PreviewPortrait.visible = presenter.portrait.visible and presenter.portrait.texture != null
		return
	var background_path := String(visual.get("background_path", ""))
	if not background_path.is_empty() and ResourceLoader.exists(background_path): %PreviewBackground.texture = load(background_path) as Texture2D
	var portrait_path := String(visual.get("portrait_path", ""))
	if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path):
		%PreviewPortrait.texture = load(portrait_path) as Texture2D
		%PreviewPortrait.visible = true

func _build_connections(locked: bool) -> void:
	for child in %Connections.get_children():
		%Connections.remove_child(child)
		child.queue_free()
	for direction in ["to", "from"]:
		var edges: Array[Dictionary] = []
		for edge in presenter.library.edges:
			if edge[direction] == selected: edges.append(edge)
		if edges.is_empty():
			if direction == "from": %Connections.add_child(skin.label("故事在此暂告一段落", 12, "muted"))
			continue
		%Connections.add_child(skin.label("从这里而来" if direction == "to" else "故事的去向", 12, "muted"))
		for edge in edges:
			var peer: String = edge.from if direction == "to" else edge.to
			var link := skin.button("", func():
				_select(peer)
				canvas.center_on(peer), Vector2(0, 56))
			link.flat = true
			link.set_meta("peer", peer)
			%Connections.add_child(link)
			var layout := VBoxContainer.new()
			layout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			layout.offset_left = 8
			layout.offset_right = -8
			layout.offset_top = 6
			layout.mouse_filter = Control.MOUSE_FILTER_IGNORE
			link.add_child(layout)
			for pair in [[display_title(peer), "ink", 14], ["条件尚未揭晓" if locked or status(peer) == "locked" else String(edge.label), "muted", 12]]:
				var label := skin.label(pair[0], pair[2], pair[1])
				label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				label.mouse_filter = Control.MOUSE_FILTER_IGNORE
				layout.add_child(label)
			link.tooltip_text = display_title(peer) + "\n" + layout.get_child(1).text

func _request_replay() -> void:
	if selected.is_empty() or status(selected) == "locked": return
	if selected == _current_identity():
		presenter.close_menu()
		return
	if not presenter.archive.progress.has(selected): return
	var target := selected
	menus.confirm("重读「%s」？" % display_title(target), "当前阅读位置将切换到这份剧本的开头。已有存档、书签和已读记录会保留。", func():
		if presenter.archive.replay_file(target) == OK: presenter.close_menu())

func _locate_current() -> void:
	search.text = ""
	chapter.select(0)
	only_marks = false
	%Bookmarks.set_pressed_no_signal(false)
	%Bookmarks.icon = skin.icon("bookmark")
	var identity := _current_identity()
	if cards.has(identity): selected = identity
	_filter(false)
	if cards.has(selected): canvas.center_on(selected)

func graph_bounds() -> Rect2:
	if positions.is_empty(): return Rect2(Vector2.ZERO, Vector2(202, 126))
	var bounds := Rect2(positions.values()[0], card_size)
	for position in positions.values(): bounds = bounds.merge(Rect2(position, card_size))
	return bounds.grow_individual(34, 44, 34, 34)

func fit_graph() -> void:
	if positions.is_empty(): return
	var bounds := graph_bounds()
	canvas.zoom = clampf(minf((canvas.size.x - 28) / bounds.size.x, (canvas.size.y - 110) / bounds.size.y), canvas.min_zoom, 1.0)
	canvas.pan = Vector2(canvas.size.x / 2, (canvas.size.y + 12) / 2) - bounds.get_center() * canvas.zoom
	canvas.refresh()
	for lane in _lanes: lane.add_theme_font_size_override("font_size", maxi(14, roundi(10.0 / canvas.zoom)))

func _input(event: InputEvent) -> void:
	# Follow explicit keyboard traversal, not focus restoration when Cherry
	# uncovers this route after a confirmation. Restoration preserves the pan.
	if event is InputEventKey and event.is_pressed() and is_visible_in_tree():
		for action in ["ui_focus_next", "ui_focus_prev", "ui_left", "ui_right", "ui_up", "ui_down"]:
			if event.is_action(action):
				_reveal_keyboard_focus.call_deferred()
				break

func _reveal_keyboard_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	for identity in cards:
		if cards[identity] == focused:
			canvas.center_on(identity)
			return
