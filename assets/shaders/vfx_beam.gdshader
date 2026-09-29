// 能量光束：沿模型 -Z 的条带，绕光束轴自动朝向镜头（单个四边形）。
// 网格：x ∈ [-0.5, 0.5]（宽），z ∈ [-1, 0]（长）；节点缩放 x = 宽度，z = 长度。
// UV.x = 横向，UV.y = 沿长度（0 起点 → 1 终点）。
// 实例参数：tint 元素色，alpha 强度，len 世界长度（用于纹理平铺），seed 随机偏移。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://assets/shaders/vfx_common.gdshaderinc"

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D streak_tex : filter_linear_mipmap, repeat_enable;
// 0 灵光（金/无）；1 火焰；2 水龙（螺旋水纹）；3 雷光（闪烁细芯）；4 光柱（竖直天光，柔和）
uniform int style = 0;
uniform float intensity = 1.35;
uniform float occlude = 0.3;  // 对背景的遮挡（预乘混合），明亮场景中保持元素色饱和
uniform float core_width = 0.16;
uniform float scroll_speed = 3.0;
uniform float near_fade = 1.2;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float alpha = 1.0;
instance uniform float len = 10.0;
instance uniform float seed = 0.0;

void vertex() {
	vec3 origin = MODEL_MATRIX[3].xyz;
	vec3 axis = MODEL_MATRIX[2].xyz;
	vec3 along = origin + axis * VERTEX.z;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	vec3 dir = normalize(axis);
	vec3 side = cross(dir, normalize(cam - along));
	float sl = length(side);
	side = sl > 1e-4 ? side / sl : normalize(cross(dir, vec3(0.0, 1.0, 0.1)));
	float w = length(MODEL_MATRIX[0].xyz);
	vec3 world = along + side * VERTEX.x * w;
	VERTEX = world;
	MODELVIEW_MATRIX = VIEW_MATRIX;
	MODELVIEW_NORMAL_MATRIX = mat3(VIEW_MATRIX);
}

void fragment() {
	float x = UV.x * 2.0 - 1.0;
	float s = UV.y * len;
	float t = TIME * scroll_speed + seed;
	float n = texture(noise_tex, vec2(s * 0.08 - t * 0.35, UV.x * 0.6 + seed)).g;
	float n2 = texture(noise_tex, vec2(s * 0.19 - t * 0.8, UV.x * 1.3)).r;
	float st = texture(streak_tex, vec2(s * 0.05 - t * 0.5, UV.x)).r;
	float wob = (n - 0.5) * 0.35;
	float xx = x + wob * (style == 3 ? 0.9 : 0.35);
	float glow = exp(-xx * xx * 3.2);
	float core = exp(-pow(xx / core_width, 2.0));
	float body;
	vec3 c;
	if (style == 1) {
		float flame = glow * (0.45 + n2 * 0.9) * (0.7 + st * 0.6);
		body = flame + core * 0.7;
		c = vfx_fire_ramp(flame * 0.65 + core * 0.45 + 0.1) * 1.1;
	} else if (style == 2) {
		float spiral = 0.5 + 0.5 * sin(s * 1.6 - t * 6.0 + x * 5.0 + n * 4.0);
		body = glow * (0.35 + spiral * 0.75) * (0.7 + n2 * 0.5) + core * 0.6;
		c = mix(tint.rgb * 0.9, vec3(0.85, 0.97, 1.0), core * 0.55 + smoothstep(0.75, 1.0, spiral) * glow * 0.35);
	} else if (style == 3) {
		float flick = 0.6 + 0.4 * sin(TIME * 90.0 + seed * 10.0);
		body = (glow * 0.45 * (0.5 + n2) + core * 1.6) * flick;
		c = mix(tint.rgb, vec3(1.0), core);
	} else if (style == 4) {
		body = glow * (0.4 + st * 0.5) * 0.6 + core * 0.35;
		c = mix(tint.rgb, vec3(1.0), core * 0.6);
	} else {
		body = glow * (0.5 + st * 0.6) + core * 1.1;
		c = mix(tint.rgb, vec3(1.0), clamp(core * 0.7, 0.0, 1.0));
	}
	float ends = smoothstep(0.0, min(0.6 / max(len, 0.1), 0.2), UV.y) * smoothstep(1.0, 1.0 - min(1.5 / max(len, 0.1), 0.3), UV.y);
	float a = body * ends * alpha * vfx_near_fade(-VERTEX.z, near_fade);
	a = clamp(a, 0.0, 1.5);
	ALBEDO = c * a * intensity;
	ALPHA = clamp(a, 0.0, 1.0) * occlude;
}
