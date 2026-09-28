// 体素云：顶点色 × 昼夜色调（tint），柔和受光，不投影。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_disabled;

uniform vec3 tint : source_color = vec3(1.0);

void fragment() {
	ALBEDO = COLOR.rgb * COLOR.rgb * tint;
	ROUGHNESS = 1.0;
	BACKLIGHT = vec3(0.35) * tint;
}
