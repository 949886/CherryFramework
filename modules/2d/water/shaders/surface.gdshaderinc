// 共享高度协议：纹理为 sample_count×1 的 RF，R 通道直接保存水体局部 Y。
// 线性过滤用于与 CPU 的相邻样本插值保持一致，不对高度进行 0～1 归一化。
uniform sampler2D surface_profile : filter_linear, repeat_disable;
uniform float surface_width=256.0;
// 输入水体局部 X，输出局部水面 Y，超出岸边范围会夹到端点。
float water_surface_at(float x) {
    float t=clamp(x/max(surface_width,.001),0.0,1.0);
    float count=float(textureSize(surface_profile,0).x);
    // t*(count-1) 映射到样本下标，再加半个纹素对齐 texel 中心。
    // 直接使用 t 作为 UV 会采到错误的插值位置，使网格与水面遮罩错位。
    return texture(surface_profile,vec2((t*(count-1.0)+.5)/count,.5)).r;
}
