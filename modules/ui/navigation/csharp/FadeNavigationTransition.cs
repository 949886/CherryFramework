using Godot;
using System.Threading.Tasks;

/// <summary>Built-in alpha fade transition for Control-based NavigationPages.</summary>
[GlobalClass]
public partial class FadeNavigationTransition : TweenNavigationTransition
{
    /// <inheritdoc/>
    public override Task PushAsync(NavigationPage incoming, NavigationPage? outgoing) =>
        AnimateAsync(incoming, true, Vector2.Zero, 1.0f, true);

    /// <inheritdoc/>
    public override Task PopAsync(NavigationPage outgoing, NavigationPage? incoming) =>
        AnimateAsync(outgoing, false, Vector2.Zero, 1.0f, true);
}
