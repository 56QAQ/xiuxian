// 秘境传送门：旋涡状自发光平面（加色混合），颜色为材质参数（每个传送门一个材质）。
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 portal_color : source_color = vec4(0.35, 0.9, 1.0, 1.0);
uniform vec4 portal_color2 : source_color = vec4(0.7, 0.35, 1.0, 1.0);
uniform float intensity = 2.4;

float hash2(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), u.x), mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y *= 1.1;
	float r = length(p);
	float a = atan(p.y, p.x);
	float t = TIME;
	// 旋涡：角度随半径扭转
	float swirl = a + r * 5.0 - t * 1.6;
	float arms = 0.5 + 0.5 * sin(swirl * 3.0);
	float n = vnoise(vec2(swirl * 1.5, r * 6.0 - t * 2.0));
	float core = exp(-r * r * 5.0);
	float ring = smoothstep(1.0, 0.82, r) * smoothstep(0.55, 0.95, r);
	float body = smoothstep(1.0, 0.6, r) * (0.35 + 0.65 * arms * n);
	vec3 c = mix(portal_color2.rgb, portal_color.rgb, clamp(arms * 0.7 + core, 0.0, 1.0));
	float v = body + core * 1.6 + ring * 0.8;
	// 星点
	float sp = step(0.985, hash2(floor(vec2(swirl * 8.0, r * 20.0))));
	v += sp * smoothstep(1.0, 0.3, r) * 1.5;
	float edge = smoothstep(1.02, 0.9, r);
	ALBEDO = c * v * intensity * edge;
}
