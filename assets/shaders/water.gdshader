// 国风水面：玉青浅水 → 黛蓝深水（比尔定律）、折射、柔和的岸边泡沫、平缓波纹法线、
// 菲涅尔反射（天空辐照度由引擎给出：远山与云会映在水里）+ 屏幕空间反射（亭台、树影倒映），
// 太阳/月亮高光由光照计算。
// 水深：优先使用地形高度图（大地图，height_tex，开启 MSAA 或兼容渲染器下也可靠），
// 否则使用深度纹理；深度纹理不可用时（如 MSAA 下的部分驱动、兼容渲染器）自动跳过屏幕空间反射。
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.36, 0.64, 0.58);
uniform vec3 deep_color : source_color = vec3(0.05, 0.17, 0.24);
uniform vec3 foam_color : source_color = vec3(0.92, 0.95, 0.96);
uniform vec3 sky_color : source_color = vec3(0.62, 0.76, 0.92);
uniform float daylight = 1.0;
uniform float absorption = 0.34;
uniform float clarity = 0.72;
uniform float foam_width = 0.55;
uniform float wave_strength = 0.18;
uniform float reflect_strength = 0.85;
uniform int ssr_steps = 20;
uniform float fallback_depth = 3.0;       // 无高度图且无深度纹理时的水深（米）
// 地形高度图：r = 方块柱顶高度 / height_scale；height_rect = (x0, z0, 宽, 深)
uniform bool use_height_tex = false;
uniform sampler2D height_tex : filter_linear, repeat_disable;
uniform vec4 height_rect = vec4(0.0, 0.0, 1024.0, 1024.0);
uniform float height_scale = 255.0;
uniform float water_level = 11.8;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying vec3 wpos;

float hash2(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

// 波纹高度（用于有限差分求法线）：长涌 + 细碎涟漪
float waves(vec2 p, float t) {
	float h = 0.0;
	h += sin(dot(p, vec2(0.11, 0.07)) + t * 0.7) * 0.45;
	h += sin(dot(p, vec2(-0.08, 0.15)) + t * 0.9) * 0.3;
	h += sin(dot(p, vec2(0.23, -0.19)) + t * 1.5) * 0.12;
	h += (vnoise(p * 0.3 + vec2(t * 0.18, t * 0.11)) - 0.5) * 0.6;
	h += (vnoise(p * 0.9 - vec2(t * 0.3, -t * 0.2)) - 0.5) * 0.22;
	h += (vnoise(p * 2.6 + vec2(t * 0.6, t * 0.4)) - 0.5) * 0.06;
	return h;
}

float scene_depth(sampler2D dt, vec2 uv, mat4 inv_proj) {
	float d = texture(dt, uv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(uv, d) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(uv * 2.0 - 1.0, d);
#endif
	vec4 v = inv_proj * vec4(ndc, 1.0);
	return -v.z / v.w;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	vec2 p = wpos.xz;
	float e = 0.3;
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float ws = wave_strength * (1.0 - smoothstep(30.0, 300.0, dist) * 0.85);
	float h0 = waves(p, t);
	float hx = waves(p + vec2(e, 0.0), t);
	float hz = waves(p + vec2(0.0, e), t);
	vec3 nw = normalize(vec3(-(hx - h0) / e * ws, 1.0, -(hz - h0) / e * ws));
	vec3 nv = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	NORMAL = nv;
	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);

	// 水深：地形高度图（垂直水深）或深度纹理（沿视线厚度）
	float scene_d = scene_depth(depth_tex, SCREEN_UV, INV_PROJECTION_MATRIX);
	float water_d = -VERTEX.z;
	float view_thick = max(scene_d - water_d, 0.0);
	float vdepth = fallback_depth;
	bool depth_ok = view_thick < 400.0;
	if (use_height_tex) {
		vec2 huv = (p - height_rect.xy) / height_rect.zw;
		float th = texture(height_tex, huv).r * height_scale;
		bool inside = huv.x > 0.0 && huv.y > 0.0 && huv.x < 1.0 && huv.y < 1.0;
		vdepth = inside ? max(water_level - th, 0.0) : 40.0;
		// 深水处本就可能读到远处：只有浅水处读到“无穷远”才说明深度纹理不可用
		depth_ok = depth_ok || vdepth > 30.0;
	} else if (depth_ok) {
		vdepth = view_thick * max(abs(V.y), 0.15);
	}
	float thick = (use_height_tex || !depth_ok) ? vdepth / max(abs(V.y), 0.22) : view_thick;
	float trans = exp(-thick * absorption);
	vec3 water_col = mix(deep_color, shallow_color, trans);

	// 折射
	vec2 ruv = SCREEN_UV + nw.xz * 0.018 * clamp(thick * 0.3, 0.0, 1.0);
	if (depth_ok && scene_depth(depth_tex, ruv, INV_PROJECTION_MATRIX) < water_d) {
		ruv = SCREEN_UV;
	}
	vec3 refr = textureLod(screen_tex, ruv, 0.0).rgb;
	float see = trans * clarity;

	// 菲涅尔
	float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(nw, V), 0.0, 1.0), 5.0);
	fres = clamp(fres * reflect_strength, 0.0, 0.9);

	// 屏幕空间反射（视空间步进；深度纹理不可用或兼容渲染器时跳过）
	float hit = 0.0;
	vec3 ssr = vec3(0.0);
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	bool use_ssr = false;
#else
	bool use_ssr = depth_ok && ssr_steps > 0;
#endif
	if (use_ssr) {
		vec3 upv = (VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz;
		vec3 rv = normalize(reflect(normalize(VERTEX), normalize(mix(nv, upv, 0.65))));
		if (rv.z < 0.2) {
			vec3 pos = VERTEX;
			float stp = 0.5 + dist * 0.012;
			for (int i = 0; i < ssr_steps; i++) {
				pos += rv * stp;
				stp *= 1.25;
				vec4 cp = PROJECTION_MATRIX * vec4(pos, 1.0);
				vec2 suv = cp.xy / cp.w * 0.5 + 0.5;
				if (suv.x < 0.0 || suv.x > 1.0 || suv.y < 0.0 || suv.y > 1.0) {
					break;
				}
				float sd = scene_depth(depth_tex, suv, INV_PROJECTION_MATRIX);
				float pd = -pos.z;
				if (pd > sd && pd - sd < stp * 1.6 + 0.6 && sd > water_d + 0.3) {
					vec2 edge = min(suv, 1.0 - suv);
					hit = smoothstep(0.0, 0.08, min(edge.x, edge.y)) * (1.0 - 0.7 * float(i) / float(ssr_steps));
					ssr = textureLod(screen_tex, suv + nw.xz * 0.012, 0.0).rgb;
					break;
				}
			}
		}
	}

	// 岸边泡沫（沿等深线，柔和、带噪声断续）
	float fn = vnoise(p * 1.5 + vec2(t * 0.35, -t * 0.25)) * 0.65 + vnoise(p * 4.0 - vec2(t * 0.6, t * 0.3)) * 0.35;
	float band = 1.0 - smoothstep(0.0, foam_width * (0.5 + 0.9 * fn), vdepth);
	band *= step(0.001, vdepth);
	float ripple = 0.5 + 0.5 * sin(vdepth * 18.0 - t * 1.6 + fn * 3.0);
	float foam = smoothstep(0.35, 0.75, band * (0.45 + 0.4 * fn + 0.3 * ripple));

	vec3 base = water_col * (1.0 - see);
	ALBEDO = mix(base * 0.9, foam_color, foam * 0.85);
	vec3 em = refr * see * (1.0 - fres) * (1.0 - foam);
	em += ssr * fres * hit * (1.0 - foam);
	EMISSION = em;
	ROUGHNESS = mix(0.05, 0.6, foam);
	METALLIC = 0.0;
	// 有屏幕空间反射处降低天空反射，避免叠加过亮
	SPECULAR = mix(0.5, 0.1, hit * (1.0 - foam)) * mix(1.0, 0.3, foam);
	ALPHA = 1.0;
}
