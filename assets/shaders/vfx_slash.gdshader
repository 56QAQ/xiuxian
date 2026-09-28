// 剑气月牙：沿挥砍轨迹生成的弧形条带。
// UV.x = 沿弧（0 起手 → 1 收势/前缘），UV.y = 横向（0 内侧 → 1 外缘刃口）。
// 实例参数：tint 元素色，prog 生命进度（0 → 1，尾部先消散）。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://assets/shaders/vfx_common.gdshaderinc"

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// 0 剑光（金/无）；1 水；2 火；3 木；4 土
uniform int style = 0;
uniform float intensity = 2.2;
uniform float occlude = 0.45;  // 对背景的遮挡（预乘混合），明亮场景中保持元素色饱和
uniform float thickness = 0.55;
uniform float near_fade = 1.2;
instance uniform vec4 tint : source_color = vec4(1.0, 0.9, 0.6, 1.0);
instance uniform float prog = 0.0;

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float n = texture(noise_tex, vec2(u * 2.0 - prog * 0.6, v * 0.5 + prog * 0.3)).g;
	float n2 = texture(noise_tex, vec2(u * 5.0 + prog, v * 1.3)).r;
	// 月牙厚度：两端尖、前缘略厚
	float prof = pow(sin(3.14159 * pow(clamp(u, 0.0, 1.0), 0.75)), 0.65);
	float th = thickness * prof;
	if (style == 1 || style == 2) {
		th *= 0.75 + n * 0.6;
	}
	float inner = 1.0 - th;
	float body = smoothstep(inner - 0.08, inner + 0.25, v) * smoothstep(1.0, 0.96, v);
	float edge = smoothstep(0.86, 0.985, v) * smoothstep(1.0, 0.975, v) * prof;
	// 尾部先消散（带噪声的溶解边）
	float dissolve = smoothstep(prog * 1.25 - 0.1, prog * 1.25 + 0.15, u + (n2 - 0.5) * 0.35);
	float life = 1.0 - smoothstep(0.55, 1.0, prog);
	float a = (body * (0.55 + n * 0.6) + edge * 1.6) * dissolve * life;
	a *= vfx_near_fade(-VERTEX.z, near_fade);
	vec3 col = tint.rgb;
	vec3 c;
	if (style == 2) {
		c = vfx_fire_ramp(body * 0.6 + edge * 0.6 + n * 0.3);
	} else if (style == 1) {
		c = mix(col, vec3(0.85, 0.97, 1.0), edge * 0.8 + smoothstep(0.6, 0.9, n) * 0.5);
	} else {
		c = mix(col, vec3(1.0), clamp(edge * 0.55, 0.0, 1.0));
	}
	a = clamp(a, 0.0, 1.0);
	ALBEDO = c * a * intensity;
	ALPHA = a * occlude;
}
