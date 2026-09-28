shader_type canvas_item;
// 屏幕边缘渗墨：低血量时朱红墨色自四周向内洇开（随心跳起伏），灵力枯竭时为青灰墨。
// 覆盖全屏的 ColorRect；amount 0..1 控制洇入深度。形状为圆角矩形（超椭圆）+ 大小两层噪声毛边，
// 靠边处浓、向内渐淡，前沿有一道积墨线，像墨汁在宣纸上洇开。

uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform vec4 ink_color : source_color = vec4(0.5, 0.02, 0.02, 1.0);
uniform float amount = 0.0;
uniform float pulse = 0.0;         // 心跳（0..1），由脚本驱动
uniform float aspect = 1.7778;

float gauss(float x) { return exp(-x * x); }

void fragment() {
	vec2 q = (UV - 0.5) * 2.0;                 // -1..1
	// 超椭圆距离：0 = 中心，1 = 屏幕边（四角圆润）
	float p = 5.0;
	float sd = pow(pow(abs(q.x), p) + pow(abs(q.y), p), 1.0 / p);
	float d = 1.0 - sd;                          // 距边（0 在边上）
	vec2 nuv = vec2(UV.x * aspect, UV.y);
	float n = texture(noise_tex, nuv * 0.45 + vec2(TIME * 0.005, -TIME * 0.003)).r;
	float n2 = texture(noise_tex, nuv * 1.6 + vec2(-TIME * 0.008, TIME * 0.01)).r;
	float fib = texture(noise_tex, nuv * 4.0).g;
	float reach = amount * (0.17 + 0.035 * pulse);
	// 墨的前沿：大尺度起伏（有的地方洇得深、有的浅）+ 细碎毛边（宣纸纤维吸墨）
	float front = reach * (0.35 + 1.3 * n) + (n2 - 0.5) * 0.05 * amount + (fib - 0.5) * 0.015 * amount;
	float inside = 1.0 - smoothstep(front - 0.02, front + 0.005, d);
	// 浓淡：边缘最浓，向前沿渐淡；前沿积墨
	float t = clamp(d / max(front, 0.001), 0.0, 1.0);
	float dens = mix(0.85, 0.28, smoothstep(0.0, 1.0, t)) * (0.75 + 0.35 * n2);
	float rim = gauss((d - front) / 0.01) * 0.3;
	// 前沿之外再淡淡晕开一层水渍
	float wash = (1.0 - smoothstep(front, front + 0.08, d)) * 0.12;
	float alpha = (inside * (dens + rim) + wash) * clamp(amount * 2.2, 0.0, 1.0);
	vec3 c = ink_color.rgb * (0.7 + 0.45 * n2) * (1.0 - rim);
	COLOR = vec4(c, clamp(alpha, 0.0, 0.72) * ink_color.a);
}
