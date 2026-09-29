// 角色/兵器/妖兽体素着色器（VoxMesh 生成的网格共用）。
// 顶点色 rgb = sRGB 反照率（已乘 AO）；alpha = 属性字节 / 255：高 4 位材质，低 4 位发光等级（0~15）。
// 材质：0 布 1 皮肤 2 头发 3 金饰 4 钢银 5 宝石 6 皮革 7 毛皮 8 眼睛 9 石 10 鳞角 11 丝绸 12 玉 13 火焰
// 自定义光照：包裹漫反射（皮肤带暖色次表面）、GGX 高光（金属着色 F0）、头发各向异性光泽、宝石闪光；
// 另加视角菲涅尔边缘光，让角色在任何背景下都轮廓清晰。
// instance uniform（战斗用）：flash / flash_color / dissolve / tint，与 voxel.gdshader 相同（兼容渲染器下为普通 uniform）。
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;

uniform float emission_gain = 4.0;
uniform float rim_strength : hint_range(0.0, 2.0) = 0.55;
uniform vec3 rim_color : source_color = vec3(1.0, 0.96, 0.9);
uniform float spec_gain : hint_range(0.0, 3.0) = 1.0;
uniform float voxel_density = 80.0;   // 每米体素数（溶解颗粒）

#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
// 兼容渲染器的实例参数槽位受硬件 UBO 限制（全场景约 256 个实例），角色部件一多就会溢出；
// 这里改为普通 uniform，由 CharacterRig 在首次受击/消散时为该角色复制一份材质承载。
uniform float flash = 0.0;
uniform vec4 flash_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float dissolve = 0.0;
uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0);
#else
instance uniform float flash = 0.0;          // 受击闪白 0~1
instance uniform vec4 flash_color = vec4(1.0, 1.0, 1.0, 1.0);
instance uniform float dissolve = 0.0;       // 死亡消散 0~1
instance uniform vec4 tint = vec4(1.0, 1.0, 1.0, 0.0); // rgb 色调，a 为混合量
#endif

varying vec3 local_pos;
varying vec4 v_mat;     // x 粗糙度 y 金属度 z 高光强度 w 包裹光
varying vec4 v_fx;      // x 边缘光 y 头发光泽 z 自发光（材质） w 次表面（皮肤）
varying float v_glow;   // 发光等级 0~1
varying vec3 v_tan;     // 发丝方向（视空间）

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
	float attr = floor(COLOR.a * 255.0 + 0.5);
	float m = floor(attr / 16.0);
	v_glow = (attr - m * 16.0) / 15.0;
	// 默认：布
	vec4 a = vec4(0.86, 0.0, 0.35, 0.3);
	vec4 f = vec4(0.3, 0.0, 0.0, 0.0);
	if (m < 0.5) {
	} else if (m < 1.5) {        // 皮肤
		a = vec4(0.58, 0.0, 0.32, 0.55); f = vec4(0.42, 0.0, 0.0, 1.0);
	} else if (m < 2.5) {        // 头发
		a = vec4(0.5, 0.0, 0.3, 0.3); f = vec4(0.4, 1.0, 0.0, 0.0);
	} else if (m < 3.5) {        // 金饰（金属度适中：没有环境反射时也保持金黄）
		a = vec4(0.3, 0.42, 1.25, 0.05); f = vec4(0.45, 0.0, 0.05, 0.0);
	} else if (m < 4.5) {        // 钢银
		a = vec4(0.2, 0.9, 1.0, 0.0); f = vec4(0.55, 0.0, 0.03, 0.0);
	} else if (m < 5.5) {        // 宝石
		a = vec4(0.06, 0.25, 1.6, 0.25); f = vec4(0.6, 0.0, 0.3, 0.0);
	} else if (m < 6.5) {        // 皮革
		a = vec4(0.52, 0.0, 0.5, 0.12); f = vec4(0.3, 0.0, 0.0, 0.0);
	} else if (m < 7.5) {        // 毛皮
		a = vec4(0.9, 0.0, 0.22, 0.45); f = vec4(0.65, 0.35, 0.0, 0.0);
	} else if (m < 8.5) {        // 眼睛
		a = vec4(0.12, 0.0, 0.9, 0.6); f = vec4(0.1, 0.0, 0.16, 0.0);
	} else if (m < 9.5) {        // 石
		a = vec4(0.95, 0.0, 0.2, 0.1); f = vec4(0.22, 0.0, 0.0, 0.0);
	} else if (m < 10.5) {       // 鳞角
		a = vec4(0.32, 0.05, 0.7, 0.2); f = vec4(0.45, 0.0, 0.0, 0.0);
	} else if (m < 11.5) {       // 丝绸
		a = vec4(0.46, 0.0, 0.5, 0.35); f = vec4(0.45, 0.45, 0.0, 0.0);
	} else if (m < 12.5) {       // 玉
		a = vec4(0.18, 0.0, 0.8, 0.6); f = vec4(0.5, 0.0, 0.1, 0.4);
	} else {                     // 火焰/光效
		a = vec4(0.9, 0.0, 0.0, 1.0); f = vec4(0.0, 0.0, 1.0, 0.0);
	}
	v_mat = a;
	v_fx = f;
	// 发丝方向：侧面沿模型 Y，顶/底面沿模型 Z
	vec3 t = abs(NORMAL.y) > 0.5 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
	v_tan = normalize((MODELVIEW_MATRIX * vec4(t, 0.0)).xyz);
}

void fragment() {
	if (dissolve > 0.0) {
		float h = hash(floor(local_pos * voxel_density * 0.5));
		if (h < dissolve) {
			discard;
		}
	}
	vec3 c = srgb_to_linear(COLOR.rgb);
	c = mix(c, c * srgb_to_linear(tint.rgb), tint.a);
	vec3 fc = srgb_to_linear(flash_color.rgb);
	// 金饰：略提亮（弥补金属度带来的漫反射损失）
	if (v_mat.y > 0.3 && v_mat.y < 0.6) {
		c *= 1.12;
	}
	ALBEDO = mix(c, fc, flash * 0.8);
	ROUGHNESS = v_mat.x;
	METALLIC = v_mat.y;
	SPECULAR = clamp(0.5 * v_mat.z, 0.0, 1.0);
	float glow = max(v_glow, v_fx.z);
	// 菲涅尔边缘光（与光源无关，保证轮廓）
	float ndv = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - ndv, 3.0);
	vec3 rim = rim_color * mix(vec3(1.0), c * 2.2 + 0.1, 0.45) * fres * rim_strength * v_fx.x * 0.35;
	EMISSION = c * glow * emission_gain + rim + fc * flash * 0.6;
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float cndl = clamp(ndl, 0.0, 1.0);
	float ndv = clamp(dot(NORMAL, VIEW), 0.001, 1.0);
	// 包裹漫反射；皮肤在明暗交界处偏暖红（次表面散射的近似）
	float w = v_mat.w;
	float diff = clamp((ndl + w) / (1.0 + w), 0.0, 1.0);
	vec3 sss = vec3(1.0);
	if (v_fx.w > 0.0) {
		float term = clamp(1.0 - abs(ndl) * 1.6, 0.0, 1.0) * v_fx.w;
		sss = mix(vec3(1.0), vec3(1.25, 0.72, 0.62), term * 0.55);
	}
	DIFFUSE_LIGHT += diff * sss * ATTENUATION * LIGHT_COLOR / PI;
	// GGX 高光
	vec3 H = normalize(LIGHT + VIEW);
	float ndh = clamp(dot(NORMAL, H), 0.0, 1.0);
	float ldh = clamp(dot(LIGHT, H), 0.0, 1.0);
	float r = max(v_mat.x, 0.05);
	float a = r * r;
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float D = a2 / (PI * dd * dd);
	float V = 0.5 / (cndl * (ndv * (1.0 - a) + a) + ndv * (cndl * (1.0 - a) + a) + 1e-4);
	vec3 f0 = mix(vec3(0.04 * v_mat.z), ALBEDO, v_mat.y);
	vec3 F = f0 + (vec3(1.0) - f0) * pow(1.0 - ldh, 5.0);
	vec3 spec = D * V * F * cndl * v_mat.z;
	// 头发/毛皮/丝绸：各向异性光泽带（Kajiya-Kay × 法线朝向，体素平面上只在朝光面出现细窄光泽）
	if (v_fx.y > 0.0) {
		float th = dot(normalize(v_tan), H);
		float sn = sqrt(max(1.0 - th * th, 0.0));
		float band = pow(sn, 96.0) * pow(ndh, 6.0);
		spec += band * v_fx.y * 0.35 * mix(ALBEDO * 3.0, vec3(1.0), 0.3) * cndl;
	}
	// 背光边缘（光在身后时勾出亮边）
	float back = pow(1.0 - ndv, 4.0) * clamp(dot(-VIEW, LIGHT) + 0.2, 0.0, 1.0) * clamp(ndl + 0.5, 0.0, 1.0);
	spec += back * v_fx.x * 0.35 * mix(vec3(1.0), ALBEDO, 0.4);
	SPECULAR_LIGHT += spec * spec_gain * ATTENUATION * LIGHT_COLOR * SPECULAR_AMOUNT;
}
