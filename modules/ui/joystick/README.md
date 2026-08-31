# Cherry UI Joystick

`ui.joystick` ships one API in two runtime implementations:

- `gdscript/` for regular Godot projects
- `csharp/` for projects with a root-level `.csproj`

`JoystickModule` selects the runtime when Cherry enters the editor tree. It creates a `.gdignore` in the unused runtime directory and asks `EditorFileSystem` to rescan, mirroring the language-selection behavior of `ui.navigation`.

## Runtime classes

- `CherryVirtualJoystick`
- `VirtualButton`
- `VirtualDirectionButton`
- `VirtualProgressButton`
- `TouchInputManager`

The GDScript implementation exposes the same names through `class_name`; the C# implementation retains its existing `[GlobalClass]` types.

`TouchInputManager` uses module-local script references and no longer depends on the old `res://UI/Joystick/...` installation path.
