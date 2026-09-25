# Cherry Story native icons

Original SVG artwork for the Galgame presenter: 24-unit view box, 1.7-unit
rounded strokes, rendered at 18 logical pixels by default. White artwork is a
neutral tint mask; `StorySkin` applies the active palette and button-state
colors. No icon font, remote dependency or generated bitmap is required.

Import these files as **DPITexture** (`importer="svg"`), keeping their `.import`
settings in version control. Godot then rasterizes the embedded SVG source at
the viewport's current oversampling scale, including in exported games. The
default Texture2D importer bakes an 18×18 bitmap that blurs at larger window
sizes. `StorySkin.icon(id, extent)` caches variants for controls with a different
logical size; changing that size does not enlarge every other button icon.

`resources/galgame_icons.tres` registers semantic names and explicit texture
references. It is included in the scene dependency resource so selected-scene
exports retain every icon. To add artwork, create an SVG and register its
texture in that resource, then use `skin.button(..., icon_id)`,
`skin.icon_view(...)` or `skin.icon_label(...)`. Settings tab icons are chosen
by the `icon` field in `galgame_settings.json`.

Keep labels as ordinary text. Icon-only controls need a tooltip. Dynamic
controls swap textures for their current state; choice arrows use the same
interpolated tint as their text, including on frosted glass.
