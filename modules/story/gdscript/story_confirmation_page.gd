class_name StoryConfirmationPage
extends NavigationDialog
## Results arrive after Cherry restores the covered page. Back cancels; only
## explicit confirmation returns true. There is no second focus/modal stack.

var skin: StorySkin
var caption: String
var message: String
var cancel_button: Button

func configure(theme_skin: StorySkin, title: String, text: String) -> void:
	skin = theme_skin
	caption = title
	message = text

func _ready() -> void:
	theme = skin.theme
	$Card/Content/Heading.text = caption
	$Card/Content/Message.text = message
	skin.refresh_labels(self)
	cancel_button = $Card/Content/Buttons/Cancel
	cancel_button.icon = skin.icon("close")
	cancel_button.pressed.connect(func(): navigator.maybe_pop(false))
	var confirm_button: Button = $Card/Content/Buttons/Confirm
	confirm_button.icon = skin.icon("check")
	confirm_button.pressed.connect(func(): navigator.maybe_pop(true))

func on_navigation_entered(_previous: NavigationRoute, _reason: EnterReason) -> void:
	cancel_button.grab_focus()
