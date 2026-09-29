// 冲击环：画在平面四边形上的扩散光环（节点缩放负责扩张，着色器负责环形轮廓与消散）。
// 轮廓：外缘锐利的亮线 + 向内渐隐的冲击带，没有内部填充（不会像实心球/气泡那样挡住视线）。
// 预乘混合：occlude 控制对背景的遮挡，使元素色在明亮场景中依然饱和。
// 实例参数：tint 颜色，prog 进度（0 → 1），thick 冲击带宽度（相对半径）。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://assets/shaders/vfx_common.gdshaderinc"

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float intensity = 1.5;
uniform float occlude = 0.4;
uniform float near_fade = 1.5;
// 0 灵气环；1 水波（多重涟漪）；2 火环（火焰色带）；3 尘浪（暗淡、宽、不发光）
uniform int style = 0;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float prog = 0.0;
instance uniform float thick = 0.18;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d = length(p);
	float ang = atan(p.y, p.x) / 6.28318;
	float n = texture(noise_tex, vec2(ang * 4.0, prog * 0.4)).g;
	float n2 = texture(noise_tex, vec2(ang * 9.0 + prog * 0.3, d * 0.3)).r;
	float th = max(thick * (1.0 - prog * 0.5), 0.02);
	float edge = 0.975;
	// 外缘亮线
	float rim = smoothstep(edge - 0.035, edge, d) * smoothstep(1.0, edge, d);
	// 冲击带：从内向外逐渐增强
	float band = smoothstep(edge - th, edge, d) * step(d, edge);
	band = band * band;
	float broken = mix(1.0, smoothstep(0.25, 0.75, n), 0.25 + prog * 0.55) * (0.75 + n2 * 0.5);
	if (style == 1) {
		float waves = 0.5 + 0.5 * sin((d - prog * 0.6) * 55.0);
		band *= 0.4 + waves * 0.8;
	}
	float life = (1.0 - prog) * (1.0 - prog);
	float a = (rim * 0.9 + band * 0.55) * broken * life * tint.a;
	a *= vfx_near_fade(-VERTEX.z, near_fade);
	vec3 c = mix(tint.rgb, vec3(1.0), rim * 0.35 * (1.0 - prog));
	float occ = occlude;
	if (style == 2) {
		c = vfx_fire_ramp(band * 0.6 + rim * 0.5 + n * 0.25) * 1.1;
	} else if (style == 3) {
		c = tint.rgb * 0.8;
		occ = 0.85;
		a *= 0.55;
	}
	a = clamp(a, 0.0, 1.0);
	ALBEDO = c * a * (style == 3 ? 1.0 : intensity);
	ALPHA = a * occ;
}
