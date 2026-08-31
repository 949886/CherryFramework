// Created by Copilot on 2026-03-10.
// Virtual Direction Button for mobile touch input in Godot 4.x.

using Godot;
using System;

namespace VirtualJoystickPlugin
{
    /// <summary>
    /// A virtual button for mobile touch input that provides directional aiming.
    /// Triggers when dragged to the edge or released, passing an angle (in radians) via signal.
    /// </summary>
    [Tool]
    [GlobalClass]
    public partial class VirtualDirectionButton : Control
    {
        #region Exported Properties
        
        [ExportGroup("Appearance")]

        [Export] public Texture2D NormalTexture { get; set; }
        [Export] public Texture2D PressedTexture { get; set; }

        [Export]
        public float ButtonRadius
        {
            get => _buttonRadius;
            set { _buttonRadius = Mathf.Max(value, 10f); _UpdateMinimumSize(); QueueRedraw(); }
        }

        [Export] public Color NormalColor { get; set; } = new Color(0.2f, 0.2f, 0.2f, 0.6f);
        [Export] public Color PressedColor { get; set; } = new Color(0.5f, 0.5f, 0.5f, 0.9f);
        [Export] public Color IconColor { get; set; } = Colors.White;
        
        [Export] public Color ArcColor { get; set; } = new Color(1f, 0.6f, 0.2f, 1f);
        [Export] public float ArcWidth { get; set; } = 4f;
        [Export(PropertyHint.Range, "0,3.14,0.01")] public float ArcSpread { get; set; } = 0.5f;

        [Export] public string Label { get; set; } = "";
        [Export] public int LabelFontSize { get; set; } = 20;

        [Export(PropertyHint.Range, "0,1,0.01")]
        public float PressedScale { get; set; } = 0.9f;

        #endregion

        #region Signals

        [Signal] public delegate void DirectionActivatedEventHandler(float angle);
        [Signal] public delegate void ButtonDownEventHandler();

        #endregion

        #region Private Fields

        private float _buttonRadius = 40f;
        private bool _isPressed;
        private int _touchIndex = -1;
        
        private float _currentAngle = 0f;

        #endregion

        #region Public API

        public bool IsPressed => _isPressed;

        public float EffectiveRadius => Mathf.Min(Size.X, Size.Y) / 2f;

        #endregion

        #region Lifecycle

        public override void _Ready()
        {
            _UpdateMinimumSize();
        }

        public override void _Input(InputEvent @event)
        {
            if (@event is InputEventScreenTouch touchEvent)
            {
                _HandleTouch(touchEvent);
            }
            else if (@event is InputEventScreenDrag dragEvent)
            {
                _HandleDrag(dragEvent);
            }
        }

        public override void _Draw()
        {
            var center = Size / 2f;
            var effectiveRadius = EffectiveRadius;
            var currentRadius = _isPressed ? effectiveRadius * PressedScale : effectiveRadius;
            var currentColor = _isPressed ? PressedColor : NormalColor;

            if (_isPressed && PressedTexture != null)
            {
                _DrawTexture(PressedTexture, center, currentRadius, currentColor);
            }
            else if (NormalTexture != null)
            {
                _DrawTexture(NormalTexture, center, currentRadius, currentColor);
            }
            else
            {
                // Draw default circle button with antialiasing
                DrawCircle(center, currentRadius, currentColor, true, -1f, true);

                // Outer ring with antialiasing
                var ringColor = new Color(currentColor.R + 0.15f, currentColor.G + 0.15f, currentColor.B + 0.15f, currentColor.A);
                DrawArc(center, currentRadius, 0f, Mathf.Tau, 128, ringColor, 2f, true);

                // Inner highlight
                if (_isPressed)
                {
                    var highlightColor = new Color(1f, 1f, 1f, 0.15f);
                    DrawCircle(center, currentRadius * 0.7f, highlightColor, true, -1f, true);
                    
                    // Direction Arc Outline Indicator
                    var arcRadius = currentRadius * 0.9f;
                    DrawArc(center, arcRadius, _currentAngle - ArcSpread, _currentAngle + ArcSpread, 32, ArcColor, ArcWidth, true);
                }
            }

            // Draw label text
            if (!string.IsNullOrEmpty(Label))
            {
                _DrawLabel(center);
            }
        }

        public override Vector2 _GetMinimumSize()
        {
            return new Vector2(_buttonRadius * 2f, _buttonRadius * 2f);
        }

        #endregion

        #region Input Handling

        private void _HandleTouch(InputEventScreenTouch touch)
        {
            if (touch.Pressed)
            {
                if (_isPressed) return;

                var localPos = touch.Position - GlobalPosition;
                var center = Size / 2f;
                if (localPos.DistanceTo(center) <= EffectiveRadius)
                {
                    _Press(touch.Index, localPos, center);
                }
            }
            else
            {
                if (touch.Index == _touchIndex)
                {
                    // Trigger throw on release
                    _ReleaseAndActivate();
                }
            }
        }

        private void _HandleDrag(InputEventScreenDrag drag)
        {
            if (drag.Index != _touchIndex) return;

            var localPos = drag.Position - GlobalPosition;
            var center = Size / 2f;
            var dist = localPos.DistanceTo(center);
            
            if (dist > 1f)
            {
                _currentAngle = (localPos - center).Angle();
            }

            // If dragged outside the effective radius, trigger action immediately
            if (dist >= EffectiveRadius * 1f)
            {
                _ReleaseAndActivate();
            }
            else
            {
                QueueRedraw();
            }
        }

        private void _Press(int index, Vector2 localPos, Vector2 center)
        {
            _touchIndex = index;
            _isPressed = true;
            
            if (localPos.DistanceTo(center) > 1f)
                _currentAngle = (localPos - center).Angle();
            else
                _currentAngle = 0f; // Default facing right if pressed exactly dead center

            EmitSignal(SignalName.ButtonDown);
            QueueRedraw();
        }

        private void _ReleaseAndActivate()
        {
            _isPressed = false;
            _touchIndex = -1;

            if (!Engine.IsEditorHint())
            {
                EmitSignal(SignalName.DirectionActivated, _currentAngle);
            }

            QueueRedraw();
        }

        #endregion

        #region Drawing Helpers

        private void _DrawTexture(Texture2D texture, Vector2 center, float radius, Color modulate)
        {
            var texSize = texture.GetSize();
            var scale = (radius * 2f) / Mathf.Max(texSize.X, texSize.Y);
            var drawPos = center - texSize * scale / 2f;
            DrawTextureRect(texture, new Rect2(drawPos, texSize * scale), false, modulate);
        }

        private void _DrawLabel(Vector2 center)
        {
            var font = ThemeDB.FallbackFont;
            if (font == null) return;

            var scaledFontSize = _buttonRadius > 0f
                ? (int)(LabelFontSize * (EffectiveRadius / _buttonRadius))
                : LabelFontSize;
            scaledFontSize = Mathf.Max(scaledFontSize, 8); 

            var textSize = font.GetStringSize(Label, HorizontalAlignment.Center, -1, scaledFontSize);
            var textPos = center - new Vector2(textSize.X / 2f, -textSize.Y / 4f);
            DrawString(font, textPos, Label, HorizontalAlignment.Center, -1, scaledFontSize, IconColor);
        }

        private void _UpdateMinimumSize()
        {
            CustomMinimumSize = _GetMinimumSize();
        }

        #endregion

        #region Cleanup

        public override void _Notification(int what)
        {
            if (what == NotificationResized)
            {
                QueueRedraw();
            }
        }

        #endregion
    }
}
