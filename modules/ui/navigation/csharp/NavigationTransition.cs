using Godot;
using System.Threading.Tasks;

/// <summary>
/// Base class for Cherry page presentation transitions.
/// </summary>
/// <remarks>
/// Transition methods execute inside Navigator's serialized operation queue.
/// The next stack mutation cannot begin until the current transition completes.
/// </remarks>
[GlobalClass]
public abstract partial class NavigationTransition : Resource
{
    /// <summary>
    /// Presents <paramref name="incoming"/> over <paramref name="outgoing"/>.
    /// Incoming is already inside the SceneTree when this method runs.
    /// </summary>
    public virtual Task PushAsync(NavigationPage incoming, NavigationPage? outgoing) => Task.CompletedTask;

    /// <summary>
    /// Removes <paramref name="outgoing"/> visually and reveals
    /// <paramref name="incoming"/>. Navigator frees outgoing after completion.
    /// </summary>
    public virtual Task PopAsync(NavigationPage outgoing, NavigationPage? incoming) => Task.CompletedTask;
}
