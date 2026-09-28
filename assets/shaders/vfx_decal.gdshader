// 地面贴花（贴合地形的网格）：地裂、焦痕、霜花。预乘混合：暗部压暗地面，亮部（熔岩/灵光/霜）加色发光。
// crack.png：R 裂纹 / G 裂纹泛光 / B 中心污迹 / A 透明度；scorch.png、frost.png：L 亮度 / A 透明度。
// 实例参数：tint 发光色，fade 整体透明度，glow 发光强度。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://assets/shaders/vfx_common.gdshaderinc"

uniform sampler2D tex : filter_linear_mipmap, repeat_disable;
// 0 地裂；1 焦痕；2 霜花
uniform int kind = 0;
uniform vec3 dark = vec3(0.05, 0.04, 0.03);
instance uniform vec4 tint : source_color = vec4(1.0, 0.5, 0.15, 1.0);
instance uniform float fade = 1.0;
instance uniform float glow = 0.0;

void fragment() {
	vec4 t = texture(tex, UV);
	float a;
	vec3 add = vec3(0.0);
	vec3 base = dark;
	if (kind == 0) {
		a = clamp(t.r * 0.95 + t.b * 0.55, 0.0, 1.0);
		add = tint.rgb * (t.r * 1.4 + t.g * 0.45) * glow;
	} else if (kind == 1) {
		a = t.a * 0.85;
		base = dark * (0.6 + t.r);
		add = tint.rgb * t.a * smoothstep(0.35, 0.0, t.r) * glow * 0.5;
	} else {
		a = t.a * 0.55;
		base = mix(tint.rgb, vec3(0.92, 0.97, 1.0), t.r) * 0.85;
		add = tint.rgb * t.a * t.r * glow * 0.4;
	}
	a *= fade;
	ALBEDO = base * a + add * fade;
	ALPHA = a;
}
