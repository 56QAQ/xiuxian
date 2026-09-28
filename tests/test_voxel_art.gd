extends Node
## 体素美术测试：角色（发型 × 性别 × 服饰、兽耳/尾/角、眼型/花钿、随机外貌）、兵器、妖兽、
## 材质通道、LOD、异步构建、性能与三角形预算。

var runner: Node


func _ok(c: bool, m: String) -> void:
	runner.check(c, m)


func _has_all_bones(rig: CharacterRig) -> bool:
	for b in CharacterRig.BONES:
		if rig.bone(b) == null:
			return false
	return true


func _step(rig: CharacterRig, seconds: float, dt: float = 1.0 / 30.0) -> void:
	var t := 0.0
	while t < seconds:
		rig._process(dt)
		t += dt


## 统计三角形：lod 0 = 近景实例，1 = 远景实例（visibility_range_begin > 0）
func _tris(n: Node, lod: int) -> int:
	var t := 0
	if n is MeshInstance3D and n.name != "Blink":
		var mi := n as MeshInstance3D
		var is_lod1 := mi.visibility_range_begin > 0.0
		if mi.mesh != null and (lod == 1) == is_lod1:
			for si in mi.mesh.get_surface_count():
				t += (mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	for c in n.get_children():
		t += _tris(c, lod)
	return t


func test_vox_mesh() -> void:
	# 单体素：6 面 24 顶点
	var cv := VoxCanvas.new(Vector3i(0, 0, 0), Vector3i(2, 2, 2))
	cv.put(1, 1, 1, Color.RED)
	var m := VoxMesh.build_one(cv, 1.0)
	_ok(m.surface_get_array_len(0) == 24, "单体素 24 顶点")
	# 同色竖柱（1×4×1）：侧面沿 Y 合并 → 4 个侧面 + 顶 + 底 = 6 个四边形
	var col := VoxCanvas.new(Vector3i(0, 0, 0), Vector3i(0, 3, 0))
	col.box(Vector3i(0, 0, 0), Vector3i(0, 3, 0), Color.BLUE)
	_ok(VoxMesh.build_one(col, 1.0).surface_get_array_len(0) == 24, "竖柱侧面合并")
	# 异色竖柱不合并
	col.put(0, 1, 0, Color.GREEN)
	_ok(VoxMesh.build_one(col, 1.0).surface_get_array_len(0) > 24, "异色不合并")
	# 二维合并：同色平板 4×4×1 → 6 个四边形
	var slab := VoxCanvas.new(Vector3i(0, 0, 0), Vector3i(3, 3, 0))
	slab.box(Vector3i(0, 0, 0), Vector3i(3, 3, 0), Color.WHITE)
	_ok(VoxMesh.build_one(slab, 1.0).surface_get_array_len(0) == 24, "平板二维合并")
	# 包围盒尺寸：网格 AABB 与体素范围一致（含 shift）
	var b := VoxCanvas.new(Vector3i(-3, 0, -3), Vector3i(3, 5, 3))
	b.shift = Vector3(-0.5, 0, -0.5)
	b.box(Vector3i(-3, 0, -3), Vector3i(3, 5, 3), Color.WHITE, 0.1)
	var aabb := VoxMesh.build_one(b, 1.0).get_aabb()
	_ok(aabb.position.is_equal_approx(Vector3(-3.5, 0, -3.5)) and aabb.size.is_equal_approx(Vector3(7, 6, 7)), "奇数宽度半格居中 %s" % str(aabb))
	# 缓存
	var k1 := VoxMesh.cached("test|a", func() -> ArrayMesh: return VoxMesh.build_one(cv, 1.0))
	var k2 := VoxMesh.cached("test|a", func() -> ArrayMesh: return ArrayMesh.new())
	_ok(k1 == k2, "网格缓存命中")
	# 降采样：2×2×2 实心块 → 1 体素
	var ds := VoxCanvas.new(Vector3i(0, 0, 0), Vector3i(3, 3, 3))
	ds.box(Vector3i(0, 0, 0), Vector3i(1, 1, 1), Color.RED)
	var half := ds.downsample(2)
	_ok(half.count_solid() == 1, "LOD 降采样 %d" % half.count_solid())


func test_material_channel() -> void:
	# 属性字节 = 材质 << 4 | 发光等级，原样进入顶点色 alpha
	var cv := VoxCanvas.new(Vector3i(0, 0, 0), Vector3i(2, 0, 0))
	cv.set_mat(VoxCanvas.M_GOLD)
	cv.put(0, 0, 0, Color(0.9, 0.7, 0.2))
	cv.putm(1, 0, 0, VoxCanvas.glow(Color(1, 0.2, 0.1), 1.0), VoxCanvas.M_GEM)
	cv.set_mat(VoxCanvas.M_SKIN)
	cv.put(2, 0, 0, Color(1, 0.8, 0.7))
	_ok(cv.get_mat(0, 0, 0) == VoxCanvas.M_GOLD, "金饰材质")
	_ok(cv.get_mat(1, 0, 0) == VoxCanvas.M_GEM, "宝石材质")
	_ok(cv.get_mat(2, 0, 0) == VoxCanvas.M_SKIN, "皮肤材质")
	_ok((cv.get_raw(1, 0, 0) & 15) == 15, "发光等级")
	var arr := VoxMesh.mesh_arrays([cv], 1.0)
	var cols: PackedColorArray = arr[Mesh.ARRAY_COLOR]
	var mats := {}
	for c in cols:
		mats[int(round(c.a * 255.0)) >> 4] = true
	_ok(mats.has(VoxCanvas.M_GOLD) and mats.has(VoxCanvas.M_GEM) and mats.has(VoxCanvas.M_SKIN), "顶点色 alpha 带材质 %s" % str(mats.keys()))
	# 角色网格使用角色着色器；实例参数照常可用
	var rig := CharacterBuilder.build({})
	add_child(rig)
	var mi: MeshInstance3D = rig.meshes[0]
	var mat := mi.mesh.surface_get_material(0) as ShaderMaterial
	_ok(mat != null and mat.shader.resource_path.ends_with("voxel_char.gdshader"), "角色着色器")
	rig.flash(1.0, Color.RED)
	rig.set_dissolve(0.3)
	rig.set_tint(Color.BLUE, 0.5)
	_step(rig, 0.1)
	rig.queue_free()


func test_hairstyle_gender_outfit_matrix() -> void:
	var n := 0
	for st in CharacterBuilder.HAIR_STYLES:
		for g in ["female", "male"]:
			for o in CharacterBuilder.OUTFITS:
				var rig := CharacterBuilder.build({"hair_style": st, "gender": g, "outfit": o})
				add_child(rig)
				_ok(rig is CharacterRig, "%s/%s/%s 返回 CharacterRig" % [st, g, o])
				_ok(_has_all_bones(rig), "%s/%s/%s 骨骼齐全" % [st, g, o])
				_ok(rig.meshes.size() >= 14, "%s/%s/%s 网格数量 %d" % [st, g, o, rig.meshes.size()])
				_step(rig, 0.2)
				rig.queue_free()
				n += 1
	_ok(n == CharacterBuilder.HAIR_STYLES.size() * 6, "%d 种组合" % n)


func test_skeleton_metric_layout() -> void:
	# 2× 精度后骨骼位置（米）与旧版一致：动画、碰撞、武器握点不受影响
	var rig := CharacterBuilder.build({"gender": "female", "build": 0.4})
	var expect := {"hips": Vector3(0, 0.75, 0), "spine": Vector3(0, 0.075, 0), "head": Vector3(0, 0.45, 0),
		"arm_r": Vector3(0.25, 0.4, 0), "forearm_r": Vector3(0, -0.3, 0), "hand_r": Vector3(0, -0.275, 0),
		"leg_r": Vector3(0.1, 0, 0), "shin_r": Vector3(0, -0.375, 0)}
	for b in expect:
		var p: Vector3 = rig.bone(b).position
		_ok(p.is_equal_approx(expect[b]), "骨骼 %s 位置 %s" % [b, str(p)])
	var male := CharacterBuilder.build({"gender": "male", "build": 0.7})
	_ok(male.bone("arm_r").position.is_equal_approx(Vector3(0.325, 0.4, 0)), "男性肩宽 %s" % str(male.bone("arm_r").position))
	_ok(male.bone("leg_r").position.is_equal_approx(Vector3(0.1125, 0, 0)), "男性腿距 %s" % str(male.bone("leg_r").position))
	rig.free()
	male.free()


func test_hair_springs_exist_and_hang() -> void:
	var expect := {"twin_tails": "hair_tail_l_0", "ponytail": "hair_pony_0", "long": "hair_back_0", "flowing": "hair_back_1_0", "braid": "hair_braid_0", "double_bun": "hair_ribbon_l"}
	for st in expect:
		var rig := CharacterBuilder.build({"hair_style": st})
		add_child(rig)
		var b: Node3D = rig.bone(expect[st])
		_ok(b != null, "%s 有弹簧发束 %s" % [st, expect[st]])
		if b != null:
			var rest_basis: Basis = b.basis
			_step(rig, 1.5)
			# 静止时应基本保持在静止方向（不乱甩、不外翘）
			var ang := rad_to_deg((rest_basis * Vector3.DOWN).angle_to(b.basis * Vector3.DOWN))
			_ok(ang < 25.0, "%s 静止下垂偏差 %.1f°" % [st, ang])
		rig.queue_free()
	# 裙甲随腿摆动：前片在迈步时向前张开
	var ar := CharacterBuilder.build({"outfit": "armor"})
	add_child(ar)
	_ok(ar.bone("cloth_front") != null, "战甲前裙甲")
	ar.set_locomotion(Vector3(0, 0, -4.0), true, false, false)
	_step(ar, 1.0)
	ar.queue_free()


func test_ears_tails_horns_marks_eyes() -> void:
	for ears in CharacterBuilder.EARS:
		for g in ["female", "male"]:
			var rig := CharacterBuilder.build({"ears": ears, "gender": g, "tail": "fox", "horns": "dragon"})
			add_child(rig)
			_ok(_has_all_bones(rig), "耳型 %s 骨骼齐全" % ears)
			if ears == "fox" or ears == "cat":
				_ok(rig.bone("ear_l") != null and rig.bone("ear_r") != null, "%s 兽耳弹簧骨骼" % ears)
			_ok(rig.bone("tail_0") != null and rig.bone("tail_3") != null, "狐尾弹簧链")
			_step(rig, 0.2)
			rig.queue_free()
	for es in CharacterBuilder.EYE_STYLES:
		for mark in CharacterBuilder.MARKS:
			for brow in 3:
				for g in ["female", "male"]:
					var s := CharSpec.from(CharacterBuilder.appearance_with_defaults({"eye_style": es, "mark": mark, "brow_style": brow, "gender": g}))
					var cv := CharacterBuilder.head_canvas(s)
					_ok(cv.count_solid() > 24000, "头部 %s/%s/%d/%s 体素 %d" % [es, mark, brow, g, cv.count_solid()])
					# 眼睛：两眼都有眼睛材质（虹膜/高光）
					var eye_l := 0
					var eye_r := 0
					for x in range(-16, 16):
						for y in range(10, 22):
							if cv.get_mat(x, y, -16) == VoxCanvas.M_EYE:
								if x < 0:
									eye_l += 1
								else:
									eye_r += 1
					_ok(eye_l >= 20 and eye_l == eye_r, "%s/%s 双眼对称 %d/%d" % [es, g, eye_l, eye_r])
	var blink := CharacterBuilder.build({}).bone("head").get_node_or_null("Blink")
	_ok(blink != null, "眨眼贴片")
	if blink != null:
		blink.get_parent().get_parent().get_parent().get_parent().free()


func test_appearance_json_values_supported() -> void:
	# data/appearance.json 中的每个可选值都能构建（捏人界面据此生成选项）
	var f := FileAccess.open("res://data/appearance.json", FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var lists := {"hair_styles": CharacterBuilder.HAIR_STYLES, "eye_styles": CharacterBuilder.EYE_STYLES, "marks": CharacterBuilder.MARKS, "ears": CharacterBuilder.EARS, "outfits": CharacterBuilder.OUTFITS}
	for k in lists:
		for e in d[k]:
			_ok((lists[k] as Array).has(str(e["id"])), "%s 值 %s 受支持" % [k, str(e["id"])])


func test_random_appearance() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var males := 0
	var beast_ears_m := 0
	for i in 40:
		var a := CharacterBuilder.random_appearance(rng)
		_ok(CharacterBuilder.HAIR_STYLES.has(str(a["hair_style"])), "随机发型合法")
		_ok(CharacterBuilder.OUTFITS.has(str(a["outfit"])), "随机服饰合法")
		_ok(CharacterBuilder.EARS.has(str(a["ears"])), "随机耳型合法")
		_ok(CharacterBuilder.EYE_STYLES.has(str(a["eye_style"])), "随机眼型合法")
		_ok(CharacterBuilder.MARKS.has(str(a["mark"])), "随机花钿合法")
		_ok((a["outfit_colors"] as Array).size() == 3, "服饰三色")
		for k in CharacterBuilder.DEFAULT_APPEARANCE:
			_ok(a.has(k), "随机外貌含字段 %s" % k)
		if a["gender"] == "male":
			males += 1
			if a["ears"] != "human":
				beast_ears_m += 1
	_ok(males > 8 and males < 32, "性别分布 %d/40" % males)
	_ok(beast_ears_m <= 10, "男性多为人耳（兽耳 %d）" % beast_ears_m)
	var r1 := RandomNumberGenerator.new()
	r1.seed = 7
	var r2 := RandomNumberGenerator.new()
	r2.seed = 7
	_ok(CharacterBuilder.random_appearance(r1, "female") == CharacterBuilder.random_appearance(r2, "female"), "同种子结果一致")
	var r3 := RandomNumberGenerator.new()
	r3.seed = 99
	_ok(CharacterBuilder.random_appearance(r3, "male")["gender"] == "male", "指定性别")
	for i in 6:
		var rig := CharacterBuilder.build(CharacterBuilder.random_appearance(rng))
		_ok(_has_all_bones(rig), "随机 NPC 骨骼齐全")
		rig.free()


func test_weapons() -> void:
	var visuals: Array = [
		{"kind": "sword"}, {"kind": "saber"}, {"kind": "spear"}, {"kind": "fist"},
		{"kind": "sword", "glow": "fire", "detail": 2}, {"kind": "saber", "glow": "water", "detail": 0},
		{"kind": "spear", "flag": "#c81e1e", "glow": "fire"}, {"kind": "spear", "flag": "#2040c0"},
		{"kind": "fist", "guard": "#c0c4cc", "glow": "metal"}, {"kind": "sword", "grade": 5},
	]
	for id in ["sword_iron", "sword_green", "saber_iron", "spear_iron", "flag_spear_fire", "fist_wraps"]:
		visuals.append(DB.item(id)["weapon"]["visual"])
	for v in visuals:
		var w := WeaponBuilder.build(v)
		_ok(w is Node3D, "兵器 %s" % str(v))
		_ok(float(w.get_meta("tip_length", 0.0)) > 0.05, "tip_length %s" % str(v))
		var has_mesh := false
		for c in w.get_children():
			if c is MeshInstance3D and (c as MeshInstance3D).mesh.get_surface_count() > 0:
				has_mesh = true
		_ok(has_mesh, "兵器有网格 %s" % str(v))
		if str(v.get("kind", "")) == "spear":
			_ok(float(w.get_meta("tip_length")) > 1.0, "枪长")
		if v.has("flag"):
			_ok(w.get_node_or_null("Banner") != null, "旗面")
		w.free()
	# 刃长（米）与旧版一致：剑 length 36（旧体素）→ (36+6)×0.025
	var sw := WeaponBuilder.build({"kind": "sword", "length": 36})
	_ok(is_equal_approx(float(sw.get_meta("tip_length")), 42 * 0.025), "剑尖距离 %.3f" % float(sw.get_meta("tip_length")))
	sw.free()
	# 挂接：拳套挂两只手，其它挂右手并清空左手
	var rig := CharacterBuilder.build({}, {"weapon": {"kind": "fist"}})
	add_child(rig)
	_ok(rig.stance == "fist", "拳套持械姿势")
	var att_l := 0
	var att_r := 0
	for c in rig.bone("hand_l").get_children():
		if c.has_meta("attachment"):
			att_l += 1
	for c in rig.bone("hand_r").get_children():
		if c.has_meta("attachment"):
			att_r += 1
	_ok(att_l == 1 and att_r == 1, "拳套左右手各一只")
	WeaponBuilder.attach_to_rig(rig, {"kind": "spear", "flag": "#c81e1e", "glow": "fire"})
	_ok(rig.stance == "spear", "换枪后持械姿势")
	_step(rig, 0.3)
	_ok(rig.weapon_tip("r").distance_to(rig.bone("hand_r").global_position) > 1.0, "枪尖位置")
	for kind in ["sword", "saber", "spear", "fist"]:
		_ok(not AnimLib.stance_pose(kind).is_empty(), "持械姿势 %s" % kind)
	rig.queue_free()
	# 角色构建时带武器：武器挂在右手
	var r2 := CharacterBuilder.build({}, {"weapon": {"kind": "spear", "flag": "#c81e1e", "glow": "fire"}})
	var att := 0
	for c in r2.bone("hand_r").get_children():
		if c.has_meta("attachment"):
			att += 1
	_ok(att == 1, "构建时挂武器")
	r2.free()


func test_beasts() -> void:
	for model in BeastBuilder.MODELS:
		var rig := BeastBuilder.build(model, [], 1.2)
		add_child(rig)
		_ok(rig is BeastRig and rig is CharacterRig, "%s 是 BeastRig" % model)
		_ok(rig.meshes.size() >= 5, "%s 网格 %d" % [model, rig.meshes.size()])
		_ok(rig.bone("hips") != null, "%s 有 hips 根骨骼" % model)
		_ok(is_equal_approx(rig.scale.x, 1.2), "%s 体型缩放" % model)
		if model == "golem":
			_ok(_has_all_bones(rig), "石傀为人形骨骼")
		# 移动：慢走 / 小跑 / 快跑 / 腾空
		for v in [Vector3(0, 0, -1.0), Vector3(0, 0, -4.0), Vector3(0, 0, -10.0)]:
			rig.set_locomotion(v, true, false, false)
			_step(rig, 0.3)
		rig.set_locomotion(Vector3(0, 2, -5), false, false, false)
		_step(rig, 0.2)
		rig.set_locomotion(Vector3.ZERO, true, false, false)
		_step(rig, 0.2)
		# 剪辑：攻击剪辑在出手帧发出 hit
		for clip in BeastRig.CLIP_NAMES:
			var hits := [0]
			var cb := func(ev: String) -> void:
				if ev == "hit":
					hits[0] += 1
			rig.anim_event.connect(cb)
			var dur := rig.play(clip)
			_ok(dur > 0.1, "%s 剪辑 %s 时长" % [model, clip])
			_step(rig, dur + 0.3)
			rig.anim_event.disconnect(cb)
			if clip in ["bite", "pounce", "charge", "slam", "spit"]:
				_ok(hits[0] == 1, "%s/%s 发出一次 hit（%d）" % [model, clip, hits[0]])
				_ok(BeastRig.hit_time(rig.body, clip) > 0.0 or model == "golem", "%s/%s hit 时间" % [model, clip])
		# 数据中的攻击名（gore / rock）
		for extra in ["gore", "rock"]:
			_ok(rig.play(extra) > 0.1, "%s 别名 %s" % [model, extra])
			_step(rig, 0.1)
		rig.flash(1.0, Color.RED)
		rig.set_dissolve(0.3)
		rig.queue_free()
	# 死亡保持
	var w := BeastBuilder.build("wolf", ["#8a8a88", "#5a5a58", "#e8e0d0"], 1.0)
	add_child(w)
	var done := [false]
	w.action_finished.connect(func(n: String) -> void:
		if n == "death":
			done[0] = true)
	w.play("death")
	_step(w, 2.0)
	_ok(done[0], "死亡剪辑结束信号")
	_ok(w.is_playing(), "死亡保持最后姿势")
	w.queue_free()


func test_lod_and_triangle_budget() -> void:
	VoxMesh.finish_pending()
	var spear: Dictionary = {"kind": "spear", "flag": "#c81e1e", "glow": "fire", "length": 84}
	for a in [{}, {"outfit": "robe", "hair_style": "flowing"}, {"gender": "male", "outfit": "armor", "hair_style": "short"}]:
		var rig := CharacterBuilder.build(a, {"weapon": spear})
		VoxMesh.finish_pending()
		var t0 := _tris(rig, 0)
		var t1 := _tris(rig, 1)
		print("    %s 三角形 LOD0 %d / LOD1 %d" % [str(a), t0, t1])
		_ok(t0 > 20000 and t0 <= 120000, "LOD0 三角形预算 %d" % t0)
		_ok(t1 > 2000 and t1 <= 30000, "LOD1 三角形预算 %d" % t1)
		# 每个近景实例都有对应的远景实例（visibility range 切换）
		var n0 := 0
		var n1 := 0
		for m in rig.meshes:
			if m.name == "Blink":
				continue
			if m.visibility_range_begin > 0.0:
				n1 += 1
			elif m.visibility_range_end > 0.0:
				n0 += 1
		_ok(n0 > 10 and n0 == n1, "LOD 实例成对 %d/%d" % [n0, n1])
		rig.free()
	for model in BeastBuilder.MODELS:
		var b := BeastBuilder.build(model, [], 1.0)
		VoxMesh.finish_pending()
		var bt0 := _tris(b, 0)
		var bt1 := _tris(b, 1)
		_ok(bt0 > 1000 and bt0 <= 120000 and bt1 <= 30000 and bt1 > 0, "%s 三角形 %d / %d" % [model, bt0, bt1])
		b.free()
	# 界面预览：不挂远景实例
	var ui := CharacterBuilder.build({}, {}, {"lod": false})
	var any_lod := false
	for m in ui.meshes:
		if m.visibility_range_begin > 0.0 or m.visibility_range_end > 0.0:
			any_lod = true
	_ok(not any_lod, "预览角色无 LOD 切换")
	ui.free()


func test_build_async() -> void:
	VoxMesh.clear_cache()
	var app := {"hair_style": "braid", "outfit": "martial", "hair_color": "#3a5ad0"}
	var rig := CharacterBuilder.build_async(app, {"weapon": {"kind": "sword", "glow": "water"}})
	add_child(rig)
	_ok(_has_all_bones(rig), "异步：骨架立即可用")
	_ok(rig.play("sword_1") > 0.1, "异步：可立即播放剪辑")
	var ready := [false]
	rig.meshes_ready.connect(func() -> void: ready[0] = true)
	var frames := 0
	while rig.meshes_pending() and frames < 600:
		await get_tree().process_frame
		frames += 1
	_ok(not rig.meshes_pending() and ready[0], "异步：网格就绪（%d 帧）" % frames)
	_ok(rig.visible, "异步：就绪后显示")
	var filled := 0
	for m in rig.meshes:
		if m.mesh != null and m.mesh.get_surface_count() > 0:
			filled += 1
	_ok(filled >= 14, "异步：网格已填充 %d" % filled)
	# 同外貌的同步构建命中缓存
	var t0 := Time.get_ticks_usec()
	var r2 := CharacterBuilder.build(app)
	_ok((Time.get_ticks_usec() - t0) / 1000.0 < 20.0, "异步后同步构建命中缓存")
	r2.free()
	var b := BeastBuilder.build_async("wolf", [], 1.0)
	add_child(b)
	b.finish_meshes()
	_ok(b.visible and not b.meshes_pending(), "妖兽异步构建")
	rig.queue_free()
	b.queue_free()


func test_build_time_budget() -> void:
	# 预热（脚本/材质加载）
	CharacterBuilder.build({}).free()
	VoxMesh.finish_pending()
	var times: Array[float] = []
	for i in 3:
		VoxMesh.clear_cache()
		var t0 := Time.get_ticks_usec()
		var rig := CharacterBuilder.build({})
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
		rig.free()
	times.sort()
	var med := times[1]
	print("    角色生成（无缓存，%d 线程）中位数 %.1f ms：%s" % [OS.get_processor_count(), med, str(times)])
	# 目标 ≤ 150 ms（4 核空闲机器实测约 70~110 ms）；测试阈值留出机器负载余量
	_ok(med < 400.0, "单个角色生成 < 400 ms（%.1f ms）" % med)
	var t1 := Time.get_ticks_usec()
	var rig2 := CharacterBuilder.build({})
	var cached := (Time.get_ticks_usec() - t1) / 1000.0
	rig2.free()
	print("    缓存命中 %.1f ms" % cached)
	_ok(cached < 15.0, "缓存命中生成 < 15 ms（%.1f ms）" % cached)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var t2 := Time.get_ticks_usec()
	for i in 12:
		CharacterBuilder.build(CharacterBuilder.random_appearance(rng)).free()
	var crowd := (Time.get_ticks_usec() - t2) / 1000.0
	print("    12 个随机 NPC 共 %.0f ms" % crowd)
	_ok(crowd < 12 * 400.0, "12 个 NPC 平均 < 400 ms")
	VoxMesh.finish_pending()
