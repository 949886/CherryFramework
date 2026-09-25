class_name StoryDialogueBox
extends PanelContainer
## One native component is used on the stage and in settings subpages.

var text: RichTextLabel
var speaker: Label
var roman: Label
var voice: Label
var voice_row: HBoxContainer
var voice_icon: TextureRect
var nameplate: PanelContainer
var glass: ColorRect
var content: VBoxContainer
var narration := false

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(0, 185)
	var capture := BackBufferCopy.new()
	capture.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(capture)
	glass = ColorRect.new()
	glass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	glass.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glass.material = ShaderMaterial.new()
	(glass.material as ShaderMaterial).shader = preload("../resources/dialogue_glass.gdshader")
	add_child(glass)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_theme_constant_override("margin_left", 34)
	margin.add_theme_constant_override("margin_right", 34)
	margin.add_theme_constant_override("margin_top", 34)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)
	content = VBoxContainer.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_theme_constant_override("separation", 12)
	margin.add_child(content)
	text = RichTextLabel.new()
	text.bbcode_enabled = true
	text.custom_minimum_size = Vector2(0, 100)
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Long narration remains scrollable; the presenter excludes scrollbar clicks
	# from its advance gesture while ordinary clicks still advance the story.
	text.mouse_filter = Control.MOUSE_FILTER_PASS
	content.add_child(text)
	voice_row = HBoxContainer.new()
	voice_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	voice_row.add_theme_constant_override("separation", 8)
	content.add_child(voice_row)
	voice_icon = TextureRect.new()
	voice_icon.custom_minimum_size = Vector2(16, 16)
	voice_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	voice_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	voice_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	voice_row.add_child(voice_icon)
	voice = Label.new()
	voice.text = "MAHIRO"
	voice.add_theme_font_size_override("font_size", 12)
	voice_row.add_child(voice)
	nameplate = PanelContainer.new()
	nameplate.set_as_top_level(false)
	# Top-level container children are laid out by PanelContainer. The nameplate
	# is an overlay sibling of the panel's content via a plain Control wrapper.
	var overlay := Control.new()
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)
	overlay.add_child(nameplate)
	nameplate.position = Vector2(26, -21)
	nameplate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	nameplate.add_child(row)
	speaker = Label.new()
	speaker.add_theme_font_size_override("font_size", 20)
	row.add_child(speaker)
	roman = Label.new()
	roman.text = "MAHIRO"
	roman.add_theme_font_size_override("font_size", 11)
	row.add_child(roman)
	resized.connect(_update_glass_size)

func apply_skin(skin: StorySkin) -> void:
	theme = skin.theme
	var settings := skin.preferences.values
	var fill: Color = skin.colors.paper
	fill.a = 0.0 if settings.glass else float(settings.opacity) / 100.0
	add_theme_stylebox_override("panel", StorySkin.box(fill, Color.TRANSPARENT if settings.glass else skin.colors.line, 18))
	nameplate.add_theme_stylebox_override("panel", StorySkin.box(skin.colors.name, Color.TRANSPARENT, 10, 12))
	for label_node in [speaker, roman]:
		label_node.add_theme_color_override("font_color", skin.colors.name_ink)
	voice.add_theme_color_override("font_color", skin.colors.accent)
	voice_icon.texture = skin.icon("voice", int(voice_icon.custom_minimum_size.x))
	voice_icon.self_modulate = skin.colors.accent
	voice_row.visible = bool(settings.voice_badge) and not narration
	nameplate.visible = not narration
	skin.style_body(text)
	glass.visible = bool(settings.glass)
	skin.style_glass(glass.material as ShaderMaterial, skin.colors.paper, size, 18.0)
	_update_glass_size()

func _update_glass_size() -> void:
	if glass != null:
		(glass.material as ShaderMaterial).set_shader_parameter("panel_size", size)
