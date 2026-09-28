// 碎块（MultiMesh）：实例颜色（sRGB）乘顶点色，INSTANCE_CUSTOM.x 为溶解进度 0~1。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

varying float v_dissolve;
varying vec3 local_pos;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92), lessThan(c, vec3(0.04045)));
}

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	v_dissolve = INSTANCE_CUSTOM.x;
	local_pos = VERTEX;
}

void fragment() {
	if (v_dissolve > 0.0 && hash(floor(local_pos * 6.0)) < v_dissolve) {
		discard;
	}
	vec3 c = srgb_to_linear(COLOR.rgb);
	float glow = clamp((1.0 - COLOR.a) * 2.0, 0.0, 1.0);
	ALBEDO = c;
	ROUGHNESS = 0.85;
	SPECULAR = 0.3;
	EMISSION = c * glow * 3.0;
}
