shader_type canvas_item;
// 中央玉璧：半透明玉环带 + 左侧朱砂笔触（生命）+ 右侧青色流动灵液（灵力）。
// 坐标：UV 0..1 覆盖正方形控件；角度与 Control.draw_arc 一致（0 = 右，90° = 下）。
// 生命弧自 108° 顺时针至 252°（左侧自下而上），灵力弧自 72° 逆时针至 -72°（右侧自下而上）。

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float size_px = 320.0;     // 控件边长（像素）
uniform float ring_r = 118.0;      // 环带中线半径
uniform float band_w = 18.0;       // 玉环带宽
uniform float hp = 1.0;            // 当前生命比例
uniform float hp_lag = 1.0;        // 延迟显示的生命比例（失血残痕）
uniform float qi = 1.0;            // 当前灵力比例
uniform float burn = 0.0;          // 灵力枯竭 0/1
uniform float low = 0.0;           // 低血量强度 0..1
uniform float disc_alpha = 0.5;   // 玉环整体透明度
uniform float fade = 1.0;          // 整体淡入淡出

const float SPAN = 144.0;

float sat(float x) { return clamp(x, 0.0, 1.0); }

vec4 over(vec4 under, vec4 top) {
	float a = top.a + under.a * (1.0 - top.a);
	vec3 c = (top.rgb * top.a + under.rgb * under.a * (1.0 - top.a)) / max(a, 1e-4);
	return vec4(c, a);
}

void fragment() {
	vec2 p = (UV - 0.5) * size_px;
	float r = length(p);
	float ang = degrees(atan(p.y, p.x));          // -180..180
	float a360 = mod(ang + 360.0, 360.0);
	float dr = r - ring_r;
	float hw_band = band_w * 0.5;
	float circ = radians(SPAN) * ring_r;            // 弧长（像素）
	vec4 col = vec4(0.0);

	// ---------------------------------------------------------------- 玉环带
	float band = 1.0 - smoothstep(hw_band - 1.0, hw_band + 0.6, abs(dr));
	if (band > 0.0) {
		vec2 puv = vec2(a360 / 360.0 * 5.0, r / 110.0);
		float n = texture(noise_tex, puv).r;
		float n2 = texture(noise_tex, puv * 2.3 + 0.4).r;
		vec3 jade = mix(vec3(0.24, 0.55, 0.44), vec3(0.76, 0.93, 0.84), smoothstep(0.25, 0.8, n));
		jade = mix(jade, vec3(0.93, 0.98, 0.95), smoothstep(0.62, 0.85, n2) * 0.35);
		// 横截面高光：外缘亮、内缘暗，像打磨过的玉面
		float sheen = 0.82 + 0.28 * (dr / hw_band);
		jade *= sheen;
		// 谷纹：沿环排布的小凸点
		float s = a360 / 360.0 * 6.2831853 * ring_r / 7.0;
		vec2 cell = vec2(fract(s) - 0.5, fract(dr / 7.0 + 0.5 * floor(s) * 0.5) - 0.5);
		float dot_d = length(cell * 7.0);
		float grain = (1.0 - smoothstep(1.1, 1.9, dot_d)) * (1.0 - smoothstep(hw_band - 3.0, hw_band - 1.5, abs(dr)));
		jade = mix(jade, vec3(0.95, 1.0, 0.97), grain * 0.35);
		col = vec4(jade, band * disc_alpha * (0.85 + 0.3 * grain));
		// 灵力枯竭：灵力侧玉面裂纹
		if (burn > 0.5 && a360 > 270.0 - 1.0 || burn > 0.5 && a360 < 90.0) {
			float crack = 1.0 - texture(noise_tex, vec2(a360 / 360.0 * 3.0, r / 60.0)).a;
			col = over(col, vec4(0.06, 0.05, 0.08, crack * band * 0.9));
		}
	}
	// 外侧淡墨晕（亮背景上托住玉环）
	float halo = exp(-pow((abs(dr) - hw_band - 2.5) / 2.5, 2.0)) * (1.0 - band);
	col = over(vec4(0.02, 0.03, 0.03, halo * 0.28 * disc_alpha * 2.0), col);
	// 金色描边（内外细线）
	float rim_o = exp(-pow((dr - hw_band) / 0.75, 2.0));
	float rim_i = exp(-pow((dr + hw_band) / 0.75, 2.0));
	col = over(col, vec4(0.96, 0.84, 0.55, (rim_o * 0.75 + rim_i * 0.55) * disc_alpha * 2.2));

	// 内圈罗盘刻度：细金线 + 每 15° 一刻、每 45° 长刻
	float r_in = ring_r - hw_band - 6.0;
	float bez = exp(-pow((r - r_in) / 0.7, 2.0));
	float da15 = abs(fract(a360 / 15.0 + 0.5) - 0.5) * 15.0;
	float da45 = abs(fract(a360 / 45.0 + 0.5) - 0.5) * 45.0;
	float tick_w = 1.0 - smoothstep(0.45, 1.1, radians(da15) * r);
	float tick_len = (da45 < 1.0) ? 7.0 : 3.5;
	float tick = tick_w * step(r_in - tick_len, r) * step(r, r_in);
	col = over(col, vec4(0.96, 0.84, 0.55, (bez * 0.5 + tick * 0.55) * disc_alpha * 1.6));

	// ---------------------------------------------------------------- 生命：朱砂笔触
	float t_hp = (a360 - 108.0) / SPAN;
	if (t_hp >= -0.02 && t_hp <= 1.02) {
		float along = t_hp * circ;
		// 毛笔丝：沿弧方向拉长的噪声
		float streak = texture(noise_tex, vec2(along / 256.0, dr / 64.0 + 0.5)).g;
		float edge_n = texture(noise_tex, vec2(along / 700.0, 0.21)).r;
		// 笔画半宽：起笔饱满，末端（当前生命处）收细
		float hw = hw_band * 1.1 * (1.0 + 0.22 * exp(-t_hp * 22.0));
		float tail = smoothstep(hp - 0.12, hp, t_hp);
		hw *= mix(1.0, 0.55, tail) * (0.86 + 0.28 * edge_n);
		float inside = 1.0 - smoothstep(hw - 1.1, hw + 0.4, abs(dr));
		// 起笔圆头
		inside *= smoothstep(-0.012, 0.004, t_hp);
		// 飞白：收笔与笔画边缘处墨丝断续
		float dry = sat(smoothstep(hp - 0.2, hp, t_hp) * 0.8 + smoothstep(0.55, 1.0, abs(dr) / max(hw, 1.0)) * 0.3);
		float keep = smoothstep(dry * 0.75 - 0.1, dry * 0.75 + 0.1, streak);
		float end_cut = step(t_hp, hp + (streak - 0.5) * 0.03);
		float a_hp = inside * keep * end_cut * step(0.001, hp);
		vec3 ink = mix(vec3(0.46, 0.03, 0.02), vec3(0.9, 0.17, 0.09), smoothstep(0.15, 0.85, streak));
		ink = mix(ink, vec3(1.0, 0.45, 0.3), low * (0.5 + 0.5 * sin(TIME * 7.0)) * 0.45);
		// 失血残痕：暗赭色
		float lag_in = step(hp, t_hp) * step(t_hp, hp_lag) * (1.0 - smoothstep(hw_band * 0.75 - 1.0, hw_band * 0.75 + 0.4, abs(dr)));
		col = over(col, vec4(0.3, 0.1, 0.06, lag_in * 0.85 * (0.75 + 0.25 * streak)));
		col = over(col, vec4(ink, a_hp));
	}

	// ---------------------------------------------------------------- 灵力：青色灵液
	float t_qi = (72.0 - ang) / SPAN;
	if (t_qi >= -0.02 && t_qi <= 1.02 && abs(ang) < 100.0) {
		float along = t_qi * circ;
		float hw = hw_band * 0.66;
		float inside = (1.0 - smoothstep(hw - 1.0, hw + 0.4, abs(dr))) * smoothstep(-0.01, 0.004, t_qi);
		float lvl = qi;
		float fill = inside * smoothstep(lvl + 0.004, lvl - 0.004, t_qi) * step(0.001, qi);
		float flow = texture(noise_tex, vec2(along / 160.0 - TIME * 0.35, dr / 40.0 + 0.2)).r;
		float flow2 = texture(noise_tex, vec2(along / 70.0 - TIME * 0.8, dr / 18.0 + 0.6)).b;
		vec3 liq = mix(vec3(0.05, 0.3, 0.72), vec3(0.34, 0.8, 1.0), smoothstep(0.25, 0.8, flow));
		// 流光：沿流动方向的亮纹
		liq = mix(liq, vec3(0.85, 0.98, 1.0), smoothstep(0.62, 0.9, flow2) * 0.55);
		// 管壁高光（偏外侧的一道亮线）
		liq += vec3(0.35, 0.45, 0.5) * exp(-pow((dr - hw * 0.35) / 1.2, 2.0)) * 0.7;
		// 液面：末端发光
		float men = exp(-pow((t_qi - lvl) * circ / 3.0, 2.0)) * inside;
		if (burn > 0.5) {
			float fl = 0.55 + 0.45 * sin(TIME * 18.0);
			liq = mix(liq, vec3(1.0, 0.28, 0.22), 0.75 * fl);
		}
		// 空槽：刻出的浅沟
		float groove = inside * (1.0 - fill) * 0.22;
		col = over(col, vec4(0.02, 0.05, 0.08, groove));
		col = over(col, vec4(liq, fill * 0.96));
		col = over(col, vec4(0.9, 1.0, 1.0, men * 0.85 * step(0.001, qi) * step(qi, 0.999)));
	}
	// 生命空槽
	float t_hp2 = (a360 - 108.0) / SPAN;
	if (t_hp2 >= 0.0 && t_hp2 <= 1.0) {
		float g_in = 1.0 - smoothstep(hw_band * 0.5 - 1.0, hw_band * 0.5 + 0.4, abs(dr));
		col = over(vec4(0.03, 0.02, 0.02, g_in * 0.18 * step(hp_lag, t_hp2)), col);
	}
	COLOR = vec4(col.rgb, col.a * fade);
}
