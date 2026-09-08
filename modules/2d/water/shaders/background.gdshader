shader_type canvas_item;
render_mode unshaded;
#include "surface.gdshaderinc"
uniform vec3 uv_to_water_x;
uniform vec3 uv_to_water_y;
uniform vec3 water_to_uv_x;
uniform vec3 water_to_uv_y;
uniform vec4 regions[8];
uniform int region_count=0;
uniform float source_surface_y=7.5;
uniform vec4 air_color : source_color=vec4(0,.004,.008,1);
void fragment() {
    vec3 uv=vec3(UV,1);
    vec2 p=vec2(dot(uv_to_water_x,uv),dot(uv_to_water_y,uv));
    vec4 color=texture(TEXTURE,UV);
    for(int i=0;i<8;i++) {
        vec4 r=regions[i];
        if(i<region_count && p.x>=r.x && p.x<r.z && p.y>=r.y && p.y<r.w) {
            float surface=water_surface_at(p.x);
            if(p.y<surface) color=air_color;
            else {
                float fraction=clamp((p.y-surface)/max(r.w-surface,.5),0.0,1.0);
                vec3 source=vec3(p.x,mix(source_surface_y,r.w,fraction),1);
                color=texture(TEXTURE,vec2(dot(water_to_uv_x,source),dot(water_to_uv_y,source)));
            }
            break;
        }
    }
    COLOR=color;
}
