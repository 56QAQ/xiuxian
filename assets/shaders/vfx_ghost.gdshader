// 残影：角色剪影的半透明灵光复制（瞬步、突进）。保留少量原色，边缘菲涅尔发亮，横向扫描线溶解。
// 每个残影一份材质：tint 灵光色，fade 透明度（0 → 消失）。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

#include "res://assets/shaders/vfx_common.gdshaderinc"

uniform float intensity = 1.3;
uniform float occlude = 0.3;  // 对背景的遮挡（预乘混合），明亮场景中保持元素色饱和
uniform vec4 tint : source_color = vec4(0.6, 0.85, 1.0, 1.0);
uniform float fade = 1.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.6);
	float scan = 0.75 + 0.25 * sin(wpos.y * 60.0);
	float cut = step(1.0 - fade * 1.15, fract(wpos.y * 3.7 + wpos.x * 1.3) * 0.6 + 0.4 * fade);
	vec3 own = vfx_lin(COLOR.rgb);
	vec3 c = mix(tint.rgb, own * 1.5 + tint.rgb * 0.3, 0.25);
	float a = (0.06 + fres * 0.75) * scan * fade * cut * vfx_near_fade(-VERTEX.z, 1.2);
	a = clamp(a, 0.0, 1.0);
	ALBEDO = c * a * intensity;
	ALPHA = a * occlude;
}
