# Approved galgame presenter integration

The approved reference is `cherry-story-mahiro.html` from the September 2026 UI
design session. This is a native Godot implementation, not an embedded web page.
The existing minimal presenter and technical example remain available for plugin
regression tests; the project launches the new galgame example.

## Completion requirements

- [x] Native 16:9 stage, letterboxing, dialogue nameplate and voice indicator;
      choices anchored above the dialogue at every supported window size.
- [x] Provided pastel background, extracted Mahiro sprite and happy expression.
- [x] Sans-serif body, original serif accents, default line height 1.5; six fresh
      palettes plus original palettes; shared dialogue/preview styling.
- [x] Separate save/load pages, 24 real persistent slots with thumbnails, metadata,
      overwrite/load confirmation, corrupt/missing-save handling.
- [x] Scrollable backlog with speaker, choice and narration records, voice replay.
- [x] Five complete settings pages: text, reading, sound, display and system;
      settings persist across launch. Only relevant subpages show a preview.
- [x] Optional frosted glass after motion, conditional blur/tint/saturation
      controls, no edge highlight; preview matches the active dialogue.
- [x] Real script-file graph with branches/rejoins, zoom/pan, search, bookmarks,
      current/read/unread/locked states, spoiler hiding and verified replay.
- [x] Playback integration: pause menus, auto, read-only skip by default, hide,
      voice lifecycle, keyboard controls, restart and locale handling.
- [x] Native regression coverage and rendered checks at multiple resolutions.
- [x] Task changes committed locally at each milestone, with existing unrelated
      project/import changes preserved. No push or PR requested.

## Implementation milestones

1. Validated settings schema and persistence; real file graph and archive model.
2. Native presenter, menu pages, graph view and supplied assets; playable example.
3. Regression/runtime/render verification, remaining fixes, local integration commit.

## Existing workspace changes at start

`project.godot` already enables the Cherry editor plugin and navigation registry.
`characters/` is untracked. Six Story example `.import` files are modified in the
Cherry submodule. These are not part of the UI integration and must not be staged.

## Verification record (2026-09-25)

- Godot 4.7.2 .NET on Windows; the Story module also runs entirely in GDScript.
- Full relocated regression suite: 18 stages, 545 checks, zero failures.
- Subsequent focused menu/focus and selected-scene export suite: 9 stages,
  212 checks, zero failures (native UI expanded from 59 to 63 checks).
- Final project-native D3D12 Forward+ render run: 63 native checks, zero failures.
  Compatibility/OpenGL renders were also inspected.
- Rendered sizes: 1280x720, 1600x900, 1920x1200, 900x900. Letterboxing,
  dialogue/choice anchors, thumbnail crop and settings preview were verified.
- All three first branches and both endings were traversed through StoryPlayer.
- Selected-scene PCK was launched from an empty directory: 23 checks, including
  eight script files, JSON schema/catalog, portraits, shader and settings preview.
- Root project import and main-scene smoke run succeeded. The sandbox's system
  certificate-store warning is unrelated to local UI/assets and is filtered by
  the existing runner; no script errors remain.
- Milestone commits: 33b804a (models), 6046269 (native UI); final validation and
  root launch configuration are committed separately after this record.

Reports are retained by the runner under the system temporary directory:
`cherry-story-tests-jf_z_dd1/report.json` (full suite) and
`cherry-story-tests-a4pvn4d0/report.json` (focused final suite).
