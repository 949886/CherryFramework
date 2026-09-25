extends SceneTree
## Real Cherry transactions with normal motion. Assertions cover scene lifetime,
## focus and input ownership, not just whether an alpha property stayed at one.

var checks := 0
var failures := 0
var module_root := (get_script() as Script).resource_path.get_base_dir().get_base_dir()
var presenter: StoryGalgamePresenter
var menus: StoryGalgameMenus
var nav: Navigator
var confirmed := 0

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: " + message)

func settle() -> void:
	for frame in range(4): await process_frame

func finish_navigation() -> void:
	var deadline := Time.get_ticks_msec() + 2000
	while nav.is_operating and Time.get_ticks_msec() < deadline: await process_frame
	check(not nav.is_operating, "navigation transaction completes")
	await settle()

func capture(name: String) -> void:
	if "--render" not in OS.get_cmdline_user_args(): return
	await RenderingServer.frame_post_draw
	var path := "user://navigation-" + name + ".png"
	root.get_texture().get_image().save_png(path)
	print("RENDER " + ProjectSettings.globalize_path(path))

func _run() -> void:
	root.content_scale_size = Vector2i(1280, 720)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
	var scene: Control = load(module_root.path_join("examples/galgame_demo.tscn")).instantiate()
	presenter = scene.get_node("Presenter")
	presenter.save_directory = "user://navigation_test_%d" % OS.get_process_id()
	root.add_child(scene)
	await settle()
	menus = presenter.menu
	nav = menus.navigator
	presenter.preferences.set_value("motion", "normal")
	presenter.preferences.set_value("instant", true)
	check(nav.route_count == 1 and nav.current_route.path.ends_with("/gameplay"), "gameplay is a real root route")
	check(nav.current_route.page.is_ancestor_of(presenter.dialogue), "native dialogue belongs to gameplay page")
	presenter.footer_buttons.settings.grab_focus()
	presenter.open_menu("settings")
	check(nav.is_transitioning and presenter.paused and menus._input_blocker.visible, "entry uses Cherry transition and blocks gameplay input")
	var pending := nav.scheduled_current_route
	menus.open("save")
	check(nav.scheduled_current_route == pending, "rapid navigation during entry cannot queue duplicate menus")
	await capture("entering")
	await finish_navigation()
	var settings := menus.active_page
	var settings_route := settings.route
	var text_tab := settings.settings_tabs.get_child(0)
	var original_preview := settings.preview
	check(settings is NavigationPage and nav.current_route == settings_route, "settings scene commits as current route")
	check(nav.first_route.state == NavigationRoute.State.COVERED, "gameplay is covered by menu")
	check(presenter.footer_buttons.settings.focus_mode == Control.FOCUS_NONE, "Cherry blocks covered gameplay focus")
	settings.select_section("display")
	await settle()
	var display_scroll := settings.settings_tabs.get_child(settings.settings_tabs.current_tab) as ScrollContainer
	display_scroll.scroll_vertical = 120
	await settle()
	var scroll_position := display_scroll.scroll_vertical
	settings.select_section("text")
	settings.select_section("sound")
	settings.select_section("text")
	check(settings.preview == original_preview and settings.settings_tabs.get_child(0) == text_tab, "tabs retain native controls and dialogue preview")
	check(nav.current_route == settings_route and not nav.is_operating, "local tabs never restart a navigation transaction")
	check(is_equal_approx(settings.modulate.a, 1.0), "tab changes keep page surface fully drawn")
	settings.select_section("display")
	await settle()
	check(display_scroll.scroll_vertical == scroll_position, "tab return preserves scroll position")
	var size_control: Control = settings._controls.font_size
	presenter.preferences.set_value("font_size", 29)
	presenter.preferences.reset_section("text")
	check(settings._controls.font_size == size_control and size_control.value == 23, "reset rebinds persistent controls without rebuilding")
	await capture("settings")
	var prior_focus := root.gui_get_focus_owner()
	menus.confirm("测试确认", "返回后应保留当前页。", func(): confirmed += 1)
	await finish_navigation()
	check(menus.confirmation is NavigationDialog and settings_route.state == NavigationRoute.State.COVERED, "confirmation is Cherry modal route")
	check(settings._tab_buttons.display.focus_mode == Control.FOCUS_NONE, "modal covers underlying menu controls")
	await capture("confirm")
	menus.back()
	await finish_navigation()
	check(confirmed == 0 and nav.current_route == settings_route, "back cancels only confirmation")
	check(root.gui_get_focus_owner() == prior_focus, "Cherry restores exact covered focus")
	check(menus.active_page == settings and display_scroll.scroll_vertical == scroll_position, "confirmation retains page and scroll")
	menus.confirm("测试确认", "只有确定应执行回调。", func(): confirmed += 1)
	await finish_navigation()
	nav.maybe_pop(true)
	await finish_navigation()
	check(confirmed == 1, "confirmation action runs once after modal pop")
	menus.open("save")
	check(settings.is_inside_tree() and settings.visible, "old page stays mounted through incoming transition")
	await finish_navigation()
	var save_page := menus.active_page
	var first_card: Button = save_page._slot_cards[0].button
	for index in range(4):
		save_page.select_slot_page(index)
		check(save_page._slot_cards[0].button == first_card and first_card.get_meta("slot_index") == index * 6, "slot pagination rebinds existing card: %d" % index)
	check(nav.current_route.page == save_page and not nav.is_operating, "slot pagination leaves route unchanged")
	save_page.select_slot_page(0)
	save_page._slot_action(0)
	check(presenter.archive.read_slot(0).status == "ready" and save_page._slot_cards[0].button == first_card, "saving updates existing slot card")
	menus.back()
	await finish_navigation()
	check(menus.active_page == settings and settings.preview != null, "back reveals retained settings instance")
	menus.back()
	check(presenter.paused and nav.is_transitioning, "gameplay remains paused during pop animation")
	await finish_navigation()
	check(not menus.is_open and not presenter.paused, "gameplay resumes only after final pop commits")
	check(root.gui_get_focus_owner() == presenter.footer_buttons.settings, "gameplay focus restores to opener")
	presenter.preferences.set_value("motion", "reduced")
	presenter.open_menu("settings")
	check(not nav.is_operating and menus.is_open, "reduced motion uses immediate native navigation")
	menus.confirm("读取", "模拟关闭整个菜单流程。", func(): presenter.close_menu())
	nav.maybe_pop(true)
	await finish_navigation()
	check(nav.route_count == 1 and not presenter.paused, "load-style confirmation closes flow through navigation queue")
	presenter.archive.player.stop()
	scene.queue_free()
	await settle()
	print("Galgame navigation: %d passed, %d failed" % [checks - failures, failures])
	quit(1 if failures else 0)
