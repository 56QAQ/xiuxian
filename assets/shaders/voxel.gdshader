// 体素通用着色器：顶点色为 sRGB 反照率，顶点 alpha 编码自发光强度（alpha = 1 - 0.5·s）。
// instance uniform 用于每个实例的受击闪白、溶解与色调，无需复制材质。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform float emission_gain = 4.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.82;

instance uniform float flash = 0.0;          // 受击闪白 0~1
instance uniform vec4 flash_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform float dissolve = 0.0;       // 死亡/碎屑消散 0~1
instance uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0); // rgb 色调，a 为混合量

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
	local_pos = VERTEX;
}

void fragment() {
	if (dissolve > 0.0) {
		float h = hash(floor(local_pos * 30.0));
		if (h < dissolve) {
			discard;
		}
	}
	vec3 c = srgb_to_linear(COLOR.rgb);
	c = mix(c, c * srgb_to_linear(tint.rgb), tint.a);
	float glow = clamp((1.0 - COLOR.a) * 2.0, 0.0, 1.0);
	ALBEDO = mix(c, srgb_to_linear(flash_color.rgb), flash * 0.8);
	ROUGHNESS = roughness_value;
	SPECULAR = 0.3;
	EMISSION = c * glow * emission_gain + srgb_to_linear(flash_color.rgb) * flash * 0.6;
}
