class_name VfxLib
## 特效资源库：贴图、着色器、共享材质、程序网格与五行配色。
## 全部按需创建并缓存在 FX._mats 中（测试退出时统一清理）。
## 材质之间共享，单个特效的颜色/透明度/进度通过 instance uniform（tint、fade、prog ...）控制。

const TEX_DIR := "res://assets/textures/vfx/"
const SHADER_DIR := "res://assets/shaders/"

## 五行特效配色：main 主色，core 高光核心，dark 暗部/烟尘，glyph 法阵中心字序号
const PALETTE := {
	"metal": {"main": Color(1.0, 0.84, 0.46), "core": Color(1.0, 0.98, 0.88), "dark": Color(0.5, 0.42, 0.22), "glyph": 0, "slash": 0},
	"wood": {"main": Color(0.4, 0.95, 0.42), "core": Color(0.86, 1.0, 0.72), "dark": Color(0.12, 0.3, 0.1), "glyph": 1, "slash": 3},
	"water": {"main": Color(0.34, 0.72, 1.0), "core": Color(0.86, 0.97, 1.0), "dark": Color(0.14, 0.26, 0.45), "glyph": 2, "slash": 1},
	"fire": {"main": Color(1.0, 0.46, 0.12), "core": Color(1.0, 0.9, 0.62), "dark": Color(0.18, 0.1, 0.07), "glyph": 3, "slash": 2},
	"earth": {"main": Color(0.95, 0.7, 0.34), "core": Color(1.0, 0.93, 0.72), "dark": Color(0.42, 0.32, 0.2), "glyph": 4, "slash": 4},
	"none": {"main": Color(0.6, 0.84, 1.0), "core": Color(0.93, 0.97, 1.0), "dark": Color(0.25, 0.32, 0.45), "glyph": 5, "slash": 0},
	"thunder": {"main": Color(0.74, 0.64, 1.0), "core": Color(0.96, 0.94, 1.0), "dark": Color(0.2, 0.15, 0.35), "glyph": 6, "slash": 0},
}

## 少数无属性法诀的专属色（如血神刀芒）
const SPELL_COLORS := {
	"blood_blade": Color(1.0, 0.16, 0.2),
}


static func _cache() -> Dictionary:
	return FX._mats


static func is_elem(e: String) -> bool:
	return PALETTE.has(e)


static func pal(e: String) -> Dictionary:
	return PALETTE.get(e, PALETTE["none"])


static func main_color(e: String) -> Color:
	return pal(e)["main"]


static func core_color(e: String) -> Color:
	return pal(e)["core"]


## 由颜色推断最接近的五行（兼容旧接口只传颜色的调用）
static func elem_of_color(c: Color) -> String:
	var best := "none"
	var bd := 99.0
	for e in Elem.COLORS:
		var k: Color = Elem.COLORS[e]
		var d := Vector3(c.r - k.r, c.g - k.g, c.b - k.b).length()
		if d < bd:
			bd = d
			best = e
	return best if bd < 0.3 else "none"


## 法诀的特效元素（雷系法诀单独归为 thunder）
static func spell_elem(def: Dictionary) -> String:
	var e := str(def.get("element", Elem.NONE))
	var st: Dictionary = def.get("status", {})
	if str(st.get("id", "")) == "shock":
		return "thunder"
	return e if PALETTE.has(e) else "none"


static func spell_color(def: Dictionary) -> Color:
	var id := str(def.get("id", ""))
	if SPELL_COLORS.has(id):
		return SPELL_COLORS[id]
	return main_color(spell_elem(def))


## Compatibility 渲染器 / 无头模式（没有 RenderingDevice）时使用精简特效
static func is_lite() -> bool:
	var k := "lite"
	var c := _cache()
	if not c.has(k):
		c[k] = RenderingServer.get_rendering_device() == null
	return c[k]


# ================================================================ 资源

static func tex(name: String) -> Texture2D:
	var k := "tex:" + name
	var c := _cache()
	if not c.has(k):
		c[k] = load(TEX_DIR + name + ".png")
	return c[k]


static func shader(name: String) -> Shader:
	var k := "sh:" + name
	var c := _cache()
	if not c.has(k):
		c[k] = load(SHADER_DIR + "vfx_" + name + ".gdshader")
	return c[k]


static func _make(key: String, shader_name: String, params: Dictionary) -> ShaderMaterial:
	var c := _cache()
	if c.has(key):
		return c[key]
	var m := ShaderMaterial.new()
	m.shader = shader(shader_name)
	for p in params:
		var v = params[p]
		if v is String and str(v).begins_with("tex:"):
			v = tex(str(v).substr(4))
		m.set_shader_parameter(p, v)
	c[key] = m
	return m


## 粒子/精灵材质预设
const PARTICLE_MATS := {
	"glow": {"tex": "tex:glow", "core_white": 0.5, "additive": 0.75},
	"glow_soft": {"tex": "tex:glow", "intensity": 0.8, "additive": 0.8},
	"spark": {"tex": "tex:spark", "mode": 1, "stretch": 7.0, "core_white": 0.7, "intensity": 2.2, "additive": 0.9},
	"streak": {"tex": "tex:spark", "mode": 1, "stretch": 12.0, "core_white": 0.5, "intensity": 1.6, "additive": 0.85},
	"flare": {"tex": "tex:flare", "core_white": 0.8, "intensity": 1.8, "near_fade": 2.5, "additive": 0.9},
	"mote": {"tex": "tex:mote", "core_white": 0.6, "intensity": 1.8, "additive": 0.8},
	"flame": {"tex": "tex:flame", "hframes": 4, "vframes": 4, "color_mode": 1, "intensity": 1.7, "additive": 0.5},
	"smoke": {"tex": "tex:smoke", "hframes": 2, "vframes": 2, "loop_frames": false, "color_mode": 3, "additive": 0.0, "intensity": 1.0, "near_fade": 2.0},
	"leaf": {"tex": "tex:leaf", "hframes": 2, "vframes": 1, "loop_frames": false, "color_mode": 3, "additive": 0.0, "intensity": 1.0},
	"shard": {"tex": "tex:shard", "color_mode": 3, "additive": 0.45, "intensity": 1.5},
	"paper": {"tex": "tex:talisman", "color_mode": 2, "additive": 0.0, "intensity": 1.0},
	"drop": {"tex": "tex:spark", "mode": 1, "stretch": 3.0, "additive": 0.0, "intensity": 1.0},
	"flat_glow": {"tex": "tex:glow", "mode": 2, "intensity": 1.2, "additive": 0.7},
}


static func particle_mat(name: String) -> ShaderMaterial:
	var key := "pm:" + name
	var c := _cache()
	if c.has(key):
		return c[key]
	var params: Dictionary = PARTICLE_MATS.get(name, PARTICLE_MATS["glow"])
	return _make(key, "particle", params)


static func ribbon_mat(profile: String) -> ShaderMaterial:
	match profile:
		"blade":
			return _make("rb:blade", "ribbon", {"streak_tex": "tex:ribbon", "profile": 1, "intensity": 2.0, "core_power": 1.2, "streak_amount": 0.5, "scroll": 0.5})
		"bolt":
			return _make("rb:bolt", "ribbon", {"streak_tex": "tex:ribbon", "profile": 2, "intensity": 2.6, "core_power": 1.6, "streak_amount": 0.0})
		"fire":
			return _make("rb:fire", "ribbon", {"streak_tex": "tex:ribbon", "profile": 0, "intensity": 1.6, "streak_amount": 0.9, "scroll": 3.0, "fire": 1})
		"wake":
			return _make("rb:wake", "ribbon", {"streak_tex": "tex:ribbon", "profile": 0, "intensity": 1.1, "core_power": 0.25, "streak_amount": 0.9, "scroll": 2.5, "near_fade": 3.2, "occlude": 0.2})
		_:
			return _make("rb:center", "ribbon", {"streak_tex": "tex:ribbon", "profile": 0, "intensity": 1.7, "streak_amount": 0.6, "scroll": 2.0})


static func slash_mat(style: int) -> ShaderMaterial:
	return _make("slash:%d" % style, "slash", {"noise_tex": "tex:noise", "style": style})


static func ring_mat(style: int = 0) -> ShaderMaterial:
	return _make("ring:%d" % style, "ring", {"noise_tex": "tex:noise", "style": style})


static func circle_mat() -> ShaderMaterial:
	return _make("circle", "circle", {"circle_tex": "tex:circle", "glyph_tex": "tex:glyphs"})


static func beam_mat(style: int) -> ShaderMaterial:
	return _make("beam:%d" % style, "beam", {"noise_tex": "tex:noise", "streak_tex": "tex:ribbon", "style": style,
		"core_width": 0.12 if style == 3 else 0.2})


static func energy_mat(style: int) -> ShaderMaterial:
	return _make("energy:%d" % style, "energy", {"noise_tex": "tex:noise", "style": style})


static func ice_mat() -> ShaderMaterial:
	return _make("ice", "ice", {"noise_tex": "tex:noise"})


static func decal_mat(kind: String) -> ShaderMaterial:
	var k := {"crack": 0, "scorch": 1, "frost": 2}.get(kind, 0) as int
	var t := {"crack": "tex:crack", "scorch": "tex:scorch", "frost": "tex:frost"}.get(kind, "tex:crack") as String
	return _make("decal:" + kind, "decal", {"tex": t, "kind": k})


static func field_mat(style: int) -> ShaderMaterial:
	return _make("field:%d" % style, "field", {"noise_tex": "tex:noise", "detail_tex": "tex:frost", "style": style})


static func ghost_mat() -> ShaderMaterial:
	return _make("ghost", "ghost", {})


## 热浪扭曲（读取屏幕纹理，仅 Forward+ 使用）
static func distort_mat() -> ShaderMaterial:
	var m := _make("distort", "distort", {"noise_tex": "tex:noise"})
	# 先于其他透明特效绘制：屏幕纹理只含不透明物体，避免把身后的光效“抹掉”
	m.render_priority = -20
	return m


## 护盾材质：每个护盾独立（受击涟漪 uniform 数组）
static func new_shield_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = shader("shield")
	m.set_shader_parameter("hex_tex", tex("hex"))
	m.set_shader_parameter("noise_tex", tex("noise"))
	var hits: Array[Vector4] = []
	for i in 4:
		hits.append(Vector4(0, 1, 0, -1))
	m.set_shader_parameter("hits", hits)
	return m


## 碎石/碎块（受光照，使用粒子颜色）
static func debris_mat() -> StandardMaterial3D:
	var c := _cache()
	if c.has("debris"):
		return c["debris"]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.9
	c["debris"] = m
	return m


# ================================================================ 网格

static func quad() -> QuadMesh:
	var c := _cache()
	if not c.has("m:quad"):
		var q := QuadMesh.new()
		q.size = Vector2.ONE
		c["m:quad"] = q
	return c["m:quad"]


## 竖长四边形（符纸）
static func quad_tall() -> QuadMesh:
	var c := _cache()
	if not c.has("m:quad_tall"):
		var q := QuadMesh.new()
		q.size = Vector2(0.5, 1.0)
		c["m:quad_tall"] = q
	return c["m:quad_tall"]


## 水平地面四边形（XZ 平面，边长 1）
static func plane() -> PlaneMesh:
	var c := _cache()
	if not c.has("m:plane"):
		var p := PlaneMesh.new()
		p.size = Vector2.ONE
		c["m:plane"] = p
	return c["m:plane"]


static func cube() -> BoxMesh:
	var c := _cache()
	if not c.has("m:cube"):
		var b := BoxMesh.new()
		b.size = Vector3.ONE
		c["m:cube"] = b
	return c["m:cube"]


## 光束条带：x ∈ [-0.5, 0.5]，z ∈ [-1, 0]（着色器中绕轴朝向镜头）
static func beam_strip() -> ArrayMesh:
	var c := _cache()
	if c.has("m:beam"):
		return c["m:beam"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 8
	for i in segs:
		var z0 := -float(i) / segs
		var z1 := -float(i + 1) / segs
		var v0 := float(i) / segs
		var v1 := float(i + 1) / segs
		var quad_v := [Vector3(-0.5, 0, z0), Vector3(0.5, 0, z0), Vector3(0.5, 0, z1), Vector3(-0.5, 0, z1)]
		var quad_uv := [Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(quad_uv[idx])
			st.add_vertex(quad_v[idx])
	var m := st.commit()
	m.custom_aabb = AABB(Vector3(-0.6, -0.6, -1.05), Vector3(1.2, 1.2, 1.1))
	c["m:beam"] = m
	return m


## 飞行剑气月牙（XZ 平面，凸向 -Z；UV.x 沿弧，UV.y 横向 0 内 → 1 外）
static func crescent() -> ArrayMesh:
	var c := _cache()
	if c.has("m:crescent"):
		return c["m:crescent"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 20
	var span := deg_to_rad(75.0)
	var rows: Array = []
	for i in n + 1:
		var u := float(i) / n
		var a := lerpf(-span, span, u)
		var outer := Vector3(sin(a), 0, -cos(a) + 0.55)
		var inner := Vector3(sin(a) * 0.62, 0, (-cos(a) + 0.55) * 0.62 + 0.12)
		rows.append([inner, outer, u])
	for i in n:
		var a0: Array = rows[i]
		var a1: Array = rows[i + 1]
		var quad_v := [a0[0], a0[1], a1[1], a1[0]]
		var quad_uv := [Vector2(a0[2], 0), Vector2(a0[2], 1), Vector2(a1[2], 1), Vector2(a1[2], 0)]
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_uv(quad_uv[idx])
			st.add_vertex(quad_v[idx])
	var m := st.commit()
	c["m:crescent"] = m
	return m


## 六棱双锥（冰锥、金针、木刺）：长 1，沿 -Z，尖端在 -Z
static func spike() -> ArrayMesh:
	var c := _cache()
	if c.has("m:spike"):
		return c["m:spike"]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tip := Vector3(0, 0, -0.75)
	var back := Vector3(0, 0, 0.25)
	var ring: Array[Vector3] = []
	for i in 6:
		var a := TAU * i / 6.0
		ring.append(Vector3(cos(a) * 0.14, sin(a) * 0.14, 0.0))
	for i in 6:
		var a := ring[i]
		var b := ring[(i + 1) % 6]
		for tri in [[tip, a, b], [back, a, b]]:
			var v0: Vector3 = tri[0]
			var v1: Vector3 = tri[1]
			var v2: Vector3 = tri[2]
			var center := (v0 + v1 + v2) / 3.0
			var outward := ((v1 - v0).cross(v2 - v0)).normalized()
			if outward.dot(Vector3(center.x, center.y, 0.0)) < 0.0:
				outward = -outward
			# Godot 以顺时针为正面：保证 (v1-v0)×(v2-v0) 指向内侧
			if (v1 - v0).cross(v2 - v0).dot(outward) > 0.0:
				var tmp := v1
				v1 = v2
				v2 = tmp
			for v in [v0, v1, v2]:
				st.set_normal(outward)
				st.set_uv(Vector2(float(i) / 6.0, (v as Vector3).z + 0.75))
				st.add_vertex(v)
	var m := st.commit()
	c["m:spike"] = m
	return m


## 开口圆柱（光柱、水柱），高 1，底面在 y=0
static func tube() -> CylinderMesh:
	var c := _cache()
	if not c.has("m:tube"):
		var cm := CylinderMesh.new()
		cm.top_radius = 1.0
		cm.bottom_radius = 1.0
		cm.height = 1.0
		cm.radial_segments = 24
		cm.rings = 4
		cm.cap_top = false
		cm.cap_bottom = false
		c["m:tube"] = cm
	return c["m:tube"]


static func cone_tube() -> CylinderMesh:
	var c := _cache()
	if not c.has("m:cone_tube"):
		var cm := CylinderMesh.new()
		cm.top_radius = 0.35
		cm.bottom_radius = 1.0
		cm.height = 1.0
		cm.radial_segments = 24
		cm.rings = 4
		cm.cap_top = false
		cm.cap_bottom = false
		c["m:cone_tube"] = cm
	return c["m:cone_tube"]


static func sphere() -> SphereMesh:
	var c := _cache()
	if not c.has("m:sphere"):
		var s := SphereMesh.new()
		s.radius = 1.0
		s.height = 2.0
		s.radial_segments = 32
		s.rings = 16
		c["m:sphere"] = s
	return c["m:sphere"]


static func torus() -> TorusMesh:
	var c := _cache()
	if not c.has("m:torus"):
		var t := TorusMesh.new()
		t.inner_radius = 0.86
		t.outer_radius = 1.0
		t.rings = 32
		t.ring_segments = 8
		c["m:torus"] = t
	return c["m:torus"]


## 体素碎岩（variant 0..3），molten=true 时带熔岩发光裂缝
static func rock(variant: int, molten: bool = false) -> ArrayMesh:
	var key := "m:rock%d%s" % [variant, "m" if molten else ""]
	var c := _cache()
	if c.has(key):
		return c[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = 900 + variant
	var g := VoxelGrid.new(6, 5, 6)
	var base := [Color(0.46, 0.4, 0.34), Color(0.52, 0.44, 0.34), Color(0.4, 0.36, 0.33), Color(0.5, 0.42, 0.3)][variant % 4] as Color
	if molten:
		base = Color(0.26, 0.2, 0.18)
	g.fill_ellipsoid(Vector3(2.5, 2.0, 2.5), Vector3(2.9, 2.4, 2.9), base)
	for i in 10:
		g.clear_voxel(rng.randi_range(0, 5), rng.randi_range(0, 4), rng.randi_range(0, 5))
	for z in 6:
		for y in 5:
			for x in 6:
				if g.is_solid(x, y, z):
					var shade := 0.85 + rng.randf() * 0.3
					var col := Color(base.r * shade, base.g * shade, base.b * shade)
					if molten and rng.randf() < 0.24:
						col = VoxelGrid.glow(Color(1.0, 0.3 + rng.randf() * 0.18, 0.04), 0.45)
					g.set_color(x, y, z, col)
	var m := VoxelMesher.build(g, 1.0 / 5.0, Vector3(-0.6, -0.5, -0.6))
	c[key] = m
	return m


## 体素叶片（飞叶摘花）
static func leaf_mesh() -> ArrayMesh:
	var c := _cache()
	if c.has("m:leaf"):
		return c["m:leaf"]
	var g := VoxelGrid.new(7, 1, 12)
	for z in 12:
		var v := float(z) / 11.0
		var w := sin(PI * v) * 3.2 * (1.0 - 0.25 * v)
		for x in 7:
			if absf(x - 3.0) <= w:
				var mid := absf(x - 3.0) < 0.5
				var col := Color(0.55, 1.0, 0.45) if mid else Color(0.25, 0.8, 0.3).lerp(Color(0.5, 0.95, 0.35), v)
				g.set_color(x, 0, z, VoxelGrid.glow(col, 0.55 if mid else 0.3))
	var m := VoxelMesher.build(g, 0.045, Vector3(-3.5, -0.5, -6.0) * 0.045)
	c["m:leaf"] = m
	return m


## 体素火鸦
static func crow_mesh() -> ArrayMesh:
	var c := _cache()
	if c.has("m:crow"):
		return c["m:crow"]
	var g := VoxelGrid.new(13, 3, 9)
	var hot := VoxelGrid.glow(Color(1.0, 0.75, 0.25), 1.0)
	var mid := VoxelGrid.glow(Color(1.0, 0.42, 0.1), 0.9)
	var dark := VoxelGrid.glow(Color(0.8, 0.18, 0.05), 0.7)
	# 身体（沿 -Z 为前）
	g.fill_box(Vector3i(5, 0, 2), Vector3i(7, 2, 6), mid)
	g.fill_box(Vector3i(5, 1, 0), Vector3i(7, 2, 2), hot)   # 头
	g.set_color(6, 1, 0, VoxelGrid.glow(Color(1, 1, 0.8), 1.0))
	# 翅膀（展开，末端上翘）
	for i in 5:
		g.fill_box(Vector3i(4 - i, 1 + (1 if i >= 3 else 0), 3), Vector3i(4 - i, 1 + (1 if i >= 3 else 0), 5 - (1 if i >= 2 else 0)), dark if i >= 3 else mid)
		g.fill_box(Vector3i(8 + i, 1 + (1 if i >= 3 else 0), 3), Vector3i(8 + i, 1 + (1 if i >= 3 else 0), 5 - (1 if i >= 2 else 0)), dark if i >= 3 else mid)
	# 尾羽
	g.fill_box(Vector3i(5, 1, 7), Vector3i(7, 1, 8), dark)
	var m := VoxelMesher.build(g, 0.07, Vector3(-6.5, -1.5, -4.5) * 0.07)
	c["m:crow"] = m
	return m


## 贴合地面的网格（圆盘/方形，n×n 顶点），用于地面贴花、领域、预警法阵。
## 顶点高度通过向下射线取得；uv_rot 旋转贴图。返回网格的局部原点位于 center。
static func ground_mesh(center: Vector3, radius: float, n: int = 9, uv_rot: float = 0.0, lift: float = 0.06) -> ArrayMesh:
	var heights := PackedFloat32Array()
	heights.resize(n * n)
	var flat := true
	var first := 0.0
	for j in n:
		for i in n:
			var lx := (float(i) / (n - 1) * 2.0 - 1.0) * radius
			var lz := (float(j) / (n - 1) * 2.0 - 1.0) * radius
			var p := center + Vector3(lx, 0, lz)
			var h := 0.0
			var hit := CombatUtil.ray_world(p + Vector3.UP * 3.0, p + Vector3.DOWN * 4.0)
			if not hit.is_empty():
				h = (hit["position"] as Vector3).y - center.y
			heights[j * n + i] = h
			if i == 0 and j == 0:
				first = h
			elif absf(h - first) > 0.03:
				flat = false
	if flat:
		n = 2
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cr := cos(uv_rot)
	var sr := sin(uv_rot)
	var verts: Array[Vector3] = []
	var uvs: Array[Vector2] = []
	var src_n := int(sqrt(heights.size()))
	for j in n:
		for i in n:
			var fx := float(i) / (n - 1)
			var fz := float(j) / (n - 1)
			var h := first
			if not flat:
				h = heights[j * src_n + i]
			verts.append(Vector3((fx * 2.0 - 1.0) * radius, h + lift, (fz * 2.0 - 1.0) * radius))
			var u := fx - 0.5
			var v := fz - 0.5
			uvs.append(Vector2(u * cr - v * sr + 0.5, u * sr + v * cr + 0.5))
	for j in n - 1:
		for i in n - 1:
			var a := j * n + i
			for idx in [a, a + 1, a + n + 1, a, a + n + 1, a + n]:
				st.set_uv(uvs[idx])
				st.set_normal(Vector3.UP)
				st.add_vertex(verts[idx])
	return st.commit()
