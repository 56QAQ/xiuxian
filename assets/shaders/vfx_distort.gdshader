// 热浪扭曲（火焰上方的空气折射）：朝向镜头的四边形，读取屏幕纹理并按向上滚动的噪声偏移。
// 仅在 Forward+ 下使用（Compatibility 渲染器中不生成）。实例参数：fade 强度（0 → 1）。
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://assets/shaders/vfx_common.gdshaderinc"

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
uniform float strength = 0.008;
instance uniform float fade = 1.0;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * vfx_billboard(MODEL_MATRIX, INV_VIEW_MATRIX, 0.0);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// 下宽上窄的热浪区域
	float mask = smoothstep(1.0, 0.1, length(vec2(p.x * (1.2 - UV.y * 0.3), p.y)));
	mask *= mask;
	vec2 n = texture(noise_tex, vec2(UV.x * 1.5, UV.y * 1.2 + TIME * 0.9)).rg - 0.5;
	float s = strength * fade * mask * vfx_near_fade(-VERTEX.z, 1.5);
	vec2 off = n * s * 2.0;
	ALBEDO = texture(screen_tex, SCREEN_UV + off).rgb;
	ALPHA = clamp(mask * fade * 3.0, 0.0, 1.0);
}
