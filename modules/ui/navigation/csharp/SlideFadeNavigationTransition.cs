using Godot;

/// <summary>A short slide with an alpha fade, useful for panels and modals.</summary>
[GlobalClass]
public partial class SlideFadeNavigationTransition : SlideNavigationTransition
{
    public SlideFadeNavigationTransition()
    {
        Duration = 0.22;
        FromEdge = Edge.Bottom;
        DistanceRatio = 0.08f;
    }

    protected override bool UsesFade => true;
}
