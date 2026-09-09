using Godot;
using System.Threading.Tasks;

/// <summary>Slides in from a page edge and exits toward the same edge on Pop.</summary>
[GlobalClass]
public partial class SlideNavigationTransition : TweenNavigationTransition
{
    public enum Edge { Left, Right, Top, Bottom }

    [Export] public Edge FromEdge { get; set; } = Edge.Right;

    /// <summary>Travel as a fraction of the page width/height (1 = one full page).</summary>
    [Export(PropertyHint.Range, "0,2,0.01,or_greater")]
    public float DistanceRatio { get; set; } = 1.0f;

    public SlideNavigationTransition()
    {
        Duration = 0.28;
        EaseType = Tween.EaseType.Out;
        TransitionType = Tween.TransitionType.Cubic;
    }

    protected virtual bool UsesFade => false;

    public override Task PushAsync(NavigationPage incoming, NavigationPage? outgoing) =>
        AnimateAsync(incoming, true, GetOffset(incoming), 1.0f, UsesFade);

    public override Task PopAsync(NavigationPage outgoing, NavigationPage? incoming) =>
        AnimateAsync(outgoing, false, GetOffset(outgoing), 1.0f, UsesFade);

    private Vector2 GetOffset(NavigationPage page)
    {
        Vector2 extent = page.Size;
        Vector2 fallback = page.GetParentControl()?.Size ?? page.GetViewportRect().Size;
        if (extent.X <= 0)
            extent.X = fallback.X;
        if (extent.Y <= 0)
            extent.Y = fallback.Y;
        float distance = Mathf.Max(DistanceRatio, 0.0f);
        return FromEdge switch
        {
            Edge.Left => new Vector2(-extent.X * distance, 0),
            Edge.Top => new Vector2(0, -extent.Y * distance),
            Edge.Bottom => new Vector2(0, extent.Y * distance),
            _ => new Vector2(extent.X * distance, 0),
        };
    }
}
