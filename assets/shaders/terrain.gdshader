// 地形着色器：与 voxel.gdshader 约定一致（顶点色 = sRGB 反照率，alpha < 1 编码自发光强度 s：alpha = 1 - 0.5·s）。
// 额外：按世界坐标逐方块/逐“像素”扰动颜色、方块描边（合并后的大面仍显示 1 米方块格），
// 熔岩脉动发光；远景 LOD 在已加载近景区块的圆形范围内丢弃片元（hole_center / hole_radius）。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_lambert, specular_schlick_ggx;

uniform float block_size = 1.0;
uniform float variation = 0.07;       // 逐方块亮度扰动
uniform float texel_variation = 0.05; // 方块内 8×8 “像素”扰动
uniform float edge_strength = 0.16;   // 方块描边强度
uniform float detail_distance = 70.0; // 细节淡出距离
uniform float emission_gain = 3.2;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.93;
uniform vec2 hole_center = vec2(0.0);
uniform float hole_radius = 0.0;

varying vec3 world_pos;
varying vec3 world_nrm;

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + vec3(0.055)) / vec3(1.055), vec3(2.4)), c / vec3(12.92), lessThan(c, vec3(0.04045)));
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.71, 0.113, 0.419));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	if (hole_radius > 0.0 && distance(world_pos.xz, hole_center) < hole_radius) {
		discard;
	}
	vec3 n = world_nrm;
	vec3 p = world_pos / block_size;
	vec3 cell = floor(p - n * 0.5);
	vec3 c = srgb_to_linear(COLOR.rgb);
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	float near_k = 1.0 - smoothstep(detail_distance * 0.5, detail_distance, dist);
	// 逐方块扰动
	float hb = hash3(cell);
	c *= 1.0 + (hb - 0.5) * 2.0 * variation;
	// 方块面坐标
	vec3 f = fract(p);
	vec2 e;
	if (abs(n.y) > 0.5) {
		e = f.xz;
	} else if (abs(n.x) > 0.5) {
		e = f.zy;
	} else {
		e = f.xy;
	}
	// 方块内“像素”
	vec2 texel = floor(e * 8.0);
	float ht = hash3(cell * 1.37 + vec3(texel, dot(n, vec3(1.0, 2.0, 3.0))));
	c *= 1.0 + (ht - 0.5) * 2.0 * texel_variation * near_k;
	// 描边（按屏幕导数抗锯齿）
	vec2 d2 = min(e, 1.0 - e);
	float edge = min(d2.x, d2.y);
	float fw = fwidth(edge) * 1.5 + 0.0001;
	float line = 1.0 - smoothstep(0.03, 0.03 + fw * 1.5 + 0.02, edge);
	float line_k = 1.0 - smoothstep(detail_distance * 0.8, detail_distance * 1.6, dist);
	c *= 1.0 - line * edge_strength * line_k;
	ALBEDO = c;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.25;
	float glow = clamp((1.0 - COLOR.a) * 2.0, 0.0, 1.0);
	if (glow > 0.0) {
		float pulse = 0.75 + 0.25 * sin(TIME * 1.3 + hb * 6.2831 + world_pos.x * 0.15);
		float flow = 0.85 + 0.3 * hash3(floor(world_pos * 2.0) + vec3(floor(TIME * 1.5)));
		EMISSION = c * glow * emission_gain * pulse * mix(1.0, flow, near_k);
	}
}
