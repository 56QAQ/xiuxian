// 风格化水面：深度着色（比尔定律）、折射、岸边泡沫、程序化波纹法线、菲涅尔天空反射。
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_disabled, diffuse_lambert, specular_schlick_ggx;

uniform vec3 shallow_color : source_color = vec3(0.34, 0.74, 0.76);
uniform vec3 deep_color : source_color = vec3(0.04, 0.19, 0.34);
uniform vec3 foam_color : source_color = vec3(0.93, 0.97, 1.0);
uniform vec3 sky_color : source_color = vec3(0.62, 0.76, 0.92);
uniform float daylight = 1.0;
uniform float absorption = 0.22;
uniform float clarity = 0.75;
uniform float foam_width = 0.7;
uniform float wave_strength = 0.32;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

varying vec3 wpos;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

// 波纹高度（用于有限差分求法线）
float waves(vec2 p, float t) {
	float h = 0.0;
	h += sin(dot(p, vec2(0.21, 0.13)) + t * 1.1) * 0.5;
	h += sin(dot(p, vec2(-0.17, 0.29)) + t * 1.4) * 0.35;
	h += sin(dot(p, vec2(0.43, -0.37)) + t * 2.1) * 0.18;
	h += (vnoise(p * 0.55 + vec2(t * 0.35, t * 0.2)) - 0.5) * 0.9;
	h += (vnoise(p * 1.4 - vec2(t * 0.5, -t * 0.3)) - 0.5) * 0.35;
	return h;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float t = TIME;
	vec2 p = wpos.xz;
	float e = 0.35;
	float h0 = waves(p, t);
	float hx = waves(p + vec2(e, 0.0), t);
	float hz = waves(p + vec2(0.0, e), t);
	float dist = length(wpos - CAMERA_POSITION_WORLD);
	float ws = wave_strength * (1.0 - smoothstep(60.0, 400.0, dist) * 0.8);
	vec3 nw = normalize(vec3(-(hx - h0) / e * ws, 1.0, -(hz - h0) / e * ws));
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);

	// 水深（沿视线）
	float depth_raw = texture(depth_tex, SCREEN_UV).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc = vec3(SCREEN_UV, depth_raw) * 2.0 - 1.0;
#else
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_raw);
#endif
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float scene_d = -view.z;
	float water_d = -VERTEX.z;
	float thick = max(scene_d - water_d, 0.0);
	// 视线越平，看到的水越厚
	float trans = exp(-thick * absorption);
	vec3 water_col = mix(deep_color, shallow_color, trans);

	// 折射
	vec2 ruv = SCREEN_UV + nw.xz * 0.02 * clamp(thick * 0.3, 0.0, 1.0);
	float d2 = texture(depth_tex, ruv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
	vec3 ndc2 = vec3(ruv, d2) * 2.0 - 1.0;
#else
	vec3 ndc2 = vec3(ruv * 2.0 - 1.0, d2);
#endif
	vec4 v2 = INV_PROJECTION_MATRIX * vec4(ndc2, 1.0);
	v2.xyz /= v2.w;
	if (-v2.z < water_d) {
		ruv = SCREEN_UV;
	}
	vec3 refr = textureLod(screen_tex, ruv, 0.0).rgb;
	float see = trans * clarity;

	// 菲涅尔
	vec3 V = normalize(CAMERA_POSITION_WORLD - wpos);
	float fres = 0.03 + 0.97 * pow(1.0 - clamp(dot(nw, V), 0.0, 1.0), 5.0);
	fres = clamp(fres, 0.0, 0.85);

	// 泡沫
	float fn = vnoise(p * 1.7 + vec2(t * 0.4, -t * 0.3));
	float foam = 1.0 - smoothstep(0.0, foam_width * (0.6 + 0.8 * fn), thick);
	foam *= step(0.001, thick);
	float foam_edge = step(0.45, fn + foam * 0.6) * foam;

	vec3 base = water_col * (1.0 - see);
	vec3 sky = sky_color * daylight * 0.85 + vec3(0.02, 0.03, 0.06);
	ALBEDO = mix(base, foam_color, foam_edge * 0.85);
	EMISSION = refr * see * (1.0 - fres) * (1.0 - foam_edge) + sky * fres * 0.6 * (1.0 - foam_edge);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = 1.0;
}
