// 粒子发射器版本（CPUParticles3D）：与 vfx_particle.gdshader 相同，但 tint/fade 为常量。
// Compatibility 渲染器中实例参数缓冲很小（64 KB UBO 时全场仅 256 个实例可用），
// 常驻/对象池中的发射器不占用实例参数槽位。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://assets/shaders/vfx_common.gdshaderinc"

const vec4 tint = vec4(1.0, 1.0, 1.0, 1.0);
const float fade = 1.0;

#include "res://assets/shaders/vfx_particle_body.gdshaderinc"
