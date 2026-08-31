using Godot;
using System.Threading.Tasks;

/// <summary>Built-in alpha fade transition for Control-based NavigationPages.</summary>
[GlobalClass]
public partial class FadeNavigationTransition : NavigationTransition
{
    /// <summary>Fade duration in seconds.</summary>
    [Export(PropertyHint.Range, "0,5,0.01")]
    public double Duration { get; set; } = 0.18;

    /// <inheritdoc/>
    public override async Task PushAsync(NavigationPage incoming, NavigationPage? outgoing)
    {
        if (Duration <= 0)
            return;
        Color modulate = incoming.Modulate;
        modulate.A = 0;
        incoming.Modulate = modulate;
        Tween tween = incoming.CreateTween();
        tween.TweenProperty(incoming, "modulate:a", 1.0, Duration);
        await incoming.ToSignal(tween, Tween.SignalName.Finished);
    }

    /// <inheritdoc/>
    public override async Task PopAsync(NavigationPage outgoing, NavigationPage? incoming)
    {
        if (Duration <= 0)
            return;
        Tween tween = outgoing.CreateTween();
        tween.TweenProperty(outgoing, "modulate:a", 0.0, Duration);
        await outgoing.ToSignal(tween, Tween.SignalName.Finished);
    }
}
