shader_type canvas_item;
render_mode unshaded;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0, 0.97, 0.98, 0.7);
uniform float blur_pixels : hint_range(0.0, 40.0) = 22.0;
uniform float saturation : hint_range(0.5, 2.0) = 1.45;
uniform vec2 panel_size = vec2(1152.0, 185.0);
uniform float radius = 18.0;

void fragment() {
    // Preserve inherited entrance/selection/menu opacity. Assigning a new
    // COLOR below would otherwise make a fading Control's glass stay opaque.
    float surface_opacity = COLOR.a;
    // Only the scene already drawn behind this card is sampled. Text is drawn
    // later as ordinary Controls and therefore never passes through this blur.
    float lod = log2(max(1.0, blur_pixels * 0.5));
    vec3 blurred = textureLod(screen_texture, SCREEN_UV, lod).rgb;
    float luminance = dot(blurred, vec3(0.2126, 0.7152, 0.0722));
    blurred = mix(vec3(luminance), blurred, saturation);
    vec2 q = abs((UV - 0.5) * panel_size) - panel_size * 0.5 + radius;
    float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    float mask = 1.0 - smoothstep(-1.0, 1.0, distance);
    COLOR = vec4(mix(blurred, tint.rgb, tint.a), mask * surface_opacity);
}
