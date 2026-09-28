// 领域地面（贴合地形的圆盘网格）：藤蔓（木）/ 冰域水旋（水）/ 流沙漩涡（土）/ 火海（火）/ 灵纹（无）。
// 预乘混合：底色半透明覆盖地面，纹路加色发光；外缘有清晰的范围环（可读性）。
// 实例参数：tint 元素色，alpha 整体强度（出现/消散），seed 随机偏移。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://assets/shaders/vfx_common.gdshaderinc"

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_tex : filter_linear_mipmap, repeat_disable;
// 0 藤蔓；1 冰域；2 流沙；3 火海；4 灵纹
uniform int style = 0;
uniform float intensity = 1.4;
instance uniform vec4 tint : source_color = vec4(0.4, 0.9, 0.4, 1.0);
instance uniform float alpha = 1.0;
instance uniform float seed = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	float t = TIME + seed * 10.0;
	float n = texture(noise_tex, p * 0.6 + vec2(seed, t * 0.03)).r;
	float n2 = texture(noise_tex, p * 1.4 - vec2(t * 0.05, seed)).g;
	float edge = smoothstep(1.0, 0.97, r);
	float rim = smoothstep(0.9, 0.975, r) * edge;
	float cover = 0.0;       // 覆盖地面的底色不透明度
	vec3 cover_col = vec3(0.0);
	float lines = 0.0;       // 发光纹路
	vec3 line_col = tint.rgb;
	if (style == 0) {
		// 藤蔓：自中心螺旋蔓延的藤茎（深绿茎身 + 亮绿脉络）与叶斑，茎身压暗地面、脉络发光
		float w1 = sin(ang * 5.0 + r * 8.0 + n * 5.0 - t * 0.25);
		float w2 = sin(ang * 3.0 - r * 11.0 + n2 * 4.0 + t * 0.2);
		float body1 = smoothstep(0.72, 0.9, w1) * smoothstep(0.08, 0.25, r);
		float body2 = smoothstep(0.8, 0.94, w2) * smoothstep(0.15, 0.35, r);
		float vein = smoothstep(0.93, 0.99, w1) + smoothstep(0.96, 0.995, w2) * 0.7;
		// 叶斑：沿藤茎的周期性椭圆
		float lp = fract(r * 5.0 + ang * 0.8 + n);
		float leaf = smoothstep(0.55, 0.8, w1) * smoothstep(0.35, 0.0, abs(lp - 0.5)) * smoothstep(0.2, 0.4, r);
		cover = (0.22 + n * 0.15) * edge + (body1 + body2 * 0.8) * 0.75 + leaf * 0.5;
		cover_col = mix(vec3(0.06, 0.16, 0.05), vec3(0.14, 0.32, 0.08), leaf) + tint.rgb * 0.05;
		lines = vein * 0.9 * edge + leaf * 0.25 + smoothstep(0.78, 0.92, n2) * 0.2 * edge;
		line_col = mix(tint.rgb, vec3(0.75, 1.0, 0.45), 0.35);
	} else if (style == 1) {
		// 冰域：霜花贴图 + 缓慢旋转的寒气
		vec2 q = vfx_rot(p, t * 0.05) * 0.5 + 0.5;
		float frost = texture(detail_tex, q).a * texture(detail_tex, q).r;
		float swirl = 0.5 + 0.5 * sin(ang * 3.0 + r * 8.0 - t * 1.2 + n * 4.0);
		cover = (0.28 + frost * 0.4) * edge;
		cover_col = vec3(0.75, 0.88, 1.0) * 0.8;
		lines = frost * 0.6 + swirl * smoothstep(0.5, 1.0, n2) * 0.35;
		line_col = mix(tint.rgb, vec3(0.9, 0.98, 1.0), 0.5);
	} else if (style == 2) {
		// 流沙：向中心旋入的螺旋沙纹
		float sp = sin(ang * 4.0 + log(max(r, 0.02)) * 7.0 + t * 2.2 + n * 2.0);
		cover = (0.55 + sp * 0.15) * edge * smoothstep(0.0, 0.2, r + 0.1);
		cover_col = mix(vec3(0.45, 0.33, 0.18), vec3(0.7, 0.55, 0.32), 0.5 + sp * 0.5) * (0.8 + n2 * 0.3);
		lines = smoothstep(0.6, 1.0, sp) * 0.2 + smoothstep(0.35, 0.0, r) * 0.25;
		line_col = tint.rgb * 0.8;
	} else if (style == 3) {
		float fl = texture(noise_tex, vec2(ang / 6.28318 * 3.0, r * 0.8 - t * 0.4)).g;
		cover = 0.35 * edge;
		cover_col = vec3(0.12, 0.03, 0.01);
		lines = smoothstep(0.45, 0.9, fl * (1.2 - r * 0.4)) * 0.9;
		line_col = vfx_fire_ramp(fl);
	} else {
		float wv = 0.5 + 0.5 * sin(r * 30.0 - t * 3.0);
		cover = 0.12 * edge;
		cover_col = tint.rgb * 0.2;
		lines = wv * smoothstep(0.3, 1.0, r) * 0.25;
	}
	lines += rim * 1.4;
	cover += rim * 0.2;
	// 方形网格只保留圆内部分
	float inside = smoothstep(1.0, 0.985, r);
	float a = clamp(cover, 0.0, 1.0) * alpha * inside;
	vec3 add = line_col * lines * alpha * intensity * inside;
	ALBEDO = cover_col * a + add;
	ALPHA = a;
}
