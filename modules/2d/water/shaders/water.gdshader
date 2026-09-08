shader_type canvas_item;
render_mode unshaded;
// 取已绘制的背景屏幕拷贝，做折射和染色；水体应排在背景及需要折射的物体之后。
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
#include "surface.gdshaderinc"
uniform float clock=0.0;
uniform vec2 light_position=vec2(-10000.0);
uniform float light_strength=0.0;
uniform vec2 pattern_offset=vec2(0.0);
// 折射强度以渲染视口像素计，后面乘 SCREEN_PIXEL_SIZE 转成归一化 UV 偏移。
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
// 逆仿射矩阵的两行 (a,b,tx)/(c,d,ty)，将屏幕像素还原到水体局部坐标。
uniform vec3 screen_to_water_x=vec3(1,0,0);
uniform vec3 screen_to_water_y=vec3(0,1,0);
uniform vec2 water_y_axis_screen=vec2(0,1);
// 顶点阶段保存未变换的局部坐标，光学图案不会因相机移动而漂移。
varying vec2 water_position;
void vertex() { water_position=VERTEX; }
// 无状态伪随机函数，只用于图案；它不参与 CPU 的弹簧随机数序列。
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
// 在周围 3×3 格中求最近与次近种子距离之差。
// 差接近零表示 Voronoi 边界，后续将这些边界绘成水底焦散亮纹。
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
    // 深度以动态水面为基准，不使用固定水平线，波浪起伏时染色与亮边同步变化。
    float depth=max(0.0,p.y-water_surface_at(p.x));
    vec2 uv=SCREEN_UV+vec2(sin(pattern.y*.15+clock*2.2),cos(pattern.x*.11+clock*1.4))*refraction_pixels*SCREEN_PIXEL_SIZE;
    vec3 screen_pixel=vec3(uv/SCREEN_PIXEL_SIZE,1.0);
    vec2 sample_local=vec2(dot(screen_to_water_x,screen_pixel),dot(screen_to_water_y,screen_pixel));
    if(sample_local.x>=0.0 && sample_local.x<surface_width) {
        // 若折射 UV 越过水面，就沿水体局部 +Y 推回水面下 2 像素。
        // 必须同时使用正/逆变换，才能在旋转、缩放和相机缩放后仍避免取到水面上方的黑色空气。
        float correction=max(0.0,water_surface_at(sample_local.x)+2.0-sample_local.y);
        uv+=water_y_axis_screen*correction*SCREEN_PIXEL_SIZE;
    }
    vec3 scene=texture(screen_texture,uv).rgb;
    float light=exp(-distance(p,light_position)*.021)*light_strength;
    vec3 tint=mix(shallow_color.rgb,deep_color.rgb,clamp(depth/depth_range,0.0,1.0));
    // 背景亮度随水深衰减，蓝绿通道保留较多；tint 是额外叠加水色，不是透明混合系数。
    vec3 attenuation=mix(vec3(.72,.95,1.05),vec3(.40,.51,.72),clamp(depth/depth_range,0.0,1.0));
    vec3 col=scene*attenuation+tint*tint_strength;
    float caustic=1.0-smoothstep(.012,.065,cellular(pattern*.065+vec2(clock*.05,-clock*.035)));
    col+=vec3(.025,.11,.25)*caustic*(.13+light*.22)*exp(-depth*.003)*caustic_strength;
    // 正弦波高次幂收窄为光束，再按深度指数衰减，模拟浅水处较强的光照。
    float beam=pow(max(0.0,sin(pattern.x*.08+pattern.y*.045+clock*.25)),14.0);
    col+=vec3(.06,.33,.43)*beam*exp(-depth*.023)*.24;
    // 最多 8 条定点光柱，随深度横向倾斜；位置与 CPU 的 light_shafts 一一对应。
    float shafts=0.0;
    for(int i=0;i<8;i++) {
        if(i<shaft_count) shafts+=exp(-pow((p.x+depth*.55-shaft_positions[i])/14.0,2.0));
    }
    col+=vec3(.07,.26,.40)*shafts*exp(-depth*.018)*.7;
    col+=vec3(.015,.17,.24)*light;
    // 最后覆盖水面高亮带，它与网格、背景适配器读取同一条浮点高度曲线。
    if(depth<surface_thickness && p.x>=0.0 && p.x<surface_width) col=surface_color.rgb;
    COLOR=vec4(col,1.0);
}
