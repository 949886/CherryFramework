// Created by Copilot on 2026-03-10.
// Touch Input Manager - Unified mobile touch controls layout.

using Godot;
using System;

namespace VirtualJoystickPlugin
{
    /// <summary>
    /// A ready-to-use mobile touch control layout that creates a joystick + action buttons.
    /// Add this node to your scene and configure via exported properties.
    /// It will automatically create child controls if they are not present.
    /// </summary>
    [GlobalClass]
    public partial class TouchInputManager : CanvasLayer
    {
        #region Exported Properties

        [ExportGroup("General")]

        [Export] public bool AutoHideOnDesktop { get; set; } = true;

        [Export(PropertyHint.Range, "0.5,3.0,0.1")]
        public float ControlScale { get; set; } = 1.0f;

        [ExportGroup("Joystick Settings")]

        [Export] public CherryVirtualJoystick.JoystickMode JoystickMode { get; set; } = CherryVirtualJoystick.JoystickMode.Fixed;
        [Export] public CherryVirtualJoystick.VisibilityMode JoystickVisibility { get; set; } = CherryVirtualJoystick.VisibilityMode.Always;

        [Export] public string MoveLeftAction { get; set; } = "move_left";
        [Export] public string MoveRightAction { get; set; } = "move_right";
        [Export] public string MoveUpAction { get; set; } = "jump";
        [Export] public string MoveDownAction { get; set; } = "move_down";

        [ExportGroup("Button Settings")]

        [Export] public bool ShowJumpButton { get; set; } = true;
        [Export] public string JumpAction { get; set; } = "jump";

        [Export] public bool ShowAttackButton { get; set; } = true;
        [Export] public string AttackAction { get; set; } = "attack";

        [Export] public bool ShowDashButton { get; set; } = false;
        [Export] public string DashAction { get; set; } = "dash";

        #endregion

        #region Signals

        [Signal] public delegate void JoystickInputChangedEventHandler(Vector2 output);

        #endregion

        #region Private Fields

        private CherryVirtualJoystick _joystick;
        private VirtualButton _jumpButton;
        private VirtualButton _attackButton;
        private VirtualButton _dashButton;
        private Control _container;

        #endregion

        #region Public API

        /// <summary>Access the joystick component directly.</summary>
        public CherryVirtualJoystick Joystick => _joystick;

        /// <summary>Current joystick output.</summary>
        public Vector2 JoystickOutput => _joystick?.Output ?? Vector2.Zero;

        /// <summary>Show or hide all touch controls at runtime.</summary>
        public void SetControlsVisible(bool visible)
        {
            if (_container != null)
                _container.Visible = visible;
        }

        #endregion

        #region Lifecycle

        public override void _Ready()
        {
            // Hide on desktop if configured
            if (AutoHideOnDesktop && !_IsMobilePlatform())
            {
                // Still create controls but hide them - useful for testing
                // Toggle with SetControlsVisible(true) to test on desktop
            }

            _CreateLayout();
        }

        #endregion

        #region Layout Creation

        private void _CreateLayout()
        {
            // Root container - full screen
            _container = new Control();
            _container.Name = "TouchControls";
            _container.SetAnchorsPreset(Control.LayoutPreset.FullRect);
            _container.MouseFilter = Control.MouseFilterEnum.Ignore;
            AddChild(_container);

            _CreateJoystick();
            _CreateActionButtons();

            if (AutoHideOnDesktop && !_IsMobilePlatform())
            {
                _container.Visible = false;
            }
        }

        private void _CreateJoystick()
        {
            // Joystick touch area - left side of screen
            var joystickArea = new Control();
            joystickArea.Name = "JoystickArea";
            joystickArea.SetAnchorsPreset(Control.LayoutPreset.BottomLeft);
            joystickArea.MouseFilter = Control.MouseFilterEnum.Ignore;

            float baseRadius = 75f * ControlScale;
            float areaSize = baseRadius * 4f;
            joystickArea.Size = new Vector2(areaSize, areaSize);
            joystickArea.Position = new Vector2(30f * ControlScale, -areaSize - 30f * ControlScale);

            _container.AddChild(joystickArea);

            // Create joystick
            _joystick = new CherryVirtualJoystick();
            _joystick.Name = "CherryVirtualJoystick";
            _joystick.Mode = JoystickMode;
            _joystick.Visibility = JoystickVisibility;
            _joystick.BaseRadius = baseRadius;
            _joystick.HandleRadius = 35f * ControlScale;
            _joystick.DeadZone = 0.2f;
            _joystick.ClampZone = 1.0f;

            _joystick.ActionLeft = MoveLeftAction;
            _joystick.ActionRight = MoveRightAction;
            _joystick.ActionUp = MoveUpAction;
            _joystick.ActionDown = MoveDownAction;

            // Center joystick in area
            _joystick.Position = new Vector2(
                (areaSize - baseRadius * 2f) / 2f,
                (areaSize - baseRadius * 2f) / 2f
            );
            _joystick.Size = new Vector2(baseRadius * 2f, baseRadius * 2f);

            _joystick.JoystickInput += (output) => EmitSignal(SignalName.JoystickInputChanged, output);

            joystickArea.AddChild(_joystick);
        }

        private void _CreateActionButtons()
        {
            // Button container - right side of screen
            float buttonRadius = 40f * ControlScale;
            float spacing = 20f * ControlScale;
            float rightMargin = 30f * ControlScale;
            float bottomMargin = 30f * ControlScale;            var buttonArea = new Control();
            buttonArea.Name = "ButtonArea";
            buttonArea.SetAnchorsPreset(Control.LayoutPreset.BottomRight);
            buttonArea.MouseFilter = Control.MouseFilterEnum.Ignore;

            // Calculate button area size
            float areaWidth = buttonRadius * 2f * 2f + spacing; // 2 columns
            float areaHeight = buttonRadius * 2f * 2f + spacing; // 2 rows
            buttonArea.Size = new Vector2(areaWidth, areaHeight);
            buttonArea.Position = new Vector2(-areaWidth - rightMargin, -areaHeight - bottomMargin);

            _container.AddChild(buttonArea);

            // Layout buttons in a diamond/arc pattern (common in mobile games):
            //        [Jump]
            //  [Dash]      [Attack]
            float centerX = areaWidth / 2f;
            float centerY = areaHeight / 2f;

            if (ShowAttackButton)
            {
                _attackButton = _CreateButton("AttackButton", AttackAction, "A", buttonRadius);
                _attackButton.PressedColor = new Color(0.8f, 0.3f, 0.3f, 0.9f);
                _attackButton.Position = new Vector2(
                    areaWidth - buttonRadius * 2f,
                    centerY - buttonRadius
                );
                buttonArea.AddChild(_attackButton);
            }

            if (ShowJumpButton)
            {
                _jumpButton = _CreateButton("JumpButton", JumpAction, "B", buttonRadius);
                _jumpButton.PressedColor = new Color(0.3f, 0.6f, 0.8f, 0.9f);
                _jumpButton.Position = new Vector2(
                    centerX - buttonRadius,
                    0
                );
                buttonArea.AddChild(_jumpButton);
            }

            if (ShowDashButton)
            {
                _dashButton = _CreateButton("DashButton", DashAction, "X", buttonRadius);
                _dashButton.PressedColor = new Color(0.3f, 0.8f, 0.3f, 0.9f);
                _dashButton.Position = new Vector2(
                    0,
                    centerY - buttonRadius
                );
                buttonArea.AddChild(_dashButton);
            }
        }

        private VirtualButton _CreateButton(string name, string action, string label, float radius)
        {
            var button = new VirtualButton();
            button.Name = name;
            button.Action = action;
            button.Label = label;
            button.ButtonRadius = radius;
            button.Size = new Vector2(radius * 2f, radius * 2f);
            return button;
        }

        #endregion

        #region Utilities

        private bool _IsMobilePlatform()
        {
            return OS.HasFeature("mobile") || OS.HasFeature("android") || OS.HasFeature("ios");
        }

        #endregion
    }
}
