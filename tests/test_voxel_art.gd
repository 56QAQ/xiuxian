extends Node
## 体素美术测试：角色（发型 × 性别 × 服饰、兽耳/尾/角、眼型/花钿、随机外貌）、兵器、妖兽、性能预算。

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
	_ok(n == 36, "36 种组合")


func test_hair_springs_exist_and_hang() -> void:
	var expect := {"twin_tails": "hair_tail_l_0", "ponytail": "hair_pony_0", "long": "hair_back_0", "flowing": "hair_back_1_0"}
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
				var cv := CharacterBuilder.head_canvas(CharSpec.from(CharacterBuilder.appearance_with_defaults({"eye_style": es, "mark": mark, "brow_style": brow})))
				_ok(cv.count_solid() > 3000, "头部 %s/%s/%d 体素" % [es, mark, brow])
	var blink := CharacterBuilder.build({}).bone("head").get_node_or_null("Blink")
	_ok(blink != null, "眨眼贴片")
	if blink != null:
		blink.get_parent().get_parent().get_parent().get_parent().free()


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


func test_build_time_budget() -> void:
	# 预热（脚本/材质加载）
	CharacterBuilder.build({}).free()
	var times: Array[float] = []
	for i in 3:
		VoxMesh.clear_cache()
		var t0 := Time.get_ticks_usec()
		var rig := CharacterBuilder.build({})
		times.append((Time.get_ticks_usec() - t0) / 1000.0)
		rig.free()
	times.sort()
	var med := times[1]
	print("    角色生成（无缓存）中位数 %.1f ms：%s" % [med, str(times)])
	_ok(med < 80.0, "单个角色生成 < 80 ms（%.1f ms）" % med)
	var t1 := Time.get_ticks_usec()
	var rig2 := CharacterBuilder.build({})
	var cached := (Time.get_ticks_usec() - t1) / 1000.0
	rig2.free()
	_ok(cached < 15.0, "缓存命中生成 < 15 ms（%.1f ms）" % cached)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	var t2 := Time.get_ticks_usec()
	for i in 20:
		CharacterBuilder.build(CharacterBuilder.random_appearance(rng)).free()
	var crowd := (Time.get_ticks_usec() - t2) / 1000.0
	print("    20 个随机 NPC 共 %.0f ms" % crowd)
	_ok(crowd < 20 * 80.0, "20 个 NPC 平均 < 80 ms")
