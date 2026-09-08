shader_type canvas_item;
render_mode unshaded;
#include "surface.gdshaderinc"
// UV 与水体局部坐标之间的双向仿射变换，由背景适配器每帧同步。
uniform vec3 uv_to_water_x;
uniform vec3 uv_to_water_y;
uniform vec3 water_to_uv_x;
uniform vec3 water_to_uv_y;
// 每项为局部矩形 (左, 上, 右, 下)，只有这些浅水区域允许重建原图水位。
uniform vec4 regions[8];
uniform int region_count=0;
uniform float source_surface_y=7.5;
uniform vec4 air_color : source_color=vec4(0,.004,.008,1);
void fragment() {
    vec3 uv=vec3(UV,1);
    // 先把当前纹素转为水体局部坐标，再判断它位于动态水面之上还是之下。
    vec2 p=vec2(dot(uv_to_water_x,uv),dot(uv_to_water_y,uv));
    vec4 color=texture(TEXTURE,UV);
    for(int i=0;i<8;i++) {
        vec4 r=regions[i];
        if(i<region_count && p.x>=r.x && p.x<r.z && p.y>=r.y && p.y<r.w) {
            float surface=water_surface_at(p.x);
            // 退水区域用空气色覆盖原先画死的蓝色；水面下方则从原图确定已浸水的行开始取样。
            if(p.y<surface) color=air_color;
            else {
                // 将“当前水面→修正区底部”归一化，再映射到“原图水下采样行→修正区底部”。
                // 波峰处伸展真实水下图像，区域底部回到原坐标，避免出现黑缝，同时保留深处地形。
                float fraction=clamp((p.y-surface)/max(r.w-surface,.5),0.0,1.0);
                vec3 source=vec3(p.x,mix(source_surface_y,r.w,fraction),1);
                color=texture(TEXTURE,vec2(dot(water_to_uv_x,source),dot(water_to_uv_y,source)));
            }
            // 修正区域若重叠，优先使用数组中第一个命中的区域。
            break;
        }
    }
    COLOR=color;
}
