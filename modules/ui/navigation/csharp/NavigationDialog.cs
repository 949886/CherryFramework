using Godot;

/// <summary>
/// Marker/base page for Dialog UI presented as a Cherry Modal route.
/// </summary>
/// <remarks>
/// Dialog is intentionally not a NavigationPresentation value. NavigationDialog
/// uses the same route stack, lifecycle, PopScope, transition, result and back
/// semantics as every other NavigationPage.
/// </remarks>
public abstract partial class NavigationDialog : NavigationPage
{
}
