// Created by Copilot on 2026-03-10.
// Virtual Joystick plugin for Godot 4.x with C#.

using Godot;
using System;

namespace VirtualJoystickPlugin
{
    /// <summary>
    /// A virtual joystick control for mobile touch input.
    /// Supports Fixed, Dynamic (appears at touch position), and Following (follows finger) modes.
    /// </summary>
    [Tool]
    [GlobalClass]
    public partial class CherryVirtualJoystick : Control
    {
        #region Enums

        public enum JoystickMode
        {
            /// <summary>Joystick stays at its initial position.</summary>
            Fixed,
            /// <summary>Joystick appears where the player touches.</summary>
            Dynamic,
            /// <summary>Joystick base follows the thumb when it exceeds the clamp zone.</summary>
            Following,
            /// <summary>
            /// Combines Dynamic and Following: the joystick appears at the touch position
            /// (like Dynamic) and then the base follows the thumb when it exceeds the
            /// clamp zone (like Following).
            /// </summary>
            DynamicFollowing
        }

        public enum VisibilityMode
        {
            /// <summary>Always visible.</summary>
            Always,
            /// <summary>Only visible when touched.</summary>
            TouchOnly,
            /// <summary>Always visible but changes opacity when touched.</summary>
            FadeInOut
        }

        #endregion

        #region Exported Properties

        [ExportGroup("Joystick")]

        /// <summary>
        /// The behavior mode of the virtual joystick.
        /// Fixed: Stays in place.
        /// Dynamic: Appears where the user touches within the control area.
        /// Following: Moves its base to follow the user's finger.
        /// DynamicFollowing: Appears at the touch point (like Dynamic) and then
        /// follows the finger when it exceeds the clamp zone (like Following).
        /// </summary>
        [Export]
        public JoystickMode Mode
        {
            get => _mode;
            set { _mode = value; QueueRedraw(); }
        }

        /// <summary>
        /// Controls when the joystick is visible.
        /// Always: Always visible.
        /// TouchOnly: Only visible when actively being touched.
        /// FadeInOut: Always visible but changes opacity when touched.
        /// </summary>
        [Export]
        public VisibilityMode Visibility
        {
            get => _visibilityMode;
            set
            {
                _visibilityMode = value;
                _UpdateVisibility();
                QueueRedraw();
            }
        }

        /// <summary>
        /// The inner zone (0.0 to 1.0) where input is ignored.
        /// Useful for preventing drift or accidental small inputs.
        /// </summary>
        [Export(PropertyHint.Range, "0,1,0.01")]
        public float DeadZone
        {
            get => _deadZone;
            set => _deadZone = Mathf.Clamp(value, 0f, 1f);
        }

        /// <summary>
        /// The outer limit (relative to base radius) where the handle stops moving.
        /// Values less than 1.0 restrict handle movement inside the base.
        /// </summary>
        [Export(PropertyHint.Range, "-1,1,0.01")]
        public float ClampZone
        {
            get => _clampZone;
            set => _clampZone = Mathf.Clamp(value, -1f, 1f);
        }

        /// <summary>
        /// Extra margin (in pixels) around the control rect that accepts touch input.
        /// Only applies to Dynamic and Following modes. Use this to make the touch area
        /// larger than the visible joystick. Set to 0 for no extra margin.
        /// </summary>
        [Export(PropertyHint.Range, "0,1000,1")]
        public float TouchAreaMargin
        {
            get => _touchAreaMargin;
            set => _touchAreaMargin = Mathf.Max(value, 0f);
        }

        [ExportGroup("Input Actions")]

        /// <summary>Input action name to trigger when moving left.</summary>
        [Export] public string ActionLeft { get; set; } = "";
        
        /// <summary>Input action name to trigger when moving right.</summary>
        [Export] public string ActionRight { get; set; } = "";
        
        /// <summary>Input action name to trigger when moving up.</summary>
        [Export] public string ActionUp { get; set; } = "";
        
        /// <summary>Input action name to trigger when moving down.</summary>
        [Export] public string ActionDown { get; set; } = "";

        [ExportGroup("Appearance")]

        /// <summary>Texture used for the background/base of the joystick. If null, a circle is drawn.</summary>
        [Export] public Texture2D BaseTexture { get; set; }
        
        /// <summary>Texture used for the movable handle of the joystick. If null, a circle is drawn.</summary>
        [Export] public Texture2D HandleTexture { get; set; }

        /// <summary>Radius of the joystick base in pixels.</summary>
        [Export]
        public float BaseRadius
        {
            get => _baseRadius;
            set { _baseRadius = Mathf.Max(value, 10f); _UpdateMinimumSize(); QueueRedraw(); }
        }

        /// <summary>Radius of the joystick handle in pixels.</summary>
        [Export]
        public float HandleRadius
        {
            get => _handleRadius;
            set { _handleRadius = Mathf.Max(value, 5f); QueueRedraw(); }
        }

        /// <summary>Color of the joystick base when no texture is provided, or tint if texture is present.</summary>
        [Export] public Color BaseColor { get; set; } = new Color(0.15f, 0.15f, 0.15f, 0.6f);
        
        /// <summary>Color of the joystick handle when at rest.</summary>
        [Export] public Color HandleColor { get; set; } = new Color(0.8f, 0.8f, 0.8f, 0.8f);
        
        /// <summary>Color of the joystick handle when actively pressed.</summary>
        [Export] public Color HandlePressedColor { get; set; } = new Color(1f, 1f, 1f, 1f);

        /// <summary>Opacity of the joystick when not being touched (used in FadeInOut mode).</summary>
        [Export(PropertyHint.Range, "0,1,0.01")]
        public float InactiveOpacity { get; set; } = 0.5f;

        /// <summary>Opacity of the joystick when being touched (used in FadeInOut mode).</summary>
        [Export(PropertyHint.Range, "0,1,0.01")]
        public float ActiveOpacity { get; set; } = 1.0f;

        #endregion

        #region Signals

        [Signal] public delegate void JoystickInputEventHandler(Vector2 output);
        [Signal] public delegate void JoystickPressedEventHandler();
        [Signal] public delegate void JoystickReleasedEventHandler();

        #endregion

        #region Private Fields

        private JoystickMode _mode = JoystickMode.Fixed;
        private VisibilityMode _visibilityMode = VisibilityMode.Always;
        private float _deadZone = 0.2f;
        private float _clampZone = 1.0f;
        private float _touchAreaMargin = 100f;
        private float _baseRadius = 75f;
        private float _handleRadius = 35f;

        private bool _isPressed;
        private int _touchIndex = -1;
        private Vector2 _output = Vector2.Zero;

        // Positions relative to center of control
        private Vector2 _baseCenter;
        private Vector2 _handlePosition;
        private Vector2 _initialPosition; // For Dynamic/Following mode

        #endregion

        #region Public API

        /// <summary>
        /// Current joystick output as a normalized Vector2 (after dead zone applied).
        /// X: -1 (left) to 1 (right), Y: -1 (up) to 1 (down).
        /// </summary>
        public Vector2 Output => _output;

        /// <summary>Whether the joystick is currently being pressed.</summary>
        public bool IsPressed => _isPressed;

        /// <summary>Current output strength (0 to 1).</summary>
        public float Strength => _output.Length();

        /// <summary>Current output angle in radians.</summary>
        public float Angle => _output.Angle();

        /// <summary>
        /// The effective base radius derived from the control's current Size.
        /// Drawing and hit-testing use this value so the joystick always fits its Control rect.
        /// </summary>
        public float EffectiveBaseRadius => Mathf.Min(Size.X, Size.Y) / 2f;

        /// <summary>
        /// The effective handle radius, scaled proportionally to the control's current Size.
        /// If BaseRadius is 0 or HandleRadius is 0, falls back to a sensible default.
        /// </summary>
        public float EffectiveHandleRadius =>
            _baseRadius > 0f
                ? EffectiveBaseRadius * (_handleRadius / _baseRadius)
                : EffectiveBaseRadius * 0.47f;

        #endregion

        #region Lifecycle

        public override void _Ready()
        {
            _initialPosition = Position;
            _baseCenter = Size / 2f;
            _handlePosition = _baseCenter;

            _UpdateVisibility();
            _UpdateMinimumSize();
        }

        public override void _Input(InputEvent @event)
        {
            if (@event is InputEventScreenTouch touchEvent)
            {
                _HandleTouchEvent(touchEvent);
            }
            else if (@event is InputEventScreenDrag dragEvent)
            {
                _HandleDragEvent(dragEvent);
            }
        }

        public override void _Draw()
        {
            _DrawBase();
            _DrawHandle();
        }

        public override Vector2 _GetMinimumSize()
        {
            return new Vector2(_baseRadius * 2f, _baseRadius * 2f);
        }

        #endregion

        #region Input Handling

        private void _HandleTouchEvent(InputEventScreenTouch touch)
        {
            if (touch.Pressed)
            {
                if (_isPressed) return; // Already tracking a finger

                if (_mode == JoystickMode.Fixed)
                {
                    // Check if touch is within the base circle
                    var localPos = _ScreenToLocal(touch.Position);
                    if (localPos.DistanceTo(_baseCenter) <= EffectiveBaseRadius)
                    {
                        _StartTouch(touch.Index, localPos);
                    }
                }
                else // Dynamic, Following, or DynamicFollowing
                {
                    // Check if touch is within the expanded touch area
                    var expandedRect = GetGlobalRect().Grow(_touchAreaMargin);
                    if (expandedRect.HasPoint(touch.Position))
                    {
                        var localPos = _ScreenToLocal(touch.Position);
                        _baseCenter = localPos;
                        _handlePosition = localPos;
                        _StartTouch(touch.Index, localPos);
                    }
                }
            }
            else // Released
            {
                if (touch.Index == _touchIndex)
                {
                    _EndTouch();
                }
            }
        }

        private void _HandleDragEvent(InputEventScreenDrag drag)
        {
            if (drag.Index != _touchIndex) return;

            var localPos = _ScreenToLocal(drag.Position);
            _UpdateHandlePosition(localPos);
        }

        private void _StartTouch(int index, Vector2 localPos)
        {
            _touchIndex = index;
            _isPressed = true;

            _UpdateHandlePosition(localPos);
            _UpdateVisibility();
            EmitSignal(SignalName.JoystickPressed);
            QueueRedraw();
        }

        private void _EndTouch()
        {
            _isPressed = false;
            _touchIndex = -1;
            _output = Vector2.Zero;

            // Reset positions
            if (_mode != JoystickMode.Fixed)
            {
                _baseCenter = Size / 2f;
            }
            _handlePosition = _baseCenter;

            _UpdateInputActions(Vector2.Zero);
            _UpdateVisibility();
            EmitSignal(SignalName.JoystickInput, Vector2.Zero);
            EmitSignal(SignalName.JoystickReleased);
            QueueRedraw();
        }

        private void _UpdateHandlePosition(Vector2 localPos)
        {
            var diff = localPos - _baseCenter;
            var dist = diff.Length();
            var effectiveRadius = EffectiveBaseRadius;
            var maxDist = effectiveRadius * _clampZone;

            // Following and DynamicFollowing modes: move base to follow the thumb
            if ((_mode == JoystickMode.Following || _mode == JoystickMode.DynamicFollowing) && dist > maxDist && maxDist > 0)
            {
                var overflow = diff.Normalized() * (dist - maxDist);
                _baseCenter += overflow;
            }

            // Clamp handle within the clamp zone
            if (maxDist > 0 && dist > maxDist)
            {
                _handlePosition = _baseCenter + diff.Normalized() * maxDist;
            }
            else
            {
                _handlePosition = localPos;
            }

            // Calculate normalized output
            if (maxDist > 0)
            {
                var rawOutput = (_handlePosition - _baseCenter) / maxDist;

                // Apply dead zone
                var strength = rawOutput.Length();
                if (strength < _deadZone)
                {
                    _output = Vector2.Zero;
                }
                else
                {
                    // Remap from [deadZone, 1] to [0, 1]
                    var remappedStrength = (strength - _deadZone) / (1f - _deadZone);
                    _output = rawOutput.Normalized() * Mathf.Min(remappedStrength, 1f);
                }
            }
            else
            {
                _output = Vector2.Zero;
            }

            _UpdateInputActions(_output);
            EmitSignal(SignalName.JoystickInput, _output);
            QueueRedraw();
        }

        #endregion

        #region Input Action Mapping

        private void _UpdateInputActions(Vector2 output)
        {
            if (Engine.IsEditorHint()) return;

            _UpdateSingleAction(ActionLeft, -output.X);
            _UpdateSingleAction(ActionRight, output.X);
            _UpdateSingleAction(ActionUp, -output.Y);
            _UpdateSingleAction(ActionDown, output.Y);
        }

        private void _UpdateSingleAction(string action, float strength)
        {
            if (string.IsNullOrEmpty(action)) return;
            if (!InputMap.HasAction(action)) return;

            if (strength > 0)
            {
                if (!Input.IsActionPressed(action))
                {
                    Input.ActionPress(action, strength);
                }
                else
                {
                    // Update action strength by re-pressing
                    Input.ActionRelease(action);
                    Input.ActionPress(action, strength);
                }
            }
            else
            {
                if (Input.IsActionPressed(action))
                {
                    Input.ActionRelease(action);
                }
            }
        }

        #endregion

        #region Drawing

        private void _DrawBase()
        {
            var radius = EffectiveBaseRadius;

            if (BaseTexture != null)
            {
                var texSize = BaseTexture.GetSize();
                var scale = (radius * 2f) / Mathf.Max(texSize.X, texSize.Y);
                var drawPos = _baseCenter - texSize * scale / 2f;
                DrawTextureRect(BaseTexture, new Rect2(drawPos, texSize * scale), false, BaseColor);
            }
            else
            {
                // Draw default filled circle with antialiasing
                DrawCircle(_baseCenter, radius, BaseColor, true, -1f, true);

                // Draw dead zone indicator (subtle ring)
                if (_deadZone > 0)
                {
                    var dzColor = new Color(BaseColor.R, BaseColor.G, BaseColor.B, BaseColor.A * 0.3f);
                    DrawArc(_baseCenter, radius * _deadZone, 0f, Mathf.Tau, 128, dzColor, 1.5f, true);
                }

                // Draw outer ring
                var ringColor = new Color(BaseColor.R + 0.1f, BaseColor.G + 0.1f, BaseColor.B + 0.1f, BaseColor.A * 0.8f);
                DrawArc(_baseCenter, radius, 0f, Mathf.Tau, 128, ringColor, 2f, true);
            }
        }

        private void _DrawHandle()
        {
            var color = _isPressed ? HandlePressedColor : HandleColor;
            var radius = EffectiveHandleRadius;

            if (HandleTexture != null)
            {
                var texSize = HandleTexture.GetSize();
                var scale = (radius * 2f) / Mathf.Max(texSize.X, texSize.Y);
                var drawPos = _handlePosition - texSize * scale / 2f;
                DrawTextureRect(HandleTexture, new Rect2(drawPos, texSize * scale), false, color);
            }
            else
            {
                // Draw default handle with antialiasing
                DrawCircle(_handlePosition, radius, color, true, -1f, true);

                // Draw handle border
                var borderColor = new Color(color.R * 0.8f, color.G * 0.8f, color.B * color.A);
                DrawArc(_handlePosition, radius, 0f, Mathf.Tau, 128, borderColor, 2f, true);

                // Draw inner highlight
                var highlightColor = new Color(1f, 1f, 1f, color.A * 0.3f);
                DrawCircle(_handlePosition, radius * 0.4f, highlightColor, true, -1f, true);            }
        }

        #endregion

        #region Visibility

        private void _UpdateVisibility()
        {
            switch (_visibilityMode)
            {
                case VisibilityMode.Always:
                    Modulate = new Color(Modulate, 1f);
                    Visible = true;
                    break;

                case VisibilityMode.TouchOnly:
                    Visible = _isPressed;
                    break;

                case VisibilityMode.FadeInOut:
                    Visible = true;
                    var targetAlpha = _isPressed ? ActiveOpacity : InactiveOpacity;
                    var tween = CreateTween();
                    tween.TweenProperty(this, "modulate:a", targetAlpha, 0.15);
                    break;
            }
        }

        #endregion

        #region Utilities

        private Vector2 _ScreenToLocal(Vector2 screenPos)
        {
            return screenPos - GlobalPosition;
        }

        private void _UpdateMinimumSize()
        {
            CustomMinimumSize = _GetMinimumSize();
        }

        public override void _Notification(int what)
        {
            if (what == NotificationPredelete)
            {
                // Clean up input actions on removal
                if (!Engine.IsEditorHint())
                {
                    _ReleaseAllActions();
                }
            }
            else if (what == NotificationResized)
            {
                // Keep base center and handle position in sync when the control is resized
                _baseCenter = Size / 2f;
                if (!_isPressed)
                {
                    _handlePosition = _baseCenter;
                }
                QueueRedraw();
            }
        }

        private void _ReleaseAllActions()
        {
            _ReleaseAction(ActionLeft);
            _ReleaseAction(ActionRight);
            _ReleaseAction(ActionUp);
            _ReleaseAction(ActionDown);
        }

        private void _ReleaseAction(string action)
        {
            if (string.IsNullOrEmpty(action)) return;
            if (!InputMap.HasAction(action)) return;
            if (Input.IsActionPressed(action))
            {
                Input.ActionRelease(action);
            }
        }

        #endregion
    }
}
