class_name BeastBuilder
## 妖兽体素模型生成（2× 精度，VOXEL = 0.0125m；骨骼位置的米制尺寸与旧版一致，BeastRig 剪辑不受影响）。
## BeastBuilder.build(model, colors, size) -> BeastRig（继承 CharacterRig）；build_async() 同参数，网格在后台生成。
## model：wolf 狼 / fox 狐 / boar 野猪 / bear 熊 / golem 石傀（人形骨骼）/ snake 蛇 / crane 鹤 / spider 蛛
## colors：[主色, 副色, 点缀色]（"#rrggbb"），缺省用各模型默认配色；size：整体缩放（1 = 标准体型）。
## 细节：毛皮（背深腹浅分区、竖向毛丝、表面毛簇）、发光竖瞳眼 + 高光、鼻头/獠牙/趾爪、蛇鳞（覆瓦鳞片 + 腹鳞横纹）、
##       鹤羽（飞羽羽轴、尾羽分叉）、蛛甲（几丁质光泽 + 刚毛）、石傀（石块缝 + 苔藓 + 发光符文）。
## 骨骼与剪辑见 BeastRig。网格按 (model, colors) 缓存（VoxMesh.part，两级 LOD），同种妖兽成群生成几乎零开销。
## 注意：绘制在工作线程中进行，表格一律用 static var / 局部变量。

const VOXEL := 0.0125
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

static var _lod: bool = true


static func build(model: String, colors: Array = [], size: float = 1.0) -> BeastRig:
	return _assemble(model, colors, size, false)


## 异步：立即返回（隐藏的）骨架，网格在工作线程生成，完成后自动显示并发出 meshes_ready
static func build_async(model: String, colors: Array = [], size: float = 1.0) -> BeastRig:
	return _assemble(model, colors, size, true)


static func _assemble(model: String, colors: Array, size: float, async: bool) -> BeastRig:
	if not DEFAULT_COLORS.has(model):
		model = "wolf"
	var cols: Array = (DEFAULT_COLORS[model] as Array).duplicate()
	for i in mini(colors.size(), 3):
		cols[i] = colors[i]
	var c1 := CharacterBuilder.col(cols[0], Color.GRAY)
	var c2 := CharacterBuilder.col(cols[1], Color.DIM_GRAY)
	var c3 := CharacterBuilder.col(cols[2], Color.WHITE)
	var key := "b2|%s|%s" % [model, str(cols)]
	var rig := BeastRig.new()
	rig.name = "BeastRig"
	rig.model = model
	rig.voxel_size = VOXEL
	VoxMesh.begin_batch(async)
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
	var recs: Variant = VoxMesh.end_batch()
	rig.body_scale = maxf(size, 0.1)
	rig.scale = Vector3.ONE * rig.body_scale
	if rig.body == "humanoid":
		rig.stance = "fist"
	rig.setup()
	if async and recs is Array and not (recs as Array).is_empty():
		rig.set_pending_meshes(recs)
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
	VoxMesh.attach(bone, VoxMesh.part(key, maker, VOXEL, _lod), "Mesh", mirror, _lod)


## 毛皮色：按高度分区（腹部浅、背部深），2 体素块噪声 + 竖向毛丝暗纹
static func _fur(c_main: Color, c_back: Color, c_belly: Color, yrel: float, x: int, y: int, z: int, back_t: float = 0.45, belly_t: float = -0.4) -> Color:
	var h := VoxCanvas.h3(x >> 1, y >> 1, z >> 1)
	var c := c_main
	if yrel > back_t + float(h & 1) * 0.1:
		c = c_back
	elif yrel < belly_t - float((h >> 1) & 1) * 0.08:
		c = c_belly
	elif yrel > back_t - 0.12 and (h & 6) == 0:
		c = c_main.lerp(c_back, 0.5)
	var k := 0.9 + 0.14 * float((h >> 2) & 3) / 3.0
	if (VoxCanvas.h3(x, 7, z) & 7) == 0:
		k *= 0.86
	return VoxCanvas.tone(c, k)


## 带毛色分区的椭球（只给外壳着色，内部直接填暗色）；tufts > 0 时上半表面随机长出毛簇
static func _blob(cv: VoxCanvas, c: Vector3, r: Vector3, cm: Color, cb: Color, cl: Color, back_t: float = 0.45, belly_t: float = -0.4, tufts: int = 0) -> void:
	cv.set_mat(VoxCanvas.M_FUR)
	var v_in := cv.e(VoxCanvas.tone(cm, 0.6))
	var lo := Vector3i((c - r).floor())
	var hi := Vector3i((c + r).ceil())
	var inv := Vector3(1.0 / r.x, 1.0 / r.y, 1.0 / r.z)
	var sh := 1.0 - 2.6 / minf(r.x, minf(r.y, r.z))
	var thr := sh * sh if sh > 0.0 else -1.0
	var tuft_pts: Array[Vector3i] = []
	var d := cv.data
	lo = Vector3i(maxi(lo.x, cv.lo.x), maxi(lo.y, cv.lo.y), maxi(lo.z, cv.lo.z))
	hi = Vector3i(mini(hi.x, cv.hi.x), mini(hi.y, cv.hi.y), mini(hi.z, cv.hi.z))
	for z in range(lo.z, hi.z + 1):
		var dz := (z + 0.5 - c.z) * inv.z
		for y in range(lo.y, hi.y + 1):
			var dy := (y + 0.5 - c.y) * inv.y
			var r2 := dz * dz + dy * dy
			if r2 > 1.0:
				continue
			var row := cv.sx * (y - cv.lo.y + 1) + cv.sxy * (z - cv.lo.z + 1) + 1 - cv.lo.x
			for x in range(lo.x, hi.x + 1):
				var dx := (x + 0.5 - c.x) * inv.x
				var d2 := dx * dx + r2
				if d2 > 1.0:
					continue
				if d2 < thr:
					d[row + x] = v_in
					continue
				d[row + x] = cv.e(_fur(cm, cb, cl, dy, x, y, z, back_t, belly_t))
				if tufts > 0 and d2 > 0.86 and dy > -0.15 and VoxCanvas.h3(x, y, z) % tufts == 0:
					tuft_pts.append(Vector3i(x, y, z))
	# 毛簇：沿外法线主轴伸出 1~2 格，尖端略亮
	for p in tuft_pts:
		var n := (Vector3(p) + Vector3(0.5, 0.5, 0.5) - c) * inv
		var ax := Vector3i.ZERO
		var an := n.abs()
		if an.y >= an.x and an.y >= an.z:
			ax = Vector3i(0, signi(int(sign(n.y))), 0)
		elif an.x >= an.z:
			ax = Vector3i(signi(int(sign(n.x))), 0, 0)
		else:
			ax = Vector3i(0, 0, signi(int(sign(n.z))))
		var col := _fur(cm, cb, cl, n.y, p.x, p.y, p.z, back_t, belly_t)
		var q := p + ax
		if not cv.solid(q.x, q.y, q.z):
			cv.put(q.x, q.y, q.z, VoxCanvas.tone(col, 1.06))
			if (VoxCanvas.h3(p.x, p.z, p.y) & 3) == 0:
				var q2 := q + ax + (Vector3i(0, 0, 1) if ax.y != 0 else Vector3i.ZERO)
				cv.put(q2.x, q2.y, q2.z, VoxCanvas.tone(col, 1.12))


## 圆柱段（沿 -Y）：从 y0 到 y1，半径 rx/rz 线性变化（毛皮外壳着色）
static func _limb(cv: VoxCanvas, y0: int, y1: int, r0: Vector2, r1: Vector2, cm: Color, zoff0: float = 0.0, zoff1: float = 0.0, stripe: Color = Color(0, 0, 0, 0)) -> void:
	cv.set_mat(VoxCanvas.M_FUR)
	var v_in := cv.e(VoxCanvas.tone(cm, 0.6))
	for y in range(y1, y0 + 1):
		var t := float(y0 - y) / float(maxi(y0 - y1, 1))
		var r := r0.lerp(r1, t)
		var zo := lerpf(zoff0, zoff1, t)
		for z in range(-int(ceil(r.y)) - 3, int(ceil(r.y)) + 4):
			for x in range(-int(ceil(r.x)) - 1, int(ceil(r.x)) + 1):
				var dx := (x + 0.5) / r.x
				var dz := (z + 0.5 - zo) / r.y
				var d2 := dx * dx + dz * dz
				if d2 > 1.0:
					continue
				if d2 < 0.45:
					if cv.has(x, y, z):
						cv.data[cv.ix(x, y, z)] = v_in
					continue
				var k := 0.9 + 0.14 * float(VoxCanvas.h3(x >> 1, y >> 1, z >> 1) & 3) / 3.0
				if (VoxCanvas.h3(x, 3, z) & 7) == 0:
					k *= 0.87
				var c := cm
				if stripe.a > 0.0 and posmod(y, 7) < 2:
					c = stripe
				cv.put(x, y, z, VoxCanvas.tone(c, k))


## 背脊鬃毛：沿中线的一排参差尖刺（z0..z1），从 y0 起向上、向后倾
static func _bristles(cv: VoxCanvas, y0: int, z0: int, z1: int, c: Color) -> void:
	cv.set_mat(VoxCanvas.M_FUR)
	for z in range(z0, z1):
		var h := VoxCanvas.h1(z * 3 + 1)
		var hh := 2 + h % 5
		if h % 7 == 0:
			continue
		for k in hh:
			var y := y0 + k
			var lean := k / 2
			var top := k >= hh - 2
			cv.put(-1, y, z + lean, VoxCanvas.tone(c, 1.15 if top else 0.9))
			cv.put(0, y, z + lean, VoxCanvas.tone(c, 1.05 if top else 0.85))
			if k < hh - 2:
				cv.put(-2 + (h & 1) * 3, y, z + lean, VoxCanvas.tone(c, 0.8))


## 兽眼（绘在表面上）：上眼睑暗线、发光虹膜、竖瞳、高光、下缘亮色；side -1 左 / 1 右；x0 为内侧列
static func _eye(cv: VoxCanvas, x0: int, y0: int, side: int, iris: Color, w: int = 4, slit: bool = true, glow: float = 0.45) -> void:
	var lid := Color(0.08, 0.06, 0.06)
	for j in w:
		var x := x0 + j * side
		for r in 4:
			var y := y0 - r
			var fz := _front(cv, x, y)
			if fz > 9000:
				continue
			var c: Color
			var m := VoxCanvas.M_EYE
			if r == 0:
				c = lid
				m = VoxCanvas.M_HAIR
			elif r == 3:
				if j == 0 or j == w - 1:
					continue
				c = VoxCanvas.glow(iris.lightened(0.35), glow)
			else:
				c = VoxCanvas.glow(iris, glow)
				if j == w / 2 and slit:
					c = Color(0.05, 0.03, 0.03)
				elif j == 0 and r == 1:
					c = Color(1, 1, 1, 0.8)
				elif j == w - 1 and r == 2:
					c = VoxCanvas.glow(iris.darkened(0.3), glow * 0.6)
			cv.putm(x, y, fz, c, m)


static func _front(cv: VoxCanvas, x: int, y: int) -> int:
	return OutfitBuilder.front_z(cv, x, y)


# ================================================================ 四足：狼 / 狐 / 野猪 / 熊

## 四足体型参数（体素，2×）
static func _qspec(model: String) -> Dictionary:
	match model:
		"fox":
			return {"upper": 14, "lower": 16, "body_len": 52, "rear_r": Vector3(11, 12, 16), "chest_r": Vector3(12, 14, 16), "leg_r": 4.0, "paw": Vector3(5, 4, 6),
				"neck_len": 12, "neck_r": 7.0, "neck_pitch": 24.0, "head_r": Vector3(10, 9, 9), "snout": Vector3(4.4, 4, 10), "ears": "fox", "tail": "fox", "stride": 1.0, "gallop": 5.5, "amp": 34.0, "wag": 22.0}
		"boar":
			return {"upper": 14, "lower": 16, "body_len": 68, "rear_r": Vector3(17, 19, 22), "chest_r": Vector3(19, 22, 22), "leg_r": 4.6, "paw": Vector3(5, 4, 6),
				"neck_len": 10, "neck_r": 13.0, "neck_pitch": -6.0, "head_r": Vector3(11, 12, 14), "snout": Vector3(6.4, 6.0, 16), "ears": "small", "tail": "thin", "tusks": true, "mane": true, "stride": 1.1, "gallop": 5.0, "amp": 26.0, "wag": 30.0}
		"bear":
			return {"upper": 20, "lower": 20, "body_len": 76, "rear_r": Vector3(21, 23, 24), "chest_r": Vector3(23, 25, 24), "leg_r": 8.0, "paw": Vector3(9, 6, 10),
				"neck_len": 16, "neck_r": 14.0, "neck_pitch": 4.0, "head_r": Vector3(14, 13, 13), "snout": Vector3(7.2, 6.4, 12), "muzzle": true, "ears": "round", "tail": "stub", "stride": 1.5, "gallop": 6.0, "amp": 26.0, "wag": 5.0}
	# 狼
	return {"upper": 20, "lower": 22, "body_len": 64, "rear_r": Vector3(13, 15, 20), "chest_r": Vector3(15, 19, 20), "leg_r": 5.2, "paw": Vector3(6, 4, 8),
		"neck_len": 16, "neck_r": 10.0, "neck_pitch": 22.0, "head_r": Vector3(13.6, 12, 12), "snout": Vector3(6.0, 5.4, 14), "ears": "wolf", "tail": "bushy", "ruff": true, "stride": 1.4, "gallop": 6.5, "amp": 32.0, "wag": 16.0}


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
	var mane: bool = q.get("mane", false)
	var ruff: bool = q.get("ruff", false)
	var tufts := 17 if model != "boar" else 11
	var leg_y := upper + lower   # 腿关节高度（离地）
	# hips 在后髋关节上方 4 格；spine（前躯/肩）在其前方
	var hips := _bone(rig, "hips", Vector3(0, leg_y + 4, L * 0.3))
	var spine := _bone(hips, "spine", Vector3(0, 2, -L * 0.55))
	# 后躯
	_mesh(hips, "q_rear|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-26, -24, -44), Vector3i(25, 30, 28))
		_blob(cv, Vector3(0, 3.0, -4.0), rear_r, c1, back, belly, 0.45, -0.4, tufts)
		if mane:
			_bristles(cv, int(rear_r.y) + 2, -32, 4, c2.darkened(0.35))
		return cv)
	# 前躯（胸更深）
	_mesh(spine, "q_chest|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-30, -30, -28), Vector3i(29, 34, 36))
		_blob(cv, Vector3(0, 0.0, 4.0), chest_r, c1, back, belly, 0.45, -0.4, tufts)
		if ruff:
			# 狼：颈部厚毛领（毛簇更密）
			_blob(cv, Vector3(0, 5.0, -8.0), Vector3(chest_r.x + 2.4, chest_r.y * 0.85, 10.0), c1, back, belly, 0.55, -0.2, 7)
		if mane:
			_bristles(cv, int(chest_r.y) + 2, -20, 28, c2.darkened(0.4))
		if model == "bear":
			# 肩峰
			_blob(cv, Vector3(0, 10.0, 8.0), Vector3(chest_r.x * 0.8, 9.0, 14.0), c1, back, belly, 0.45, -0.4, tufts)
		return cv)
	# 颈、头、颌
	var nl: int = q["neck_len"]
	var nr: float = q["neck_r"]
	var npitch: float = q.get("neck_pitch", 18.0)
	var neck := _bone(spine, "neck", Vector3(0, chest_r.y * 0.35, -chest_r.z * 0.55), Vector3(npitch, 0, 0))
	_mesh(neck, "q_neck|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-20, -20, -nl - 16), Vector3i(19, 21, 12))
		for i in range(0, nl + 6, 2):
			var zc := -i + 4.0
			_blob(cv, Vector3(0, 0.0, zc), Vector3(nr, nr * 1.05, 4.4), c1, back, belly, 0.5, -0.45, tufts)
		return cv)
	var hr: Vector3 = q["head_r"]
	var sn: Vector3 = q["snout"]
	var head := _bone(neck, "head", Vector3(0, 2, -nl - 2), Vector3(-npitch, 0, 0))
	var eye_col := Color("f0c040") if model != "boar" else Color("e04020")
	if model == "fox":
		eye_col = Color("ffb020")
	var muzzle: bool = q.get("muzzle", false)
	var tusks: bool = q.get("tusks", false)
	_mesh(head, "q_head|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-20, -18, -int(hr.z + sn.z) - 10), Vector3i(19, 21, 16))
		_blob(cv, Vector3(0, 1.0, -hr.z * 0.5), hr, c1, back, belly, 0.55, -0.5, 0)
		# 吻部（上颌）
		cv.set_mat(VoxCanvas.M_FUR)
		var sz0 := -hr.z * 0.9
		for i in int(sn.z) + 1:
			var t := float(i) / sn.z
			var cz := sz0 - i
			var rr := Vector2(sn.x * (1.0 - t * 0.25), sn.y * (1.0 - t * 0.2))
			for y in range(-int(rr.y) - 2, int(rr.y) + 2):
				for x in range(-int(rr.x) - 2, int(rr.x) + 2):
					var dx := (x + 0.5) / rr.x
					var dy := (y + 0.5 + 1.6) / rr.y
					if dx * dx + dy * dy <= 1.0:
						var c := belly if (y < -2 and model != "boar") else c1
						if model == "boar":
							c = VoxCanvas.tone(c2, 0.9)
						elif muzzle:
							c = c3.lerp(c1, 0.25)
						elif y > int(rr.y) - 2:
							c = VoxCanvas.tone(c1, 0.92)
						cv.put(x, y, int(floor(cz)), VoxCanvas.tone(c, 0.92 + 0.1 * float(VoxCanvas.h3(x >> 1, y >> 1, i) & 1)))
		var tipz := int(floor(sz0 - sn.z))
		# 鼻头（湿亮）+ 鼻孔 + 高光
		var nose := Color(0.1, 0.08, 0.08) if model != "boar" else Color("d8a0a0")
		cv.set_mat(VoxCanvas.M_JADE)
		cv.box(Vector3i(-3, -2, tipz - 2), Vector3i(2, 1, tipz), nose)
		cv.put(-2, 1, tipz - 2, nose.lightened(0.4))
		cv.put(-2, -1, tipz - 3, Color(0.02, 0.02, 0.02))
		cv.put(1, -1, tipz - 3, Color(0.02, 0.02, 0.02))
		if model == "boar":
			cv.box(Vector3i(-4, -4, tipz - 2), Vector3i(3, 2, tipz - 2), Color("c89090"))
			cv.box(Vector3i(-2, -2, tipz - 3), Vector3i(-1, -1, tipz - 3), Color(0.25, 0.1, 0.1))
			cv.box(Vector3i(0, -2, tipz - 3), Vector3i(1, -1, tipz - 3), Color(0.25, 0.1, 0.1))
		# 眼（发光、竖瞳、高光）+ 眉骨暗影
		var ex := int(hr.x * 0.42)
		var ey := 5
		_eye(cv, ex, ey, 1, eye_col, 4, model != "bear", 0.45)
		_eye(cv, -ex - 1, ey, -1, eye_col, 4, model != "bear", 0.45)
		cv.set_mat(VoxCanvas.M_FUR)
		for j in 5:
			for sd: int in [-1, 1]:
				var x := (ex + j) if sd > 0 else (-ex - 1 - j)
				var fz := _front(cv, x, ey + 1)
				if fz < 9000:
					cv.put(x, ey + 1, fz, VoxCanvas.tone(c1, 0.62))
		# 獠牙（野猪）：自下颌外翻上弯
		if tusks:
			cv.set_mat(VoxCanvas.M_SCALE)
			for sd: int in [-1, 1]:
				var tx := 6 if sd > 0 else -7
				for k in 9:
					var ty := -4 + k
					var tz := tipz + 6 - k / 3
					cv.put(tx + sd * (k / 4), ty, tz, c3 if k < 7 else c3.lightened(0.2))
					cv.put(tx + sd * (k / 4), ty, tz + 1, c3.darkened(0.12))
		return cv)
	var jaw := _bone(head, "jaw", Vector3(0, -3, -hr.z * 0.8))
	_mesh(jaw, "q_jaw|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-10, -10, -int(sn.z) - 12), Vector3i(9, 4, 8))
		var jl := int(sn.z) + 2
		cv.set_mat(VoxCanvas.M_FUR)
		for i in jl:
			var w := int(ceil(sn.x * (1.0 - float(i) / jl * 0.35)))
			for x in range(-w, w):
				for y in range(-4, 0):
					cv.put(x, y, -i, VoxCanvas.tone(belly if model != "boar" else c2, 0.9 + 0.1 * float(y == -1)))
			if i < jl - 1:
				# 牙：犬齿更长
				cv.set_mat(VoxCanvas.M_SCALE)
				var fang := i == jl - 3
				var tc := Color(0.96, 0.94, 0.88)
				cv.put(-w, 0, -i, tc if i % 2 == 0 or fang else Color(0.6, 0.2, 0.2))
				cv.put(w - 1, 0, -i, tc if i % 2 == 0 or fang else Color(0.6, 0.2, 0.2))
				if fang:
					cv.put(-w, 1, -i, tc)
					cv.put(w - 1, 1, -i, tc)
				cv.set_mat(VoxCanvas.M_FUR)
		# 舌
		cv.set_mat(VoxCanvas.M_JADE)
		cv.box(Vector3i(-2, -1, -jl + 4), Vector3i(1, -1, -2), Color("c05060"))
		cv.box(Vector3i(-1, -1, -jl + 4), Vector3i(0, -1, -2), Color("a83850"))
		return cv)
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
		_mesh(e, "q_ear|" + key, func() -> Variant:
			var cv := VoxCanvas.new(Vector3i(-10, -2, -6), Vector3i(9, 22, 4))
			cv.set_mat(VoxCanvas.M_FUR)
			var h := 16
			var w := 6.8
			match ears:
				"fox":
					h = 18
					w = 7.6
				"small":
					h = 6
					w = 5.0
				"round":
					h = 6
					w = 5.2
			for y in range(0, h):
				var t := float(y) / h
				var hw := w * (1.0 - t) + 0.6
				if ears == "round":
					hw = w * sqrt(maxf(1.0 - pow(t * 1.1, 2.0), 0.05))
				for x in range(-10, 10):
					var ax := absf(x + 0.5)
					if ax > hw:
						continue
					var tipc := c1 if t < 0.7 or model != "fox" else c3
					var k := 0.9 + 0.1 * float(VoxCanvas.h1(x + 3) & 1)
					cv.put(x, y, 0, VoxCanvas.tone(tipc, k))
					cv.put(x, y, 1, VoxCanvas.tone(c1, 0.82))
					cv.put(x, y, 2, VoxCanvas.tone(c1, 0.78))
					if ax < hw - 1.6 and t < 0.75:
						var inner := belly.lerp(Color(1, 0.8, 0.8), 0.2) if model != "boar" else c2
						cv.put(x, y, -1, inner if ax < hw - 2.4 else VoxCanvas.tone(inner, 0.85))
						# 耳内绒毛
						if t < 0.4 and (VoxCanvas.h3(x, y >> 1, 1) & 3) == 0:
							cv.put(x, y, -2, belly.lightened(0.1))
			return cv, sd < 0)
	# 腿
	var lr: float = q["leg_r"]
	var paw: Vector3 = q["paw"]
	var legx_f := chest_r.x * 0.62
	var legx_b := rear_r.x * 0.62
	var claw := Color(0.92, 0.9, 0.84) if model != "bear" else Color(0.24, 0.2, 0.18)
	for spec in [["fl", spine, legx_f, -6.0, 1.0], ["fr", spine, legx_f, -6.0, 1.0], ["bl", hips, legx_b, -4.0, -1.0], ["br", hips, legx_b, -4.0, -1.0]]:
		var nm: String = spec[0]
		var parent: Node3D = spec[1]
		var sx := -1.0 if nm.ends_with("l") else 1.0
		var front := nm.begins_with("f")
		var ly: float = spec[3]
		var leg := _bone(parent, "leg_" + nm, Vector3(sx * float(spec[2]), ly, 2.0 if front else 0.0))
		var sh := _bone(leg, "shin_" + nm, Vector3(0, -upper, 0))
		var fr := front
		_mesh(leg, "q_up_%s|%s" % ["f" if fr else "b", key], func() -> Variant:
			var cv := VoxCanvas.new(Vector3i(-16, -upper - 6, -18), Vector3i(15, 16, 18))
			if fr:
				_limb(cv, 8, -upper, Vector2(lr * 1.35, lr * 1.5), Vector2(lr, lr), c1)
			else:
				# 后腿：大腿肌肉更粗、向前鼓
				_limb(cv, 10, -upper, Vector2(lr * 1.7, lr * 2.0), Vector2(lr, lr * 1.1), c1, -2.0, 3.0)
			return cv, sx < 0)
		_mesh(sh, "q_lo_%s|%s" % ["f" if fr else "b", key], func() -> Variant:
			var cv := VoxCanvas.new(Vector3i(-14, -lower - 8, -18), Vector3i(13, 8, 14))
			var stripe := Color(0, 0, 0, 0)
			if model == "fox":
				stripe = VoxCanvas.tone(c3, 1.0)
			_limb(cv, 4, -lower + 4, Vector2(lr * 0.95, lr * 0.95), Vector2(lr * 0.8, lr * 0.85), VoxCanvas.tone(c1, 0.95) if model != "fox" else c3, 0.0 if fr else 2.0, 0.0)
			# 爪：前伸，四趾分开（趾缝暗线）
			var pc := c3 if model == "fox" else VoxCanvas.tone(c2, 0.8)
			if model == "wolf" or model == "bear":
				pc = VoxCanvas.tone(c1, 0.8)
			cv.set_mat(VoxCanvas.M_FUR)
			var px := int(paw.x)
			var pz := int(paw.z)
			for y in range(-lower, -lower + int(paw.y) + 1):
				for z in range(-pz - 2, 4):
					for x in range(-px, px):
						var gap := posmod(x + px, (2 * px) / 4 if px >= 4 else 2) == 0 and z < -2 and y < -lower + int(paw.y)
						cv.put(x, y, z, VoxCanvas.tone(pc, (0.7 if gap else 0.92 + 0.1 * float(VoxCanvas.h3(x >> 1, y, z >> 1) & 1))))
			# 趾甲 / 蹄
			cv.set_mat(VoxCanvas.M_SCALE)
			if model == "boar":
				for x in range(-px, px):
					cv.put(x, -lower, -pz - 2, Color(0.18, 0.14, 0.12))
					cv.put(x, -lower + 1, -pz - 2, Color(0.2, 0.16, 0.14))
				cv.box(Vector3i(-1, -lower, -pz - 2), Vector3i(0, -lower + 3, -pz - 2), Color(0.1, 0.08, 0.07))
			else:
				var step := maxi((2 * px) / 4, 2)
				for x in range(-px + step / 2, px, step):
					cv.put(x, -lower, -pz - 3, claw)
					cv.put(x, -lower + 1, -pz - 3, claw.darkened(0.1))
					cv.put(x, -lower, -pz - 4, claw.darkened(0.2))
			return cv, sx < 0)
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
	var base := _bone(hips, "base_tail", Vector3(0, rear_r.y * 0.55, rear_r.z * 0.55 - 2.0), Vector3(tail_rest, 0, 0))
	var segs := 3
	var seg_len := 14
	var r0 := 4.4
	var r_mid := 6.8
	match tail_kind:
		"fox":
			segs = 4
			seg_len = 14
			r0 = 5.2
			r_mid = 10.0
		"thin":
			segs = 2
			seg_len = 10
			r0 = 2.0
			r_mid = 1.8
		"stub":
			segs = 1
			seg_len = 8
			r0 = 5.0
			r_mid = 4.4
	var parent2: Node3D = base
	for i in segs:
		var tb := HairStyles.spring_bone(parent2, "tail_%d" % i, Vector3(0, 0 if i == 0 else -seg_len, 0), Vector3(12 if i > 0 else 0, 0, 0), seg_len, 0.14, 40)
		var ii := i
		_mesh(tb, "q_tail%d|%s" % [i, key], func() -> Variant:
			var R := int(ceil(r_mid)) + 4
			var cv := VoxCanvas.new(Vector3i(-R, -seg_len - 4, -R), Vector3i(R - 1, 4, R - 1))
			cv.set_mat(VoxCanvas.M_FUR)
			for yi in range(-2, seg_len + 2):
				var t := (ii + float(yi) / seg_len) / float(segs)
				var r := lerpf(r0, r_mid, sin(minf(t * 1.6, 1.0) * PI * 0.5)) if t < 0.6 else lerpf(r_mid, 2.0, (t - 0.6) / 0.4)
				if tail_kind == "thin":
					r = 2.0 - t
				for z in range(-R, R):
					for x in range(-R, R):
						var ang := atan2(z + 0.5, x + 0.5)
						var tuft := int(floor((ang + PI) / TAU * 10.0))
						var th := VoxCanvas.h3(tuft, (yi + ii * 16 + tuft * 3) / 5, ii)
						var d := Vector2(x + 0.5, z + 0.5).length()
						var rr := r + float(th & 3) * (0.5 if tail_kind != "thin" else 0.0)
						if d > rr:
							continue
						var c := c1
						if tail_kind == "fox" and t > 0.78:
							c = c2
						elif tail_kind == "bushy" and t > 0.8:
							c = back
						elif tail_kind == "bushy" and z > 2:
							c = back
						if d > rr - 1.0:
							c = VoxCanvas.tone(c, 0.9)
						cv.put(x, -yi, z, VoxCanvas.tone(c, 0.9 + 0.14 * float((th >> 3) & 3) / 3.0))
			return cv)
		parent2 = tb


# ================================================================ 石傀（人形骨骼）

static func _golem(rig: BeastRig, stone: Color, dark: Color, glow: Color, key: String) -> void:
	var hips := _bone(rig, "hips", Vector3(0, 52, 0))
	var spine := _bone(hips, "spine", Vector3(0, 8, 0))
	var head := _bone(spine, "head", Vector3(0, 44, -6))
	var arm_l := _bone(spine, "arm_l", Vector3(-32, 36, 0))
	var arm_r := _bone(spine, "arm_r", Vector3(32, 36, 0))
	var fore_l := _bone(arm_l, "forearm_l", Vector3(0, -24, 0))
	var fore_r := _bone(arm_r, "forearm_r", Vector3(0, -24, 0))
	var hand_l := _bone(fore_l, "hand_l", Vector3(0, -24, 0))
	var hand_r := _bone(fore_r, "hand_r", Vector3(0, -24, 0))
	var leg_l := _bone(hips, "leg_l", Vector3(-12, -4, 0))
	var leg_r := _bone(hips, "leg_r", Vector3(12, -4, 0))
	var shin_l := _bone(leg_l, "shin_l", Vector3(0, -24, 0))
	var shin_r := _bone(leg_r, "shin_r", Vector3(0, -24, 0))
	var moss := Color("5a7a3a")
	# 石块纹理：块状明暗 + 块缝 + 块面上缘亮 + 苔藓（只长在朝上一侧）；内部直接填暗色
	var rock := func(cv: VoxCanvas, a: Vector3i, b: Vector3i, block: int) -> void:
		cv.set_mat(VoxCanvas.M_STONE)
		var v_in := cv.e(VoxCanvas.tone(stone, 0.6))
		for z in range(a.z, b.z + 1):
			for y in range(a.y, b.y + 1):
				for x in range(a.x, b.x + 1):
					var surf := x == a.x or x == b.x or y == a.y or y == b.y or z == a.z or z == b.z
					if not surf:
						cv.data[cv.ix(x, y, z)] = v_in
						continue
					var bx := floori(x / float(block))
					var by := floori((y + (bx & 1) * (block / 2)) / float(block))
					var bz := floori(z / float(block))
					var bh := VoxCanvas.h3(bx, by, bz)
					var c := VoxCanvas.tone(stone, 0.8 + 0.28 * float(bh & 7) / 7.0)
					var ly := posmod(y + (bx & 1) * (block / 2), block)
					if ly == 0 or posmod(x, block) == 0 or posmod(z, block) == 0:
						c = VoxCanvas.tone(dark, 0.8)
					elif ly == block - 1:
						c = VoxCanvas.tone(c, 1.1)
					if (bh >> 5) % 5 == 0 and y > (a.y + b.y) / 2 and (VoxCanvas.h3(x, y, z) & 3) != 0:
						c = moss.lerp(c, 0.25 + 0.2 * float(VoxCanvas.h3(x, z, y) & 1))
						cv.putm(x, y, z, c, VoxCanvas.M_FUR)
						continue
					cv.put(x, y, z, c)
	var g := VoxCanvas.glow(glow, 0.95)
	var g2 := VoxCanvas.glow(glow.lightened(0.5), 1.0)
	_mesh(hips, "g_hips|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-24, -14, -16), Vector3i(23, 12, 16))
		rock.call(cv, Vector3i(-20, -10, -12), Vector3i(19, 8, 12), 8)
		# 腰间符文带
		cv.set_mat(VoxCanvas.M_FLAME)
		for x in range(-18, 18, 3):
			cv.put(x, 0, -13, g)
		return cv)
	_mesh(spine, "g_torso|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-34, -4, -22), Vector3i(33, 50, 22))
		rock.call(cv, Vector3i(-18, 0, -12), Vector3i(17, 16, 12), 8)
		rock.call(cv, Vector3i(-28, 18, -18), Vector3i(27, 42, 16), 10)
		rock.call(cv, Vector3i(-20, 42, -14), Vector3i(19, 46, 12), 10)
		# 胸口符文核心：发光阵纹 + 刻槽
		cv.set_mat(VoxCanvas.M_FLAME)
		var core := ["....#....", "..#.#.#..", ".#..#..#.", "#..###..#", "####O####", "#..###..#", ".#..#..#.", "..#.#.#..", "....#...."]
		cv.stamp(core, {"#": g, "O": g2}, Vector3i(-5, 34, -19), Vector3i(1, 0, 0), Vector3i(0, -1, 0))
		# 胸前刻槽中的发光纹路（从核心延伸到两肩）
		for k in 14:
			cv.put(-6 - k, 30 + k / 3, -19, VoxCanvas.glow(glow, 0.7))
			cv.put(5 + k, 30 + k / 3, -19, VoxCanvas.glow(glow, 0.7))
		for y in range(20, 40, 5):
			cv.put(-24, y, -19, VoxCanvas.glow(glow, 0.6))
			cv.put(23, y + 2, -19, VoxCanvas.glow(glow, 0.6))
		# 背后符文
		for k in 5:
			cv.put(-2 + k, 30 + (k % 2) * 3, 17, g)
		return cv)
	_mesh(head, "g_head|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-14, -4, -16), Vector3i(13, 22, 12))
		rock.call(cv, Vector3i(-10, 0, -12), Vector3i(9, 16, 8), 6)
		# 眼缝（发光）+ 额头横槽
		cv.set_mat(VoxCanvas.M_FLAME)
		for x in [-6, -5, -4, 3, 4, 5]:
			cv.put(x, 9, -13, g)
		cv.put(-5, 10, -13, g2)
		cv.put(4, 10, -13, g2)
		cv.set_mat(VoxCanvas.M_STONE)
		cv.box(Vector3i(-8, 13, -13), Vector3i(7, 14, -13), VoxCanvas.tone(dark, 0.7))
		# 下颌石块
		cv.box(Vector3i(-7, 0, -14), Vector3i(6, 3, -13), VoxCanvas.tone(stone, 0.85))
		return cv)
	for side: int in [-1, 1]:
		var arm := arm_r if side > 0 else arm_l
		var fore := fore_r if side > 0 else fore_l
		var hand := hand_r if side > 0 else hand_l
		var mir := side < 0
		_mesh(arm, "g_uarm|" + key, func() -> Variant:
			var cv := VoxCanvas.new(Vector3i(-16, -28, -16), Vector3i(16, 12, 16))
			rock.call(cv, Vector3i(-10, -24, -10), Vector3i(10, 2, 10), 8)
			rock.call(cv, Vector3i(-12, -4, -12), Vector3i(14, 10, 12), 8)
			cv.set_mat(VoxCanvas.M_FLAME)
			cv.put(15, 4, -1, VoxCanvas.glow(glow, 0.7))
			cv.put(15, 4, 0, VoxCanvas.glow(glow, 0.7))
			cv.put(15, 5, 0, g2)
			return cv, mir)
		_mesh(fore, "g_farm|" + key, func() -> Variant:
			var cv := VoxCanvas.new(Vector3i(-16, -28, -16), Vector3i(16, 6, 16))
			rock.call(cv, Vector3i(-10, -22, -10), Vector3i(10, 2, 10), 8)
			cv.set_mat(VoxCanvas.M_FLAME)
			for y in range(-18, -2, 5):
				cv.put(11, y, 0, VoxCanvas.glow(glow, 0.6))
				cv.put(11, y - 1, 0, VoxCanvas.glow(glow, 0.5))
			return cv, mir)
		_mesh(hand, "g_hand|" + key, func() -> Variant:
			var cv := VoxCanvas.new(Vector3i(-16, -18, -16), Vector3i(16, 6, 16))
			rock.call(cv, Vector3i(-12, -14, -12), Vector3i(12, 2, 12), 6)
			# 指节
			cv.set_mat(VoxCanvas.M_STONE)
			for z in range(-10, 11, 5):
				cv.box(Vector3i(-10, -16, z - 1), Vector3i(10, -15, z + 1), VoxCanvas.tone(stone, 0.9))
			return cv, mir)
		var leg := leg_r if side > 0 else leg_l
		var shin := shin_r if side > 0 else shin_l
		_mesh(leg, "g_thigh|" + key, func() -> Variant:
			var cv := VoxCanvas.new(Vector3i(-14, -28, -14), Vector3i(14, 8, 14))
			rock.call(cv, Vector3i(-10, -24, -10), Vector3i(10, 4, 10), 8)
			return cv, mir)
		_mesh(shin, "g_shin|" + key, func() -> Variant:
			var cv := VoxCanvas.new(Vector3i(-16, -30, -20), Vector3i(16, 4, 16))
			rock.call(cv, Vector3i(-10, -24, -10), Vector3i(10, 2, 10), 8)
			rock.call(cv, Vector3i(-12, -28, -18), Vector3i(12, -22, 12), 6)
			cv.set_mat(VoxCanvas.M_FLAME)
			cv.put(-1, -12, -11, VoxCanvas.glow(glow, 0.6))
			cv.put(0, -12, -11, VoxCanvas.glow(glow, 0.6))
			return cv, mir)


# ================================================================ 蛇

static func _snake(rig: BeastRig, c1: Color, c2: Color, c3: Color, key: String) -> void:
	var n := 9
	var seg_len := 16
	var hips := _bone(rig, "hips", Vector3(0, 10, 0))
	var belly := c2
	var pattern := VoxCanvas.tone(c1, 0.55)
	var parent := hips
	# 鳞片着色（覆瓦状：每片 4×3，上缘亮、下缘暗、片缝错位）+ 背部菱形斑纹 + 腹部横鳞
	var scale_col := func(x: int, y: int, z: int, rr: float, zz: int) -> Color:
		var c := c1
		if y < -rr * 0.35:
			var bz := posmod(zz, 4)
			c = belly if bz != 0 else VoxCanvas.tone(belly, 0.78)
			return VoxCanvas.tone(c, 1.04 if bz == 1 else 1.0)
		var pz := posmod(zz, 20)
		var md := absi(x) + absi(pz - 10)
		if y > 0 and md < 5:
			c = pattern
		elif y > 0 and md < 7:
			c = c3.lerp(c1, 0.45)
		# 覆瓦鳞：按 (x, z) 错位分片
		var row := floori(zz / 3.0)
		var col := floori((x + (row & 1) * 2) / 4.0)
		var ry := posmod(zz, 3)
		var rx := posmod(x + (row & 1) * 2, 4)
		var k := 1.0
		if ry == 0:
			k = 1.12
		elif ry == 2 or rx == 0:
			k = 0.8
		k *= 0.95 + 0.08 * float(VoxCanvas.h3(col, row, 3) & 1)
		return VoxCanvas.tone(c, k)
	for i in range(0, n + 1):
		var bn: Node3D = hips
		if i > 0:
			bn = _bone(parent, "seg_%d" % i, Vector3(0, 0, seg_len))
		var r := 11.2 - float(i) * 0.8
		var ii := i
		_mesh(bn, "s_seg%d|%s" % [i, key], func() -> Variant:
			var R := int(ceil(r)) + 3
			var cv := VoxCanvas.new(Vector3i(-R, -R, -3), Vector3i(R - 1, R - 1, seg_len + 3))
			cv.set_mat(VoxCanvas.M_SCALE)
			var v_in := cv.e(VoxCanvas.tone(c1, 0.5))
			for z in range(-2, seg_len + 2):
				var rr := r - 0.6 * float(z) / seg_len
				for y in range(-R, R):
					for x in range(-R, R):
						var dx := (x + 0.5) / rr
						var dy := (y + 0.5) / (rr * 0.85)
						var d2 := dx * dx + dy * dy
						if d2 > 1.0:
							continue
						if d2 < 0.5:
							cv.data[cv.ix(x, y, z)] = v_in
							continue
						cv.put(x, y, z, scale_col.call(x, y, z, rr, z + ii * seg_len))
			return cv)
		parent = bn
	# 尾尖（弹簧）
	var t0 := HairStyles.spring_bone(parent, "tail_0", Vector3(0, 0, seg_len), Vector3(-90, 0, 0), 16, 0.16, 35)
	_mesh(t0, "s_tail|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-6, -20, -6), Vector3i(5, 4, 5))
		cv.set_mat(VoxCanvas.M_SCALE)
		for yi in range(0, 18):
			var rr := 3.2 * (1.0 - yi / 18.0) + 0.6
			for z in range(-4, 4):
				for x in range(-4, 4):
					if Vector2(x + 0.5, z + 0.5).length() <= rr:
						cv.put(x, -yi, z, VoxCanvas.tone(c1 if z > -2 else belly, 0.9 + 0.1 * float(((x + yi) >> 1) & 1)))
		return cv)
	# 颈与头（向前）
	var neck := _bone(hips, "neck", Vector3(0, 0, 0))
	_mesh(neck, "s_neck|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-14, -14, -28), Vector3i(13, 14, 4))
		cv.set_mat(VoxCanvas.M_SCALE)
		var v_in := cv.e(VoxCanvas.tone(c1, 0.5))
		for z in range(-24, 2):
			var rr := 10.8 - float(-z) * 0.08
			for y in range(-12, 12):
				for x in range(-12, 12):
					var dx := (x + 0.5) / rr
					var dy := (y + 0.5) / (rr * 0.85)
					var d2 := dx * dx + dy * dy
					if d2 > 1.0:
						continue
					if d2 < 0.5:
						cv.data[cv.ix(x, y, z)] = v_in
						continue
					cv.put(x, y, z, scale_col.call(x, y, z, rr, z + 400))
		return cv)
	var head := _bone(neck, "head", Vector3(0, 0, -24))
	_mesh(head, "s_head|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-16, -10, -28), Vector3i(15, 12, 6))
		cv.set_mat(VoxCanvas.M_SCALE)
		for z in range(-24, 4):
			var t := float(-z) / 24.0
			var w := 12.0 - t * 4.8
			var h := 7.6 - t * 2.8
			for y in range(-2, int(ceil(h)) + 1):
				for x in range(-int(ceil(w)), int(ceil(w))):
					if absf(x + 0.5) <= w and y + 0.5 <= h:
						var c := c1 if y > 0 else belly
						# 头顶大鳞片（盾鳞）
						var k := 0.92 + 0.1 * float(((x >> 2) + (z >> 2)) & 1)
						if y > h - 1.5 and (posmod(x, 5) == 0 or posmod(z, 5) == 0):
							k = 0.78
						cv.put(x, y, z, VoxCanvas.tone(c, k))
		# 眼：金色竖瞳 + 眉鳞
		for sd: int in [-1, 1]:
			var x := 8 if sd > 0 else -9
			cv.set_mat(VoxCanvas.M_EYE)
			cv.box(Vector3i(x, 3, -15), Vector3i(x, 5, -13), VoxCanvas.glow(c3, 0.5))
			cv.put(x, 4, -14, Color(0.05, 0.03, 0.02))
			cv.put(x, 5, -14, Color(0.05, 0.03, 0.02))
			cv.put(x, 5, -15, Color(1, 1, 1, 0.8))
			cv.set_mat(VoxCanvas.M_SCALE)
			cv.box(Vector3i(x, 6, -16), Vector3i(x + sd, 6, -12), VoxCanvas.tone(c1, 0.55))
		# 鼻孔
		cv.put(-3, 4, -24, Color(0.1, 0.1, 0.1))
		cv.put(2, 4, -24, Color(0.1, 0.1, 0.1))
		return cv)
	var jaw := _bone(head, "jaw", Vector3(0, -2, 0))
	_mesh(jaw, "s_jaw|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-14, -6, -26), Vector3i(13, 3, 4))
		cv.set_mat(VoxCanvas.M_SCALE)
		for z in range(-22, 2):
			var w := 10.8 - float(-z) * 0.2
			for x in range(-int(ceil(w)), int(ceil(w))):
				if absf(x + 0.5) <= w:
					cv.put(x, -2, z, belly)
					cv.put(x, -1, z, VoxCanvas.tone(belly, 0.9))
		# 口腔 + 叉舌
		cv.set_mat(VoxCanvas.M_JADE)
		cv.box(Vector3i(-6, 0, -18), Vector3i(5, 0, -2), Color("802838"))
		cv.box(Vector3i(-1, 1, -20), Vector3i(0, 1, -4), Color("c04050"))
		cv.put(-2, 1, -22, Color("c04050"))
		cv.put(1, 1, -22, Color("c04050"))
		# 毒牙
		cv.set_mat(VoxCanvas.M_SCALE)
		for sd: int in [-1, 1]:
			var fx := 5 if sd > 0 else -6
			cv.box(Vector3i(fx, 0, -17), Vector3i(fx, 3, -17), Color(0.96, 0.95, 0.9))
		return cv)


# ================================================================ 鹤

static func _crane(rig: BeastRig, white: Color, black: Color, red: Color, key: String) -> void:
	var hips := _bone(rig, "hips", Vector3(0, 76, 0))
	_mesh(hips, "c_body|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-18, -18, -24), Vector3i(17, 18, 42))
		_blob(cv, Vector3(0, 0, 4), Vector3(13, 13, 21), white, white, VoxCanvas.tone(white, 0.93), 0.6, -0.5, 0)
		# 背羽：覆瓦状羽片（每片 5 宽，羽缘略暗）
		cv.set_mat(VoxCanvas.M_FUR)
		for z in range(-8, 20):
			for x in range(-10, 10):
				var fz := int(floor((z + (floori(x / 5.0) & 1) * 2) / 4.0))
				var y := 12
				while y > 0 and not cv.solid(x, y, z):
					y -= 1
				if y > 4 and posmod(z + (floori(x / 5.0) & 1) * 2, 4) == 0:
					cv.put(x, y, z, VoxCanvas.tone(white, 0.86))
		# 尾部黑色长羽（收拢的次级飞羽）：一根根羽片，末端分叉
		for z in range(16, 40):
			for x in range(-10, 10):
				var y0 := 2 - (z - 16) / 3
				var feather := floori((x + 10) / 4.0)
				var fend := 36 + VoxCanvas.h1(feather + 9) % 4
				if z > fend:
					continue
				for y in range(y0 - 4, y0 + 4):
					var c := VoxCanvas.tone(black, 0.9 + 0.2 * float((x + z) & 1))
					if posmod(x + 10, 4) == 0:
						c = VoxCanvas.tone(black, 1.6)   # 羽轴
					cv.put(x, y, z, c)
		return cv)
	var n0 := _bone(hips, "neck_0", Vector3(0, 8, -16), Vector3(62, 0, 0))
	var n1 := _bone(n0, "neck_1", Vector3(0, 0, -18), Vector3(-30, 0, 0))
	for nb in [[n0, "c_n0"], [n1, "c_n1"]]:
		var node: Node3D = nb[0]
		var is_upper: bool = str(nb[1]) == "c_n1"
		_mesh(node, str(nb[1]) + "|" + key, func() -> Variant:
			var cv := VoxCanvas.new(Vector3i(-7, -7, -24), Vector3i(6, 7, 6))
			cv.set_mat(VoxCanvas.M_FUR)
			for z in range(-20, 4):
				for y in range(-4, 4):
					for x in range(-4, 4):
						if (x == -4 or x == 3) and (y == -4 or y == 3):
							continue
						var c := black if is_upper else white
						cv.put(x, y, z, VoxCanvas.tone(c, 0.92 + 0.1 * float(((x + y + z) >> 1) & 1)))
			return cv)
	var head := _bone(n1, "head", Vector3(0, 0, -20), Vector3(-28, 0, 0))
	_mesh(head, "c_head|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-8, -8, -32), Vector3i(7, 10, 8))
		cv.set_mat(VoxCanvas.M_FUR)
		cv.rbox(Vector3i(-4, -4, -8), Vector3i(3, 4, 2), black, 1)
		cv.box(Vector3i(-4, -2, 0), Vector3i(3, 2, 3), white)
		# 丹顶（红冠，微微发亮）
		cv.set_mat(VoxCanvas.M_JADE)
		cv.rbox(Vector3i(-3, 4, -6), Vector3i(2, 6, 0), VoxCanvas.glow(red, 0.15), 1)
		cv.put(-1, 7, -4, VoxCanvas.glow(red.lightened(0.2), 0.2))
		# 眼
		cv.set_mat(VoxCanvas.M_EYE)
		for sd: int in [-1, 1]:
			var ex := 3 if sd > 0 else -4
			cv.put(ex, 2, -6, Color(0.95, 0.85, 0.3))
			cv.put(ex, 2, -5, Color(0.05, 0.05, 0.05))
			cv.put(ex, 3, -6, Color(1, 1, 1, 0.8))
		# 长喙（上）：两格宽，尖端变暗
		cv.set_mat(VoxCanvas.M_SCALE)
		for z in range(-28, -8):
			var t := float(-8 - z) / 20.0
			var bc := Color("c8b890").lerp(Color("8a7a58"), t)
			cv.box(Vector3i(-1, 0, z), Vector3i(0, 1 if t < 0.7 else 0, z), bc)
			if t < 0.4:
				cv.put(-2, 0, z, bc.darkened(0.1))
				cv.put(1, 0, z, bc.darkened(0.1))
		return cv)
	var jaw := _bone(head, "jaw", Vector3(0, -1, -8))
	_mesh(jaw, "c_jaw|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-4, -4, -24), Vector3i(3, 2, 2))
		cv.set_mat(VoxCanvas.M_SCALE)
		for z in range(-18, 0):
			cv.put(-1, -1, z, Color("a89870"))
			cv.put(0, -1, z, Color("a89870"))
		return cv)
	for side: int in [-1, 1]:
		var sn := "l" if side < 0 else "r"
		var w := _bone(hips, "wing_" + sn, Vector3(side * 12.0, 6, -8))
		var wt := _bone(w, "wing_tip_" + sn, Vector3(0, 0, 0))
		# 翅膀静止时收拢在身侧（沿 +Z 向后折叠）；展开时绕 Z 外展
		_mesh(w, "c_wing|" + key, func() -> Variant:
			var cv := VoxCanvas.new(Vector3i(-4, -32, -6), Vector3i(6, 6, 40))
			cv.set_mat(VoxCanvas.M_FUR)
			for z in range(-2, 36):
				for y in range(-20, 4):
					var t := float(z + 2) / 38.0
					if y < -20 + int(t * 12.0):
						continue
					# 覆羽（白）→ 飞羽（黑），飞羽一根根分开（羽缝 + 羽轴）
					var c := white
					var fe := floori((z + 2) / 4.0)
					if z >= 20 or (y < -12 and z >= 12):
						c = black
						var fz := posmod(z + 2, 4)
						if fz == 0:
							c = VoxCanvas.tone(black, 0.6)
						elif fz == 2:
							c = VoxCanvas.tone(black, 1.5)
						# 飞羽末端参差
						if y < -18 + int(t * 12.0) + (VoxCanvas.h1(fe) % 3):
							continue
					elif posmod(y, 4) == 0:
						c = VoxCanvas.tone(white, 0.86)
					cv.put(0, y, z, VoxCanvas.tone(c, 0.92 + 0.1 * float(((y + z) >> 1) & 1)))
					cv.put(1, y, z, VoxCanvas.tone(c, 0.84))
					if y > -6 and z < 24:
						cv.put(2, y, z, VoxCanvas.tone(c, 0.8))
			return cv, side < 0)
		wt.set_meta("bone", true)
		var leg := _bone(hips, "leg_" + sn, Vector3(side * 6.0, -10, 4))
		var shin := _bone(leg, "shin_" + sn, Vector3(0, -30, 0))
		_mesh(leg, "c_leg|" + key, func() -> Variant:
			var cv := VoxCanvas.new(Vector3i(-6, -34, -6), Vector3i(5, 4, 5))
			cv.set_mat(VoxCanvas.M_FUR)
			cv.rbox(Vector3i(-3, -8, -3), Vector3i(2, 0, 2), VoxCanvas.tone(white, 0.9), 1)
			cv.set_mat(VoxCanvas.M_SCALE)
			cv.box(Vector3i(-1, -30, -1), Vector3i(0, -8, 0), Color("3a3a3a"))
			# 腿上的横纹鳞
			for y in range(-30, -8, 3):
				cv.box(Vector3i(-1, y, -1), Vector3i(0, y, 0), Color("2a2a2a"))
			return cv, side < 0)
		_mesh(shin, "c_shin|" + key, func() -> Variant:
			var cv := VoxCanvas.new(Vector3i(-8, -40, -16), Vector3i(7, 4, 8))
			cv.set_mat(VoxCanvas.M_SCALE)
			cv.box(Vector3i(-1, -36, -1), Vector3i(0, 0, 0), Color("333333"))
			cv.box(Vector3i(-2, -2, -2), Vector3i(1, 1, 1), Color("3a3a3a"))
			for y in range(-36, 0, 3):
				cv.box(Vector3i(-1, y, -1), Vector3i(0, y, 0), Color("262626"))
			# 爪：三趾前 + 一趾后，趾尖爪甲
			for z in range(-10, 6):
				cv.box(Vector3i(-1, -36, z), Vector3i(0, -36, z), Color("2a2a2a"))
			for sd: int in [-1, 1]:
				for k in 6:
					cv.put(sd * (1 + k / 2) - (1 if sd < 0 else 0), -36, -2 - k, Color("2a2a2a"))
			cv.put(-1, -36, -11, Color("888070"))
			cv.put(0, -36, -11, Color("888070"))
			return cv, side < 0)
			# 腿（shin）下端着地：hips 76 - 10 - 30 - 36 = 0
	var tail := HairStyles.spring_bone(hips, "tail_0", Vector3(0, 2, 28), Vector3(-100, 0, 0), 12, 0.2, 25)
	_mesh(tail, "c_tail|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-8, -16, -3), Vector3i(7, 2, 3))
		cv.set_mat(VoxCanvas.M_FUR)
		for y in range(-12, 1):
			for x in range(-6, 6):
				if y < -9 and (x & 1) == 0:
					continue
				cv.put(x, y, 0, VoxCanvas.tone(white, 0.95 - 0.02 * float(x & 1)))
		return cv)


# ================================================================ 蜘蛛

static func _spider(rig: BeastRig, body: Color, mark: Color, eye: Color, key: String) -> void:
	var hips := _bone(rig, "hips", Vector3(0, 22, 16))
	var hair := VoxCanvas.tone(body, 1.35)
	_mesh(hips, "sp_abd|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-24, -22, -8), Vector3i(23, 26, 48))
		_blob(cv, Vector3(0, 4, 20), Vector3(20, 18, 24), body, VoxCanvas.tone(body, 0.8), VoxCanvas.tone(body, 1.1), 0.6, -0.6, 9)
		# 甲壳光泽：背部换几丁质材质
		for z in range(-4, 46):
			for x in range(-20, 20):
				var y := 24
				while y > 0 and not cv.solid(x, y, z):
					y -= 1
				if y <= 0:
					continue
				# 背部沙漏斑纹（带亮边）
				var w := 3.0 + absf(float(z - 22)) * 0.35
				var ax := absf(x + 0.5)
				if ax < w and z > 4 and z < 40:
					var c := VoxCanvas.tone(mark, 0.9 + 0.2 * float(((x + z) >> 1) & 1))
					if ax > w - 1.2:
						c = mark.lightened(0.3)
					cv.putm(x, y, z, c, VoxCanvas.M_SCALE)
				elif (VoxCanvas.h3(x, z, 5) & 3) == 0:
					cv.putm(x, y, z, VoxCanvas.tone(body, 1.15), VoxCanvas.M_SCALE)
		# 纺器
		cv.set_mat(VoxCanvas.M_SCALE)
		cv.rbox(Vector3i(-3, -2, 42), Vector3i(2, 1, 45), VoxCanvas.tone(body, 0.7), 1)
		return cv)
	var spine := _bone(hips, "spine", Vector3(0, 0, -8))
	_mesh(spine, "sp_ceph|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-18, -14, -28), Vector3i(17, 16, 8))
		_blob(cv, Vector3(0, 1, -10), Vector3(14, 11, 16), body, VoxCanvas.tone(body, 0.85), VoxCanvas.tone(body, 1.1), 0.5, -0.6, 11)
		# 八只眼（发光，大小不一，带高光）
		cv.set_mat(VoxCanvas.M_EYE)
		for p in [[-4, 8, 2], [3, 8, 2], [-8, 6, 1], [7, 6, 1], [-2, 11, 1], [1, 11, 1], [-6, 10, 1], [5, 10, 1]]:
			var ex: int = p[0]
			var ey: int = p[1]
			var sz: int = p[2]
			var fz := _front(cv, ex, ey)
			if fz > 9000:
				continue
			for dy in sz + 1:
				for dx in sz + 1:
					cv.put(ex + dx - sz / 2, ey - dy, fz - 1, VoxCanvas.glow(eye if dy > 0 or sz == 0 else eye.lightened(0.3), 0.75))
			if sz > 1:
				cv.put(ex, ey, fz - 2, Color(1, 1, 1, 0.7))
		return cv)
	for side: int in [-1, 1]:
		var jn := "jaw_" + ("l" if side < 0 else "r")
		var j := _bone(spine, jn, Vector3(side * 4.0, -4, -24))
		_mesh(j, "sp_fang|" + key, func() -> Variant:
			var cv := VoxCanvas.new(Vector3i(-4, -14, -6), Vector3i(4, 2, 4))
			cv.set_mat(VoxCanvas.M_SCALE)
			cv.rbox(Vector3i(-2, -6, -2), Vector3i(1, 0, 1), VoxCanvas.tone(mark, 0.6), 1)
			cv.set_mat(VoxCanvas.M_FUR)
			for y in range(-6, 0, 2):
				cv.put(-3, y, 0, hair)
			cv.set_mat(VoxCanvas.M_SCALE)
			for k in 7:
				cv.put(-1 + (1 if k > 4 else 0), -7 - k, -1 - k / 3, Color(0.92, 0.88, 0.8).darkened(0.05 * k))
			return cv, side < 0)
	# 八条腿：每侧 4 条，从头胸部两侧伸出，上段斜向上外，下段向下着地；关节环 + 刚毛
	var fwd := [-35.0, -12.0, 12.0, 38.0]   # 绕 Y 的朝向（度，负为向前）
	for i in range(1, 5):
		for side: int in [-1, 1]:
			var sn := "%d%s" % [i, "l" if side < 0 else "r"]
			var yaw: float = fwd[i - 1] * (-1.0 if side < 0 else 1.0)
			# leg_*：只带朝向（绕 Y），摆腿绕竖直轴；femur 节点（非骨骼）抬起大腿；knee_* 让小腿向下着地
			var leg := _bone(spine, "leg_" + sn, Vector3(side * 11.0, 0, -16.0 + i * 5.0), Vector3(0, yaw, 0))
			var femur := Node3D.new()
			femur.name = "femur"
			femur.rotation_degrees = Vector3(0, 0, side * 125.0)
			leg.add_child(femur)
			var knee := _bone(femur, "knee_" + sn, Vector3(0, -28, 0), Vector3(0, 0, -side * 105.0))
			_mesh(femur, "sp_femur|" + key, func() -> Variant:
				var cv := VoxCanvas.new(Vector3i(-5, -31, -5), Vector3i(4, 3, 4))
				cv.set_mat(VoxCanvas.M_SCALE)
				for y in range(-28, 1):
					var r := 2 if y > -24 else 2
					cv.box(Vector3i(-r, y, -r), Vector3i(r - 1, y, r - 1), VoxCanvas.tone(body, 0.9 + 0.15 * float((y >> 1) & 1)))
				for y in range(-24, 0, 6):
					cv.box(Vector3i(-3, y, -3), Vector3i(2, y, 2), VoxCanvas.tone(mark, 0.7))
				cv.set_mat(VoxCanvas.M_FUR)
				for y in range(-26, -2, 3):
					cv.put(-3, y, 0, hair)
					cv.put(2, y - 1, -1, hair)
				return cv, side < 0)
			_mesh(knee, "sp_tibia|" + key, func() -> Variant:
				var cv := VoxCanvas.new(Vector3i(-5, -44, -5), Vector3i(4, 4, 4))
				cv.set_mat(VoxCanvas.M_SCALE)
				cv.rbox(Vector3i(-3, -4, -3), Vector3i(2, 2, 2), VoxCanvas.tone(mark, 0.8), 1)
				for y in range(-40, -3):
					var th := 2 if y > -28 else 1
					cv.box(Vector3i(-th, y, -th), Vector3i(th - 1, y, th - 1), VoxCanvas.tone(body, 0.88 + 0.15 * float((y >> 1) & 1)))
				cv.box(Vector3i(-1, -42, -1), Vector3i(0, -40, 0), VoxCanvas.tone(mark, 0.5))
				cv.set_mat(VoxCanvas.M_FUR)
				for y in range(-36, -6, 4):
					cv.put(-3 if y > -28 else -2, y, 0, hair)
				return cv, side < 0)
