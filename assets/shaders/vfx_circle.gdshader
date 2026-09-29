// 法阵：三层可独立旋转的阵纹（外圈符文 / 八卦 / 五芒星阵）+ 中心元素字 + 辉光。
// 贴图 circle.png 的 R/G/B 分别为三层；mipmap 低层级用作柔和辉光。
// 实例参数：tint 颜色，alpha 整体强度，spin 旋转角，reveal 显现（0 → 1 由内向外绘出），
//           glyph 中心字序号（0 金 1 木 2 水 3 火 4 土 5 灵 6 雷 7 敕，<0 不画），fill 预警填充进度（0 → 1）。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://assets/shaders/vfx_common.gdshaderinc"

uniform sampler2D circle_tex : filter_linear_mipmap, repeat_disable;
uniform sampler2D glyph_tex : filter_linear_mipmap, repeat_disable;
uniform float intensity = 1.8;
uniform float occlude = 0.25;  // 对背景的遮挡（预乘混合），明亮场景中保持元素色饱和
uniform float glow_amount = 0.9;
uniform float near_fade = 1.0;
instance uniform vec4 tint : source_color = vec4(0.8, 0.9, 1.0, 1.0);
instance uniform float alpha = 1.0;
instance uniform float spin = 0.0;
instance uniform float reveal = 1.0;
instance uniform float glyph = -1.0;
instance uniform float fill = -1.0;

float layer(vec2 p, float ang, int ch) {
	vec4 s = texture(circle_tex, vfx_rot(p, ang) * 0.5 + 0.5);
	return ch == 0 ? s.r : (ch == 1 ? s.g : s.b);
}

float glow_layer(vec2 p, float ang, int ch) {
	vec4 s = textureLod(circle_tex, vfx_rot(p, ang) * 0.5 + 0.5, 3.5);
	return ch == 0 ? s.r : (ch == 1 ? s.g : s.b);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float inside = smoothstep(1.02, 0.99, r);
	float a01 = fract(atan(p.y, p.x) / 6.28318 + 0.25);
	// 由内向外逐层绘出（每层带角度扫描）
	float rv_in = clamp(reveal * 3.0, 0.0, 1.0);
	float rv_mid = clamp(reveal * 3.0 - 1.0, 0.0, 1.0);
	float rv_out = clamp(reveal * 3.0 - 2.0, 0.0, 1.0);
	float m_in = step(a01, rv_in) * step(0.001, rv_in);
	float m_mid = step(a01, rv_mid) * step(0.001, rv_mid);
	float m_out = step(a01, rv_out) * step(0.001, rv_out);
	float l_out = layer(p, spin * 0.5, 0) * m_out;
	float l_mid = layer(p, -spin * 0.8, 1) * m_mid;
	float l_in = layer(p, spin * 1.25, 2) * m_in;
	float g_out = glow_layer(p, spin * 0.5, 0) * m_out;
	float g_mid = glow_layer(p, -spin * 0.8, 1) * m_mid;
	float g_in = glow_layer(p, spin * 1.25, 2) * m_in;
	float lines = l_out + l_mid + l_in;
	float glow = (g_out + g_mid + g_in) * glow_amount;
	// 中心字
	vec2 q = vfx_rot(p, -spin * 0.3) / 0.44 + 0.5;
	q.y = 1.0 - q.y;
	float gi = floor(max(glyph, 0.0) + 0.5);
	vec2 cell = vec2(mod(gi, 4.0), floor(gi / 4.0));
	vec2 guv = (cell + clamp(q, 0.0, 1.0)) / vec2(4.0, 2.0);
	float gmask = step(0.0, glyph) * step(abs(q.x - 0.5), 0.5) * step(abs(q.y - 0.5), 0.5) * rv_in;
	float gch = textureLod(glyph_tex, guv, 0.0).r * gmask;
	glow += textureLod(glyph_tex, guv, 3.0).r * 0.6 * gmask;
	// 底光与预警填充
	float base = smoothstep(1.0, 0.2, r) * 0.08 * rv_in;
	float f = 0.0;
	if (fill >= 0.0) {
		f = smoothstep(fill, fill - 0.04, r) * 0.22 + smoothstep(0.03, 0.0, abs(r - fill)) * 0.7 * step(0.02, fill);
	}
	float a = (lines + gch * 1.2 + glow * 0.5 + base + f) * alpha * inside;
	a *= vfx_near_fade(-VERTEX.z, near_fade);
	vec3 c = mix(tint.rgb, vec3(1.0), clamp((lines + gch) * 0.35, 0.0, 0.8));
	a = clamp(a, 0.0, 1.5);
	ALBEDO = c * a * intensity;
	ALPHA = clamp(a, 0.0, 1.0) * occlude;
}
