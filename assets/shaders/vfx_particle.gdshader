// 特效精灵/粒子通用着色器（预乘混合：additive=1 为纯加色发光，0 为普通透明，如烟尘、叶片、符纸）。
// 粒子：INSTANCE_CUSTOM.x = 旋转角，.y = 生命进度，.z = 序列帧进度；颜色来自粒子颜色（sRGB）。
// 单个精灵：通过实例参数 tint / fade 控制颜色与透明度。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://assets/shaders/vfx_common.gdshaderinc"

instance uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform float fade = 1.0;

#include "res://assets/shaders/vfx_particle_body.gdshaderinc"
