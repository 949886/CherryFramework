# Approved galgame presenter integration

The approved reference is `cherry-story-mahiro.html` from the September 2026 UI
design session. This is a native Godot implementation, not an embedded web page.
The existing minimal presenter and technical example remain available for plugin
regression tests; the project launches the new galgame example.

## Completion requirements

- [ ] Native 16:9 stage, letterboxing, dialogue nameplate and voice indicator;
      choices anchored above the dialogue at every supported window size.
- [ ] Provided pastel background, extracted Mahiro sprite and happy expression.
- [ ] Sans-serif body, original serif accents, default line height 1.5; six fresh
      palettes plus original palettes; shared dialogue/preview styling.
- [ ] Separate save/load pages, 24 real persistent slots with thumbnails, metadata,
      overwrite/load confirmation, corrupt/missing-save handling.
- [ ] Scrollable backlog with speaker, choice and narration records, voice replay.
- [ ] Five complete settings pages: text, reading, sound, display and system;
      settings persist across launch. Only relevant subpages show a preview.
- [ ] Optional frosted glass after motion, conditional blur/tint/saturation
      controls, no edge highlight; preview matches the active dialogue.
- [ ] Real script-file graph with branches/rejoins, zoom/pan, search, bookmarks,
      current/read/unread/locked states, spoiler hiding and verified replay.
- [ ] Playback integration: pause menus, auto, read-only skip by default, hide,
      voice lifecycle, keyboard controls, restart and locale handling.
- [ ] Native regression coverage and rendered checks at multiple resolutions.
- [ ] Task changes committed locally at each milestone, with existing unrelated
      project/import changes preserved. No push or PR requested.

## Implementation milestones

1. Validated settings schema and persistence; real file graph and archive model.
2. Native presenter, menu pages, graph view and supplied assets; playable example.
3. Regression/runtime/render verification, remaining fixes, local integration commit.

## Existing workspace changes at start

`project.godot` already enables the Cherry editor plugin and navigation registry.
`characters/` is untracked. Six Story example `.import` files are modified in the
Cherry submodule. These are not part of the UI integration and must not be staged.
