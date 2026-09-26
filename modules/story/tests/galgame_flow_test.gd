extends SceneTree
## Native graph interaction regressions. All archives stay in an isolated
## user directory; pointer events travel through the viewport's real GUI path.

var checks := 0
var failures := 0
var module_root := (get_script() as Script).resource_path.get_base_dir().get_base_dir()
var presenter: StoryGalgamePresenter
var flow: StoryFlowView

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func settle() -> void:
	for i in range(4): await process_frame

func pointer(point: Vector2, button: MouseButton, pressed: bool) -> void:
	# Godot caches the hovered Control on motion, as a physical pointer does
	# when moving between a graph card, toolbar and the minimap.
	if pressed:
		var hover := InputEventMouseMotion.new()
		hover.position = point
		hover.global_position = point
		root.push_input(hover, true)
	var event := InputEventMouseButton.new()
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	root.push_input(event, true)

func motion(point: Vector2, relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	event.global_position = point
	event.relative = relative
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	root.push_input(event, true)

func capture(name: String) -> void:
	await settle()
	if "--render" in OS.get_cmdline_user_args():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("user://flow-" + name + ".png")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	root.content_scale_size = root.size
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var scene: Control = load(module_root.path_join("examples/galgame_demo.tscn")).instantiate()
	presenter = scene.get_node("Presenter")
	presenter.save_directory = "user://galgame_flow_test_%d" % OS.get_process_id()
	root.add_child(scene)
	await settle()
	presenter.preferences.set_value("instant", true)
	presenter.preferences.set_value("motion", "reduced")
	for i in range(12):
		if presenter._state.mode == "choice": break
		presenter.advance_time(5)
		presenter.advance()
		await settle()
	presenter.open_menu("flow")
	await settle()
	flow = presenter.menu.active_page.body.get_child(0)
	var current := presenter.archive.player.current_story.get_identity()
	var previous := ""
	var locked := ""
	for identity in flow.cards:
		if flow.status(identity) == "read": previous = identity
		if flow.status(identity) == "locked": locked = identity
	check(flow.cards.size() == presenter.library.nodes.size(), "one persistent card per script file")
	check(flow.selected == current, "current script selected on opening")
	check(flow.get_node("%PreviewBackground").texture == presenter.background.texture, "preview uses actual scene background")
	check(flow.get_node("%PreviewPortrait").texture == presenter.portrait.texture, "preview uses actual scene portrait")
	check(flow.get_node("%Replay").text == "继续阅读", "current node offers resume")
	var labels: Array[String] = []
	for edge in presenter.library.edges:
		if edge.from == current: labels.append(edge.label)
	check(labels == ["先吃饭", "去洗澡", "当然选真寻酱"], "branch captions come from compiled choices")
	await capture("overview")
	var cards := flow.cards.duplicate()
	var positions := flow.positions.duplicate()
	flow.search.text = presenter.library.nodes[current].source.get_file()
	flow.search.text_changed.emit(flow.search.text)
	check(flow.selected == current and flow.cards[current].modulate.a == 1.0, "filename search finds current script")
	check(flow.cards[previous].modulate.a < 0.5 and flow.cards[previous].visible, "nonmatching route context remains visible but dimmed")
	check(flow.cards == cards and flow.positions == positions, "search retains card identity and graph geometry")
	flow.search.text = "no-such-script"
	flow.search.text_changed.emit(flow.search.text)
	check(flow.no_results and not flow.canvas.world.visible and not flow.minimap.visible, "no results hides graph and minimap")
	check(flow.get_node("%DetailEmpty").visible and not flow.get_node("%DetailContent").visible, "no results clears detail content")
	await capture("empty")
	flow.get_node("%ClearFilters").pressed.emit()
	check(not flow.no_results and flow.selected == current and flow.search.text.is_empty(), "clear filters restores current script")
	flow.get_node("%Bookmark").pressed.emit()
	flow.get_node("%Bookmarks").button_pressed = true
	check(flow.cards[current].matched and not flow.cards[previous].matched, "bookmark filter follows persistent archive")
	flow._locate_current()
	check(not flow.only_marks and flow.chapter.selected == 0, "locate resets active filters")
	flow._select(locked)
	check(flow.get_node("%DetailFile").text == "剧本文件 · 未解锁", "locked file path concealed")
	check(flow.get_node("%PreviewBackground").texture == null and flow.get_node("%PreviewPortrait").texture == null, "locked preview cannot expose saved assets")
	check(flow.get_node("%Bookmark").disabled and flow.get_node("%Replay").disabled, "locked actions disabled")
	check(flow.get_node("%DetailTitle").text != presenter.library.nodes[locked].title, "locked title concealed")
	await capture("locked")
	flow._select(current)
	var record: Dictionary = presenter.archive.progress[current]
	var read_count: float = flow.get_node("%ReadProgress").value
	record.read["stale-key-from-old-script"] = true
	flow._show_details()
	check(flow.get_node("%ReadProgress").value == read_count, "stale reading hashes do not inflate progress")
	flow.fit_graph()
	await settle()
	# Drag starts over another native card, crosses its moving bounds, and
	# releases without selecting it. A subsequent click must still work.
	var card: Control = flow.cards[previous]
	var point := card.get_global_rect().get_center()
	var old_pan := flow.canvas.pan
	pointer(point, MOUSE_BUTTON_LEFT, true)
	motion(point + Vector2(48, 20), Vector2(48, 20))
	pointer(point + Vector2(48, 20), MOUSE_BUTTON_LEFT, false)
	await settle()
	check(not flow.canvas.pan.is_equal_approx(old_pan), "native card drag pans canvas")
	check(flow.selected == current and not flow.canvas.pointer_armed(), "drag release suppresses accidental selection")
	point = card.get_global_rect().get_center()
	pointer(point, MOUSE_BUTTON_LEFT, true)
	pointer(point, MOUSE_BUTTON_LEFT, false)
	await settle()
	check(flow.selected == previous, "normal native click still selects after drag")
	var zoom := flow.canvas.zoom
	pointer(card.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_UP, true)
	pointer(card.get_global_rect().get_center(), MOUSE_BUTTON_WHEEL_UP, false)
	check(flow.canvas.zoom > zoom, "wheel over card zooms canvas")
	flow.canvas.zoom_at(flow.canvas.size / 2.0, 99)
	check(flow.canvas.zoom == flow.canvas.max_zoom, "zoom respects upper bound")
	flow.canvas.zoom_at(flow.canvas.size / 2.0, 0.01)
	check(flow.canvas.zoom == flow.canvas.min_zoom, "zoom respects lower bound")
	flow.fit_graph()
	await settle()
	var mini_point: Vector2 = flow.minimap.get_global_transform() * (flow.minimap.mapping() * (flow.positions[current] + flow.card_size / 2.0))
	pointer(mini_point, MOUSE_BUTTON_LEFT, true)
	pointer(mini_point, MOUSE_BUTTON_LEFT, false)
	check(flow.selected == previous, "minimap navigation preserves selected script")
	check((flow.canvas.pan + (flow.positions[current] + flow.card_size / 2.0) * flow.canvas.zoom).distance_to(flow.canvas.size / 2.0) < 1.0, "minimap centers requested world point")
	var pan := flow.canvas.pan
	flow.get_node("%Replay").pressed.emit()
	check(presenter.menu.confirmation != null, "visited script replay uses Cherry confirmation")
	presenter.menu.dismiss_confirmation()
	await settle()
	check(flow.selected == previous and flow.canvas.pan == pan and flow.cards == cards, "cancel retains selection, pan and native cards")
	for palette in ["mint", "night"]:
		presenter.preferences.set_value("palette", palette)
		check(flow.cards[current].get_theme_stylebox("normal").bg_color == presenter.skin.colors.name, "current card follows palette: " + palette)
		check(flow.get_node("Frame/Split/DetailPanel").get_theme_stylebox("panel").bg_color == presenter.skin.colors.paper, "detail follows palette: " + palette)
		flow.fit_graph()
		await capture(palette)
	# Continue must leave the real VM instruction untouched, unlike replay.
	flow._select(current)
	var ip: int = presenter.archive.player.vm.ip
	flow.get_node("%Replay").pressed.emit()
	await settle()
	check(not presenter.menu.is_open and presenter.archive.player.vm.ip == ip, "continue closes menus without restarting current script")
	presenter.archive.player.stop()
	scene.queue_free()
	await settle()
	print("Galgame flow: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
