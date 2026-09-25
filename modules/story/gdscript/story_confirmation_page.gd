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
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = skin.theme
	var card := PanelContainer.new()
	card.position = Vector2(365, 235)
	card.size = Vector2(550, 225)
	card.add_theme_stylebox_override("panel", StorySkin.box(skin.colors.paper, skin.colors.line, 18, 28))
	add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 20)
	card.add_child(content)
	content.add_child(skin.label(caption, 24))
	var text := skin.label(message, 16, "muted")
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(text)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", 12)
	content.add_child(buttons)
	cancel_button = skin.button("取消", func(): navigator.maybe_pop(false), Vector2(110, 40), "close")
	buttons.add_child(cancel_button)
	buttons.add_child(skin.button("确定", func(): navigator.maybe_pop(true), Vector2(110, 40), "check"))

func on_navigation_entered(_previous: NavigationRoute, _reason: EnterReason) -> void:
	cancel_button.grab_focus()
