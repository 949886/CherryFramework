using Godot;
using System.Threading.Tasks;

/// <summary>Scales around a configurable pivot, optionally fading at the same time.</summary>
[GlobalClass]
public partial class ScaleNavigationTransition : TweenNavigationTransition
{
    /// <summary>Relative scale at the hidden endpoint. Below 1 grows in; above 1 shrinks in.</summary>
    [Export(PropertyHint.Range, "0.01,2,0.01,or_greater")]
    public float HiddenScale { get; set; } = 0.9f;

    /// <summary>Normalized pivot within the page. (0.5, 0.5) is the center.</summary>
    [Export] public Vector2 PivotRatio { get; set; } = new(0.5f, 0.5f);
    [Export] public bool Fade { get; set; } = true;

    public ScaleNavigationTransition()
    {
        Duration = 0.24;
        EaseType = Tween.EaseType.Out;
        TransitionType = Tween.TransitionType.Cubic;
    }

    public override Task PushAsync(NavigationPage incoming, NavigationPage? outgoing) =>
        AnimateAsync(incoming, true, Vector2.Zero, HiddenScale, Fade, PivotRatio);

    public override Task PopAsync(NavigationPage outgoing, NavigationPage? incoming) =>
        AnimateAsync(outgoing, false, Vector2.Zero, HiddenScale, Fade, PivotRatio);
}
