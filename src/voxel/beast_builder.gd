class_name BeastBuilder
## 妖兽体素模型生成。BeastBuilder.build(model, colors, size) -> BeastRig（继承 CharacterRig）。
## model：wolf 狼 / fox 狐 / boar 野猪 / bear 熊 / golem 石傀（人形骨骼）/ snake 蛇 / crane 鹤 / spider 蛛
## colors：[主色, 副色, 点缀色]（"#rrggbb"），缺省用各模型默认配色；size：整体缩放（1 = 标准体型）。
## 骨骼与剪辑见 BeastRig。网格按 (model, colors) 缓存，同种妖兽成群生成几乎零开销。

const VOXEL := 0.025
const MODELS: Array[String] = ["wolf", "fox", "boar", "golem", "bear", "snake", "crane", "spider"]

const DEFAULT_COLORS := {
	"wolf": ["#8a8a88", "#5a5a58", "#e8e0d0"],
	"fox": ["#e05a20", "#fff0e0", "#402010"],
	"boar": ["#5a4030", "#8a7060", "#e8e0c8"],
	"bear": ["#5a3a24", "#2e1e14", "#c8a070"],
	"golem": ["#8a8478", "#5a564e", "#60e0ff"],
	"snake": ["#3a8a4a", "#e8d890", "#f0c020"],
	"crane": ["#f4f2ee", "#1a1a1e", "#e02030"],
	"spider": ["#2a2228", "#6a2a3a", "#ff3040"],
}


static func build(model: String, colors: Array = [], size: float = 1.0) -> BeastRig:
	if not DEFAULT_COLORS.has(model):
		model = "wolf"
	var cols: Array = DEFAULT_COLORS[model].duplicate()
	for i in mini(colors.size(), 3):
		cols[i] = colors[i]
	var c1 := CharacterBuilder.col(cols[0], Color.GRAY)
	var c2 := CharacterBuilder.col(cols[1], Color.DIM_GRAY)
	var c3 := CharacterBuilder.col(cols[2], Color.WHITE)
	var key := "%s|%s" % [model, str(cols)]
	var rig := BeastRig.new()
	rig.name = "BeastRig"
	rig.model = model
	rig.voxel_size = VOXEL
	match model:
		"golem":
			rig.body = "humanoid"
			_golem(rig, c1, c2, c3, key)
		"snake":
			rig.body = "serpent"
			_snake(rig, c1, c2, c3, key)
		"crane":
			rig.body = "bird"
			_crane(rig, c1, c2, c3, key)
		"spider":
			rig.body = "spider"
			_spider(rig, c1, c2, c3, key)
		_:
			rig.body = "quad"
			_quad(rig, model, c1, c2, c3, key)
	rig.body_scale = maxf(size, 0.1)
	rig.scale = Vector3.ONE * rig.body_scale
	if rig.body == "humanoid":
		rig.stance = "fist"
	rig.setup()
	return rig


# ================================================================ 工具

static func _bone(parent: Node3D, bone_name: String, pos_vox: Vector3, rot_deg: Vector3 = Vector3.ZERO) -> Node3D:
	var n := Node3D.new()
	n.name = bone_name
	n.position = pos_vox * VOXEL
	n.rotation_degrees = rot_deg
	n.set_meta("bone", true)
	parent.add_child(n)
	return n


static func _mesh(bone: Node3D, key: String, maker: Callable, mirror: bool = false) -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Mesh"
	mi.mesh = VoxMesh.cached(key, maker)
	if mirror:
		mi.scale = Vector3(-1, 1, 1)
	bone.add_child(mi)


## 毛皮色：按高度分区（腹部浅、背部深），带细噪声与竖向毛丝
static func _fur(c_main: Color, c_back: Color, c_belly: Color, yrel: float, x: int, y: int, z: int, back_t: float = 0.45, belly_t: float = -0.4) -> Color:
	var h := VoxCanvas.h3(x, y, z)
	var c := c_main
	if yrel > back_t + float(h & 1) * 0.12:
		c = c_back
	elif yrel < belly_t - float((h >> 1) & 1) * 0.1:
		c = c_belly
	var k := 0.9 + 0.16 * float((h >> 2) & 3) / 3.0
	if ((x * 3 + z) & 7) == 0:
		k *= 0.9
	return VoxCanvas.tone(c, k)


## 带毛色分区的椭球
static func _blob(cv: VoxCanvas, c: Vector3, r: Vector3, cm: Color, cb: Color, cl: Color, back_t: float = 0.45, belly_t: float = -0.4) -> void:
	var lo := Vector3i((c - r).floor())
	var hi := Vector3i((c + r).ceil())
	for z in range(lo.z, hi.z + 1):
		for y in range(lo.y, hi.y + 1):
			for x in range(lo.x, hi.x + 1):
				var d := (Vector3(x + 0.5, y + 0.5, z + 0.5) - c) / r
				if d.length_squared() <= 1.0:
					cv.put(x, y, z, _fur(cm, cb, cl, d.y, x, y, z, back_t, belly_t))


## 圆柱段（沿 -Y）：从 y0 到 y1，半径 rx/rz 线性变化
static func _limb(cv: VoxCanvas, y0: int, y1: int, r0: Vector2, r1: Vector2, cm: Color, zoff0: float = 0.0, zoff1: float = 0.0) -> void:
	for y in range(y1, y0 + 1):
		var t := float(y0 - y) / float(maxi(y0 - y1, 1))
		var r := r0.lerp(r1, t)
		var zo := lerpf(zoff0, zoff1, t)
		for z in range(-int(ceil(r.y)) - 2, int(ceil(r.y)) + 3):
			for x in range(-int(ceil(r.x)) - 1, int(ceil(r.x)) + 1):
				var dx := (x + 0.5) / r.x
				var dz := (z + 0.5 - zo) / r.y
				if dx * dx + dz * dz <= 1.0:
					cv.put(x, y, z, VoxCanvas.tone(cm, 0.9 + 0.14 * float(VoxCanvas.h3(x, y, z) & 3) / 3.0))


## 背脊鬃毛：沿中线的一排参差尖刺（z0..z1），从 y0 起向上
static func _bristles(cv: VoxCanvas, y0: int, z0: int, z1: int, c: Color) -> void:
	for z in range(z0, z1):
		var h := VoxCanvas.h1(z * 3 + 1)
		var hh := 1 + h % 3
		if h % 5 == 0:
			continue
		for y in range(y0 - 2, y0 + hh):
			var top := y >= y0 + hh - 1
			cv.put(-1, y, z, VoxCanvas.tone(c, 1.15 if top else 0.9))
			if y < y0 + hh - 2:
				cv.put(0, y, z, VoxCanvas.tone(c, 0.85))
		# 向后倾的毛尖
		cv.put(-1, y0 + hh, z + 1, VoxCanvas.tone(c, 1.2))


static func _eye(cv: VoxCanvas, x: int, y: int, z: int, iris: Color, glow: float = 0.3) -> void:
	cv.put(x, y, z, VoxelGrid.glow(iris, glow))
	cv.put(x, y + 1, z, VoxCanvas.tone(iris, 0.5))


# ================================================================ 四足：狼 / 狐 / 野猪 / 熊

## 四足体型参数
static func _qspec(model: String) -> Dictionary:
	match model:
		"fox":
			return {"hip_y": 17, "upper": 7, "lower": 8, "body_len": 26, "rear_r": Vector3(5.5, 6, 8), "chest_r": Vector3(6, 7, 8), "leg_r": 2.0, "paw": Vector3(2.5, 2, 3),
				"neck_len": 6, "neck_r": 3.5, "neck_pitch": 24.0, "head_r": Vector3(5, 4.5, 4.5), "snout": Vector3(2.2, 2, 5), "ears": "fox", "tail": "fox", "stride": 1.0, "gallop": 5.5, "amp": 34.0, "wag": 22.0}
		"boar":
			return {"hip_y": 17, "upper": 7, "lower": 8, "body_len": 34, "rear_r": Vector3(8.5, 9.5, 11), "chest_r": Vector3(9.5, 11, 11), "leg_r": 2.3, "paw": Vector3(2.5, 2, 3),
				"neck_len": 5, "neck_r": 6.5, "neck_pitch": -6.0, "head_r": Vector3(5.5, 6, 7), "snout": Vector3(3.2, 3.0, 8), "ears": "small", "tail": "thin", "tusks": true, "mane": true, "stride": 1.1, "gallop": 5.0, "amp": 26.0, "wag": 30.0}
		"bear":
			return {"hip_y": 22, "upper": 10, "lower": 10, "body_len": 38, "rear_r": Vector3(10.5, 11.5, 12), "chest_r": Vector3(11.5, 12.5, 12), "leg_r": 4.0, "paw": Vector3(4.5, 3, 5),
				"neck_len": 8, "neck_r": 7.0, "neck_pitch": 4.0, "head_r": Vector3(7, 6.5, 6.5), "snout": Vector3(3.6, 3.2, 6), "muzzle": true, "ears": "round", "tail": "stub", "stride": 1.5, "gallop": 6.0, "amp": 26.0, "wag": 5.0}
	# 狼
	return {"hip_y": 24, "upper": 10, "lower": 11, "body_len": 32, "rear_r": Vector3(6.5, 7.5, 10), "chest_r": Vector3(7.5, 9.5, 10), "leg_r": 2.6, "paw": Vector3(3, 2, 4),
		"neck_len": 8, "neck_r": 5.0, "neck_pitch": 22.0, "head_r": Vector3(6.8, 6, 6), "snout": Vector3(3.0, 2.7, 7), "ears": "wolf", "tail": "bushy", "ruff": true, "stride": 1.4, "gallop": 6.5, "amp": 32.0, "wag": 16.0}


static func _quad(rig: BeastRig, model: String, c1: Color, c2: Color, c3: Color, key: String) -> void:
	var q := _qspec(model)
	rig.stride = q["stride"]
	rig.gallop_speed = q["gallop"]
	rig.leg_amp = q["amp"]
	rig.tail_wag = q["wag"]
	var L: int = q["body_len"]
	var upper: int = q["upper"]
	var lower: int = q["lower"]
	var rear_r: Vector3 = q["rear_r"]
	var chest_r: Vector3 = q["chest_r"]
	var belly := c3 if model != "boar" else c2
	var back := c2 if model != "boar" else VoxCanvas.tone(c1, 0.7)
	if model == "fox":
		back = VoxCanvas.tone(c1, 0.85)
		belly = c2
	if model == "bear":
		back = VoxCanvas.tone(c1, 0.8)
		belly = VoxCanvas.tone(c1, 0.9)
	var leg_y := upper + lower   # 腿关节高度（离地）
	# hips 在后髋关节上方 2 格；spine（前躯/肩）在其前方 L/2
	var hips := _bone(rig, "hips", Vector3(0, leg_y + 2, L * 0.3))
	var spine := _bone(hips, "spine", Vector3(0, 1, -L * 0.55))
	# 后躯
	_mesh(hips, "q_rear|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-14, -12, -22), Vector3i(13, 14, 14))
		_blob(cv, Vector3(0, 1.5, -2.0), rear_r, c1, back, belly)
		if model == "boar" and q.get("mane", false):
			_bristles(cv, int(rear_r.y) + 1, -16, 2, c2.darkened(0.35))
		return VoxMesh.build_one(cv, VOXEL))
	# 前躯（胸更深）
	_mesh(spine, "q_chest|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-15, -15, -14), Vector3i(14, 16, 18))
		_blob(cv, Vector3(0, 0.0, 2.0), chest_r, c1, back, belly)
		if q.get("ruff", false):
			# 狼：颈部厚毛领
			_blob(cv, Vector3(0, 2.5, -4.0), Vector3(chest_r.x + 1.2, chest_r.y * 0.85, 5.0), c1, back, belly, 0.55, -0.2)
		if model == "boar":
			_bristles(cv, int(chest_r.y) + 1, -10, 14, c2.darkened(0.4))
		if model == "bear":
			_blob(cv, Vector3(0, 5.0, 4.0), Vector3(chest_r.x * 0.8, 4.5, 7.0), c1, back, belly)
		return VoxMesh.build_one(cv, VOXEL))
	# 颈、头、颌
	var nl: int = q["neck_len"]
	var nr: float = q["neck_r"]
	var npitch: float = q.get("neck_pitch", 18.0)
	var neck := _bone(spine, "neck", Vector3(0, chest_r.y * 0.35, -chest_r.z * 0.55), Vector3(npitch, 0, 0))
	_mesh(neck, "q_neck|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-10, -10, -nl - 8), Vector3i(9, 10, 6))
		for i in nl + 3:
			var zc := -i + 2.0
			_blob(cv, Vector3(0, 0.0, zc), Vector3(nr, nr * 1.05, 2.2), c1, back, belly, 0.5, -0.45)
		return VoxMesh.build_one(cv, VOXEL))
	var hr: Vector3 = q["head_r"]
	var sn: Vector3 = q["snout"]
	var head := _bone(neck, "head", Vector3(0, 1, -nl - 1), Vector3(-npitch, 0, 0))
	var eye_col := Color("f0c040") if model != "boar" else Color("e04020")
	if model == "fox":
		eye_col = Color("ffb020")
	_mesh(head, "q_head|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-10, -9, -int(hr.z + sn.z) - 5), Vector3i(9, 10, 8))
		_blob(cv, Vector3(0, 0.5, -hr.z * 0.5), hr, c1, back, belly, 0.55, -0.5)
		# 吻部（上颌）
		var sz0 := -hr.z * 0.9
		for i in int(sn.z) + 1:
			var t := float(i) / sn.z
			var cz := sz0 - i
			var rr := Vector2(sn.x * (1.0 - t * 0.25), sn.y * (1.0 - t * 0.2))
			for y in range(-int(rr.y) - 1, int(rr.y) + 1):
				for x in range(-int(rr.x) - 1, int(rr.x) + 1):
					var dx := (x + 0.5) / rr.x
					var dy := (y + 0.5 + 0.8) / rr.y
					if dx * dx + dy * dy <= 1.0:
						var c := belly if (y < -1 and model != "boar") else c1
						if model == "boar":
							c = VoxCanvas.tone(c2, 0.9)
						elif q.get("muzzle", false):
							c = c3.lerp(c1, 0.25)
						cv.put(x, y, int(floor(cz)), VoxCanvas.tone(c, 0.92 + 0.1 * float(VoxCanvas.h3(x, y, i) & 1)))
		var tipz := int(floor(sz0 - sn.z))
		# 鼻头
		var nose := Color(0.1, 0.08, 0.08) if model != "boar" else Color("d8a0a0")
		cv.box(Vector3i(-1, -1, tipz - 1), Vector3i(0, 0, tipz), nose)
		if model == "boar":
			cv.box(Vector3i(-2, -2, tipz - 1), Vector3i(1, 1, tipz - 1), Color("c89090"))
			cv.put(-1, -1, tipz - 2, Color(0.25, 0.1, 0.1))
			cv.put(0, -1, tipz - 2, Color(0.25, 0.1, 0.1))
		# 眼（发光、带竖瞳）
		var ez := int(-hr.z * 0.85)
		var ex := int(hr.x * 0.55)
		for sd: int in [-1, 1]:
			var x := ex if sd > 0 else -ex - 1
			_eye(cv, x, 2, ez, eye_col, 0.45)
			cv.put(x + sd, 3, ez, VoxCanvas.tone(c1, 0.6))
		# 獠牙（野猪）
		if q.get("tusks", false):
			for sd: int in [-1, 1]:
				var tx := 3 if sd > 0 else -4
				var tusk := c3
				cv.box(Vector3i(tx, -2, tipz + 3), Vector3i(tx, 1, tipz + 3), tusk)
				cv.put(tx, 2, tipz + 2, tusk)
				cv.put(tx, 3, tipz + 2, tusk.darkened(0.1))
		return VoxMesh.build_one(cv, VOXEL))
	var jaw := _bone(head, "jaw", Vector3(0, -1.5, -hr.z * 0.8))
	_mesh(jaw, "q_jaw|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-5, -5, -int(sn.z) - 6), Vector3i(4, 2, 4))
		var jl := int(sn.z) + 1
		for i in jl:
			var w := int(ceil(sn.x * (1.0 - float(i) / jl * 0.35)))
			for x in range(-w, w):
				for y in range(-2, 0):
					cv.put(x, y, -i, VoxCanvas.tone(belly if model != "boar" else c2, 0.95))
			if i < jl - 1:
				# 牙
				cv.put(-w, 0, -i, Color(0.96, 0.94, 0.88) if i % 2 == 0 else Color(0.6, 0.2, 0.2))
				cv.put(w - 1, 0, -i, Color(0.96, 0.94, 0.88) if i % 2 == 0 else Color(0.6, 0.2, 0.2))
		# 舌
		cv.box(Vector3i(-1, -1, -jl + 2), Vector3i(0, -1, -1), Color("c05060"))
		return VoxMesh.build_one(cv, VOXEL))
	# 耳（弹簧）
	var ears: String = q["ears"]
	for sd: int in [-1, 1]:
		var e := Node3D.new()
		e.name = "ear_" + ("l" if sd < 0 else "r")
		e.position = Vector3(sd * hr.x * 0.55, hr.y * 0.9, -hr.z * 0.3) * VOXEL
		e.rotation_degrees = Vector3(-10, 0, -sd * 14)
		e.set_meta("spring_dir", Vector3.UP)
		e.set_meta("spring_stiffness", 0.3)
		e.set_meta("spring_limit", 15.0)
		e.set_meta("spring_length", 0.15)
		head.add_child(e)
		_mesh(e, "q_ear|" + key, func() -> ArrayMesh:
			var cv := VoxCanvas.new(Vector3i(-4, -1, -3), Vector3i(3, 9, 2))
			var h := 6
			var w := 3.0
			match ears:
				"fox":
					h = 8
					w = 3.6
				"small":
					h = 3
					w = 2.5
				"round":
					h = 3
					w = 2.6
			for y in range(0, h):
				var t := float(y) / h
				var hw := w * (1.0 - t) + 0.4
				if ears == "round":
					hw = w * sqrt(maxf(1.0 - pow(t * 1.1, 2.0), 0.05))
				for x in range(-4, 4):
					if absf(x + 0.5) <= hw:
						cv.put(x, y, 0, VoxCanvas.tone(c1 if t < 0.7 or model != "fox" else c3, 0.9))
						cv.put(x, y, 1, VoxCanvas.tone(c1, 0.85))
						if absf(x + 0.5) < hw - 1.0 and t < 0.7:
							cv.put(x, y, -1, belly.lerp(Color(1, 0.8, 0.8), 0.2) if model != "boar" else c2)
			return VoxMesh.build_one(cv, VOXEL), sd < 0)
	# 腿
	var lr: float = q["leg_r"]
	var paw: Vector3 = q["paw"]
	var legx_f := chest_r.x * 0.62
	var legx_b := rear_r.x * 0.62
	for spec in [["fl", spine, legx_f, -3.0, 1.0], ["fr", spine, legx_f, -3.0, 1.0], ["bl", hips, legx_b, -2.0, -1.0], ["br", hips, legx_b, -2.0, -1.0]]:
		var nm: String = spec[0]
		var parent: Node3D = spec[1]
		var sx := -1.0 if nm.ends_with("l") else 1.0
		var front := nm.begins_with("f")
		var ly: float = spec[3]
		var leg := _bone(parent, "leg_" + nm, Vector3(sx * float(spec[2]), ly, 1.0 if front else 0.0))
		var sh := _bone(leg, "shin_" + nm, Vector3(0, -upper, 0))
		var fr := front
		_mesh(leg, "q_up_%s|%s" % ["f" if fr else "b", key], func() -> ArrayMesh:
			var cv := VoxCanvas.new(Vector3i(-8, -upper - 3, -9), Vector3i(7, 8, 9))
			if fr:
				_limb(cv, 4, -upper, Vector2(lr * 1.35, lr * 1.5), Vector2(lr, lr), c1)
			else:
				# 后腿：大腿肌肉更粗、向前鼓
				_limb(cv, 5, -upper, Vector2(lr * 1.7, lr * 2.0), Vector2(lr, lr * 1.1), c1, -1.0, 1.5)
			return VoxMesh.build_one(cv, VOXEL), sx < 0)
		_mesh(sh, "q_lo_%s|%s" % ["f" if fr else "b", key], func() -> ArrayMesh:
			var cv := VoxCanvas.new(Vector3i(-7, -lower - 4, -9), Vector3i(6, 4, 7))
			_limb(cv, 2, -lower + 2, Vector2(lr * 0.95, lr * 0.95), Vector2(lr * 0.8, lr * 0.85), VoxCanvas.tone(c1, 0.95), 0.0 if fr else 1.0, 0.0)
			# 爪：前伸
			var pc := c3 if model == "fox" else VoxCanvas.tone(c2, 0.8)
			if model == "wolf" or model == "bear":
				pc = VoxCanvas.tone(c1, 0.8)
			for y in range(-lower, -lower + int(paw.y) + 1):
				for z in range(-int(paw.z) - 1, 2):
					for x in range(-int(paw.x), int(paw.x)):
						cv.put(x, y, z, VoxCanvas.tone(pc, 0.9 + 0.1 * float(VoxCanvas.h3(x, y, z) & 1)))
			# 趾甲 / 蹄
			if model == "boar":
				for x in range(-int(paw.x), int(paw.x)):
					cv.put(x, -lower, -int(paw.z) - 1, Color(0.18, 0.14, 0.12))
				cv.put(-1, -lower + 1, -int(paw.z) - 1, Color(0.18, 0.14, 0.12))
			else:
				for x in range(-int(paw.x), int(paw.x), 2):
					cv.put(x, -lower, -int(paw.z) - 2, Color(0.92, 0.9, 0.84) if model != "bear" else Color(0.2, 0.18, 0.16))
			return VoxMesh.build_one(cv, VOXEL), sx < 0)
	# 尾：摆动根 + 弹簧链
	var tail_kind: String = q["tail"]
	var tail_rest := -62.0
	match tail_kind:
		"fox":
			tail_rest = -72.0
		"stub":
			tail_rest = -40.0
		"thin":
			tail_rest = -20.0
	var base := _bone(hips, "base_tail", Vector3(0, rear_r.y * 0.55, rear_r.z * 0.55 - 1.0), Vector3(tail_rest, 0, 0))
	var segs := 3
	var seg_len := 7
	var r0 := 2.2
	var r_mid := 3.4
	match tail_kind:
		"fox":
			segs = 4
			seg_len = 7
			r0 = 2.6
			r_mid = 5.0
		"thin":
			segs = 2
			seg_len = 5
			r0 = 1.0
			r_mid = 0.9
		"stub":
			segs = 1
			seg_len = 4
			r0 = 2.5
			r_mid = 2.2
	var parent2: Node3D = base
	for i in segs:
		var tb := HairStyles.spring_bone(parent2, "tail_%d" % i, Vector3(0, 0 if i == 0 else -seg_len, 0), Vector3(12 if i > 0 else 0, 0, 0), seg_len, 0.14, 40)
		var ii := i
		_mesh(tb, "q_tail%d|%s" % [i, key], func() -> ArrayMesh:
			var R := int(ceil(r_mid)) + 2
			var cv := VoxCanvas.new(Vector3i(-R, -seg_len - 2, -R), Vector3i(R - 1, 2, R - 1))
			for yi in range(-1, seg_len + 1):
				var t := (ii + float(yi) / seg_len) / float(segs)
				var r := lerpf(r0, r_mid, sin(minf(t * 1.6, 1.0) * PI * 0.5)) if t < 0.6 else lerpf(r_mid, 1.0, (t - 0.6) / 0.4)
				if tail_kind == "thin":
					r = 1.0
				for z in range(-R, R):
					for x in range(-R, R):
						var d := Vector2(x + 0.5, z + 0.5).length()
						var rr := r + (0.5 if VoxCanvas.h3(x, yi + ii * 10, z) % 3 == 0 else 0.0)
						if d > rr:
							continue
						var c := c1
						if tail_kind == "fox" and t > 0.78:
							c = c2
						elif tail_kind == "bushy" and t > 0.8:
							c = back
						elif tail_kind == "bushy" and z > 1:
							c = back
						cv.put(x, -yi, z, VoxCanvas.tone(c, 0.9 + 0.15 * float(VoxCanvas.h3(z, yi, x) & 3) / 3.0))
			return VoxMesh.build_one(cv, VOXEL))
		parent2 = tb


# ================================================================ 石傀（人形骨骼）

static func _golem(rig: BeastRig, stone: Color, dark: Color, glow: Color, key: String) -> void:
	var hips := _bone(rig, "hips", Vector3(0, 26, 0))
	var spine := _bone(hips, "spine", Vector3(0, 4, 0))
	var head := _bone(spine, "head", Vector3(0, 22, -3))
	var arm_l := _bone(spine, "arm_l", Vector3(-16, 18, 0))
	var arm_r := _bone(spine, "arm_r", Vector3(16, 18, 0))
	var fore_l := _bone(arm_l, "forearm_l", Vector3(0, -12, 0))
	var fore_r := _bone(arm_r, "forearm_r", Vector3(0, -12, 0))
	var hand_l := _bone(fore_l, "hand_l", Vector3(0, -12, 0))
	var hand_r := _bone(fore_r, "hand_r", Vector3(0, -12, 0))
	var leg_l := _bone(hips, "leg_l", Vector3(-6, -2, 0))
	var leg_r := _bone(hips, "leg_r", Vector3(6, -2, 0))
	var shin_l := _bone(leg_l, "shin_l", Vector3(0, -12, 0))
	var shin_r := _bone(leg_r, "shin_r", Vector3(0, -12, 0))
	var g := VoxelGrid.glow(glow, 0.9)
	# 石块纹理：块状明暗 + 裂缝 + 苔藓
	var rock := func(cv: VoxCanvas, a: Vector3i, b: Vector3i, block: int) -> void:
		for z in range(a.z, b.z + 1):
			for y in range(a.y, b.y + 1):
				for x in range(a.x, b.x + 1):
					var bh := VoxCanvas.h3(floori(x / float(block)), floori(y / float(block)), floori(z / float(block)))
					var c := VoxCanvas.tone(stone, 0.82 + 0.26 * float(bh & 7) / 7.0)
					if posmod(y, block) == 0 or posmod(x + z, block * 2) == 0:
						c = VoxCanvas.tone(dark, 0.9)
					if (bh >> 5) % 11 == 0 and y > (a.y + b.y) / 2:
						c = Color("5a7a3a").lerp(c, 0.3)
					cv.put(x, y, z, c)
	_mesh(hips, "g_hips|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-12, -7, -8), Vector3i(11, 6, 8))
		rock.call(cv, Vector3i(-10, -5, -6), Vector3i(9, 4, 6), 4)
		return VoxMesh.build_one(cv, VOXEL))
	_mesh(spine, "g_torso|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-17, -2, -11), Vector3i(16, 25, 11))
		rock.call(cv, Vector3i(-9, 0, -6), Vector3i(8, 8, 6), 4)
		rock.call(cv, Vector3i(-14, 9, -9), Vector3i(13, 21, 8), 5)
		rock.call(cv, Vector3i(-10, 21, -7), Vector3i(9, 23, 6), 5)
		# 胸口符文核心
		for p in [[-1, 16], [0, 16], [-2, 15], [1, 15], [-1, 14], [0, 14], [-1, 17], [0, 17], [-3, 15], [2, 15]]:
			cv.put(p[0], p[1], -10, g)
		cv.box(Vector3i(-1, 15, -10), Vector3i(0, 15, -10), VoxelGrid.glow(glow.lightened(0.5), 1.0))
		for y in range(10, 20, 3):
			cv.put(-12, y, -9, VoxelGrid.glow(glow, 0.6))
			cv.put(11, y + 1, -9, VoxelGrid.glow(glow, 0.6))
		return VoxMesh.build_one(cv, VOXEL))
	_mesh(head, "g_head|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-7, -2, -8), Vector3i(6, 11, 6))
		rock.call(cv, Vector3i(-5, 0, -6), Vector3i(4, 8, 4), 3)
		for x in [-3, -2, 1, 2]:
			cv.put(x, 5, -7, g)
		cv.box(Vector3i(-4, 7, -7), Vector3i(3, 7, -7), VoxCanvas.tone(dark, 0.7))
		return VoxMesh.build_one(cv, VOXEL))
	for side: int in [-1, 1]:
		var arm := arm_r if side > 0 else arm_l
		var fore := fore_r if side > 0 else fore_l
		var hand := hand_r if side > 0 else hand_l
		var mir := side < 0
		_mesh(arm, "g_uarm|" + key, func() -> ArrayMesh:
			var cv := VoxCanvas.new(Vector3i(-8, -14, -8), Vector3i(8, 6, 8))
			rock.call(cv, Vector3i(-5, -12, -5), Vector3i(5, 1, 5), 4)
			rock.call(cv, Vector3i(-6, -2, -6), Vector3i(7, 5, 6), 4)
			cv.put(7, 2, 0, VoxelGrid.glow(glow, 0.7))
			return VoxMesh.build_one(cv, VOXEL), mir)
		_mesh(fore, "g_farm|" + key, func() -> ArrayMesh:
			var cv := VoxCanvas.new(Vector3i(-8, -14, -8), Vector3i(8, 3, 8))
			rock.call(cv, Vector3i(-5, -11, -5), Vector3i(5, 1, 5), 4)
			for y in range(-9, -1, 3):
				cv.put(6, y, 0, VoxelGrid.glow(glow, 0.6))
			return VoxMesh.build_one(cv, VOXEL), mir)
		_mesh(hand, "g_hand|" + key, func() -> ArrayMesh:
			var cv := VoxCanvas.new(Vector3i(-8, -9, -8), Vector3i(8, 3, 8))
			rock.call(cv, Vector3i(-6, -7, -6), Vector3i(6, 1, 6), 3)
			return VoxMesh.build_one(cv, VOXEL), mir)
		var leg := leg_r if side > 0 else leg_l
		var shin := shin_r if side > 0 else shin_l
		_mesh(leg, "g_thigh|" + key, func() -> ArrayMesh:
			var cv := VoxCanvas.new(Vector3i(-7, -14, -7), Vector3i(7, 4, 7))
			rock.call(cv, Vector3i(-5, -12, -5), Vector3i(5, 2, 5), 4)
			return VoxMesh.build_one(cv, VOXEL), mir)
		_mesh(shin, "g_shin|" + key, func() -> ArrayMesh:
			var cv := VoxCanvas.new(Vector3i(-8, -15, -10), Vector3i(8, 2, 8))
			rock.call(cv, Vector3i(-5, -12, -5), Vector3i(5, 1, 5), 4)
			rock.call(cv, Vector3i(-6, -14, -9), Vector3i(6, -11, 6), 3)
			return VoxMesh.build_one(cv, VOXEL), mir)


# ================================================================ 蛇

static func _snake(rig: BeastRig, c1: Color, c2: Color, c3: Color, key: String) -> void:
	var n := 9
	var seg_len := 8
	var hips := _bone(rig, "hips", Vector3(0, 5, 0))
	var belly := c2
	var pattern := VoxCanvas.tone(c1, 0.6)
	var parent := hips
	for i in range(0, n + 1):
		var bn: Node3D = hips
		if i > 0:
			bn = _bone(parent, "seg_%d" % i, Vector3(0, 0, seg_len))
		var r := 5.6 - float(i) * 0.4
		var ii := i
		_mesh(bn, "s_seg%d|%s" % [i, key], func() -> ArrayMesh:
			var R := int(ceil(r)) + 2
			var cv := VoxCanvas.new(Vector3i(-R, -R, -2), Vector3i(R - 1, R - 1, seg_len + 2))
			for z in range(-1, seg_len + 1):
				var rr := r - 0.3 * float(z) / seg_len
				for y in range(-R, R):
					for x in range(-R, R):
						var dx := (x + 0.5) / rr
						var dy := (y + 0.5) / (rr * 0.85)
						if dx * dx + dy * dy > 1.0:
							continue
						var c := c1
						if y < -rr * 0.35:
							c = belly if (z % 2 == 0) else VoxCanvas.tone(belly, 0.88)
						else:
							# 背部菱形斑纹
							var pz := posmod(z + ii * seg_len, 10)
							if absi(x) + absi(pz - 5) < 3 and y > 0:
								c = pattern
							elif absi(x) + absi(pz - 5) == 3 and y > 0:
								c = c3.lerp(c1, 0.5)
						# 鳞片：交错明暗
						var k := 0.92 + 0.12 * float((x + z * 2 + y) & 1)
						cv.put(x, y, z, VoxCanvas.tone(c, k))
			return VoxMesh.build_one(cv, VOXEL))
		parent = bn
	# 尾尖（弹簧）
	var t0 := HairStyles.spring_bone(parent, "tail_0", Vector3(0, 0, seg_len), Vector3(-90, 0, 0), 8, 0.16, 35)
	_mesh(t0, "s_tail|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-3, -10, -3), Vector3i(2, 2, 2))
		for yi in range(0, 9):
			var rr := 1.6 * (1.0 - yi / 9.0) + 0.4
			for z in range(-2, 2):
				for x in range(-2, 2):
					if Vector2(x + 0.5, z + 0.5).length() <= rr:
						cv.put(x, -yi, z, VoxCanvas.tone(c1 if z > -1 else belly, 0.9 + 0.1 * float((x + yi) & 1)))
		return VoxMesh.build_one(cv, VOXEL))
	# 颈与头（向前）
	var neck := _bone(hips, "neck", Vector3(0, 0, 0))
	_mesh(neck, "s_neck|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-7, -7, -14), Vector3i(6, 7, 2))
		for z in range(-12, 1):
			var rr := 5.4 - float(-z) * 0.08
			for y in range(-6, 6):
				for x in range(-6, 6):
					var dx := (x + 0.5) / rr
					var dy := (y + 0.5) / (rr * 0.85)
					if dx * dx + dy * dy <= 1.0:
						var c := belly if y < -rr * 0.35 else c1
						cv.put(x, y, z, VoxCanvas.tone(c, 0.92 + 0.12 * float((x + z * 2 + y) & 1)))
		return VoxMesh.build_one(cv, VOXEL))
	var head := _bone(neck, "head", Vector3(0, 0, -12))
	_mesh(head, "s_head|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-8, -5, -14), Vector3i(7, 6, 3))
		for z in range(-12, 2):
			var t := float(-z) / 12.0
			var w := 6.0 - t * 2.4
			var h := 3.8 - t * 1.4
			for y in range(-1, int(ceil(h)) + 1):
				for x in range(-int(ceil(w)), int(ceil(w))):
					if absf(x + 0.5) <= w and y + 0.5 <= h:
						var c := c1 if y > 0 else belly
						cv.put(x, y, z, VoxCanvas.tone(c, 0.92 + 0.1 * float((x + z) & 1)))
		# 眼：金色竖瞳
		for sd: int in [-1, 1]:
			var x := 4 if sd > 0 else -5
			cv.put(x, 2, -7, VoxelGrid.glow(c3, 0.5))
			cv.put(x, 3, -7, VoxCanvas.tone(c1, 0.55))
			cv.put(x, 3, -6, VoxCanvas.tone(c1, 0.55))
		cv.put(-2, 2, -12, Color(0.1, 0.1, 0.1))
		cv.put(1, 2, -12, Color(0.1, 0.1, 0.1))
		return VoxMesh.build_one(cv, VOXEL))
	var jaw := _bone(head, "jaw", Vector3(0, -1, 0))
	_mesh(jaw, "s_jaw|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-7, -3, -13), Vector3i(6, 1, 2))
		for z in range(-11, 1):
			var w := 5.4 - float(-z) * 0.2
			for x in range(-int(ceil(w)), int(ceil(w))):
				if absf(x + 0.5) <= w:
					cv.put(x, -1, z, belly)
		cv.box(Vector3i(-1, 0, -8), Vector3i(0, 0, -2), Color("c04050"))
		# 毒牙
		cv.put(-3, 0, -8, Color(0.95, 0.95, 0.9))
		cv.put(2, 0, -8, Color(0.95, 0.95, 0.9))
		return VoxMesh.build_one(cv, VOXEL))


# ================================================================ 鹤

static func _crane(rig: BeastRig, white: Color, black: Color, red: Color, key: String) -> void:
	var hips := _bone(rig, "hips", Vector3(0, 38, 0))
	_mesh(hips, "c_body|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-9, -9, -12), Vector3i(8, 9, 20))
		_blob(cv, Vector3(0, 0, 2), Vector3(6.5, 6.5, 10.5), white, white, VoxCanvas.tone(white, 0.93), 0.6, -0.5)
		# 尾部黑色长羽（收拢时覆盖在尾上的是次级飞羽）
		for z in range(8, 19):
			for x in range(-5, 5):
				var y0 := 1 - (z - 8) / 3
				for y in range(y0 - 2, y0 + 2):
					cv.put(x, y, z, VoxCanvas.tone(black, 0.9 + 0.2 * float((x + z) & 1)))
		return VoxMesh.build_one(cv, VOXEL))
	var n0 := _bone(hips, "neck_0", Vector3(0, 4, -8), Vector3(35, 0, 0))
	var n1 := _bone(n0, "neck_1", Vector3(0, 0, -9), Vector3(-45, 0, 0))
	for nb in [[n0, "c_n0"], [n1, "c_n1"]]:
		var node: Node3D = nb[0]
		var is_upper: bool = str(nb[1]) == "c_n1"
		_mesh(node, str(nb[1]) + "|" + key, func() -> ArrayMesh:
			var cv := VoxCanvas.new(Vector3i(-4, -4, -12), Vector3i(3, 4, 3))
			for z in range(-10, 2):
				for y in range(-2, 2):
					for x in range(-2, 2):
						cv.put(x, y, z, VoxCanvas.tone(black if is_upper else white, 0.92 + 0.1 * float((x + y + z) & 1)))
			return VoxMesh.build_one(cv, VOXEL))
	var head := _bone(n1, "head", Vector3(0, 0, -10), Vector3(10, 0, 0))
	_mesh(head, "c_head|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-4, -4, -16), Vector3i(3, 5, 4))
		cv.box(Vector3i(-2, -2, -4), Vector3i(1, 2, 1), black)
		cv.box(Vector3i(-2, 2, -3), Vector3i(1, 3, 0), VoxelGrid.glow(red, 0.15))   # 丹顶
		cv.box(Vector3i(-2, -1, 0), Vector3i(1, 1, 1), white)
		for sd: int in [-1, 1]:
			cv.put(1 if sd > 0 else -2, 1, -3, Color(0.95, 0.85, 0.3))
		# 长喙（上）
		for z in range(-14, -4):
			cv.put(-1, 0, z, Color("c8b890"))
			cv.put(0, 0, z, Color("b8a880"))
		return VoxMesh.build_one(cv, VOXEL))
	var jaw := _bone(head, "jaw", Vector3(0, -0.5, -4))
	_mesh(jaw, "c_jaw|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-2, -2, -12), Vector3i(1, 1, 1))
		for z in range(-9, 0):
			cv.put(-1, -1, z, Color("a89870"))
			cv.put(0, -1, z, Color("a89870"))
		return VoxMesh.build_one(cv, VOXEL))
	for side: int in [-1, 1]:
		var sn := "l" if side < 0 else "r"
		var w := _bone(hips, "wing_" + sn, Vector3(side * 6.0, 3, -4))
		var wt := _bone(w, "wing_tip_" + sn, Vector3(side * 0.0, 0, 0))
		# 翅膀静止时收拢在身侧（沿 +Z 向后折叠）；展开时绕 Z 外展
		_mesh(w, "c_wing|" + key, func() -> ArrayMesh:
			var cv := VoxCanvas.new(Vector3i(-2, -16, -3), Vector3i(3, 3, 20))
			for z in range(-1, 18):
				for y in range(-10, 2):
					var t := float(z + 1) / 19.0
					if y < -10 + int(t * 6.0):
						continue
					var c := white if z < 10 else black
					if y < -6 and z >= 6:
						c = black
					cv.put(0, y, z, VoxCanvas.tone(c, 0.9 + 0.12 * float((y + z) & 1)))
					cv.put(1, y, z, VoxCanvas.tone(c, 0.85))
			return VoxMesh.build_one(cv, VOXEL), side < 0)
		wt.set_meta("bone", true)
		var leg := _bone(hips, "leg_" + sn, Vector3(side * 3.0, -5, 2))
		var shin := _bone(leg, "shin_" + sn, Vector3(0, -15, 0))
		_mesh(leg, "c_leg|" + key, func() -> ArrayMesh:
			var cv := VoxCanvas.new(Vector3i(-3, -17, -3), Vector3i(2, 2, 2))
			cv.box(Vector3i(-1, -4, -1), Vector3i(0, 0, 0), VoxCanvas.tone(white, 0.9))
			cv.box(Vector3i(0, -15, 0), Vector3i(0, -4, 0), Color("3a3a3a"))
			cv.box(Vector3i(-1, -15, 0), Vector3i(-1, -4, 0), Color("2a2a2a"))
			return VoxMesh.build_one(cv, VOXEL), side < 0)
		_mesh(shin, "c_shin|" + key, func() -> ArrayMesh:
			var cv := VoxCanvas.new(Vector3i(-4, -20, -8), Vector3i(3, 2, 4))
			cv.box(Vector3i(-1, -18, 0), Vector3i(0, 0, 0), Color("333333"))
			# 爪
			for z in range(-5, 3):
				cv.put(-1, -18, z, Color("2a2a2a"))
			for x in [-3, 2]:
				cv.put(x, -18, -3, Color("2a2a2a"))
				cv.put(x + (1 if x < 0 else -1), -18, -2, Color("2a2a2a"))
			return VoxMesh.build_one(cv, VOXEL), side < 0)
		# 腿（shin）下端着地：hips 38 - 5 - 15 - 18 = 0
	var tail := HairStyles.spring_bone(hips, "tail_0", Vector3(0, 1, 14), Vector3(-100, 0, 0), 6, 0.2, 25)
	_mesh(tail, "c_tail|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-4, -8, -2), Vector3i(3, 1, 2))
		cv.box(Vector3i(-3, -6, 0), Vector3i(2, 0, 0), VoxCanvas.tone(white, 0.95))
		return VoxMesh.build_one(cv, VOXEL))


# ================================================================ 蜘蛛

static func _spider(rig: BeastRig, body: Color, mark: Color, eye: Color, key: String) -> void:
	var hips := _bone(rig, "hips", Vector3(0, 11, 8))
	_mesh(hips, "sp_abd|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-12, -11, -4), Vector3i(11, 13, 24))
		_blob(cv, Vector3(0, 2, 10), Vector3(10, 9, 12), body, VoxCanvas.tone(body, 0.8), VoxCanvas.tone(body, 1.1), 0.6, -0.6)
		# 背部斑纹（沙漏形）+ 绒毛
		for z in range(2, 20):
			for x in range(-6, 6):
				var w := 1.5 + absf(float(z - 11)) * 0.35
				if absf(x + 0.5) < w:
					var y := 10
					while y > 0 and not cv.solid(x, y, z):
						y -= 1
					if y > 0:
						cv.put(x, y, z, VoxCanvas.tone(mark, 0.9 + 0.2 * float((x + z) & 1)))
		# 纺器
		cv.box(Vector3i(-1, -1, 21), Vector3i(0, 0, 22), VoxCanvas.tone(body, 0.7))
		return VoxMesh.build_one(cv, VOXEL))
	var spine := _bone(hips, "spine", Vector3(0, 0, -4))
	_mesh(spine, "sp_ceph|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-9, -7, -14), Vector3i(8, 8, 4))
		_blob(cv, Vector3(0, 0.5, -5), Vector3(7, 5.5, 8), body, VoxCanvas.tone(body, 0.85), VoxCanvas.tone(body, 1.1))
		# 八只眼（发光）
		for p in [[-2, 4, -12], [1, 4, -12], [-4, 3, -11], [3, 3, -11], [-1, 5, -11], [0, 5, -11], [-3, 5, -10], [2, 5, -10]]:
			cv.put(p[0], p[1], p[2], VoxelGrid.glow(eye, 0.7))
		return VoxMesh.build_one(cv, VOXEL))
	for side: int in [-1, 1]:
		var jn := "jaw_" + ("l" if side < 0 else "r")
		var j := _bone(spine, jn, Vector3(side * 2.0, -2, -12))
		_mesh(j, "sp_fang|" + key, func() -> ArrayMesh:
			var cv := VoxCanvas.new(Vector3i(-2, -7, -3), Vector3i(2, 1, 2))
			cv.box(Vector3i(-1, -3, -1), Vector3i(0, 0, 0), VoxCanvas.tone(mark, 0.6))
			cv.box(Vector3i(-1, -6, -1), Vector3i(-1, -4, -1), Color(0.9, 0.88, 0.8))
			return VoxMesh.build_one(cv, VOXEL), side < 0)
	# 八条腿：每侧 4 条，从头胸部两侧伸出，上段斜向上外，下段向下着地
	var fwd := [-35.0, -12.0, 12.0, 38.0]   # 绕 Y 的朝向（度，负为向前）
	for i in range(1, 5):
		for side: int in [-1, 1]:
			var sn := "%d%s" % [i, "l" if side < 0 else "r"]
			var yaw: float = fwd[i - 1] * (-1.0 if side < 0 else 1.0)
			# leg_*：只带朝向（绕 Y），摆腿绕竖直轴；femur 节点（非骨骼）抬起大腿；knee_* 让小腿向下着地
			var leg := _bone(spine, "leg_" + sn, Vector3(side * 5.5, 0, -8.0 + i * 2.5), Vector3(0, yaw, 0))
			var femur := Node3D.new()
			femur.name = "femur"
			femur.rotation_degrees = Vector3(0, 0, side * 125.0)
			leg.add_child(femur)
			var knee := _bone(femur, "knee_" + sn, Vector3(0, -14, 0), Vector3(0, 0, -side * 105.0))
			_mesh(femur, "sp_femur|" + key, func() -> ArrayMesh:
				var cv := VoxCanvas.new(Vector3i(-3, -16, -3), Vector3i(2, 2, 2))
				for y in range(-14, 1):
					var r := 1 if y > -12 else 1
					cv.box(Vector3i(-r, y, -r), Vector3i(r - 1, y, r - 1), VoxCanvas.tone(body, 0.9 + 0.15 * float(y & 1)))
				for y in range(-12, 0, 3):
					cv.put(-2, y, 0, VoxCanvas.tone(mark, 0.7))
				return VoxMesh.build_one(cv, VOXEL), side < 0)
			_mesh(knee, "sp_tibia|" + key, func() -> ArrayMesh:
				var cv := VoxCanvas.new(Vector3i(-3, -22, -3), Vector3i(2, 2, 2))
				cv.box(Vector3i(-1, -2, -1), Vector3i(0, 1, 0), VoxCanvas.tone(mark, 0.8))
				for y in range(-20, -1):
					cv.box(Vector3i(-1 if y > -14 else 0, y, -1 if y > -14 else 0), Vector3i(0, y, 0), VoxCanvas.tone(body, 0.88 + 0.15 * float(y & 1)))
				return VoxMesh.build_one(cv, VOXEL), side < 0)
