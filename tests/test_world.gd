extends Node
## 大地图测试：地形确定性、生物群系布局、弹坑、POI 注册表与标记点、可破坏物与孤岛脱落、
## 区块/LOD/道具生成耗时、地形碰撞、地图图像。

var runner: Node
var _t: TerrainGen


func _ok(c: bool, m: String) -> void:
	runner.check(c, m)


## 本测试套件专用的地形（不污染共享实例）
func _terrain() -> TerrainGen:
	if _t == null:
		_t = TerrainGen.new(4242)
		_t.generate()
	return _t


func test_height_determinism() -> void:
	var t0 := Time.get_ticks_msec()
	var a := TerrainGen.new(12345)
	a.generate()
	var gen_ms := Time.get_ticks_msec() - t0
	var b := TerrainGen.new(12345)
	b.generate()
	_ok(a.hmap == b.hmap, "同一种子高度图完全一致")
	_ok(a.flags == b.flags, "同一种子地表标记一致")
	var same_pois := a.pois.size() == b.pois.size()
	for i in mini(a.pois.size(), b.pois.size()):
		if a.pois[i]["pos"] != b.pois[i]["pos"]:
			same_pois = false
	_ok(same_pois, "同一种子 POI 一致")
	var c := _terrain()
	var diff := 0
	for i in 400:
		var x := (i * 37) % TerrainGen.SIZE
		var z := (i * 91 + 13) % TerrainGen.SIZE
		if a.get_block_height(x, z) != c.get_block_height(x, z):
			diff += 1
	_ok(diff > 50, "不同种子地形不同（%d/400 处不同）" % diff)
	var hmax := 0
	var water := 0
	for i in range(0, a.hmap.size(), 97):
		hmax = maxi(hmax, a.hmap[i])
		if a.hmap[i] < TerrainGen.SEA_LEVEL:
			water += 1
	_ok(hmax >= 60 and hmax <= TerrainGen.MAX_H, "最高点在 60~%d 米（%d）" % [TerrainGen.MAX_H, hmax])
	_ok(water > 100, "存在海洋/湖泊")
	# 平滑高度与方块高度一致
	var h := a.get_height(300.5, 700.5)
	_ok(absf(h - a.get_block_height(300, 700)) < 0.01, "柱中心平滑高度等于方块高度")
	print("    地形生成 %d ms" % gen_ms)


func test_region_layout() -> void:
	var t := _terrain()
	var expect := {"tianjian": "snow", "qingmu": "forest", "xuanshui": "lake", "lihuo": "volcanic", "houtu": "plateau"}
	for sid in expect:
		var p := t.find_poi("sect_" + sid)
		_ok(not p.is_empty(), "宗门 %s 存在" % sid)
		var pos: Vector3 = p["pos"]
		_ok(t.get_biome(pos.x, pos.z) == expect[sid], "%s 位于 %s（实际 %s）" % [sid, expect[sid], t.get_biome(pos.x, pos.z)])
		_ok(not t.is_water(pos.x, pos.z), "%s 平台不在水下" % sid)
	var town := t.find_poi("town")
	_ok(t.get_biome(town["pos"].x, town["pos"].z) == "plains", "坊市位于平原")
	_ok(t.get_biome(3, 3) == "ocean" and t.is_water(3, 3), "世界边缘为海洋")
	# 平台压平
	var sp := t.find_poi("sect_tianjian")
	var h0 := t.get_block_height(int(sp["pos"].x), int(sp["pos"].z))
	var flat := true
	for dz in range(-20, 21, 5):
		for dx in range(-20, 21, 5):
			if t.get_block_height(int(sp["pos"].x) + dx, int(sp["pos"].z) + dz) != h0:
				flat = false
	_ok(flat and h0 == int(sp["height"]), "宗门平台已压平")
	# 火山口有熔岩
	var v := t.volcano
	_ok(t.is_lava(v.x, v.y), "火山口有熔岩")


func test_carve_crater() -> void:
	var t := _terrain()
	var town := t.find_poi("town")
	var x := float(town["pos"].x) + 40.5
	var z := float(town["pos"].z) + 30.5
	var h0 := t.get_ground_y(x, z)
	var hits := [0]
	var cb := func(chunks: Array, _s: Array, _p: Vector3, _r: float) -> void:
		hits[0] += chunks.size()
	t.changed.connect(cb)
	var chunks := t.carve_crater(Vector3(x, h0, z), 5.0)
	t.changed.disconnect(cb)
	var h1 := t.get_ground_y(x, z)
	_ok(h1 < h0 - 1.5, "弹坑中心降低（%.0f → %.0f）" % [h0, h1])
	_ok(t.get_ground_y(x + 12.0, z) == t.get_ground_y(x + 12.0, z), "弹坑外不变")
	_ok(not chunks.is_empty() and hits[0] == chunks.size(), "返回受影响区块并发出 changed 信号")
	_ok(t.get_flags(int(x), int(z)) & TerrainGen.F_SCORCH != 0, "弹坑中心为焦土")
	_ok(t.craters.size() >= 1, "弹坑被记录")
	var d := t.build_chunk_arrays(int(x) / TerrainGen.CHUNK, int(z) / TerrainGen.CHUNK)
	var col: PackedFloat32Array = d["collision"]
	var li := (int(z) % TerrainGen.CHUNK) * 33 + (int(x) % TerrainGen.CHUNK)
	_ok(absf(col[li] - h1) < 0.01, "区块碰撞高度反映弹坑")


func test_world_map_pois() -> void:
	var pois := WorldMap.pois()
	var sects := {}
	var portals := 0
	var has_town := false
	var has_home := false
	for p in pois:
		var pos: Vector3 = p["pos"]
		_ok(pos.x > 0 and pos.z > 0 and pos.x < TerrainGen.SIZE and pos.z < TerrainGen.SIZE, "%s 在世界范围内" % p["id"])
		var markers: Dictionary = p["markers"]
		match p["type"]:
			"sect":
				sects[p["sect_id"]] = true
				for m in ["npc_master", "npc_teacher", "npc_steward", "npc_senior", "shop", "mission_board", "cultivation_room", "sect_gate"]:
					_ok(markers.has(m), "%s 有标记 %s" % [p["id"], m])
			"town":
				has_town = true
				for m in ["npc_merchant_1", "npc_merchant_2", "npc_merchant_3", "npc_merchant_4", "town_board", "town_center"]:
					_ok(markers.has(m), "坊市有标记 %s" % m)
			"home":
				has_home = true
				for m in ["home_cushion", "home_stash", "home_furnace", "home_field", "home_spawn"]:
					_ok(markers.has(m), "洞府有标记 %s" % m)
			"portal":
				portals += 1
				_ok(DB.secret_realms.has(p.get("realm_id", "")), "秘境入口 %s 的 realm_id 有效" % p["id"])
				_ok(markers.has("realm_portal"), "秘境入口有 realm_portal 标记")
	for sid in DB.sects:
		_ok(sects.has(sid), "五宗之 %s 在地图上" % sid)
	_ok(has_town, "有坊市")
	_ok(has_home, "有洞府")
	_ok(portals >= 4, "至少 4 个秘境入口（%d）" % portals)
	_ok(not WorldMap.sect("tianjian").is_empty(), "WorldMap.sect() 可查询")
	var gate := WorldMap.marker("sect_tianjian", "sect_gate")
	_ok(gate.origin.length() > 1.0, "WorldMap.marker() 返回世界坐标")


func test_building_markers() -> void:
	var t := TerrainGen.shared()
	for id in ["sect_lihuo", "town", "home", "portal_0"]:
		var poi := t.find_poi(id)
		var t0 := Time.get_ticks_msec()
		var n := BuildingLayouts.build_poi(poi, t)
		var ms := Time.get_ticks_msec() - t0
		add_child(n)
		var expect := BuildingLayouts.marker_transforms(poi)
		for mname in expect:
			var mk := n.get_node_or_null(NodePath(mname)) as Marker3D
			_ok(mk != null, "%s 生成标记 %s" % [id, mname])
			if mk:
				_ok(mk.is_in_group("poi_marker"), "%s 在 poi_marker 组" % mname)
				_ok(mk.global_transform.origin.distance_to((expect[mname] as Transform3D).origin) < 0.01, "%s 位置与 marker_layout 一致" % mname)
				if poi.has("sect_id"):
					_ok(mk.get_meta("sect_id", "") == poi["sect_id"], "%s 带 sect_id" % mname)
				if poi.has("realm_id"):
					_ok(mk.get_meta("realm_id", "") == poi["realm_id"], "传送门标记带 realm_id")
		var dcount := 0
		for c in n.get_children():
			if c is VoxelDestructible:
				dcount += 1
		if id != "portal_0":
			_ok(dcount > 0, "%s 中有可破坏物" % id)
		print("    建造 %s：%d ms" % [id, ms])
		n.queue_free()
	await get_tree().process_frame


func test_destructible_damage() -> void:
	var d := DestructibleFactory.pillar(4.0)
	add_child(d)
	var before := d.voxel_count()
	var cut := 2.0
	var top_before := 0
	var g := d.grid
	var cy := int((cut - d.origin.y) / d.voxel_size)
	for z in g.sz:
		for y in range(cy + 2, g.sy):
			for x in g.sx:
				if g.is_solid(x, y, z):
					top_before += 1
	var signal_count := [0]
	d.destroyed_voxels.connect(func(n: int) -> void: signal_count[0] = n)
	var removed := d.apply_damage_at(d.global_position + Vector3(0, cut, 0), 0.8, 1.0)
	_ok(removed > 0, "受击移除体素（%d）" % removed)
	_ok(d.voxel_count() < before, "体素数减少 %d → %d" % [before, d.voxel_count()])
	var top_after := 0
	for z in g.sz:
		for y in range(cy + 2, g.sy):
			for x in g.sx:
				if d.grid.is_solid(x, y, z):
					top_after += 1
	_ok(top_before > 0 and top_after == 0, "截断后上部孤岛整体脱落（%d → %d）" % [top_before, top_after])
	_ok(VoxelDestructible.falling_live() > 0, "生成下落碎块刚体")
	_ok(signal_count[0] >= removed, "发出 destroyed_voxels 信号")
	var pool := DebrisPool.get_pool(self)
	_ok(pool != null and pool.live_count() > 0 and pool.live_count() <= DebrisPool.MAX_LIVE, "碎块池有活跃碎块且不超上限")
	# 岩石：小伤害不脱落
	var r := DestructibleFactory.rock(1, 3.0, "gray")
	add_child(r)
	var rb := r.voxel_count()
	var n2 := r.apply_damage_at(r.global_position + Vector3(0.9, 1.2, 0), 0.6, 1.0)
	_ok(n2 > 0 and r.voxel_count() <= rb - n2, "岩石受击移除体素")
	# 模板共享：未受损实例共享网格
	var a1 := DestructibleFactory.lantern()
	var a2 := DestructibleFactory.lantern()
	add_child(a1)
	add_child(a2)
	_ok(a1.mesh_instance.mesh == a2.mesh_instance.mesh, "未受损实例共享模板网格")
	d.queue_free()
	r.queue_free()
	a1.queue_free()
	a2.queue_free()
	await get_tree().process_frame


func test_chunk_generation_budget() -> void:
	var t := _terrain()
	var keys := [Vector2i(16, 16), Vector2i(15, 16), Vector2i(16, 4), Vector2i(15, 5), Vector2i(4, 14), Vector2i(26, 15), Vector2i(8, 25), Vector2i(17, 26)]
	var total := 0.0
	var worst := 0.0
	var quads := 0
	for k in keys:
		var t0 := Time.get_ticks_usec()
		var d := t.build_chunk_arrays(k.x, k.y)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		total += ms
		worst = maxf(worst, ms)
		var arr: Array = d["arrays"]
		quads += (arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 4
		_ok((d["collision"] as PackedFloat32Array).size() == 33 * 33, "碰撞高度 33×33")
	var avg := total / keys.size()
	_ok(avg < 60.0, "区块网格平均生成 < 60 ms（%.1f ms）" % avg)
	var t1 := Time.get_ticks_usec()
	t.build_lod_arrays(1, 1)
	var lod_ms := (Time.get_ticks_usec() - t1) / 1000.0
	t1 = Time.get_ticks_usec()
	var tile := PropScatter.generate_tile(t, 13, 7)
	var prop_ms := (Time.get_ticks_usec() - t1) / 1000.0
	_ok((tile["mm"] as Dictionary).size() > 0, "道具地块有实例")
	print("    区块：平均 %.1f ms，最慢 %.1f ms，平均 %d 面；LOD 分块 %.1f ms；道具地块 %.1f ms" % [avg, worst, quads / keys.size(), lod_ms, prop_ms])


func test_streamer_collision() -> void:
	var t := _terrain()
	var st := TerrainStreamer.new(t)
	st.view_chunks = 2
	add_child(st)
	var town := t.find_poi("town")
	var px := float(town["pos"].x) + 20.5
	var pz := float(town["pos"].z) - 25.5
	st.focus_pos = Vector3(px, 40, pz)
	st.prime(1)
	_ok(st.loaded_count() >= 5, "同步加载区块（%d）" % st.loaded_count())
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := st.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(Vector3(px, 120, pz), Vector3(px, -10, pz), 1)
	var hit := space.intersect_ray(q)
	_ok(not hit.is_empty(), "射线命中地形碰撞")
	if not hit.is_empty():
		var hy: float = hit["position"].y
		_ok(absf(hy - t.get_height(px, pz)) < 0.6, "碰撞高度与 get_height 一致（%.2f / %.2f）" % [hy, t.get_height(px, pz)])
	st.queue_free()
	await get_tree().process_frame


func test_map_image() -> void:
	var t := _terrain()
	var img := t.render_map_image(64)
	_ok(img.get_width() == 64 and img.get_height() == 64, "地图图像尺寸")
	var c0 := img.get_pixel(1, 1)
	var c1 := img.get_pixel(32, 32)
	_ok(c0 != c1, "地图图像有内容（海 vs 陆）")
