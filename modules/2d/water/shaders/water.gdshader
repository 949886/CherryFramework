shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
#include "surface.gdshaderinc"
uniform float clock=0.0;
uniform vec2 light_position=vec2(-10000.0);
uniform float light_strength=0.0;
uniform vec2 pattern_offset=vec2(0.0);
uniform vec2 refraction_pixels=vec2(.768,.432);
uniform float depth_range=170.0;
uniform vec4 shallow_color : source_color=vec4(.018,.25,.70,1.0);
uniform vec4 deep_color : source_color=vec4(.006,.014,.25,1.0);
uniform vec4 surface_color : source_color=vec4(.38,1.0,.90,1.0);
uniform float tint_strength=.16;
uniform float surface_thickness=1.8;
uniform float caustic_strength=1.0;
uniform float shaft_positions[8];
uniform int shaft_count=0;
uniform vec3 screen_to_water_x=vec3(1,0,0);
uniform vec3 screen_to_water_y=vec3(0,1,0);
uniform vec2 water_y_axis_screen=vec2(0,1);
varying vec2 water_position;
void vertex() { water_position=VERTEX; }
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float cellular(vec2 p) {
    vec2 cell=floor(p), f=fract(p); float nearest=4.0, second=4.0;
    for(int j=-1;j<=1;j++) { for(int i=-1;i<=1;i++) {
        vec2 g=vec2(float(i),float(j));
        vec2 o=.5+.35*sin(clock*.45+6.2831*vec2(hash(cell+g),hash(cell+g+19.7)));
        float d=length(g+o-f);
        if(d<nearest) { second=nearest; nearest=d; } else { second=min(second,d); }
    }}
    return second-nearest;
}
void fragment() {
    vec2 p=water_position;
    vec2 pattern=p+pattern_offset;
    float depth=max(0.0,p.y-water_surface_at(p.x));
    vec2 uv=SCREEN_UV+vec2(sin(pattern.y*.15+clock*2.2),cos(pattern.x*.11+clock*1.4))*refraction_pixels*SCREEN_PIXEL_SIZE;
    vec3 screen_pixel=vec3(uv/SCREEN_PIXEL_SIZE,1.0);
    vec2 sample_local=vec2(dot(screen_to_water_x,screen_pixel),dot(screen_to_water_y,screen_pixel));
    if(sample_local.x>=0.0 && sample_local.x<surface_width) {
        float correction=max(0.0,water_surface_at(sample_local.x)+2.0-sample_local.y);
        uv+=water_y_axis_screen*correction*SCREEN_PIXEL_SIZE;
    }
    vec3 scene=texture(screen_texture,uv).rgb;
    float light=exp(-distance(p,light_position)*.021)*light_strength;
    vec3 tint=mix(shallow_color.rgb,deep_color.rgb,clamp(depth/depth_range,0.0,1.0));
    vec3 attenuation=mix(vec3(.72,.95,1.05),vec3(.40,.51,.72),clamp(depth/depth_range,0.0,1.0));
    vec3 col=scene*attenuation+tint*tint_strength;
    float caustic=1.0-smoothstep(.012,.065,cellular(pattern*.065+vec2(clock*.05,-clock*.035)));
    col+=vec3(.025,.11,.25)*caustic*(.13+light*.22)*exp(-depth*.003)*caustic_strength;
    float beam=pow(max(0.0,sin(pattern.x*.08+pattern.y*.045+clock*.25)),14.0);
    col+=vec3(.06,.33,.43)*beam*exp(-depth*.023)*.24;
    float shafts=0.0;
    for(int i=0;i<8;i++) {
        if(i<shaft_count) shafts+=exp(-pow((p.x+depth*.55-shaft_positions[i])/14.0,2.0));
    }
    col+=vec3(.07,.26,.40)*shafts*exp(-depth*.018)*.7;
    col+=vec3(.015,.17,.24)*light;
    if(depth<surface_thickness && p.x>=0.0 && p.x<surface_width) col=surface_color.rgb;
    COLOR=vec4(col,1.0);
}
