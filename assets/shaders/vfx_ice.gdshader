// 冰晶/水晶网格（冰锥、冰枷、冰刺）：半透明、菲涅尔亮边、内部噪声裂纹、受光照。
// 实例参数：tint 颜色，alpha 透明度，prog 碎裂/溶解进度。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

#include "res://assets/shaders/vfx_common.gdshaderinc"

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float glow = 0.6;
instance uniform vec4 tint : source_color = vec4(0.7, 0.9, 1.0, 1.0);
instance uniform float alpha = 0.85;
instance uniform float prog = 0.0;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	float n = texture(noise_tex, lpos.xy * 0.9 + lpos.zx * 0.5).b;
	float cracks = smoothstep(0.82, 0.95, n);
	float dissolve = step(prog, texture(noise_tex, lpos.xz * 1.3 + lpos.y * 0.4).g * 0.95 + 0.02);
	vec3 deep = tint.rgb * 0.45;
	vec3 c = mix(deep, vec3(0.92, 0.98, 1.0), fres * 0.8 + cracks * 0.5);
	ALBEDO = c;
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
	EMISSION = tint.rgb * (fres * glow + cracks * 0.4);
	ALPHA = clamp((0.45 + fres * 0.5 + cracks * 0.3) * alpha, 0.0, 1.0) * dissolve;
}
