using Godot;
using System;

/// <summary>
/// Page-local guard consulted by <see cref="Navigator.MaybePop"/>.
/// </summary>
[GlobalClass]
public partial class PopScope : Node
{
    /// <summary>Whether back-style navigation is currently allowed through this scope.</summary>
    [Export] public bool CanPop { get; set; } = true;

    /// <summary>
    /// Raised after a MaybePop attempt. The first argument is true when the
    /// back request caused a route to pop in this Navigator or in an ancestor
    /// reached through Navigator.ParentNavigator; the second is the requested
    /// result.
    /// </summary>
    public event Action<bool, object?>? PopInvoked;

    internal void Notify(bool didPop, object? result) => PopInvoked?.Invoke(didPop, result);
}
