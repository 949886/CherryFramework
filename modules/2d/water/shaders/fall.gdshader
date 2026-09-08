shader_type canvas_item;
render_mode unshaded;
// 由瀑布节点传入的动画时间，暂停时停止；不使用不可暂停的内置 TIME。
uniform float clock=0.0;
uniform float phase=0.0;
uniform vec2 pixel_size=vec2(36.0,184.0);
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void fragment() {
 // 按实际条带尺寸量化到像素坐标，形成像素风水流，不依赖固定屏幕分辨率。
 vec2 p=floor(UV*pixel_size);
 float edge=min(UV.x,1.0-UV.x);
 // 沿纵向移动噪声采样网格，形成向下刷新的条纹；phase 让多个瀑布错开。
 float streak=hash(vec2(floor(p.x*.35),floor(p.y*.07-clock*7.0-phase)));
 // 对正弦亮度取高次幂生成细亮带，叠加低频弯曲使流线更自然。
 float ribbon=pow(max(0.0,sin(p.x*.7+sin(p.y*.03-clock*4.0))),8.0);
 vec3 color=mix(vec3(.015,.25,.68),vec3(.18,.83,.96),UV.x*.4+streak*.25);
 float alpha=.48;
 // 靠两侧增强亮度与不透明度形成轮廓；中部保持半透明，能看见后方场景。
 if(edge<.06) { color=vec3(.25,.92,1.0); alpha=.83; }
 if(edge<.025) { color=vec3(.55,1.0,1.0); alpha=.95; }
 if(streak>.88) { color+=vec3(.10,.35,.40); alpha+=.10; }
 color+=vec3(.0,.13,.18)*ribbon;
 COLOR=vec4(color,alpha);
}
