// Created by Copilot on 2026-03-13.
// Virtual Skill Button capable of tracking cooldowns and max charges.

using Godot;
using System;

namespace VirtualJoystickPlugin
{
    [Tool]
    [GlobalClass]
    public partial class VirtualProgressButton : Control
    {
        #region Exported Properties
        
        [ExportGroup("Appearance")]

        [Export] public string Action { get; set; } = "";

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

        [Export] public string Label { get; set; } = "";
        [Export] public int LabelFontSize { get; set; } = 20;

        [Export(PropertyHint.Range, "0,1,0.01")]
        public float PressedScale { get; set; } = 0.9f;

        [ExportGroup("Skill Mechanics")]

        /// <summary>
        /// Cooldown progress from 0.0 (ready) to 1.0 (just used). 
        /// Modifying this will automatically redraw.
        /// </summary>
        [Export(PropertyHint.Range, "0,1,0.01")]
        public float CooldownProgress 
        {
            get => _cooldownProgress;
            set { _cooldownProgress = Mathf.Clamp(value, 0f, 1f); QueueRedraw(); }
        }

        [Export] public Color CooldownColor { get; set; } = new Color(0.1f, 0.1f, 0.1f, 0.8f);
        [Export] public float CooldownRingWidth { get; set; } = 6f;

        [Export]
        public int ChargeCount
        {
            get => _chargeCount;
            set { _chargeCount = Mathf.Max(0, value); QueueRedraw(); }
        }

        [Export]
        public int MaxChargeCount
        {
            get => _maxChargeCount;
            set { _maxChargeCount = Mathf.Max(1, value); QueueRedraw(); }
        }

        [Export] public Color ChargeDotColor { get; set; } = new Color(0.9f, 0.9f, 0.2f, 1.0f);
        [Export] public float ChargeDotRadius { get; set; } = 4f;
        [Export] public float ChargeDotSpacing { get; set; } = 12f;
        [Export] public Vector2 ChargeDotOffset { get; set; } = new Vector2(0, -15f);


        #endregion

        #region Signals

        [Signal] public delegate void PressedEventHandler();
        [Signal] public delegate void ButtonDownEventHandler();
        [Signal] public delegate void ButtonUpEventHandler();

        #endregion

        #region Private Fields

        private float _buttonRadius = 40f;
        private float _cooldownProgress = 0f;
        private int _maxChargeCount = 1;
        private int _chargeCount = 1;

        private bool _isPressed;
        private int _touchIndex = -1;

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
            if (@event is InputEventScreenTouch touch)
            {
                if (touch.Pressed)
                {
                    if (_isPressed || _chargeCount == 0) return;

                    var localPos = touch.Position - GlobalPosition;
                    var center = Size / 2f;

                    if (localPos.DistanceTo(center) <= EffectiveRadius)
                    {
                        _touchIndex = touch.Index;
                        _isPressed = true;
                        
                        if (!Engine.IsEditorHint() && !string.IsNullOrEmpty(Action) && InputMap.HasAction(Action))
                        {
                            Input.ActionPress(Action);
                        }

                        EmitSignal(SignalName.ButtonDown);
                        QueueRedraw();
                    }
                }
                else
                {
                    if (touch.Index == _touchIndex)
                    {
                        _isPressed = false;
                        _touchIndex = -1;
                        
                        if (!Engine.IsEditorHint() && !string.IsNullOrEmpty(Action) && InputMap.HasAction(Action))
                        {
                            Input.ActionRelease(Action);
                        }

                        EmitSignal(SignalName.ButtonUp);
                        EmitSignal(SignalName.Pressed);
                        QueueRedraw();
                    }
                }
            }
        }

        public override void _Draw()
        {
            var center = Size / 2f;
            var effectiveRadius = EffectiveRadius;
            var currentRadius = _isPressed ? effectiveRadius * PressedScale : effectiveRadius;
            var currentColor = _isPressed ? PressedColor : NormalColor;

            // 1. Draw Base
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
                DrawCircle(center, currentRadius, currentColor, true, -1f, true);
                
                // Outer ring
                var ringColor = new Color(currentColor.R + 0.15f, currentColor.G + 0.15f, currentColor.B + 0.15f, currentColor.A);
                DrawArc(center, currentRadius, 0f, Mathf.Tau, 128, ringColor, 2f, true);
            }

            // 2. Draw Label
            if (!string.IsNullOrEmpty(Label))
            {
                _DrawLabel(center);
            }

            // 3. Draw Cooldown Ring
            if (_cooldownProgress > 0f && _chargeCount == 0)
            {
                // Start from top (which is -PI/2) and draw clockwise up to CooldownProgress * Tau.
                float startAngle = -Mathf.Pi / 2f;
                // Arc covers current percentage. We will draw from start angle to startAngle + mapped rotation.
                float endAngle = startAngle + (Mathf.Tau * _cooldownProgress);
                
                // Fill the center semi-transparent to visually indicate disabled state 
                DrawCircle(center, currentRadius, new Color(0, 0, 0, 0.4f));

                var arcRadius = currentRadius * 0.9f;
                var progressColor = new Color(currentColor.R + 0.2f, currentColor.G + 0.2f, currentColor.B + 0.2f, 1.0f);

                // Draw the progress arc
                // Be careful that DrawArc cannot handle straight full circle if start = end, handles that natively.
                if (_cooldownProgress >= 0.999f)
                {
                    DrawArc(center, arcRadius, 0, Mathf.Tau, 64, CooldownColor, CooldownRingWidth, true);
                }
                else
                {
                    DrawArc(center, arcRadius, startAngle, endAngle, Mathf.Max(8, (int)(64 * _cooldownProgress)), progressColor, CooldownRingWidth, true);
                }
            }

            // 4. Draw Charge Dots
            if (_maxChargeCount >= 2)
            {
                _DrawChargeDots(center, currentRadius);
            }
        }

        private void _DrawChargeDots(Vector2 center, float currentRadius)
        {
            // Position above the button using ChargeDotOffset
            Vector2 basePos = center + new Vector2(0, -effectiveRadius(currentRadius)) + ChargeDotOffset;
            float totalWidth = (_maxChargeCount - 1) * ChargeDotSpacing;
            float startX = basePos.X - totalWidth / 2f;

            for (int i = 0; i < _maxChargeCount; i++)
            {
                Vector2 dotPos = new Vector2(startX + i * ChargeDotSpacing, basePos.Y);
                bool isFilled = i < _chargeCount;

                // If filled, draw full circle. If empty, draw outline
                if (isFilled)
                {
                    DrawCircle(dotPos, ChargeDotRadius, ChargeDotColor, true, -1f, true);
                }
                else
                {
                    // Draw outer ring only, with slightly darker color for visibility
                    DrawArc(dotPos, ChargeDotRadius, 0f, Mathf.Tau, 16, ChargeDotColor, 1.5f, true);
                }
            }
        }

        private float effectiveRadius(float drawnRadius)
        {
            return _buttonRadius; // return stable base radius instead of pressed scaling bounding radius.
        }

        public override Vector2 _GetMinimumSize()
        {
            return new Vector2(_buttonRadius * 2f, _buttonRadius * 2f);
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
            if (what == NotificationPredelete && !Engine.IsEditorHint())
            {
                if (!string.IsNullOrEmpty(Action) && InputMap.HasAction(Action) && Input.IsActionPressed(Action))
                {
                    Input.ActionRelease(Action);
                }
            }
            else if (what == NotificationResized)
            {
                QueueRedraw();
            }
        }

        #endregion
    }
}
