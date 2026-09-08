shader_type canvas_item;
render_mode unshaded;
uniform float clock=0.0;
uniform float phase=0.0;
uniform vec2 pixel_size=vec2(36.0,184.0);
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void fragment() {
 vec2 p=floor(UV*pixel_size);
 float edge=min(UV.x,1.0-UV.x);
 float streak=hash(vec2(floor(p.x*.35),floor(p.y*.07-clock*7.0-phase)));
 float ribbon=pow(max(0.0,sin(p.x*.7+sin(p.y*.03-clock*4.0))),8.0);
 vec3 color=mix(vec3(.015,.25,.68),vec3(.18,.83,.96),UV.x*.4+streak*.25);
 float alpha=.48;
 if(edge<.06) { color=vec3(.25,.92,1.0); alpha=.83; }
 if(edge<.025) { color=vec3(.55,1.0,1.0); alpha=.95; }
 if(streak>.88) { color+=vec3(.10,.35,.40); alpha+=.10; }
 color+=vec3(.0,.13,.18)*ribbon;
 COLOR=vec4(color,alpha);
}
