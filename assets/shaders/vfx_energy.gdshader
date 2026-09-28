// 能量体网格（光柱、水柱、灵气护环、水龙卷等）：菲涅尔边缘 + 纵向滚动噪声，加色。
// UV 使用网格自带 UV（圆柱：UV.x 绕周，UV.y 沿高）。
// 实例参数：tint 颜色，alpha 强度，prog 进度（用于溶解）。
shader_type spatial;
render_mode unshaded, blend_premul_alpha, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

#include "res://assets/shaders/vfx_common.gdshaderinc"

uniform sampler2D noise_tex : filter_linear_mipmap, repeat_enable;
// 0 灵光；1 水流（螺旋水纹、偏白泡沫）；2 天光柱（柔和，上端渐隐）；3 火焰
uniform int style = 0;
uniform float intensity = 1.6;
uniform float occlude = 0.25;  // 对背景的遮挡（预乘混合），明亮场景中保持元素色饱和
uniform float fresnel_power = 2.0;
uniform float scroll = 1.2;
uniform vec2 tiling = vec2(2.0, 1.0);
uniform float near_fade = 1.5;
instance uniform vec4 tint : source_color = vec4(1.0);
instance uniform float alpha = 1.0;
instance uniform float prog = 0.0;

void fragment() {
	float fres = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), fresnel_power);
	vec2 uv = UV * tiling;
	float t = TIME * scroll;
	float n = texture(noise_tex, vec2(uv.x + uv.y * 0.35, uv.y * 0.6 - t * 0.5)).g;
	float n2 = texture(noise_tex, vec2(uv.x * 1.7 - uv.y * 0.5, uv.y * 1.2 - t)).r;
	float body;
	vec3 c;
	float v_fade = smoothstep(0.0, 0.08, UV.y) * smoothstep(1.0, 0.85, UV.y);
	if (style == 1) {
		float bands = 0.5 + 0.5 * sin((uv.x * 6.28318 * 2.0) + uv.y * 9.0 - t * 5.0 + n * 5.0);
		body = (0.25 + fres * 0.9) * (0.5 + bands * 0.6) * (0.6 + n2 * 0.6);
		c = mix(tint.rgb, vec3(0.9, 0.98, 1.0), smoothstep(0.7, 1.0, bands * n2 + fres * 0.4));
	} else if (style == 2) {
		body = (0.18 + fres * 0.45) * (0.55 + n * 0.7);
		v_fade = smoothstep(0.0, 0.03, UV.y) * pow(1.0 - UV.y, 1.5);
		c = mix(tint.rgb, vec3(1.0), fres * 0.3);
	} else if (style == 3) {
		body = (0.3 + fres) * (0.4 + n2 * 0.9);
		c = vfx_fire_ramp(body * 0.8);
	} else {
		body = (0.2 + fres) * (0.55 + n * 0.8);
		c = mix(tint.rgb, vec3(1.0), clamp(fres * n2, 0.0, 0.7));
	}
	float dissolve = smoothstep(prog - 0.1, prog + 0.1, n2 * 0.8 + 0.1);
	float a = body * v_fade * alpha * dissolve * vfx_near_fade(-VERTEX.z, near_fade);
	a = clamp(a, 0.0, 1.5);
	ALBEDO = c * a * intensity;
	ALPHA = clamp(a, 0.0, 1.0) * occlude;
}
