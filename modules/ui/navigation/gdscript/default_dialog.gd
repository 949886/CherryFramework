class_name DefaultDialog
extends NavigationDialog

## Built-in lightweight dialog used by Navigator.show_dialog(configure).
##
## Configure this instance before _ready() by setting [member title],
## [member message], and calling [method add_action].
##
## An action button only invokes its callback. The callback decides whether to
## close the dialog (normally with [method Navigator.pop]), keep it open, or run
## other logic.

var title: String = "Dialog"
var message: String = ""
var _actions: Array[Dictionary] = []

## Adds a button whose pressed signal invokes [param callback].
##
## The callback receives no arguments and is responsible for any navigation
## result or dismissal. It may call [code]navigator.pop(result)[/code], leave the
## dialog open, or start asynchronous work.
func add_action(text: String, callback: Callable) -> void:
    if not callback.is_valid():
        push_error("DefaultDialog.add_action requires a valid callback.")
        return
    _actions.append({"text": text, "callback": callback})

func _ready() -> void:
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_IGNORE

    var center := CenterContainer.new()
    center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    center.mouse_filter = Control.MOUSE_FILTER_IGNORE
    add_child(center)

    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(360.0, 0.0)
    panel.mouse_filter = Control.MOUSE_FILTER_STOP
    center.add_child(panel)

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 20)
    margin.add_theme_constant_override("margin_top", 18)
    margin.add_theme_constant_override("margin_right", 20)
    margin.add_theme_constant_override("margin_bottom", 18)
    panel.add_child(margin)

    var content := VBoxContainer.new()
    content.add_theme_constant_override("separation", 12)
    margin.add_child(content)

    var title_label := Label.new()
    title_label.text = title
    title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    content.add_child(title_label)

    var message_label := Label.new()
    message_label.text = message
    message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    content.add_child(message_label)

    var actions := HBoxContainer.new()
    actions.alignment = BoxContainer.ALIGNMENT_END
    actions.add_theme_constant_override("separation", 8)
    content.add_child(actions)

    if _actions.is_empty():
        add_action("Close", func() -> void: navigator.pop())
    for action: Dictionary in _actions:
        var button := Button.new()
        button.text = str(action["text"])
        var callback := action["callback"] as Callable
        button.pressed.connect(callback)
        actions.add_child(button)
