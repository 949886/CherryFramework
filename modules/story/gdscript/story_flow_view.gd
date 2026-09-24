class_name StoryFlowView
extends VBoxContainer
## One card per reachable script identity. Layout, edges and progress come from
## the library/archive, never a hand-authored graph or a list of dialogue lines.

const CARD := Vector2(202, 112)
const PITCH := Vector2(262, 158)
var presenter: StoryGalgamePresenter
var menus: StoryGalgameMenus
var skin: StorySkin
var canvas: GraphCanvas
var minimap: MiniMap
var details: VBoxContainer
var search: LineEdit
var chapter: OptionButton
var only_marks := false
var selected := ""
var cards: Dictionary = {}
var positions: Dictionary = {}
var zoom_label: Label
var progress_label: Label

func configure(host: StoryGalgamePresenter, owner_menus: StoryGalgameMenus) -> void:
	presenter = host
	menus = owner_menus
	skin = host.skin
	add_theme_constant_override("separation", 14)
	var toolbar := HBoxContainer.new()
	toolbar.add_theme_constant_override("separation", 10)
	add_child(toolbar)
	search = LineEdit.new()
	search.placeholder_text = "搜索已解锁的剧本…"
	search.custom_minimum_size.x = 270
	search.text_changed.connect(func(_text): _filter())
	toolbar.add_child(search)
	chapter = OptionButton.new()
	chapter.add_item("全部章节")
	var chapters := {}
	for node in host.library.nodes.values(): chapters[node.chapter] = true
	for title in chapters: chapter.add_item(title)
	chapter.item_selected.connect(func(_index): _filter())
	toolbar.add_child(chapter)
	var marked := skin.button("☆ 书签", func():
		only_marks = not only_marks
		_filter())
	marked.toggle_mode = true
	toolbar.add_child(marked)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toolbar.add_child(spacer)
	progress_label = skin.label("", 14, "muted")
	toolbar.add_child(progress_label)
	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 18)
	add_child(split)
	canvas = GraphCanvas.new()
	canvas.view = self
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.clip_contents = true
	canvas.custom_minimum_size = Vector2(750, 350)
	split.add_child(canvas)
	var detail_scroll := ScrollContainer.new()
	detail_scroll.custom_minimum_size.x = 328
	detail_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(detail_scroll)
	details = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 14)
	detail_scroll.add_child(details)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	add_child(footer)
	footer.add_child(skin.button("−", func(): canvas.zoom_at(canvas.size / 2, canvas.zoom / 1.2), Vector2(38, 34)))
	zoom_label = skin.label("100%", 14, "muted")
	footer.add_child(zoom_label)
	footer.add_child(skin.button("＋", func(): canvas.zoom_at(canvas.size / 2, canvas.zoom * 1.2), Vector2(38, 34)))
	footer.add_child(skin.button("适应画布", fit_graph))
	footer.add_child(skin.button("定位当前", _locate_current))
	footer.add_child(skin.label("拖动画布 · 滚轮缩放    ● 当前   ✓ 已读   ○ 未读   ◇ 未解锁", 13, "muted"))
	for identity in host.library.nodes:
		var node: Dictionary = host.library.nodes[identity]
		positions[identity] = Vector2(node.column, node.row) * PITCH + Vector2(34, 34)
		var button := skin.button("", func(): _select(identity))
		button.size = CARD
		button.clip_contents = true
		canvas.add_child(button)
		cards[identity] = button
	minimap = MiniMap.new()
	minimap.view = self
	minimap.custom_minimum_size = Vector2(186, 88)
	minimap.size = Vector2(186, 88)
	canvas.add_child(minimap)
	canvas.resized.connect(func():
		minimap.position = canvas.size - minimap.size - Vector2(12, 12))
	_refresh()
	_locate_current.call_deferred()

func status(identity: String) -> String:
	return presenter.archive.status(identity, presenter.library)

func _refresh() -> void:
	var visited := 0
	for identity in cards:
		var state := status(identity)
		var node: Dictionary = presenter.library.nodes[identity]
		var button: Button = cards[identity]
		var unlocked := state != "locked"
		var symbol: String = {"current": "●", "read": "✓", "unread": "○", "locked": "◇"}[state]
		button.text = "%s  %s%s\n\n%s" % [symbol, node.title if unlocked else "尚未解锁", "  ☆" if presenter.archive.bookmarks.has(identity) else "", node.source.get_file() if unlocked else "继续故事，发现新的可能"]
		button.add_theme_font_size_override("font_size", 14)
		button.add_theme_stylebox_override("normal", StorySkin.box(skin.colors.soft if state == "current" else skin.colors.paper, skin.colors.accent if identity == selected else skin.colors.line, 12, 14))
		if presenter.archive.progress.has(identity): visited += 1
	progress_label.text = "已探索 %d / %d 份剧本" % [visited, cards.size()]
	canvas.refresh()

func _filter() -> void:
	for identity in cards:
		var node: Dictionary = presenter.library.nodes[identity]
		var unlocked := status(identity) != "locked"
		var matches_search := search.text.is_empty() or (unlocked and (String(node.title).containsn(search.text) or String(node.source).get_file().containsn(search.text)))
		var matches_chapter: bool = chapter.selected == 0 or (unlocked and node.chapter == chapter.get_item_text(chapter.selected))
		cards[identity].visible = matches_search and matches_chapter and (not only_marks or presenter.archive.bookmarks.has(identity))
	canvas.refresh()

func _select(identity: String) -> void:
	selected = identity
	for child in details.get_children():
		details.remove_child(child)
		child.queue_free()
	var node: Dictionary = presenter.library.nodes[identity]
	var state := status(identity)
	if state == "locked":
		details.add_child(skin.label("◇ 尚未解锁", 22))
		details.add_child(_wrapped("沿着故事继续前进，新的片段会在这里慢慢展开。", 16))
	else:
		details.add_child(skin.label(node.chapter, 13, "accent"))
		details.add_child(_wrapped(node.title, 24))
		var image := TextureRect.new()
		image.texture = presenter.backdrop
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		image.custom_minimum_size = Vector2(300, 126)
		image.clip_contents = true
		details.add_child(image)
		var snapshot: Dictionary = presenter.archive.progress.get(identity, {}).get("entry", {})
		var visual: Dictionary = snapshot.get("presentation", {})
		var portrait_path := String(visual.get("portrait_path", ""))
		if not portrait_path.is_empty() and ResourceLoader.exists(portrait_path):
			var portrait := presenter._texture(image, load(portrait_path) as Texture2D, Rect2(0, 4, 156, 265))
			portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		details.add_child(_wrapped(node.summary, 16))
		details.add_child(_wrapped(node.source.get_file(), 13))
		var read_count := int(presenter.archive.progress.get(identity, {}).get("read", {}).size())
		details.add_child(skin.label("已读 %d / %d 个片段" % [read_count, node.total], 14, "muted"))
		var bar := ProgressBar.new()
		bar.max_value = maxi(1, node.total)
		bar.value = read_count
		bar.custom_minimum_size.y = 8
		bar.show_percentage = false
		details.add_child(bar)
		details.add_child(skin.button("★ 移除书签" if presenter.archive.bookmarks.has(identity) else "☆ 添加书签", func():
			presenter.archive.toggle_bookmark(identity)
			_select(identity)
			_filter()))
		var replay := skin.button("从这份剧本重新阅读", func():
			menus.confirm("回到这份剧本？", "将回到首次进入该文件时的状态。当前未保存的进度将丢失。", func():
				if presenter.archive.replay_file(identity) == OK: presenter.close_menu()))
		replay.disabled = not presenter.archive.progress.has(identity)
		details.add_child(replay)
		for direction in ["from", "to"]:
			var peers := VBoxContainer.new()
			peers.add_child(skin.label("后续故事" if direction == "from" else "来自", 14, "muted"))
			for edge in presenter.library.edges:
				if edge[direction] != identity: continue
				var peer: String = edge.to if direction == "from" else edge.from
				var peer_node: Dictionary = presenter.library.nodes.get(peer, {})
				if peer_node.is_empty(): continue
				peers.add_child(skin.button("◇ 尚未解锁" if status(peer) == "locked" else peer_node.title, func():
					_select(peer)
					canvas.center_on(peer)))
			if peers.get_child_count() > 1: details.add_child(peers)
			else: peers.free()
	_refresh()

func _wrapped(text: String, font_size: int) -> Label:
	var label := skin.label(text, font_size)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _locate_current() -> void:
	if presenter.archive.player.current_story == null: return
	var identity := presenter.archive.player.current_story.get_identity()
	if cards.has(identity):
		_select(identity)
		canvas.center_on(identity)

func graph_bounds() -> Rect2:
	var bounds := Rect2(Vector2.ZERO, CARD)
	for identity in positions:
		if cards[identity].visible: bounds = bounds.merge(Rect2(positions[identity], CARD))
	return bounds.grow(24)

func fit_graph() -> void:
	var bounds := graph_bounds()
	canvas.zoom = clampf(minf(canvas.size.x / bounds.size.x, canvas.size.y / bounds.size.y), 0.25, 1.5)
	canvas.pan = canvas.size / 2 - bounds.get_center() * canvas.zoom
	canvas.refresh()

class GraphCanvas extends Control:
	var view: StoryFlowView
	var pan := Vector2(24, 24)
	var zoom := 1.0
	var dragging := false

	func refresh() -> void:
		for identity in view.cards:
			var card: Button = view.cards[identity]
			card.position = pan + view.positions[identity] * zoom
			card.scale = Vector2.ONE * zoom
		view.zoom_label.text = "%d%%" % roundi(zoom * 100)
		queue_redraw()
		if is_instance_valid(view.minimap): view.minimap.queue_redraw()

	func center_on(identity: String) -> void:
		pan = size / 2 - (view.positions[identity] + CARD / 2) * zoom
		refresh()

	func zoom_at(point: Vector2, next: float) -> void:
		next = clampf(next, 0.25, 1.75)
		pan = point - (point - pan) * next / zoom
		zoom = next
		refresh()

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			if event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]: dragging = event.pressed
			if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
				zoom_at(event.position, zoom * (1.15 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.15))
			accept_event()
		elif event is InputEventMouseMotion and dragging:
			pan += event.relative
			refresh()
			accept_event()

	func _draw() -> void:
		draw_style_box(StorySkin.box(view.skin.colors.soft, view.skin.colors.line, 14), Rect2(Vector2.ZERO, size))
		for x in range(0, int(size.x), 24):
			for y in range(0, int(size.y), 24): draw_circle(Vector2(x, y), 0.8, view.skin.colors.line)
		for edge in view.presenter.library.edges:
			if not view.cards.has(edge.from) or not view.cards.has(edge.to): continue
			if not view.cards[edge.from].visible or not view.cards[edge.to].visible: continue
			var start: Vector2 = pan + (view.positions[edge.from] + Vector2(CARD.x, CARD.y / 2)) * zoom
			var end: Vector2 = pan + (view.positions[edge.to] + Vector2(0, CARD.y / 2)) * zoom
			var points := PackedVector2Array()
			for step in range(33):
				var t := float(step) / 32
				points.append(start.bezier_interpolate(start + Vector2(48, 0) * zoom, end - Vector2(48, 0) * zoom, end, t))
			draw_polyline(points, view.skin.colors.accent if view.status(edge.to) in ["read", "current"] else view.skin.colors.muted, 1.6, true)
			draw_circle(end, 3, view.skin.colors.accent)

class MiniMap extends Control:
	var view: StoryFlowView

	func _draw() -> void:
		draw_style_box(StorySkin.box(view.skin.colors.paper, view.skin.colors.line, 8), Rect2(Vector2.ZERO, size))
		var bounds := view.graph_bounds()
		var factor := minf((size.x - 16) / bounds.size.x, (size.y - 16) / bounds.size.y)
		for identity in view.positions:
			if view.cards[identity].visible:
				draw_rect(Rect2((view.positions[identity] - bounds.position) * factor + Vector2(8, 8), CARD * factor), view.skin.colors.accent if identity == view.selected else view.skin.colors.line)
		var visible_bounds := Rect2(-view.canvas.pan / view.canvas.zoom, view.canvas.size / view.canvas.zoom)
		var rect := Rect2((visible_bounds.position - bounds.position) * factor + Vector2(8, 8), visible_bounds.size * factor).intersection(Rect2(Vector2.ZERO, size))
		draw_rect(rect, view.skin.colors.accent, false, 1)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var bounds := view.graph_bounds()
			var factor := minf((size.x - 16) / bounds.size.x, (size.y - 16) / bounds.size.y)
			var point: Vector2 = (event.position - Vector2(8, 8)) / factor + bounds.position
			view.canvas.pan = view.canvas.size / 2 - point * view.canvas.zoom
			view.canvas.refresh()
			accept_event()
