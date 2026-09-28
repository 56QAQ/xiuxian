// 方块世界着色器（地形、远景 LOD、建筑、植被道具、秘境与试炼场共用）。
// 顶点约定：COLOR.rgb = 该面的“均值反照率”（sRGB，已乘烘焙 AO），COLOR.a < 1 编码自发光强度 s（alpha = 1 - 0.5·s）；
//           UV.x = 材质层编号（BlockIds），UV.y = 风摆幅度（米，0 = 不摆动）。
// 片元：按世界坐标取 1 米/32 像素的方块纹理（逐方块随机旋转/翻转/变体），反照率 = 顶点色 × 细节比值（纹理 / 层均值），
// 法线贴图、粗糙度与凹缝遮蔽来自 detail 数组；顶面积雪（高度 + 北方区域）、近水湿润、熔岩流动、晶体闪烁、夜间窗纸透光。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

const int F_SNOW = 1;
const int F_WET = 2;
const int F_EMIT_MASK = 16;
const int F_LAVA = 32;
const int F_METAL = 64;
const int F_NIGHT_GLOW = 128;
const int F_GLOSSY = 256;
const int F_CRYSTAL = 512;
const int F_FOLIAGE = 1024;
const int F_TERRAIN = 2048;

uniform sampler2DArray albedo_tex : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray detail_tex : hint_default_white, filter_nearest_mipmap_anisotropic, repeat_enable;
// 每层参数：x 变体数，y 变换模式（0 无 / 1 左右翻转 / 2 旋转+翻转），z 标志位，w 保色
uniform vec4 layer_info[96];
// 每层线性均值色
uniform vec4 layer_avg[96];
uniform int snow_layer = 15;

uniform float emission_gain = 3.2;
uniform float normal_strength : hint_range(0.0, 2.0) = 1.0;
uniform float block_jitter = 0.05;        // 逐方块亮度扰动
uniform float macro_variation = 0.10;     // 自然地表的大尺度色斑
uniform float detail_contrast = 1.0;      // 细节比值强度（远景 LOD 可降低）
uniform float texel_scale = 1.0;          // 纹理平铺尺度（米/张）
// 积雪：x 起始高度，y 满雪高度，z 区域开始（世界 z，由此向北积雪），w 区域满雪（世界 z）
uniform vec4 snow_params = vec4(34.0, 52.0, 360.0, 250.0);
uniform float snow_global = 0.0;          // 全局积雪 0~1（冰雪秘境）
uniform vec3 snow_tint : source_color = vec3(0.93, 0.95, 1.0);
uniform float water_level = 11.8;
uniform float wet_range = 1.4;
uniform float night_glow = 0.0;           // 夜间窗纸透光 0~1
uniform vec3 window_color : source_color = vec3(1.0, 0.72, 0.42);
uniform float wind_strength = 1.0;
uniform vec2 wind_dir = vec2(0.8, 0.6);
// 远景 LOD 丢弃圆：xy = 圆心 xz，z = 半径
uniform bool use_holes = false;
uniform vec4 holes[4];

varying vec3 w_pos;
varying vec3 w_nrm;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92), lessThan(c, vec3(0.04045)));
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float amp = UV.y * wind_strength;
	if (amp > 0.0) {
		// 风：主摆（整体顺风）+ 阵风 + 细颤
		float t = TIME;
		float ph = dot(wp.xz, vec2(0.13, 0.11));
		float gust = 0.55 + 0.45 * sin(t * 0.63 + ph * 0.7) * sin(t * 0.21 + ph * 0.3);
		float sway = sin(t * 1.9 + ph * 2.3) * gust + 0.35 * sin(t * 4.3 + wp.y * 3.1 + ph * 5.0);
		vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * sway * amp;
		off.y = -abs(sway) * amp * 0.25;
		mat3 m = mat3(MODEL_MATRIX);
		VERTEX += transpose(m) * off / max(dot(m[0], m[0]), 0.0001);
		wp += off;
	}
	w_pos = wp;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (use_holes) {
		for (int i = 0; i < 4; i++) {
			if (holes[i].z > 0.0 && distance(w_pos.xz, holes[i].xy) < holes[i].z) {
				discard;
			}
		}
	}
	int base = int(UV.x + 0.5);
	vec4 info = layer_info[base];
	int flags = int(info.z + 0.5);
	vec3 n = normalize(w_nrm);
	vec3 an = abs(n);
	// 面坐标系：uv（纹理 u 向右、v 向下）、T = +u 的世界方向、V = +v 的世界方向
	vec3 p = w_pos / texel_scale;
	vec2 uv;
	vec3 T;
	vec3 V;
	if (an.y >= an.x && an.y >= an.z) {
		float s = sign(n.y);
		uv = vec2(p.x, p.z * s);
		T = vec3(1.0, 0.0, 0.0);
		V = vec3(0.0, 0.0, s);
	} else if (an.x >= an.z) {
		float s = sign(n.x);
		uv = vec2(-p.z * s, -p.y);
		T = vec3(0.0, 0.0, -s);
		V = vec3(0.0, -1.0, 0.0);
	} else {
		float s = sign(n.z);
		uv = vec2(p.x * s, -p.y);
		T = vec3(s, 0.0, 0.0);
		V = vec3(0.0, -1.0, 0.0);
	}
	// 所在方块（面后方的实心格）
	vec3 cell = floor(w_pos - n * 0.25);
	float h1 = hash13(cell + vec3(0.37, 11.1, 5.3));
	float h2 = hash13(cell * 1.71 + vec3(3.1, 0.7, 9.9));
	float h3 = hash13(cell * 0.73 + vec3(7.7, 2.2, 1.3));
	float h4 = hash13(cell * 2.13 + vec3(1.9, 6.6, 4.4));
	// 逐方块变换：R 作用于纹理坐标（绕瓦片中心）
	mat2 R = mat2(vec2(1.0, 0.0), vec2(0.0, 1.0));
	int mode = int(info.y + 0.5);
	if (mode >= 1 && h2 < 0.5) {
		R = mat2(vec2(-1.0, 0.0), vec2(0.0, 1.0));
	}
	if (mode == 2) {
		int r = int(h1 * 4.0);
		mat2 rot = mat2(vec2(1.0, 0.0), vec2(0.0, 1.0));
		if (r == 1) {
			rot = mat2(vec2(0.0, 1.0), vec2(-1.0, 0.0));
		} else if (r == 2) {
			rot = mat2(vec2(-1.0, 0.0), vec2(0.0, -1.0));
		} else if (r == 3) {
			rot = mat2(vec2(0.0, -1.0), vec2(1.0, 0.0));
		}
		R = rot * R;
	}
	int variants = max(int(info.x + 0.5), 1);
	int layer = base + min(int(h3 * float(variants)), variants - 1);
	vec2 f = R * (fract(uv) - 0.5) + 0.5;
	vec2 gx = R * dFdx(uv);
	vec2 gy = R * dFdy(uv);
	// 熔岩：缓慢流动 + 扰动
	if ((flags & F_LAVA) != 0) {
		f += vec2(TIME * 0.035, TIME * 0.021) + 0.04 * vec2(sin(TIME * 0.7 + uv.y * 3.0), cos(TIME * 0.6 + uv.x * 3.0));
	}
	vec4 a = textureGrad(albedo_tex, vec3(f, float(layer)), gx, gy);
	vec4 d = textureGrad(detail_tex, vec3(f, float(layer)), gx, gy);
	// 细节比值：保留纹理明暗（与部分色相），均值由顶点色给出
	vec3 avg = max(layer_avg[layer].rgb, vec3(0.003));
	vec3 lw = vec3(0.2126, 0.7152, 0.0722);
	float lr = dot(a.rgb, lw) / dot(avg, lw);
	vec3 ratio = mix(vec3(lr), a.rgb / avg, info.w);
	ratio = clamp(mix(vec3(1.0), ratio, detail_contrast), vec3(0.0), vec3(3.0));
	vec3 c = srgb_to_linear(COLOR.rgb) * ratio;
	float jit = 1.0 + (h4 - 0.5) * 2.0 * block_jitter;
	if ((flags & F_TERRAIN) != 0) {
		float mv = vnoise(w_pos.xz * 0.045) * 0.65 + vnoise(w_pos.xz * 0.013 + vec2(17.0, 3.0)) * 0.35;
		c *= 1.0 + (mv - 0.5) * 2.0 * macro_variation;
		c = mix(c, c * vec3(1.04, 1.0, 0.93), clamp((mv - 0.5) * 2.0, 0.0, 1.0) * 0.6);
	}
	c *= jit;
	float rough = d.b;
	float cav = d.a;
	// 法线（切线空间 → 世界）：贴图 x = +u，y = -v（图像向上）
	vec2 nt = (d.rg * 2.0 - 1.0) * normal_strength;
	vec2 nuv = transpose(R) * vec2(nt.x, -nt.y);
	vec3 nw = normalize(T * nuv.x + V * nuv.y + n * sqrt(max(1.0 - dot(nt, nt), 0.05)));
	// 积雪（朝上的面）
	if ((flags & F_SNOW) != 0 && n.y > 0.5) {
		float region = smoothstep(snow_params.z, snow_params.w, w_pos.z);
		float alt = smoothstep(snow_params.x, snow_params.y, w_pos.y + (vnoise(w_pos.xz * 0.21) - 0.5) * 6.0);
		float amount = max(region * alt, snow_global);
		if (amount > 0.001) {
			float edge = vnoise(w_pos.xz * 0.9 + cell.xz * 0.37) * 0.5 + vnoise(w_pos.xz * 3.1) * 0.25;
			float sm = smoothstep(0.45, 0.6, amount * 1.1 + edge * 0.35 - 0.2);
			if (sm > 0.0) {
				vec4 sa = textureGrad(albedo_tex, vec3(f, float(snow_layer)), gx, gy);
				vec3 savg = max(layer_avg[snow_layer].rgb, vec3(0.003));
				vec3 sc = srgb_to_linear(snow_tint) * clamp(sa.rgb / savg, vec3(0.0), vec3(1.6));
				c = mix(c, sc, sm);
				rough = mix(rough, 0.72, sm);
				nw = normalize(mix(nw, n, sm * 0.8));
				cav = mix(cav, 1.0, sm * 0.7);
			}
		}
	}
	// 近水湿润：变暗、变光滑
	if ((flags & F_WET) != 0) {
		float wet = 1.0 - smoothstep(0.0, wet_range, w_pos.y - water_level);
		wet *= 0.85;
		c *= mix(1.0, 0.62, wet);
		rough = mix(rough, 0.22, wet);
	}
	c *= mix(1.0, cav, 0.4);
	ALBEDO = c;
	ROUGHNESS = rough;
	AO = cav;
	AO_LIGHT_AFFECT = 0.25;
	SPECULAR = (flags & F_GLOSSY) != 0 ? 0.62 : 0.35;
	METALLIC = (flags & F_METAL) != 0 ? 0.55 : 0.0;
	NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	if ((flags & F_FOLIAGE) != 0) {
		BACKLIGHT = c * 0.45;
	}
	// 自发光
	float glow = clamp((1.0 - COLOR.a) * 2.0, 0.0, 1.0);
	vec3 em = vec3(0.0);
	if ((flags & F_LAVA) != 0) {
		float pulse = 0.8 + 0.2 * sin(TIME * 1.3 + h4 * 6.2831 + w_pos.x * 0.15);
		em = c * (0.25 + 1.6 * a.a) * pulse * emission_gain * max(glow, 0.6);
	} else if (glow > 0.0) {
		float m = (flags & F_EMIT_MASK) != 0 ? a.a : 1.0;
		if ((flags & F_CRYSTAL) != 0) {
			m *= 0.75 + 0.35 * sin(TIME * 2.1 + h1 * 6.2831 + dot(w_pos, vec3(1.3, 0.7, 1.1)));
		}
		em = c * glow * m * emission_gain;
	}
	if ((flags & F_NIGHT_GLOW) != 0 && night_glow > 0.0 && h3 > 0.25) {
		em += srgb_to_linear(window_color) * a.a * night_glow * (0.6 + 0.8 * h4) * 1.4;
	}
	EMISSION = em;
}
