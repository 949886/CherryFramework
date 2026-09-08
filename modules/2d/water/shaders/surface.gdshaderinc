uniform sampler2D surface_profile : filter_linear, repeat_disable;
uniform float surface_width=256.0;
float water_surface_at(float x) {
    float t=clamp(x/max(surface_width,.001),0.0,1.0);
    float count=float(textureSize(surface_profile,0).x);
    return texture(surface_profile,vec2((t*(count-1.0)+.5)/count,.5)).r;
}
