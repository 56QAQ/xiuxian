// 护体灵光：菲涅尔球壳 + 六角符纹 + 受击涟漪（最多 4 处）。每个护盾使用独立材质实例。
// hits[i]：xyz 为局部空间命中方向（单位向量），w 为命中后经过的秒数（<0 表示无效）。
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, shadows_disabled, fog_disabled;

#include "res://assets/shaders/vfx_common.gdshaderinc"

uniform sampler2D hex_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0, 0.85, 0.45, 1.0);
uniform float strength = 1.0;     // 常驻显示强度（护体法诀期间）
uniform float flash = 0.0;        // 整体闪烁（受击/破碎）
uniform vec4 hits[4];
uniform float intensity = 1.1;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	vec3 dirn = normalize(lpos);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.2);
	vec2 uv = vec2(atan(lpos.z, lpos.x) / 6.28318 * 4.0, lpos.y * 0.9);
	float hex = texture(hex_tex, uv + vec2(TIME * 0.02, -TIME * 0.05)).r;
	float n = texture(noise_tex, uv * 0.5 + vec2(0.0, TIME * 0.1)).g;
	float ripple = 0.0;
	float patch = 0.0;
	for (int i = 0; i < 4; i++) {
		vec4 h = hits[i];
		if (h.w >= 0.0 && h.w < 1.2) {
			float d = acos(clamp(dot(dirn, normalize(h.xyz)), -1.0, 1.0));
			float r = h.w * 3.2;
			ripple += exp(-pow((d - r) / 0.12, 2.0)) * exp(-h.w * 2.5);
			patch += exp(-d * d * 10.0) * exp(-h.w * 7.0);
		}
	}
	float scan = smoothstep(0.0, 0.06, abs(fract(lpos.y * 1.2 - TIME * 0.4) - 0.5));
	float base = (fres * 0.8 + hex * (0.04 + fres * 0.45) * (0.6 + n * 0.8)) * strength * mix(0.75, 1.0, scan);
	float hitv = ripple * (0.6 + hex * 1.4) + patch * (0.8 + hex);
	float a = base + hitv + flash * (0.3 + fres + hex * 0.6);
	vec3 c = mix(tint.rgb, vec3(1.0), clamp(patch * 0.6 + ripple * 0.3 + flash * 0.3, 0.0, 0.8));
	ALBEDO = c * a * intensity;
}
