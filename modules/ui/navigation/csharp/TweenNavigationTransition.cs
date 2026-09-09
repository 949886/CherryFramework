using Godot;
using System.Threading.Tasks;

/// <summary>Shared timing and state restoration for built-in transitions.</summary>
/// <remarks>Per-run state is local; resources can be shared across Navigators.</remarks>
[GlobalClass]
public abstract partial class TweenNavigationTransition : NavigationTransition
{
    /// <summary>Duration in seconds. Zero or negative values skip animation.</summary>
    [Export(PropertyHint.Range, "0,5,0.01,or_greater")]
    public double Duration { get; set; } = 0.18;

    [Export] public Tween.EaseType EaseType { get; set; } = Tween.EaseType.InOut;
    [Export] public Tween.TransitionType TransitionType { get; set; } = Tween.TransitionType.Linear;

    protected async Task AnimateAsync(NavigationPage page, bool entering, Vector2 offset,
        float scaleFactor, bool fade, Vector2? pivotRatio = null)
    {
        if (Duration <= 0)
            return;

        Vector2 originalPosition = page.Position;
        Vector2 originalScale = page.Scale;
        Vector2 originalPivot = page.PivotOffset;
        Color originalModulate = page.Modulate;
        bool scaling = !Mathf.IsEqualApprox(scaleFactor, 1.0f);
        bool moving = !offset.IsZeroApprox() || scaling;

        try
        {
            if (scaling)
            {
                page.PivotOffset = page.Size * (pivotRatio ?? new Vector2(0.5f, 0.5f));
                // Preserve the authored transform when changing its pivot, including rotation.
                Vector2 pivotDelta = page.PivotOffset - originalPivot;
                page.Position += (pivotDelta * originalScale).Rotated(page.Rotation) - pivotDelta;
            }

            Vector2 shownPosition = page.Position;
            Vector2 hiddenPosition = shownPosition + offset;
            Vector2 hiddenScale = originalScale * Mathf.Max(scaleFactor, 0.01f);
            if (entering)
            {
                if (moving)
                    page.Position = hiddenPosition;
                if (scaling)
                    page.Scale = hiddenScale;
                if (fade)
                {
                    Color transparent = originalModulate;
                    transparent.A = 0;
                    page.Modulate = transparent;
                }
            }

            Tween tween = page.CreateTween().SetParallel();
            tween.SetPauseMode(Tween.TweenPauseMode.Process);
            tween.SetTrans(TransitionType).SetEase(EaseType);
            if (moving)
                tween.TweenProperty(page, "position", entering ? shownPosition : hiddenPosition, Duration);
            if (scaling)
                tween.TweenProperty(page, "scale", entering ? originalScale : hiddenScale, Duration);
            if (fade)
                tween.TweenProperty(page, "modulate:a", entering ? originalModulate.A : 0.0f, Duration);
            if (!moving && !scaling && !fade)
                tween.TweenInterval(Duration);
            await page.ToSignal(tween, Tween.SignalName.Finished);
        }
        finally
        {
            // Navigator removes popped pages after completion, without another draw.
            if (GodotObject.IsInstanceValid(page))
            {
                if (scaling)
                {
                    page.Scale = originalScale;
                    page.PivotOffset = originalPivot;
                }
                if (moving)
                    page.Position = originalPosition;
                if (fade)
                    page.Modulate = originalModulate;
            }
        }
    }
}
