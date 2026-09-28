// 特效精灵/粒子通用着色器（预乘混合：additive=1 为纯加色发光，0 为普通透明，如烟尘、叶片、符纸）。
// 粒子：INSTANCE_CUSTOM.x = 旋转角，.y = 生命进度，.z = 序列帧进度；颜色来自粒子颜色（sRGB）。
// 单个精灵：通过实例参数 tint / fade 控制颜色与透明度。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://assets/shaders/vfx_common.gdshaderinc"

uniform sampler2D tex : filter_linear_mipmap, repeat_disable;
uniform int hframes = 1;
uniform int vframes = 1;
uniform bool loop_frames = true;
// 0 朝向镜头；1 沿速度拉伸（粒子需开启 align_y）；2 不做广告牌（保持网格朝向）
uniform int mode = 0;
uniform float stretch = 1.0;
uniform float intensity = 1.0;
uniform float additive : hint_range(0.0, 1.0) = 1.0;
// 0 贴图亮度×颜色；1 火焰色带（贴图亮度映射到火焰颜色）；2 彩色贴图（使用贴图 RGB，alpha 通道为形状）；3 亮度+alpha 贴图（LA）
uniform int color_mode = 0;
uniform float near_fade = 1.6;
uniform float core_white = 0.0;   // 高亮处偏白（发光核心）
instance uniform vec4 tint : source_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform float fade = 1.0;

void vertex() {
	if (mode == 0) {
		MODELVIEW_MATRIX = VIEW_MATRIX * vfx_billboard(MODEL_MATRIX, INV_VIEW_MATRIX, INSTANCE_CUSTOM.x);
	} else if (mode == 1) {
		VERTEX.y -= 0.5;
		MODELVIEW_MATRIX = VIEW_MATRIX * vfx_stretch_billboard(MODEL_MATRIX, INV_VIEW_MATRIX[3].xyz, stretch);
	}
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	if (hframes * vframes > 1) {
		float total = float(hframes * vframes);
		float f = floor(INSTANCE_CUSTOM.z * total);
		f = loop_frames ? mod(f, total) : clamp(f, 0.0, total - 1.0);
		UV /= vec2(float(hframes), float(vframes));
		UV += vec2(mod(f, float(hframes)) / float(hframes), floor((f + 0.5) / float(hframes)) / float(vframes));
	}
}

void fragment() {
	vec4 t = texture(tex, UV);
	vec3 base = vfx_lin(COLOR.rgb) * tint.rgb;
	float a;
	vec3 col;
	if (color_mode == 1) {
		float v = t.r;
		a = smoothstep(0.02, 0.35, v);
		col = vfx_fire_ramp(v * 1.1) * mix(vec3(1.0), base, 0.35);
	} else if (color_mode == 2) {
		a = t.a;
		col = t.rgb * base;
	} else if (color_mode == 3) {
		a = t.a;
		col = t.r * base;
	} else {
		a = t.r;
		col = base;
	}
	col = mix(col, vec3(1.0), clamp(core_white * t.r * t.r, 0.0, 1.0));
	a *= COLOR.a * tint.a * fade * vfx_near_fade(-VERTEX.z, near_fade);
	a = clamp(a, 0.0, 1.0);
	ALBEDO = col * a * intensity;
	ALPHA = a * (1.0 - additive);
}
