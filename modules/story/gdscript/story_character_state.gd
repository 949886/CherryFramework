class_name StoryCharacterState
extends Resource
## Resourceized presentation state for a character.
##
## This demo stores a portrait texture, but the resource deliberately exposes
## metadata and an optional scene so a production project can replace a PNG/SVG
## portrait with AnimatedSprite2D, Live2D, Spine, a 3D character scene, etc.

@export var id: StringName = &"default"
@export var portrait: Texture2D
@export var presentation_scene: PackedScene
@export var metadata: Dictionary = {}
