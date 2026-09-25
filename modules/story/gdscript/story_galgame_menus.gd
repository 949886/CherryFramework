class_name StoryGalgameMenus
extends Control
## Cherry owns route lifetime, covered input/focus, modal scrims and transitions.
## Local tab/slot state belongs to the mounted StoryMenuPage, never this router.

## Supplied by menus.tscn, keeping the dependency direction scene -> script.
## Page scenes reference this class too; keeping their catalog in the scene
## avoids a script-to-scene preload cycle and allows project-specific routes.
@export var page_catalog: Resource
var presenter: StoryGalgamePresenter
var skin: StorySkin
@export var navigator: Navigator
var section_id := "text"
var slot_page := 0
@export var toast: PanelContainer
var _toast_generation := 0
@export var _input_blocker: Control
var is_open: bool:
	get: return navigator != null and (navigator.route_count > 1 or navigator.scheduled_route_count > 1)
var active_page: StoryMenuPage:
	get:
		if navigator == null: return null
		var mounted := navigator.routes()
		mounted.reverse()
		for entry in mounted:
			if entry.page is StoryMenuPage: return entry.page
		return null
var page: String:
	get: return active_page.page if active_page != null else ""
var confirmation: StoryConfirmationPage:
	get:
		if navigator != null and navigator.current_route != null:
			return navigator.current_route.page as StoryConfirmationPage
		return null

func configure(owner_presenter: StoryGalgamePresenter) -> void:
	presenter = owner_presenter
	skin = presenter.skin
	# Move the already-instantiated game view into Cherry's retained root route.
	# No controls are rebuilt; exported node references stay valid after the move.
	navigator.push_definition_configured(_definition("gameplay"), func(root_page):
		presenter.game_view.reparent(root_page, false))
	navigator.operation_queue_changed.connect(_navigation_changed)
	navigator.navigation_error.connect(func(_code, message): notify_user(message))
	update_skin("")

func _definition(identity: String) -> PageDefinition:
	return page_catalog.get_meta("pages").get(identity) as PageDefinition

func open(target: String) -> void:
	if navigator.is_operating: return
	if active_page != null and page == target:
		if target == "settings": active_page.select_section(section_id)
		elif target in ["save", "load"]: active_page.select_slot_page(slot_page)
		return
	var definition := _definition(target)
	if definition == null: return
	for entry in navigator.routes():
		if entry.path == definition.path:
			navigator.pop_until(func(candidate): return candidate == entry)
			return
	presenter.paused = true
	navigator.push_definition_configured(definition, func(incoming: StoryMenuPage):
		_prepare_transition(incoming)
		incoming.configure(self))

func _prepare_transition(incoming: NavigationPage) -> void:
	# Keep authored transition resources shared, but runtime settings per route.
	if incoming.route.transition != null:
		incoming.route.transition = incoming.route.transition.duplicate()
		if presenter.preferences.values.motion == "reduced":
			(incoming.route.transition as TweenNavigationTransition).duration = 0.0

func back() -> void:
	navigator.maybe_pop()

func close() -> void:
	# Load/restart closes the complete flow; ordinary Back pops just one route.
	navigator.pop_until(func(entry): return entry == navigator.first_route)

func _navigation_changed(_pending: int) -> void:
	_input_blocker.visible = navigator.is_operating
	presenter.paused = is_open or presenter.ui_hidden or presenter._focus_paused
	if not is_open: presenter.replay_player.stop()

func _input(_event: InputEvent) -> void:
	# Both scenes remain mounted during transitions. Gate keyboard events too,
	# until Cherry commits the new route and applies its covered-input policy.
	if navigator != null and navigator.is_operating:
		get_viewport().set_input_as_handled()

func update_skin(_key: String) -> void:
	theme = skin.theme
	for entry in navigator.routes():
		if entry.page is StoryMenuPage: entry.page.update_skin()
		if entry.transition is TweenNavigationTransition and not navigator.is_transitioning:
			var authored := entry.page.transition as TweenNavigationTransition
			entry.transition.duration = 0.0 if presenter.preferences.values.motion == "reduced" else authored.duration
	if not presenter.preferences.last_error.is_empty(): notify_user(presenter.preferences.last_error)

func confirm(title: String, message: String, action: Callable) -> void:
	if navigator.is_operating or confirmation != null or not is_open: return
	var entry := navigator.push_definition_configured(_definition("confirm"), func(dialog: StoryConfirmationPage):
		_prepare_transition(dialog)
		dialog.configure(skin, title, message))
	entry.popped.connect(func(result):
		if result == true: action.call())

func dismiss_confirmation() -> bool:
	if confirmation == null: return false
	return navigator.maybe_pop(false)

func notify_user(message: String) -> void:
	_toast_generation += 1
	var generation := _toast_generation
	(toast.get_child(0) as Label).text = message
	toast.show()
	await get_tree().create_timer(3.5).timeout
	if generation == _toast_generation: toast.hide()

func show_ending() -> void:
	open("ending")
