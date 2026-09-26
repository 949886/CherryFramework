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
	_check_strokes()
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
	if "--render" in OS.get_cmdline_user_args():
		# Capture real GPU output across graph zoom and viewport stretch. These
		# are screenshots, not assertions on implementation-generated bitmaps.
		for dimensions in [Vector2i(1280, 720), Vector2i(1920, 1080)]:
			root.size = dimensions
			await settle()
			for zoom in [0.3, 0.57, 1.0, 1.75]:
				flow.canvas.zoom_at(flow.canvas.size / 2.0, zoom)
				flow.canvas.center_on(current)
				await capture("strokes-%d-%d" % [dimensions.x, roundi(zoom * 100)])
				if is_equal_approx(zoom, 0.57): _check_rendered_stroke(current, dimensions.x)
		root.size = Vector2i(1280, 720)
		await settle()
		flow.fit_graph()
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

func _check_strokes() -> void:
	# Splitting a straight segment at arbitrary vertices must not change dash
	# length/phase. The old index-based cutting changed both at every bend.
	var samples := PackedVector2Array([Vector2.ZERO, Vector2(3, 0), Vector2(12, 0), Vector2(20, 0)])
	var segments := StoryFlowStroke.dashes(samples, 5.0, 5.0)
	check(segments.size() == 2, "dash count depends on arc length, not tessellation vertices")
	check(segments[0][0] == Vector2.ZERO and segments[0][-1] == Vector2(5, 0), "first dash crosses a curve vertex without a break")
	check(segments[1][0] == Vector2(10, 0) and segments[1][-1] == Vector2(15, 0), "dash phase carries across uneven sample spacing")
	var stroke := StoryFlowStroke.new()
	var curve := stroke.bezier(Vector2.ZERO, Vector2(170, 210), 85, 1.0)
	segments = StoryFlowStroke.dashes(curve, 5.0, 5.0)
	var uniform := true
	for path in segments.slice(0, -1):
		var length := 0.0
		for i in range(1, path.size()): length += path[i - 1].distance_to(path[i])
		uniform = uniform and absf(length - 5.0) < 0.001
	check(uniform, "curved dashes retain the approved 5-unit length")
	var outline := stroke.rounded_outline(Rect2(0, 0, 202, 126), 12)
	check(outline[0] == outline[-1] and outline.size() > 4, "rounded outline is a continuous closed path")

func _check_rendered_stroke(current: String, viewport_width: int) -> void:
	# Read the actual GPU pixels on a selected horizontal connector. A line
	# made solely of translucent AA fringes fails even when its geometry is right.
	var picture := root.get_texture().get_image()
	for edge in presenter.library.edges:
		if edge.from != current or not is_equal_approx(flow.positions[edge.from].y, flow.positions[edge.to].y): continue
		var points := flow.canvas.edge_points(edge)
		var transform := StoryFlowStroke.pixel_transform(flow.canvas)
		var center: Vector2 = transform * ((points[0] + points[-1]) / 2.0)
		var opaque_rows := 0
		for offset in range(-5, 6):
			var sample := picture.get_pixel(roundi(center.x), floori(center.y) + offset)
			var expected: Color = presenter.skin.colors.accent
			if absf(sample.r - expected.r) + absf(sample.g - expected.g) + absf(sample.b - expected.b) < 0.015: opaque_rows += 1
		check(opaque_rows >= 2, "solid connector retains opaque pixel core at viewport width %d" % viewport_width)
		return
	check(false, "render fixture contains a selected horizontal connector")
