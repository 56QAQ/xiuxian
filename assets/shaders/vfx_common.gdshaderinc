// 战斗特效公用函数（被 vfx_*.gdshader 引用）

// sRGB → 线性（顶点色/粒子色按 sRGB 书写）
vec3 vfx_lin(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(2.2));
}

// 镜头贴脸渐隐：镜头进入特效时不遮挡视线。depth 为视空间深度（-VERTEX.z）
float vfx_near_fade(float depth, float dist) {
	return smoothstep(dist * 0.35, dist, depth);
}

// 火焰色带：0 暗红 → 橙 → 黄 → 白
vec3 vfx_fire_ramp(float t) {
	t = clamp(t, 0.0, 1.0);
	vec3 c = mix(vec3(0.35, 0.02, 0.0), vec3(1.0, 0.28, 0.02), smoothstep(0.0, 0.35, t));
	c = mix(c, vec3(1.0, 0.72, 0.18), smoothstep(0.35, 0.7, t));
	c = mix(c, vec3(1.0, 0.97, 0.85), smoothstep(0.7, 1.0, t));
	return c;
}

// 绕 Z 旋转的 2D 旋转
vec2 vfx_rot(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

// 广告牌矩阵：保持模型缩放，面向镜头，并绕视线旋转 angle
mat4 vfx_billboard(mat4 model, mat4 inv_view, float angle) {
	vec3 sx = normalize(inv_view[0].xyz) * length(model[0].xyz);
	vec3 sy = normalize(inv_view[1].xyz) * length(model[1].xyz);
	vec3 sz = normalize(inv_view[2].xyz);
	float c = cos(angle);
	float s = sin(angle);
	vec3 rx = sx * c + sy * s;
	vec3 ry = -sx * s + sy * c;
	return mat4(vec4(rx, 0.0), vec4(ry, 0.0), vec4(sz, 0.0), model[3]);
}

// 沿模型 Y 轴（粒子速度方向）拉伸、另一轴朝向镜头的广告牌
mat4 vfx_stretch_billboard(mat4 model, vec3 cam_pos, float stretch) {
	vec3 pos = model[3].xyz;
	vec3 y = model[1].xyz;
	float sy = max(length(y), 1e-5);
	vec3 dir = y / sy;
	vec3 to_cam = normalize(cam_pos - pos);
	vec3 side = cross(dir, to_cam);
	float sl = length(side);
	side = sl > 1e-4 ? side / sl : normalize(cross(dir, vec3(0.0, 1.0, 0.1)));
	float sx = length(model[0].xyz);
	return mat4(vec4(side * sx, 0.0), vec4(dir * sy * stretch, 0.0), vec4(cross(side, dir), 0.0), vec4(pos, 1.0));
}
