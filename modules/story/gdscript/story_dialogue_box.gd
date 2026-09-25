@tool
class_name StoryDialogueBox
extends PanelContainer
## One native component is used on the stage and in settings subpages.

@export var text: RichTextLabel
@export var speaker: Label
@export var roman: Label
@export var voice: Label
@export var voice_row: HBoxContainer
@export var voice_icon: TextureRect
@export var nameplate: PanelContainer
@export var glass: ColorRect
@export var content: VBoxContainer
@export var narration := false

## The authored panel is a minimum, while the text settings may grow it upward.
@export_range(1, 8, 1) var visible_lines := 2
@export_range(0, 300, 1) var text_height_allowance := 102.0
var _panel_style: StyleBoxFlat
var _name_style: StyleBoxFlat

func fitted_height(settings: Dictionary, authored_minimum: float) -> float:
	return maxf(authored_minimum, float(settings.font_size) * float(settings.line_height) * visible_lines + text_height_allowance)

func _ready() -> void:
	# Copy authored styles before applying colors, preserving editor changes to
	# borders, padding and corners without modifying another scene instance.
	# Node.duplicate() (the live preview) shares resources even when they were
	# local to a PackedScene, so it also needs its own shader parameter storage.
	glass.material = glass.material.duplicate()
	_panel_style = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	_name_style = nameplate.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	add_theme_stylebox_override("panel", _panel_style)
	nameplate.add_theme_stylebox_override("panel", _name_style)
	resized.connect(_update_glass_size)

func apply_skin(skin: StorySkin) -> void:
	# Copy on change also keeps editor previews from mutating authored resources.
	_panel_style = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	_name_style = nameplate.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	add_theme_stylebox_override("panel", _panel_style)
	nameplate.add_theme_stylebox_override("panel", _name_style)
	glass.material = glass.material.duplicate()
	theme = skin.theme
	var settings := skin.preferences.values
	var fill: Color = skin.colors.paper
	fill.a = 0.0 if settings.glass else float(settings.opacity) / 100.0
	_panel_style.bg_color = fill
	_panel_style.border_color = Color.TRANSPARENT if settings.glass else skin.colors.line
	_name_style.bg_color = skin.colors.name
	for label_node in [speaker, roman]:
		label_node.add_theme_color_override("font_color", skin.colors.name_ink)
	voice.add_theme_color_override("font_color", skin.colors.accent)
	voice_icon.texture = skin.icon("voice", int(voice_icon.custom_minimum_size.x))
	voice_icon.self_modulate = skin.colors.accent
	voice_row.visible = bool(settings.voice_badge) and not narration
	nameplate.visible = not narration
	skin.style_body(text)
	glass.visible = bool(settings.glass)
	skin.style_glass(glass.material as ShaderMaterial, skin.colors.paper, size, float(_panel_style.corner_radius_top_left))
	_update_glass_size()

func _update_glass_size() -> void:
	if glass != null:
		(glass.material as ShaderMaterial).set_shader_parameter("panel_size", size)
