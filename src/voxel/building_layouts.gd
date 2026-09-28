class_name BuildingLayouts
## 各 POI 的建筑群布局：五宗山门、青云坊市、洞府、秘境入口、地标遗迹。
## 局部坐标：x 右、z 后，正面（入口）朝 -Z，节点 rotation.y = poi.yaw，原点在平台中心、y=平台高度。
## 标记点（Marker3D）名称固定，加入 group "poi_marker"，meta: poi_id、sect_id（宗门）、realm_id（秘境）。
## marker_layout() 给出不建模也能取得的标记点局部位置/朝向（供 WorldMap 在区块加载前使用）。

const F_N := 0.0          ## 面朝 -Z
const F_S := PI           ## 面朝 +Z
const F_W := PI * 0.5     ## 面朝 -X
const F_E := -PI * 0.5    ## 面朝 +X

const SECT_MARKERS := {
	"sect_gate": [Vector3(0, 0, -53), F_N],
	"npc_master": [Vector3(0, 1.75, 22.75), F_N],
	"npc_teacher": [Vector3(-16.5, 0, 2), F_E],
	"npc_steward": [Vector3(16.5, 0, -1.5), F_W],
	"npc_senior": [Vector3(-7, 0, -5), F_N],
	"shop": [Vector3(-21.25, 0, -30), F_E],
	"mission_board": [Vector3(18, 0, 7), F_W],
	"cultivation_room": [Vector3(27, 0.25, -30), F_W],
}
const TOWN_MARKERS := {
	"npc_merchant_1": [Vector3(-19.5, 0, -8.0), F_S],
	"npc_merchant_2": [Vector3(19.5, 0, -8.0), F_S],
	"npc_merchant_3": [Vector3(-19.5, 0, 8.0), F_N],
	"npc_merchant_4": [Vector3(19.5, 0, 8.0), F_N],
	"town_board": [Vector3(-9, 0, -11), F_S],
	"town_center": [Vector3(0, 0, 0), F_N],
}
const HOME_MARKERS := {
	"home_spawn": [Vector3(0, 0, -3.5), F_N],
	"home_cushion": [Vector3(0, 0.5, 12), F_N],
	"home_stash": [Vector3(5.5, 0, 12), F_W],
	"home_furnace": [Vector3(-5, 0, 10.5), F_N],
	"home_field": [Vector3(0, 0, -11), F_N],
}
const PORTAL_MARKERS := {
	"realm_portal": [Vector3(0, 0.75, -0.5), F_N],
}

static var _terrain_mat: ShaderMaterial
static var _portal_shader: Shader


static func marker_layout(poi: Dictionary) -> Dictionary:
	match str(poi.get("type", "")):
		"sect":
			return SECT_MARKERS
		"town":
			return TOWN_MARKERS
		"home":
			return HOME_MARKERS
		"portal":
			return PORTAL_MARKERS
	return {}


## POI 局部坐标 → 世界坐标
static func poi_transform(poi: Dictionary) -> Transform3D:
	var pos: Vector3 = poi["pos"]
	return Transform3D(Basis(Vector3.UP, float(poi["yaw"])), Vector3(pos.x, float(poi.get("height", pos.y)), pos.z))


## 标记点世界变换 {名称: Transform3D}
static func marker_transforms(poi: Dictionary) -> Dictionary:
	var out := {}
	var xf := poi_transform(poi)
	var lay := marker_layout(poi)
	for k in lay:
		var e: Array = lay[k]
		out[k] = xf * Transform3D(Basis(Vector3.UP, float(e[1])), e[0])
	return out


static func terrain_material() -> ShaderMaterial:
	if _terrain_mat == null:
		_terrain_mat = ShaderMaterial.new()
		_terrain_mat.shader = load("res://assets/shaders/terrain.gdshader")
	return _terrain_mat


static func build_poi(poi: Dictionary, terrain: TerrainGen) -> Node3D:
	match str(poi["type"]):
		"sect":
			return build_sect(poi, terrain)
		"town":
			return build_town(poi, terrain)
		"home":
			return build_home(poi, terrain)
		"portal":
			return build_portal(poi, terrain)
		"landmark":
			return build_landmark(poi, terrain)
	return null


static func _root(poi: Dictionary, prefix: String) -> Node3D:
	var n := Node3D.new()
	n.name = prefix
	n.transform = poi_transform(poi)
	n.set_meta("poi_id", poi["id"])
	return n


static func _add_markers(root: Node3D, poi: Dictionary) -> void:
	var lay := marker_layout(poi)
	for k in lay:
		var e: Array = lay[k]
		var mk := Marker3D.new()
		mk.name = k
		mk.position = e[0]
		mk.rotation.y = float(e[1])
		mk.add_to_group("poi_marker")
		mk.set_meta("poi_id", poi["id"])
		if poi.has("sect_id"):
			mk.set_meta("sect_id", poi["sect_id"])
		if poi.has("realm_id"):
			mk.set_meta("realm_id", poi["realm_id"])
			mk.add_to_group("realm_portal")
		root.add_child(mk)


static func _finish(root: Node3D, m: BuildingMesh) -> void:
	var mi := m.build_instance()
	mi.name = "Mesh"
	root.add_child(mi)
	var body := m.build_body()
	body.name = "Body"
	root.add_child(body)


static func _place(root: Node3D, n: Node3D, local: Vector3, yaw: float = 0.0) -> Node3D:
	root.add_child(n)
	n.position = local
	n.rotation.y = yaw
	return n


# ================================================================ 宗门

static func sect_palette(sid: String) -> Dictionary:
	var sd: Dictionary = DB.sect(sid)
	var c1 := Color.html(str(sd.get("color", "#c8281c")))
	var c2 := Color.html(str(sd.get("color2", "#d8b050")))
	var c3 := Color.html(str(sd.get("color3", "#3a4050")))
	match sid:
		"tianjian":
			return BuildingBuilder.pal_with({"roof": c3.darkened(0.2), "roof2": c3, "pillar": Color(0.58, 0.14, 0.12), "wall": c1,
				"trim": c2, "beam": Color(0.22, 0.40, 0.52), "stone": Color(0.74, 0.75, 0.78), "stone2": Color(0.60, 0.62, 0.66), "plaque": Color(0.14, 0.18, 0.28)})
		"qingmu":
			return BuildingBuilder.pal_with({"roof": c3, "roof2": c3.lightened(0.15), "pillar": Color(0.40, 0.26, 0.16), "wall": c2,
				"trim": Color(0.82, 0.72, 0.36), "beam": c1.darkened(0.2), "stone": Color(0.60, 0.62, 0.56), "stone2": Color(0.50, 0.53, 0.48),
				"door": Color(0.36, 0.22, 0.13), "plaque": Color(0.12, 0.22, 0.14)})
		"xuanshui":
			return BuildingBuilder.pal_with({"roof": c3, "roof2": c3.lightened(0.18), "pillar": c1.darkened(0.25), "wall": c2.lerp(Color.WHITE, 0.4),
				"trim": Color(0.80, 0.86, 0.95), "beam": c1, "stone": Color(0.70, 0.72, 0.76), "stone2": Color(0.58, 0.61, 0.66),
				"door": Color(0.18, 0.26, 0.45), "plaque": Color(0.10, 0.14, 0.30), "lantern": Color(0.5, 0.8, 1.0)})
		"lihuo":
			return BuildingBuilder.pal_with({"roof": c3.darkened(0.1), "roof2": Color(0.40, 0.14, 0.10), "pillar": c1, "wall": Color(0.90, 0.84, 0.76),
				"trim": c2, "beam": Color(0.55, 0.10, 0.08), "stone": Color(0.40, 0.34, 0.33), "stone2": Color(0.30, 0.25, 0.25),
				"door": Color(0.42, 0.10, 0.08), "plaque": Color(0.10, 0.06, 0.05), "lantern": Color(1.0, 0.45, 0.12)})
		"houtu":
			return BuildingBuilder.pal_with({"roof": c2.darkened(0.15), "roof2": c2.lightened(0.1), "pillar": c1.darkened(0.2), "wall": c3,
				"trim": Color(0.85, 0.66, 0.28), "beam": Color(0.44, 0.30, 0.16), "stone": Color(0.78, 0.68, 0.50), "stone2": Color(0.66, 0.56, 0.40),
				"door": Color(0.40, 0.24, 0.12), "plaque": Color(0.22, 0.14, 0.08)})
	return BuildingBuilder.pal_with({})


static func _sect_trees(sid: String) -> Array:
	match sid:
		"tianjian":
			return ["pine_snow", "pine_snow"]
		"qingmu":
			return ["bamboo", "broadleaf"]
		"xuanshui":
			return ["willow", "blossom"]
		"lihuo":
			return ["maple", "dead"]
		"houtu":
			return ["broadleaf", "shrub_yellow"]
	return ["broadleaf"]


static func build_sect(poi: Dictionary, terrain: TerrainGen) -> Node3D:
	var sid: String = poi["sect_id"]
	var root := _root(poi, "Sect_" + sid)
	var p := sect_palette(sid)
	var m := BuildingMesh.new(hash(sid))
	var B := BuildingBuilder
	# 山门牌坊 + 旗杆
	B.paifang(m, 0, -48, 17, 9, p)
	var flag: Color = p["beam"] if sid != "tianjian" else Color(0.9, 0.92, 0.96)
	for sx in [-1.0, 1.0]:
		var x: float = sx * 12.0
		m.box(Vector3(x - 0.6, 0, -50.6), Vector3(x + 0.6, 0.75, -49.4), p["stone"], true)
		m.box(Vector3(x - 0.15, 0.75, -50.15), Vector3(x + 0.15, 12, -49.85), p["wood"], true)
		m.box(Vector3(x - 0.3, 12, -50.3), Vector3(x + 0.3, 12.4, -49.7), p["trim"])
		for i in 8:
			var yy := 11.5 - i * 0.6
			m.box(Vector3(x + sx * 0.15, yy - 0.6, -50.05), Vector3(x + sx * (0.15 + 2.6 - i * 0.12), yy, -49.95), flag if i % 3 != 2 else flag.darkened(0.15))
	# 院墙（前墙留山门缺口）
	var wall_p := p.duplicate()
	for seg in [[Vector2(-44, -48), Vector2(-9.5, -48)], [Vector2(9.5, -48), Vector2(44, -48)], [Vector2(-44, -48), Vector2(-44, 46)],
			[Vector2(44, -48), Vector2(44, 46)], [Vector2(-44, 46), Vector2(44, 46)]]:
		B.wall(m, seg[0], seg[1], 3.5, wall_p)
	# 角楼
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var cx: float = sx * 44.0
			var cz: float = -48.0 if sz < 0.0 else 46.0
			m.box(Vector3(cx - 2.5, 0, cz - 2.5), Vector3(cx + 2.5, 5.0, cz + 2.5), p["stone2"], true)
			B.pavilion(m, cx, cz, 3.0, 2.5, p, 5.0)
	# 主殿（重檐）
	var info := B.hall(m, 0, 30, 22, 12, 1.75, 5.0, p, {"double": true, "stairs_w": 7.0, "door_w": 4.0})
	# 侧殿：传功殿（西，面东）、任务堂（东，面西）
	m.push(Vector3(-27, 0, 2), 3)
	B.hall(m, 0, 0, 16, 10, 1.0, 4.0, p, {"porch": 1.25, "stairs_w": 5.0})
	m.pop()
	m.push(Vector3(27, 0, 2), 1)
	B.hall(m, 0, 0, 16, 10, 1.0, 4.0, p, {"porch": 1.25, "stairs_w": 5.0})
	m.pop()
	# 任务榜（面西）
	m.push(Vector3(19, 0, 7), 1)
	B.notice_board(m, 0, 0, 3.0, p, p["door"])
	m.pop()
	# 宗门商铺（西南，面东）
	m.push(Vector3(-27, 0, -30), 3)
	B.shop(m, 0, 0, 9, 8, p, p["beam"], hash(sid) + 3)
	m.pop()
	# 静室（东南，面西）：石室 + 月洞门
	m.push(Vector3(27, 0, -30), 1)
	_meditation_room(m, p)
	m.pop()
	# 塔与亭
	B.pagoda(m, -34, 36, 6, 5, p)
	B.pavilion(m, 34, 36, 5, 3.5, p, 0.75)
	# 主院铺装石板与中轴甬道
	B.paving(m, -3, -46, 3, -14, 0.05, p, 2.0)
	# 宗门特色
	match sid:
		"tianjian":
			B.giant_sword(m, 0, -2, 13, p)
			B.giant_sword(m, -13, 6, 8, p)
			B.giant_sword(m, 13, 6, 8, p)
			for i in 4:
				B.giant_sword(m, -20 + i * 13.3, -20, 4.5, p)
		"qingmu":
			_place(root, PropBuilder.make_tree("ancient", 1), Vector3(0, 0, -1))
			_herb_garden(m, Vector3(-32, 0, -10), p)
			_herb_garden(m, Vector3(32, 0, -10), p)
		"xuanshui":
			_pool(m, root, Vector3(0, 0, -2), 9.0, 6.0, p)
			B.pavilion(m, 0, -2, 4.0, 3.0, p, 1.0)
		"lihuo":
			B.cauldron(m, 0, -2, 2.4, p)
			for sx in [-1.0, 1.0]:
				for i in 3:
					_brazier(m, Vector3(sx * 8.0, 0, -10 + i * 10), p)
			var cr := PropBuilder.make_tree("crystal", 0)
			_place(root, cr, Vector3(-36, 0, -6))
			_place(root, PropBuilder.make_tree("crystal", 2), Vector3(36, 0, -6))
		"houtu":
			_formation(m, Vector3(0, 0, -2), 8.0, p)
	# 灯柱（装饰）沿院墙
	for i in 5:
		var z := -40.0 + i * 20.0
		B.stone_post(m, -41, z, 2.0, p)
		B.stone_post(m, 41, z, 2.0, p)
	_finish(root, m)
	# 可破坏石灯笼（中轴两侧）
	var glow := Color(1.0, 0.72, 0.38) if sid != "xuanshui" else Color(0.55, 0.85, 1.0)
	for i in 4:
		var z := -42.0 + i * 8.0
		for sx in [-1.0, 1.0]:
			var d := DestructibleFactory.lantern(glow, p["stone"])
			_place(root, d, Vector3(sx * 5.0, 0, z))
	# 主院石柱（可破坏）
	for sx in [-1.0, 1.0]:
		var pl := DestructibleFactory.pillar(4.5, p["pillar"], p["trim"], 0.45)
		_place(root, pl, Vector3(sx * 9.0, 0, 16.5))
	# 树木
	var trees := _sect_trees(sid)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(sid) + 11
	for i in 6:
		for sx in [-1.0, 1.0]:
			var z := -40.0 + i * 8.5
			if absf(z + 30.0) < 5.0 or (z > -6.0 and z < 12.0):
				continue
			var kind: String = trees[rng.randi() % trees.size()]
			var t := PropBuilder.make_tree(kind, rng.randi())
			_place(root, t, Vector3(sx * 38.0, 0, z), rng.randf() * TAU)
	_add_markers(root, poi)
	return root


static func _meditation_room(m: BuildingMesh, p: Dictionary) -> void:
	var s: Color = p["stone"]
	var w := 7.0
	var d := 7.0
	m.box(Vector3(-w * 0.5 - 0.5, -0.25, -d * 0.5 - 0.5), Vector3(w * 0.5 + 0.5, 0.25, d * 0.5 + 0.5), p["stone2"], true)
	# 墙（正面月洞门）
	m.box(Vector3(-w * 0.5, 0.25, d * 0.5 - 0.5), Vector3(w * 0.5, 4.0, d * 0.5), p["wall"], true)
	m.box(Vector3(-w * 0.5, 0.25, -d * 0.5), Vector3(-w * 0.5 + 0.5, 4.0, d * 0.5), p["wall"], true)
	m.box(Vector3(w * 0.5 - 0.5, 0.25, -d * 0.5), Vector3(w * 0.5, 4.0, d * 0.5), p["wall"], true)
	m.box(Vector3(-w * 0.5, 0.25, -d * 0.5), Vector3(-1.25, 4.0, -d * 0.5 + 0.5), p["wall"], true)
	m.box(Vector3(1.25, 0.25, -d * 0.5), Vector3(w * 0.5, 4.0, -d * 0.5 + 0.5), p["wall"], true)
	m.box(Vector3(-1.25, 2.75, -d * 0.5), Vector3(1.25, 4.0, -d * 0.5 + 0.5), p["wall"], true)
	m.box(Vector3(-1.25, 2.5, -d * 0.5), Vector3(-0.75, 2.75, -d * 0.5 + 0.5), p["wall"])
	m.box(Vector3(0.75, 2.5, -d * 0.5), Vector3(1.25, 2.75, -d * 0.5 + 0.5), p["wall"])
	# 门框（石）
	m.box(Vector3(-1.5, 0.25, -d * 0.5 - 0.15), Vector3(1.5, 3.0, -d * 0.5), s)
	m.box(Vector3(-1.0, 0.25, -d * 0.5 - 0.2), Vector3(1.0, 2.6, -d * 0.5 - 0.15), Color(0.1, 0.1, 0.1))
	# 室内：蒲团 + 发光阵纹
	m.box(Vector3(-1.5, 0.25, -1.5), Vector3(1.5, 0.3, 1.5), VoxelGrid.glow(p["trim"], 0.35))
	m.box(Vector3(-0.5, 0.3, -0.5), Vector3(0.5, 0.55, 0.5), Color(0.72, 0.56, 0.3))
	BuildingBuilder.roof(m, 0, 0, w * 0.5 + 1.25, d * 0.5 + 1.25, 4.0, 2.5, p, false)


static func _herb_garden(m: BuildingMesh, c: Vector3, p: Dictionary) -> void:
	var soil := Color(0.34, 0.24, 0.16)
	var wood: Color = p["wood"]
	m.box(c + Vector3(-5, 0, -8), c + Vector3(5, 0.3, 8), soil, true)
	for i in 5:
		for j in 8:
			var col := Color(0.30, 0.72, 0.50) if (i + j) % 3 != 0 else Color(0.45, 0.85, 0.6)
			var pos := c + Vector3(-4 + i * 2.0, 0.3, -7 + j * 2.0)
			m.box(pos + Vector3(-0.3, 0, -0.3), pos + Vector3(0.3, 0.6, 0.3), col)
			if (i + j) % 4 == 0:
				m.box(pos + Vector3(-0.1, 0.6, -0.1), pos + Vector3(0.1, 0.8, 0.1), VoxelGrid.glow(Color(0.6, 1.0, 0.9), 0.8))
	for sx in [-1.0, 1.0]:
		m.box(c + Vector3(sx * 5.0 - 0.1, 0, -8), c + Vector3(sx * 5.0 + 0.1, 0.8, 8), wood)
	m.box(c + Vector3(-5, 0, -8.1), c + Vector3(5, 0.8, -7.9), wood)
	m.box(c + Vector3(-5, 0, 7.9), c + Vector3(5, 0.8, 8.1), wood)


## 水池：石栏 + 水面（水面着色器）+ 荷叶
static func _pool(m: BuildingMesh, root: Node3D, c: Vector3, hw: float, hd: float, p: Dictionary) -> void:
	var s: Color = p["stone"]
	m.box(c + Vector3(-hw, -0.5, -hd), c + Vector3(hw, 0.0, hd), Color(0.24, 0.34, 0.38))
	m.box(c + Vector3(-hw - 0.75, 0, -hd - 0.75), c + Vector3(hw + 0.75, 0.6, -hd), s, true)
	m.box(c + Vector3(-hw - 0.75, 0, hd), c + Vector3(hw + 0.75, 0.6, hd + 0.75), s, true)
	m.box(c + Vector3(-hw - 0.75, 0, -hd), c + Vector3(-hw, 0.6, hd), s, true)
	m.box(c + Vector3(hw, 0, -hd), c + Vector3(hw + 0.75, 0.6, hd), s, true)
	var water := MeshInstance3D.new()
	water.name = "PoolWater"
	var pm := PlaneMesh.new()
	pm.size = Vector2(hw * 2.0, hd * 2.0)
	water.mesh = pm
	var wm := ShaderMaterial.new()
	wm.shader = load("res://assets/shaders/water.gdshader")
	wm.set_shader_parameter("absorption", 0.6)
	water.material_override = wm
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(water)
	water.position = c + Vector3(0, 0.35, 0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 8:
		var lot := MeshInstance3D.new()
		lot.mesh = PropBuilder.mesh("lotus", i % 2)
		root.add_child(lot)
		var q := Vector3(rng.randf_range(-hw + 1.2, hw - 1.2), 0.38, rng.randf_range(-hd + 1.2, hd - 1.2))
		if absf(q.x) < 3.0 and absf(q.z) < 3.0:
			q.x += 4.0 * signf(q.x + 0.01)
		lot.position = c + q
		lot.rotation.y = rng.randf() * TAU


static func _brazier(m: BuildingMesh, c: Vector3, p: Dictionary) -> void:
	var s: Color = p["stone"]
	m.box(c + Vector3(-0.6, 0, -0.6), c + Vector3(0.6, 0.3, 0.6), s, true)
	m.box(c + Vector3(-0.25, 0.3, -0.25), c + Vector3(0.25, 1.4, 0.25), Color(0.3, 0.26, 0.22), true)
	m.box(c + Vector3(-0.7, 1.4, -0.7), c + Vector3(0.7, 1.8, 0.7), Color(0.36, 0.30, 0.18))
	m.box(c + Vector3(-0.5, 1.8, -0.5), c + Vector3(0.5, 2.2, 0.5), VoxelGrid.glow(Color(1.0, 0.5, 0.12), 1.0))
	m.box(c + Vector3(-0.25, 2.2, -0.25), c + Vector3(0.25, 2.7, 0.25), VoxelGrid.glow(Color(1.0, 0.8, 0.3), 1.0))


## 厚土宗阵法：八方立石环 + 发光阵纹
static func _formation(m: BuildingMesh, c: Vector3, r: float, p: Dictionary) -> void:
	var s: Color = p["stone"]
	var rune := VoxelGrid.glow(Color(1.0, 0.8, 0.3), 0.7)
	m.box(c + Vector3(-r, 0, -r * 0.4), c + Vector3(r, 0.25, r * 0.4), p["stone2"], true)
	m.box(c + Vector3(-r * 0.4, 0, -r), c + Vector3(r * 0.4, 0.25, r), p["stone2"], true)
	m.box(c + Vector3(-r * 0.75, 0, -r * 0.75), c + Vector3(r * 0.75, 0.25, r * 0.75), p["stone2"], true)
	for i in 8:
		var a := i * TAU / 8.0
		var q := c + Vector3(cos(a) * r, 0, sin(a) * r)
		q = Vector3(snappedf(q.x, 0.25), 0, snappedf(q.z, 0.25))
		m.box(q + Vector3(-0.6, 0, -0.6), q + Vector3(0.6, 4.0 + (i % 2) * 1.0, 0.6), s, true)
		m.box(q + Vector3(-0.65, 1.5, -0.65), q + Vector3(0.65, 1.75, 0.65), rune)
		m.box(q + Vector3(-0.65, 3.0, -0.65), q + Vector3(0.65, 3.25, 0.65), rune)
	# 阵纹
	m.box(c + Vector3(-r * 0.6, 0.25, -0.15), c + Vector3(r * 0.6, 0.3, 0.15), rune)
	m.box(c + Vector3(-0.15, 0.25, -r * 0.6), c + Vector3(0.15, 0.3, r * 0.6), rune)
	m.box(c + Vector3(-1.5, 0.25, -1.5), c + Vector3(1.5, 0.5, 1.5), p["trim"], true)
	m.box(c + Vector3(-0.5, 0.5, -0.5), c + Vector3(0.5, 1.3, 0.5), VoxelGrid.glow(Color(1.0, 0.85, 0.4), 0.9))


# ================================================================ 坊市

static func build_town(poi: Dictionary, terrain: TerrainGen) -> Node3D:
	var root := _root(poi, "Town")
	var p := BuildingBuilder.pal_with({"wall": Color(0.90, 0.87, 0.80), "roof": Color(0.24, 0.26, 0.30), "beam": Color(0.24, 0.38, 0.40)})
	var m := BuildingMesh.new(4242)
	var B := BuildingBuilder
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var signs := [Color(0.62, 0.14, 0.12), Color(0.16, 0.26, 0.46), Color(0.2, 0.36, 0.22), Color(0.5, 0.36, 0.12), Color(0.35, 0.16, 0.36)]
	# 主街两侧店铺
	var xs := [28.0, 40.0, 64.0, 76.0]
	for sx in [-1.0, 1.0]:
		for x in xs:
			var cx: float = sx * x
			# 北侧（面向 +Z）
			if not (sx > 0.0 and (x == 40.0)):
				m.push(Vector3(cx, 0, -13), 2)
				B.shop(m, 0, 0, 10, 9, p, signs[rng.randi() % signs.size()], rng.randi())
				m.pop()
			# 南侧（面向 -Z）
			m.push(Vector3(cx, 0, 13), 0)
			B.shop(m, 0, 0, 10, 9, p, signs[rng.randi() % signs.size()], rng.randi())
			m.pop()
	# 客栈（北侧东段，面向 +Z）：大宅 + 幌子
	m.push(Vector3(48, 0, -16), 2)
	B.hall(m, 0, 0, 18, 11, 0.5, 4.0, p, {"double": true, "porch": 1.25, "stairs_w": 4.0, "door_w": 3.5})
	m.pop()
	m.box(Vector3(37.5, 0, -8.5), Vector3(38.0, 9, -8.0), p["wood"], true)
	for i in 6:
		m.box(Vector3(38.0, 8.5 - i * 0.6, -8.35), Vector3(40.2, 9.0 - i * 0.6, -8.15), Color(0.85, 0.2, 0.15) if i % 2 == 0 else Color(0.95, 0.85, 0.7))
	# 十字街民居
	for sz in [-1.0, 1.0]:
		for i in 3:
			var z: float = sz * (28.0 + i * 13.0)
			m.push(Vector3(-13, 0, z), 3)
			B.hall(m, 0, 0, 9, 7, 0.25, 3.5, p, {"porch": 0.75, "plaque": false, "lanterns": i == 0, "stairs_w": 2.0, "door_w": 2.0})
			m.pop()
			m.push(Vector3(13, 0, z), 1)
			B.hall(m, 0, 0, 9, 7, 0.25, 3.5, p, {"porch": 0.75, "plaque": false, "lanterns": i == 1, "stairs_w": 2.0, "door_w": 2.0})
			m.pop()
	# 牌坊（四个街口）
	m.push(Vector3(-84, 0, 0), 3)
	B.paifang(m, 0, 0, 13, 8, p)
	m.pop()
	m.push(Vector3(84, 0, 0), 1)
	B.paifang(m, 0, 0, 13, 8, p)
	m.pop()
	m.push(Vector3(0, 0, -66), 0)
	B.paifang(m, 0, 0, 12, 7.5, p)
	m.pop()
	m.push(Vector3(0, 0, 66), 2)
	B.paifang(m, 0, 0, 12, 7.5, p)
	m.pop()
	# 摊位（面向街道）
	var cloths := [Color(0.85, 0.25, 0.2), Color(0.25, 0.45, 0.8), Color(0.9, 0.7, 0.2), Color(0.3, 0.65, 0.4)]
	var stalls := [[Vector3(-19.5, 0, -7.5), 2], [Vector3(19.5, 0, -7.5), 2], [Vector3(-19.5, 0, 7.5), 0], [Vector3(19.5, 0, 7.5), 0]]
	for i in stalls.size():
		m.push(stalls[i][0], stalls[i][1])
		B.stall(m, 0, 0, 3.0, cloths[i], p, i)
		m.pop()
	# 告示牌（面向 +Z）
	m.push(Vector3(-9, 0, -11.5), 2)
	B.notice_board(m, 0, 0, 3.5, p)
	m.pop()
	# 水井
	var s: Color = p["stone"]
	m.box(Vector3(-11.5, 0, 8.5), Vector3(-8.5, 0.9, 11.5), s, true)
	m.box(Vector3(-11, 0.5, 9), Vector3(-9, 0.95, 11), Color(0.15, 0.25, 0.3))
	for sx in [-1.0, 1.0]:
		m.box(Vector3(-10 + sx * 1.3 - 0.12, 0.9, 9.9), Vector3(-10 + sx * 1.3 + 0.12, 2.8, 10.1), p["wood"])
	m.box(Vector3(-11.6, 2.8, 9.7), Vector3(-8.4, 3.0, 10.3), p["wood"])
	B.roof(m, -10, 10, 2.0, 1.6, 3.0, 0.75, p, true, 0.0, 0.6)
	# 街灯（吊灯笼木杆）
	for i in 12:
		var x := -78.0 + i * 14.0
		if absf(x) < 20.0:
			continue
		for sz in [-1.0, 1.0]:
			var z: float = sz * 6.0
			m.box(Vector3(x - 0.12, 0, z - 0.12), Vector3(x + 0.12, 4.2, z + 0.12), p["wood"], true)
			m.box(Vector3(x - 0.12, 4.0, z - 0.12 - sz * 0.8), Vector3(x + 0.12, 4.2, z + 0.12), p["wood"])
			B.lantern(m, Vector3(x, 4.0, z - sz * 0.7), p, 0.9)
	B.paving(m, -16, -16, 16, 16, 0.05, p, 2.0)
	_finish(root, m)
	# 广场花树
	_place(root, PropBuilder.make_tree("blossom", 0), Vector3(10, 0, 11))
	_place(root, PropBuilder.make_tree("blossom", 1), Vector3(-12.5, 0, -14.5))
	_place(root, PropBuilder.make_tree("willow", 0), Vector3(-30, 0, 30))
	_place(root, PropBuilder.make_tree("broadleaf", 1), Vector3(30, 0, 34))
	# 可破坏：石灯笼、木箱、石柱
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			_place(root, DestructibleFactory.lantern(), Vector3(sx * 6.5, 0, sz * 6.5))
	var crate_spots := [Vector3(-22.5, 0, -8.5), Vector3(-22.5, 0, -7.0), Vector3(22.8, 0, 8.4), Vector3(17.0, 0, 9.0), Vector3(-17.2, 0, -9.2), Vector3(22.5, 0, -8.8)]
	for i in crate_spots.size():
		var cr := DestructibleFactory.crate(0.9 + (i % 3) * 0.15)
		_place(root, cr, crate_spots[i], i * 0.4)
	for sx in [-1.0, 1.0]:
		_place(root, DestructibleFactory.pillar(3.5, Color(0.64, 0.63, 0.6), Color(0.5, 0.5, 0.52), 0.4), Vector3(sx * 15.5, 0, -15.5))
		_place(root, DestructibleFactory.pillar(3.5, Color(0.64, 0.63, 0.6), Color(0.5, 0.5, 0.52), 0.4), Vector3(sx * 15.5, 0, 15.5))
	_add_markers(root, poi)
	return root


# ================================================================ 洞府

static func build_home(poi: Dictionary, terrain: TerrainGen) -> Node3D:
	var root := _root(poi, "Home")
	var p := BuildingBuilder.pal_with({"stone": Color(0.56, 0.55, 0.52), "stone2": Color(0.46, 0.45, 0.43)})
	var m := BuildingMesh.new(77)
	var hill := BuildingMesh.new(78)
	hill.jitter = 0.0
	var B := BuildingBuilder
	var xf := poi_transform(poi)
	var inv := xf.affine_inverse()
	var floor_y := float(poi["height"])
	var rect := terrain.home_cave_rect
	var heights := terrain.home_cave_heights
	var surf: Array = TerrainGen.SURF[TerrainGen.S_GRASS]
	var stone: Color = surf[4]
	var dirt: Color = surf[2]
	# 山体（压平前的高度）：室内与门洞处挖空；使用地形着色器使方块描边一致
	for z in rect.size.y:
		for x in rect.size.x:
			var wx := rect.position.x + x
			var wz := rect.position.y + z
			var h := float(heights[z * rect.size.x + x]) - floor_y
			if h <= 0.5:
				continue
			var lc := inv * Vector3(wx + 0.5, floor_y, wz + 0.5)
			var lx := lc.x
			var lz := lc.z
			var base := -1.0
			if absf(lx) < 7.0 and lz > 3.0 and lz < 15.0:
				base = 5.5
			elif absf(lx) < 2.0 and lz > 0.0 and lz < 3.5:
				base = 4.0
			h = maxf(h, maxf(base + 1.5, 7.0))
			var a := Vector3(floorf(lx), base, floorf(lz))
			var b := Vector3(floorf(lx) + 1.0, h, floorf(lz) + 1.0)
			var patch := terrain.n_patch.get_noise_2d(wx, wz)
			var top := TerrainGen.top_color(TerrainGen.S_GRASS, wx, wz, patch)
			var sk := 0.93 + 0.1 * TerrainGen._hash2(wx, wz)
			var st := Color(stone.r * sk, stone.g * sk, stone.b * sk)
			if h - base > 3.0:
				hill.box(a, Vector3(b.x, h - 3.0, b.z), st)
				hill.box(Vector3(a.x, h - 3.0, a.z), Vector3(b.x, h - 1.0, b.z), dirt)
				hill.box(Vector3(a.x, h - 1.0, a.z), b, surf[1], false, false, top)
			else:
				hill.box(a, b, st, false, false, top)
			hill.collider(a, b)
	var hmi := MeshInstance3D.new()
	hmi.name = "Hill"
	hmi.mesh = hill.build_mesh(terrain_material())
	root.add_child(hmi)
	var hbody := hill.build_body()
	hbody.name = "HillBody"
	root.add_child(hbody)
	# 石室地面
	B.paving(m, -7, 3, 7, 15, 0.1, p, 1.0)
	m.box(Vector3(-2, -0.2, 0), Vector3(2, 0.1, 3.5), p["stone2"])
	# 门框 + 匾额 + 小檐
	var wood := Color(0.36, 0.22, 0.14)
	for sx in [-1.0, 1.0]:
		m.box(Vector3(sx * 2.25 - 0.5, 0, 0.0), Vector3(sx * 2.25 + 0.5, 4.5, 1.0), p["stone"], true)
	m.box(Vector3(-2.75, 4.0, -0.25), Vector3(2.75, 4.75, 1.0), p["stone"])
	m.box(Vector3(-1.25, 4.1, -0.4), Vector3(1.25, 4.65, -0.25), Color(0.15, 0.12, 0.1))
	for i in 2:
		m.box(Vector3(-0.7 + i * 0.9, 4.2, -0.5), Vector3(-0.2 + i * 0.9, 4.55, -0.4), Color(0.9, 0.72, 0.3))
	B.roof(m, 0, 0.2, 3.5, 1.3, 4.75, 0.75, BuildingBuilder.pal_with({}), true, 0.0, 0.8)
	# 室内陈设：蒲团玉台、储物箱、丹炉、书架、灵晶
	var jade := Color(0.52, 0.80, 0.66)
	m.box(Vector3(-1.75, 0.1, 10.25), Vector3(1.75, 0.3, 13.75), jade.darkened(0.2), true)
	m.box(Vector3(-1.25, 0.3, 10.75), Vector3(1.25, 0.45, 13.25), VoxelGrid.glow(jade, 0.4), true)
	m.box(Vector3(-0.55, 0.45, 11.45), Vector3(0.55, 0.7, 12.55), Color(0.78, 0.60, 0.32))
	# 储物箱
	m.box(Vector3(4.75, 0.1, 11.0), Vector3(6.25, 1.1, 13.0), wood, true)
	m.box(Vector3(4.7, 1.1, 10.95), Vector3(6.3, 1.3, 13.05), wood.lightened(0.1))
	m.box(Vector3(4.65, 0.5, 11.8), Vector3(4.75, 0.8, 12.2), Color(0.9, 0.72, 0.3))
	m.box(Vector3(4.7, 0.1, 10.95), Vector3(6.3, 0.25, 13.05), Color(0.85, 0.66, 0.28))
	# 丹炉
	B.cauldron(m, -5, 10.5, 0.55, p, Color(0.4, 0.9, 1.0))
	# 书架（后墙）
	for i in 3:
		var x0 := -6.5 + i * 4.5
		if i == 1:
			continue
		m.box(Vector3(x0, 0.1, 14.4), Vector3(x0 + 3.5, 3.0, 14.9), wood, true)
		m.box(Vector3(x0, 0.1, 13.8), Vector3(x0 + 0.2, 3.0, 14.4), wood)
		m.box(Vector3(x0 + 3.3, 0.1, 13.8), Vector3(x0 + 3.5, 3.0, 14.4), wood)
		m.box(Vector3(x0, 2.9, 13.7), Vector3(x0 + 3.5, 3.1, 14.9), wood.lightened(0.1))
		for sh in 3:
			var y := 0.35 + sh * 0.85
			m.box(Vector3(x0 + 0.2, y - 0.1, 13.8), Vector3(x0 + 3.3, y, 14.4), wood.darkened(0.15))
			var bx := x0 + 0.25
			var k := 0
			while bx < x0 + 3.15:
				var bw := 0.18 + fmod(k * 0.37 + i, 0.2)
				var bh := 0.45 + fmod(k * 0.29, 0.25)
				m.box(Vector3(bx, y, 13.9), Vector3(minf(bx + bw, x0 + 3.28), y + bh, 14.4), Color.from_hsv(fmod(k * 0.17 + i * 0.3, 1.0), 0.5, 0.62))
				bx += bw + 0.03
				k += 1
	# 卷轴与蒲团旁小几
	m.box(Vector3(2.0, 0.1, 10.8), Vector3(3.2, 0.6, 11.6), wood)
	m.box(Vector3(2.2, 0.6, 11.0), Vector3(3.0, 0.72, 11.2), Color(0.92, 0.86, 0.7))
	m.box(Vector3(2.4, 0.6, 11.3), Vector3(2.6, 0.9, 11.5), VoxelGrid.glow(Color(0.5, 1.0, 0.8), 0.5))
	# 灵晶（墙角发光）
	for q in [Vector3(-6.5, 0.1, 4.0), Vector3(6.5, 0.1, 4.5), Vector3(-6.5, 3.0, 9.0), Vector3(6.5, 3.5, 14.0), Vector3(0.5, 5.0, 8.0)]:
		var cc := VoxelGrid.glow(Color(0.45, 0.85, 1.0), 0.9)
		m.box(q + Vector3(-0.25, 0, -0.25), q + Vector3(0.25, 1.0, 0.25), cc)
		m.box(q + Vector3(0.1, 0, -0.45), q + Vector3(0.4, 0.6, -0.15), cc)
	# 室内光源
	var light := OmniLight3D.new()
	light.name = "CaveLight"
	light.light_color = Color(1.0, 0.78, 0.52)
	light.light_energy = 2.2
	light.omni_range = 14.0
	light.shadow_enabled = false
	light.position = Vector3(0, 4.2, 9)
	root.add_child(light)
	var light2 := OmniLight3D.new()
	light2.name = "CrystalLight"
	light2.light_color = Color(0.5, 0.85, 1.0)
	light2.light_energy = 1.2
	light2.omni_range = 7.0
	light2.shadow_enabled = false
	light2.position = Vector3(-5, 1.5, 11)
	root.add_child(light2)
	# 前院：药田围栏、药苗、石径
	for sx in [-1.0, 1.0]:
		var x0: float = -8.0 if sx < 0.0 else 1.0
		var x1: float = x0 + 7.0
		m.box(Vector3(x0, 0, -15.1), Vector3(x1, 0.7, -14.9), wood)
		m.box(Vector3(x0, 0, -7.1), Vector3(x1, 0.7, -6.9), wood)
		m.box(Vector3(x0 - 0.1, 0, -15), Vector3(x0 + 0.1, 0.7, -7), wood)
		m.box(Vector3(x1 - 0.1, 0, -15), Vector3(x1 + 0.1, 0.7, -7), wood)
		for i in 3:
			for j in 4:
				var pos := Vector3(x0 + 1.3 + i * 2.2, 0, -13.8 + j * 2.0)
				m.box(pos + Vector3(-0.3, 0, -0.3), pos + Vector3(0.3, 0.45, 0.3), Color(0.3, 0.7, 0.45))
				m.box(pos + Vector3(-0.1, 0.45, -0.1), pos + Vector3(0.1, 0.6, 0.1), VoxelGrid.glow(Color(0.6, 1.0, 0.85), 0.7))
	for i in 7:
		var z := -16.0 + i * 2.2
		m.box(Vector3(-0.8, -0.1, z), Vector3(0.8, 0.12, z + 1.6), p["stone"])
	_finish(root, m)
	_place(root, PropBuilder.make_tree("pine", 1), Vector3(-9, 0, -3))
	_place(root, PropBuilder.make_tree("blossom", 1), Vector3(9, 0, -4))
	for sx in [-1.0, 1.0]:
		_place(root, DestructibleFactory.lantern(), Vector3(sx * 4.0, 0, -2.0))
	_add_markers(root, poi)
	return root


# ================================================================ 秘境入口

static func build_portal(poi: Dictionary, terrain: TerrainGen) -> Node3D:
	var root := _root(poi, "Portal_" + str(poi["id"]))
	var rid: String = poi.get("realm_id", "")
	var m := BuildingMesh.new(hash(poi["id"]))
	var stone := Color(0.34, 0.33, 0.37)
	var stone2 := Color(0.26, 0.25, 0.29)
	var c1 := Color(0.35, 1.0, 0.75) if rid == "herb_valley" else Color(0.75, 0.45, 1.0)
	var c2 := Color(0.2, 0.55, 1.0) if rid == "herb_valley" else Color(1.0, 0.75, 0.35)
	var rune := VoxelGrid.glow(c1, 0.85)
	# 八角基座（两层）
	m.box(Vector3(-6, 0, -3.5), Vector3(6, 0.5, 3.5), stone2, true)
	m.box(Vector3(-3.5, 0, -6), Vector3(3.5, 0.5, 6), stone2, true)
	m.box(Vector3(-5, 0, -5), Vector3(5, 0.5, 5), stone2, true)
	m.box(Vector3(-4.5, 0.5, -2.5), Vector3(4.5, 0.75, 2.5), stone, true)
	m.box(Vector3(-2.5, 0.5, -4.5), Vector3(2.5, 0.75, 4.5), stone, true)
	# 阵纹环
	for i in 16:
		var a := i * TAU / 16.0
		var q := Vector3(snappedf(cos(a) * 4.4, 0.25), 0.5, snappedf(sin(a) * 4.4, 0.25))
		m.box(q + Vector3(-0.25, 0, -0.25), q + Vector3(0.25, 0.3, 0.25), rune)
	# 门柱与门楣
	for sx in [-1.0, 1.0]:
		var x: float = sx * 3.4
		m.box(Vector3(x - 0.9, 0.75, -0.9), Vector3(x + 0.9, 1.5, 0.9), stone2, true)
		m.box(Vector3(x - 0.7, 1.5, -0.7), Vector3(x + 0.7, 8.0, 0.7), stone, true)
		for k in 4:
			var y := 2.25 + k * 1.5
			m.box(Vector3(x - 0.75, y, -0.75), Vector3(x + 0.75, y + 0.25, 0.75), rune)
	m.box(Vector3(-4.75, 8.0, -1.0), Vector3(4.75, 9.0, 1.0), stone2, true)
	m.box(Vector3(-4.25, 9.0, -0.75), Vector3(4.25, 9.5, 0.75), stone)
	m.box(Vector3(-1.0, 8.2, -1.1), Vector3(1.0, 8.8, -1.0), rune)
	BuildingBuilder.roof(m, 0, 0, 5.5, 1.75, 9.5, 1.0, BuildingBuilder.pal_with({"roof": Color(0.2, 0.2, 0.26), "roof2": Color(0.3, 0.3, 0.36), "trim": Color(0.75, 0.62, 0.35)}), true, 0.0, 1.0)
	# 四角符石
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var q := Vector3(sx * 5.0, 0.5, sz * 5.0)
			m.box(q + Vector3(-0.4, 0, -0.4), q + Vector3(0.4, 2.2, 0.4), stone, true)
			m.box(q + Vector3(-0.45, 1.6, -0.45), q + Vector3(0.45, 1.85, 0.45), rune)
	_finish(root, m)
	# 旋涡门面
	if _portal_shader == null:
		_portal_shader = load("res://assets/shaders/portal.gdshader")
	var plane := MeshInstance3D.new()
	plane.name = "PortalPlane"
	var qm := QuadMesh.new()
	qm.size = Vector2(5.4, 6.5)
	plane.mesh = qm
	var pm := ShaderMaterial.new()
	pm.shader = _portal_shader
	plane.material_override = pm
	plane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(plane)
	plane.position = Vector3(0, 0.75 + 3.6, 0)
	plane.set_instance_shader_parameter("portal_color", c1)
	plane.set_instance_shader_parameter("portal_color2", c2)
	# 浮石
	for i in 5:
		var rock := MeshInstance3D.new()
		rock.mesh = PropBuilder.mesh("pebble", i)
		var a := PI * 0.05 + i * PI * 0.9 / 4.0  # 只在门后半圈（+Z 侧）
		root.add_child(rock)
		rock.position = Vector3(cos(a) * 7.0, 4.0 + (i % 3) * 1.8, sin(a) * 5.5 + 1.0)
		rock.scale = Vector3.ONE * (1.2 + (i % 2) * 0.8)
		rock.rotation = Vector3(0.3 * i, a, 0.2)
	var light := OmniLight3D.new()
	light.name = "PortalLight"
	light.light_color = c1
	light.light_energy = 2.0
	light.omni_range = 11.0
	light.shadow_enabled = false
	light.position = Vector3(0, 3.5, -1.5)
	root.add_child(light)
	_add_markers(root, poi)
	return root


# ================================================================ 地标

static func build_landmark(poi: Dictionary, terrain: TerrainGen) -> Node3D:
	var id: String = poi["id"]
	var root := _root(poi, "Landmark_" + id.trim_prefix("landmark_"))
	if not poi.has("height"):
		var pos: Vector3 = poi["pos"]
		root.position.y = terrain.get_ground_y(pos.x, pos.z)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(id)
	var p := BuildingBuilder.pal_with({"stone": Color(0.58, 0.57, 0.54), "stone2": Color(0.48, 0.47, 0.45)})
	var m := BuildingMesh.new(hash(id))
	var B := BuildingBuilder
	match id:
		"landmark_sword_tomb":
			var tp := BuildingBuilder.pal_with({"stone": Color(0.62, 0.64, 0.68), "stone2": Color(0.5, 0.52, 0.56), "trim": Color(0.7, 0.72, 0.78)})
			B.giant_sword(m, 0, 0, 15, tp)
			for i in 9:
				var a := i * TAU / 9.0
				var q := Vector3(roundf(cos(a) * 11.0), 0, roundf(sin(a) * 11.0))
				B.giant_sword(m, q.x, q.z, rng.randf_range(4.0, 8.0), tp)
			# 石碑
			m.box(Vector3(-1.5, 0, -6.5), Vector3(1.5, 0.75, -5.5), tp["stone2"], true)
			m.box(Vector3(-1.1, 0.75, -6.25), Vector3(1.1, 4.5, -5.75), tp["stone"], true)
			for k in 5:
				m.box(Vector3(-0.2, 1.2 + k * 0.6, -6.3), Vector3(0.2, 1.5 + k * 0.6, -6.25), Color(0.2, 0.2, 0.22))
			_finish(root, m)
			for i in 4:
				var a := i * TAU / 4.0 + 0.5
				var w := DestructibleFactory.wall(5.0, 2.5, "ruin", i)
				_place(root, w, Vector3(cos(a) * 16.0, 0, sin(a) * 16.0), a + PI * 0.5)
		"landmark_battlefield":
			# 残破牌坊基座与倒塌柱段
			for i in 6:
				var q := Vector3(rng.randf_range(-14, 14), 0, rng.randf_range(-14, 14))
				m.box(q + Vector3(-0.6, -0.3, -2.5), q + Vector3(0.6, 0.9, 2.5), Color(0.52, 0.5, 0.47), true)
			for i in 14:
				var q := Vector3(rng.randf_range(-15, 15), 0, rng.randf_range(-15, 15))
				var c := Color(0.55, 0.56, 0.6) if i % 2 == 0 else Color(0.42, 0.3, 0.2)
				m.box(q + Vector3(-0.05, 0, -0.05), q + Vector3(0.05, rng.randf_range(0.8, 1.6), 0.05), c)
				m.box(q + Vector3(-0.25, 0.6, -0.04), q + Vector3(0.25, 0.7, 0.04), c)
			_finish(root, m)
			for i in 6:
				var a := i * TAU / 6.0 + rng.randf_range(-0.3, 0.3)
				var r := rng.randf_range(6.0, 13.0)
				var w := DestructibleFactory.wall(rng.randf_range(4.0, 7.0), rng.randf_range(2.0, 3.5), "ruin", i)
				_place(root, w, Vector3(cos(a) * r, 0, sin(a) * r), a)
			for i in 5:
				var a := i * TAU / 5.0 + 0.3
				var pl := DestructibleFactory.pillar(rng.randf_range(3.0, 5.0), Color(0.6, 0.58, 0.54), Color(0.5, 0.48, 0.45), 0.5, true)
				_place(root, pl, Vector3(cos(a) * 9.0, 0, sin(a) * 9.0))
		"landmark_ancient_tree":
			var t := PropBuilder.make_tree("ancient", 2)
			t.scale = Vector3.ONE * 1.8
			_place(root, t, Vector3.ZERO)
			# 小祠
			m.box(Vector3(-1.5, 0, -12.5), Vector3(1.5, 0.9, -11.5), p["stone"], true)
			m.box(Vector3(-0.9, 0.9, -12.3), Vector3(0.9, 1.1, -11.7), Color(0.62, 0.14, 0.11))
			m.box(Vector3(-0.2, 1.1, -12.1), Vector3(0.2, 1.6, -11.9), VoxelGrid.glow(Color(1.0, 0.7, 0.3), 0.8))
			_finish(root, m)
			for sx in [-1.0, 1.0]:
				_place(root, DestructibleFactory.lantern(), Vector3(sx * 2.5, 0, -12))
		_:
			root.free()
			return null
	return root
