// 静态体素着色器：与 voxel.gdshader 外观一致（顶点色 = sRGB 反照率，alpha < 1 编码自发光强度），
// 但不使用 instance uniform——用于建筑、植被、云、未受击的可破坏物等大量实例，
// 避免占用全局实例参数缓冲（兼容渲染器下每个实例占 16 个槽位，总计仅 4096）。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform float emission_gain = 4.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.82;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92), lessThan(c, vec3(0.04045)));
}

void fragment() {
	vec3 c = srgb_to_linear(COLOR.rgb);
	float glow = clamp((1.0 - COLOR.a) * 2.0, 0.0, 1.0);
	ALBEDO = c;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.3;
	EMISSION = c * glow * emission_gain;
}
