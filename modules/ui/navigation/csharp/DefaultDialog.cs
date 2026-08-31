using Godot;
using System;
using System.Collections.Generic;

/// <summary>Built-in lightweight dialog used by Navigator.ShowDialog(configure).</summary>
public partial class DefaultDialog : NavigationDialog
{
    private sealed record DialogAction(string Text, Action? Callback);
    private readonly List<DialogAction> _actions = new();

    /// <summary>Dialog title configured before _Ready.</summary>
    public string Title { get; set; } = "Dialog";

    /// <summary>Dialog message configured before _Ready.</summary>
    public string Message { get; set; } = "";

    /// <summary>
    /// Adds an action button with an optional synchronous callback.
    /// </summary>
    /// <param name="text">Text displayed by the generated button.</param>
    /// <param name="callback">
    /// Optional action invoked when the button is pressed. When null, the button
    /// remains enabled but intentionally performs no action.
    /// </param>
    /// <remarks>
    /// AddAction never dismisses the dialog implicitly.
    /// The callback owns dismissal and result semantics.
    /// It may call <c>Navigator.Pop(result)</c> to close this route with a result.
    /// It may omit Pop to keep the dialog open.
    /// Use <see cref="AddCloseAction"/> for the common null-result close action.
    /// </remarks>
    public void AddAction(string text, Action? callback = null)
        => _actions.Add(new DialogAction(text, callback));

    /// <summary>
    /// Adds an action button that closes this dialog when pressed.
    /// </summary>
    /// <param name="text">Text displayed by the generated close button.</param>
    /// <remarks>
    /// The generated callback calls <c>Navigator.Pop()</c>.
    /// Therefore the route completes with a null result.
    /// </remarks>
    public void AddCloseAction(string text)
        => AddAction(text, () => Navigator.Pop());

    public override void _Ready()
    {
        SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        MouseFilter = Control.MouseFilterEnum.Ignore;

        var center = new CenterContainer { MouseFilter = Control.MouseFilterEnum.Ignore };
        center.SetAnchorsAndOffsetsPreset(Control.LayoutPreset.FullRect);
        AddChild(center);

        var panel = new PanelContainer
        {
            CustomMinimumSize = new Vector2(360.0f, 0.0f),
            MouseFilter = Control.MouseFilterEnum.Stop,
        };
        center.AddChild(panel);

        var margin = new MarginContainer();
        margin.AddThemeConstantOverride("margin_left", 20);
        margin.AddThemeConstantOverride("margin_top", 18);
        margin.AddThemeConstantOverride("margin_right", 20);
        margin.AddThemeConstantOverride("margin_bottom", 18);
        panel.AddChild(margin);

        var content = new VBoxContainer();
        content.AddThemeConstantOverride("separation", 12);
        margin.AddChild(content);

        content.AddChild(new Label
        {
            Text = Title,
            HorizontalAlignment = HorizontalAlignment.Center,
        });
        content.AddChild(new Label
        {
            Text = Message,
            HorizontalAlignment = HorizontalAlignment.Center,
            AutowrapMode = TextServer.AutowrapMode.WordSmart,
        });

        var actions = new HBoxContainer { Alignment = BoxContainer.AlignmentMode.End };
        actions.AddThemeConstantOverride("separation", 8);
        content.AddChild(actions);

        if (_actions.Count == 0)
            AddCloseAction("Close");
        foreach (DialogAction action in _actions)
        {
            var button = new Button { Text = action.Text };
            if (action.Callback != null)
                button.Pressed += action.Callback;
            actions.AddChild(button);
        }
    }
}
