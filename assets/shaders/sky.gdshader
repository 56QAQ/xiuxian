// 国风天空：天顶/地平线渐变与地平雾带、层叠水墨远山（山脚云雾）、写意云层（分层着色、金边）、
// 太阳光晕与日轮、月亮（月面斑纹与月晕）、星空与银河。颜色由 DayNight 按时辰写入。
// 不使用 TIME（云的漂移由 cloud_time 低频推进），天空辐照度只在参数变化时增量更新。
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.26, 0.50, 0.84);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.84, 0.92);
uniform vec3 haze_color : source_color = vec3(0.84, 0.90, 0.94);
uniform vec3 ground_color : source_color = vec3(0.35, 0.40, 0.46);
uniform vec3 sun_glow_color : source_color = vec3(1.0, 0.8, 0.55);
uniform float sun_glow = 0.45;
uniform float sun_disk_size = 0.99955;
uniform float horizon_sharpness = 0.45;
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float moon_intensity = 0.0;
uniform float star_intensity = 0.0;
// 远山：ink = 最近一层山色，mist = 山脚雾色
uniform vec3 mountain_ink : source_color = vec3(0.40, 0.50, 0.56);
uniform vec3 mountain_mist : source_color = vec3(0.82, 0.88, 0.92);
uniform float mountain_strength = 1.0;
uniform float mountain_scale = 1.0;
// 云
uniform vec3 cloud_light : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 cloud_shadow : source_color = vec3(0.66, 0.72, 0.82);
uniform float cloud_cover = 0.45;
uniform float cloud_opacity = 0.9;
uniform float cloud_time = 0.0;
uniform vec2 cloud_wind = vec2(0.012, 0.004);

float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}

float hash12(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

// 周期 1D 值噪声（n 格一圈，保证方位角首尾相接）
float pnoise1(float x, float n, float seed) {
	float i = floor(x);
	float f = fract(x);
	float a = hash11(mod(i, n) + seed * 17.0);
	float b = hash11(mod(i + 1.0, n) + seed * 17.0);
	float u = f * f * (3.0 - 2.0 * f);
	return mix(a, b, u);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x), mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		s += vnoise(p) * a;
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

// 山形（仰角）：分形山脊（连绵起伏 + 尖峰），sharp 越大峰越陡
float range_h(float az, float cells, float seed, float sharp) {
	float x = az / 6.2831853 * cells;
	float h = 0.0;
	float amp = 0.55;
	float c = cells;
	float f = 1.0;
	for (int o = 0; o < 5; o++) {
		float n = pnoise1(x * f, c, seed + float(o) * 3.1);
		// 高频层用脊形噪声，产生峰
		float r = o == 0 ? n : 1.0 - abs(n * 2.0 - 1.0);
		h += r * amp;
		amp *= 0.5;
		f *= 2.0;
		c *= 2.0;
	}
	return pow(clamp(h / 1.05, 0.0, 1.0), sharp);
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	float az = atan(d.x, d.z) + 3.14159265;
	float t = pow(clamp(y, 0.0, 1.0), horizon_sharpness);
	vec3 col = mix(horizon_color, zenith_color, t);
	// 地平雾带
	col = mix(col, haze_color, exp(-max(y, 0.0) * 14.0) * 0.8);
	if (y < 0.0) {
		col = mix(haze_color, ground_color, clamp(-y * 3.0, 0.0, 1.0));
	}
	float sd = 0.0;
	float low = 0.0;
	if (LIGHT0_ENABLED) {
		sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
		low = 1.0 - smoothstep(-0.1, 0.45, LIGHT0_DIRECTION.y);
		// 地平线方向的大范围暖色晕染（日出日落更强）
		col += sun_glow_color * pow(sd, 5.0) * sun_glow * (0.3 + 1.0 * low) * (1.0 - t * 0.6);
		col += sun_glow_color * pow(sd, 60.0) * 0.5;
	}
	// 云（天顶到地平线的穹顶投影）
	float cloud_a = 0.0;
	if (y > 0.0 && cloud_cover > 0.001) {
		vec2 cp = d.xz / (y + 0.16) * 0.5 + cloud_wind * cloud_time;
		// 拉长的云带（写意横云）
		vec2 cq = vec2(cp.x * 0.7, cp.y * 1.4);
		float n = fbm(cq * 0.9);
		float n2 = fbm(cq * 2.1 + vec2(5.1, 1.7));
		float dens = n * 0.8 + n2 * 0.2;
		float cov = smoothstep(1.0 - cloud_cover - 0.08, 1.0 - cloud_cover + 0.22, dens);
		// 分层着色：朝阳面亮、背面暗，并做柔和的色阶（写意）
		vec2 lp = LIGHT0_ENABLED ? LIGHT0_DIRECTION.xz * 0.08 : vec2(0.0);
		float sh = fbm((cq - lp) * 0.9) * 0.8 + n2 * 0.2;
		float lit = clamp(0.5 + (dens - sh) * 6.0, 0.0, 1.0);
		lit = smoothstep(0.15, 0.85, floor(lit * 3.0 + 0.5) / 3.0 * 0.6 + lit * 0.4);
		vec3 cc = mix(cloud_shadow, cloud_light, lit);
		// 金边（逆光时云缘发亮）
		float rim = (1.0 - cov) * cov * 4.0;
		cc += sun_glow_color * pow(sd, 6.0) * (0.4 + rim) * 0.8;
		float fade = smoothstep(0.0, 0.16, y) * (1.0 - smoothstep(0.75, 1.0, y) * 0.3);
		cloud_a = cov * cloud_opacity * fade;
		col = mix(col, cc, cloud_a);
	}
	// 层叠水墨远山：远层淡、近层浓，山脚没入云雾
	float mtn = 0.0;
	if (mountain_strength > 0.0 && y < 0.2 * mountain_scale && y > -0.05) {
		for (int i = 0; i < 3; i++) {
			float fi = float(i);
			float base = (-0.03 - fi * 0.008) * mountain_scale;
			float amp = (0.16 - fi * 0.04) * mountain_scale;
			float r = base + amp * range_h(az + fi * 1.7, 7.0 + fi * 3.0, 11.0 + fi * 13.0, 1.6 + fi * 0.3);
			float cover = smoothstep(r + 0.0015, r - 0.0015, y);
			if (cover > 0.0) {
				// 山体：远层淡、近层浓；峰顶墨色，山腰以下渐隐入云雾（山色始终比所在处天色更深）
				float g = smoothstep(base + amp * 0.1, base + amp * 0.85, y);
				vec3 ink_c = min(mountain_ink, col * 0.85);
				vec3 layer_ink = mix(mountain_mist, ink_c, 0.45 + 0.25 * fi);
				vec3 mc = mix(mountain_mist, layer_ink, pow(g, 0.7));
				mtn = max(mtn, 0.3 + fi * 0.3);
				col = mix(col, mc, mountain_strength * cover);
			}
		}
	}
	if (LIGHT0_ENABLED && !AT_CUBEMAP_PASS && mtn == 0.0) {
		float disk = smoothstep(sun_disk_size, sun_disk_size + 0.00025, sd);
		col += LIGHT0_COLOR * disk * 10.0 * clamp(LIGHT0_ENERGY, 0.0, 2.0) * smoothstep(-0.04, 0.02, y) * (1.0 - cloud_a * 0.85);
	}
	if (moon_intensity > 0.0) {
		vec3 md = normalize(moon_dir);
		float mdot = max(dot(d, md), 0.0);
		col += vec3(0.50, 0.58, 0.82) * pow(mdot, 40.0) * 0.22 * moon_intensity * (1.0 - cloud_a * 0.5);
		if (!AT_CUBEMAP_PASS && mtn == 0.0) {
			float disk = smoothstep(0.99935, 0.9996, mdot);
			// 月面斑纹
			vec3 tang = normalize(cross(md, vec3(0.0, 1.0, 0.0)));
			vec3 bit = cross(tang, md);
			vec2 mp = vec2(dot(d, tang), dot(d, bit)) * 900.0;
			float mare = vnoise(mp * 0.8) * 0.6 + vnoise(mp * 2.1) * 0.4;
			vec3 moon_c = vec3(0.96, 0.95, 0.88) * (0.72 + 0.28 * smoothstep(0.35, 0.7, mare));
			col = mix(col, moon_c * 2.2 * moon_intensity, disk * (1.0 - cloud_a * 0.8));
		}
	}
	if (star_intensity > 0.0 && !AT_CUBEMAP_PASS && y > 0.0) {
		vec3 sp = d * 220.0;
		vec3 cell = floor(sp);
		float h = hash13(cell);
		if (h > 0.9965) {
			vec3 center = cell + vec3(0.5) + (vec3(hash13(cell + 1.3), hash13(cell + 2.7), hash13(cell + 4.1)) - 0.5) * 0.6;
			float r = length(sp - center);
			float b = smoothstep(0.35, 0.0, r) * (0.4 + 0.6 * hash13(cell * 1.7));
			col += vec3(0.9, 0.92, 1.0) * b * star_intensity * smoothstep(0.0, 0.25, y) * 2.0 * (1.0 - cloud_a) * (1.0 - step(0.001, mtn));
		}
		// 银河带
		float band = exp(-pow(dot(d, normalize(vec3(0.35, 0.3, 0.88))) * 3.2, 2.0));
		float dust = vnoise(d.xz * 14.0 + d.y * 9.0) * 0.6 + vnoise(d.xz * 37.0 - d.y * 11.0) * 0.4;
		col += vec3(0.10, 0.11, 0.18) * band * star_intensity * smoothstep(0.0, 0.3, y) * (0.45 + 0.55 * dust) * (1.0 - cloud_a);
	}
	COLOR = col;
}
