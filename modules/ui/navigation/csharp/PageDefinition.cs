
using Godot;

/// <summary>
/// Generated lookup record for one navigable scene.
/// </summary>
/// <remarks>
/// PageDefinition intentionally stores only navigation identity and the
/// PackedScene used to instantiate it. Presentation/runtime policy belongs to
/// NavigationPage and is snapshotted into NavigationRoute for each push.
/// generated/page_registry.tres is not a user-authored configuration surface.
/// </remarks>
[GlobalClass]
public partial class PageDefinition : Resource
{
    /// <summary>Canonical application route such as <c>ui://settings</c>.</summary>
    [Export] public string Path { get; set; } = "";

    /// <summary>Packed scene instantiated whenever this definition is pushed.</summary>
    [Export] public PackedScene Scene { get; set; } = null!;
}
