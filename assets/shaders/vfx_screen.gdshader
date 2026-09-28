// 屏幕特效（CanvasLayer 全屏 ColorRect）：高速疾行时的径向速度线，重击时的径向模糊与色散。
// speed / kick 均为 0 时节点隐藏，不产生额外开销。
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D noise_tex : filter_linear, repeat_enable;
uniform float speed : hint_range(0.0, 1.0) = 0.0;
uniform float kick : hint_range(0.0, 1.0) = 0.0;
uniform vec4 line_color : source_color = vec4(0.85, 0.93, 1.0, 1.0);
uniform vec2 center = vec2(0.5, 0.48);
uniform float aspect = 1.777;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - center;
	vec2 da = d * vec2(aspect, 1.0);
	float r = length(da);
	vec3 col;
	if (kick > 0.002) {
		// 径向模糊：沿指向中心的方向采样
		vec3 acc = vec3(0.0);
		float amt = kick * 0.045 * smoothstep(0.05, 0.6, r);
		for (int i = 0; i < 8; i++) {
			float s = 1.0 - amt * float(i) / 7.0;
			acc += texture(screen_tex, center + d * s).rgb;
		}
		col = acc / 8.0;
		// 色散：红蓝通道沿径向错开
		vec2 off = d * kick * 0.014;
		col.r = mix(col.r, texture(screen_tex, uv + off).r, 0.7);
		col.b = mix(col.b, texture(screen_tex, uv - off).b, 0.7);
	} else {
		col = texture(screen_tex, uv).rgb;
	}
	if (speed > 0.002) {
		float ang = atan(da.y, da.x) / 6.28318;
		float n = texture(noise_tex, vec2(ang * 4.0, TIME * 0.9)).b;
		float n2 = texture(noise_tex, vec2(ang * 9.0 + 0.3, TIME * 1.7)).g;
		float lines = smoothstep(0.72, 0.95, n) * 0.8 + smoothstep(0.8, 0.97, n2) * 0.5;
		float mask = smoothstep(0.32, 0.75, r) * smoothstep(1.25, 0.8, r);
		// 线条沿半径向外流动
		float flow = 0.6 + 0.4 * sin(r * 30.0 - TIME * 40.0 + n * 12.0);
		col = mix(col, line_color.rgb, clamp(lines * mask * flow * speed * 0.55, 0.0, 0.6));
	}
	COLOR = vec4(col, 1.0);
}
