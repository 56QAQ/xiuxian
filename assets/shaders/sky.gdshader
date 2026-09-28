// 风格化天空：天顶/地平线渐变、太阳光晕与日轮、月亮、星空。颜色由 DayNight 按时辰写入。
// 不使用 TIME，天空辐照度只在参数/光照变化时增量更新。
shader_type sky;

uniform vec3 zenith_color : source_color = vec3(0.22, 0.46, 0.84);
uniform vec3 horizon_color : source_color = vec3(0.72, 0.84, 0.95);
uniform vec3 ground_color : source_color = vec3(0.35, 0.40, 0.46);
uniform vec3 sun_glow_color : source_color = vec3(1.0, 0.8, 0.55);
uniform float sun_glow = 0.45;
uniform float sun_disk_size = 0.9994;
uniform vec3 moon_dir = vec3(0.0, -1.0, 0.0);
uniform float moon_intensity = 0.0;
uniform float star_intensity = 0.0;
uniform float horizon_sharpness = 0.42;

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void sky() {
	vec3 d = normalize(EYEDIR);
	float y = d.y;
	float t = pow(clamp(y, 0.0, 1.0), horizon_sharpness);
	vec3 col = mix(horizon_color, zenith_color, t);
	if (y < 0.0) {
		col = mix(horizon_color, ground_color, clamp(-y * 3.0, 0.0, 1.0));
	}
	if (LIGHT0_ENABLED) {
		float sd = max(dot(d, LIGHT0_DIRECTION), 0.0);
		float low = 1.0 - smoothstep(-0.1, 0.5, LIGHT0_DIRECTION.y);
		// 地平线方向的大范围暖色晕染（日出日落更强）
		col += sun_glow_color * pow(sd, 4.0) * sun_glow * (0.35 + 0.9 * low) * (1.0 - t * 0.7);
		col += sun_glow_color * pow(sd, 48.0) * 0.6;
		if (!AT_CUBEMAP_PASS) {
			float disk = smoothstep(sun_disk_size, sun_disk_size + 0.0003, sd);
			col += LIGHT0_COLOR * disk * 12.0 * clamp(LIGHT0_ENERGY, 0.0, 2.0) * smoothstep(-0.05, 0.02, y);
		}
	}
	if (moon_intensity > 0.0) {
		float md = max(dot(d, normalize(moon_dir)), 0.0);
		col += vec3(0.55, 0.62, 0.85) * pow(md, 60.0) * 0.25 * moon_intensity;
		if (!AT_CUBEMAP_PASS) {
			float disk = smoothstep(0.99955, 0.99975, md);
			col += vec3(0.95, 0.96, 1.0) * disk * 2.2 * moon_intensity;
		}
	}
	if (star_intensity > 0.0 && !AT_CUBEMAP_PASS && y > 0.0) {
		vec3 sp = d * 220.0;
		vec3 cell = floor(sp);
		float h = hash3(cell);
		if (h > 0.9965) {
			vec3 center = cell + vec3(0.5) + (vec3(hash3(cell + 1.3), hash3(cell + 2.7), hash3(cell + 4.1)) - 0.5) * 0.6;
			float r = length(sp - center);
			float b = smoothstep(0.35, 0.0, r) * (0.4 + 0.6 * hash3(cell * 1.7));
			col += vec3(0.9, 0.92, 1.0) * b * star_intensity * smoothstep(0.0, 0.25, y) * 2.0;
		}
		// 银河带
		float band = exp(-pow(dot(d, normalize(vec3(0.35, 0.3, 0.88))) * 3.2, 2.0));
		col += vec3(0.10, 0.11, 0.18) * band * star_intensity * smoothstep(0.0, 0.3, y) * (0.6 + 0.4 * hash3(floor(d * 90.0)));
	}
	COLOR = col;
}
