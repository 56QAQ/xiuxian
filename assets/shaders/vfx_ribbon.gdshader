// 拖尾条带：兵器刀光、弹道尾迹、疾行灵气尾流、闪电。
// UV.x = 年龄（0 最新 → 1 最旧），UV.y = 横向（0 → 1）；顶点色 = 元素色（sRGB）与透明度。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://assets/shaders/vfx_common.gdshaderinc"

uniform sampler2D streak_tex : filter_linear_mipmap, repeat_enable;
// 0 居中（弹道/尾流：中间亮）；1 刃边（刀光：UV.y=1 为刃尖一侧最亮）；2 闪电（极细白芯 + 宽光晕）
uniform int profile = 0;
uniform float intensity = 1.6;
uniform float occlude = 0.35;  // 对背景的遮挡（预乘混合），明亮场景中保持元素色饱和
uniform float core_power = 1.0;
uniform float streak_amount = 0.55;
uniform float scroll = 1.5;
uniform float near_fade = 1.0;
uniform int fire = 0;
uniform float fade = 1.0;  // 常规参数（不占用实例参数槽位）；逐条带透明度由顶点色控制

void fragment() {
	float age = UV.x;
	float y = UV.y;
	vec3 col = vfx_lin(COLOR.rgb);
	float life = COLOR.a;
	float glow;
	float core;
	if (profile == 1) {
		float e = y;
		glow = pow(e, 1.6) * smoothstep(0.0, 0.25, y);
		core = smoothstep(0.82, 0.97, e) * smoothstep(1.0, 0.96, e) + smoothstep(0.9, 1.0, e) * 0.6;
	} else if (profile == 2) {
		float c = abs(y * 2.0 - 1.0);
		glow = exp(-c * c * 6.0);
		core = exp(-c * c * 160.0);
	} else {
		float c = abs(y * 2.0 - 1.0);
		glow = exp(-c * c * 3.5) * smoothstep(1.0, 0.8, c);
		core = exp(-c * c * 28.0);
	}
	float s = texture(streak_tex, vec2(age * 1.5 - TIME * scroll, y * 0.8)).r;
	float streak = mix(1.0, 0.45 + s * 1.1, streak_amount);
	float head = smoothstep(0.0, 0.06, age);
	float tail = pow(clamp(1.0 - age, 0.0, 1.0), 1.3);
	float a = (glow * streak * 0.8 + core * core_power) * life * tail * head * fade;
	a *= vfx_near_fade(-VERTEX.z, near_fade);
	vec3 c;
	if (fire == 1) {
		c = vfx_fire_ramp(glow * streak * 0.8 + core * 0.5) * 1.3;
	} else {
		c = mix(col, vec3(1.0), clamp(core * 0.85, 0.0, 1.0));
	}
	a = clamp(a, 0.0, 1.0);
	ALBEDO = c * a * intensity;
	ALPHA = a * occlude;
}
