class_name HairStyles
## 发型：头顶发帽（头网格内）+ 刘海/鬓发 + 弹簧发束（双马尾、马尾、长发、披发的发尾链）+ 金饰。
## 另负责兽耳（狐/猫，弹簧骨骼 ear_l/r）、龙角（头网格内）。
##
## 头部局部坐标见 FacePainter：头颅 x -8..7，y 2..17，z -8..7；前额刘海在 z=-9（厚发 z=-10）。
## 发色：每根“发丝”（按表面坐标划分的列）有独立明暗，少量挑染 hair_color2，头顶有一圈天使环高光。

const VOXEL := 0.025

## 每种发型的头帽参数：
##  puff   发量层数（0 贴头，1 薄，2 蓬松）
##  side   两侧头发下缘 y；back 后脑下缘 y
##  bangs  刘海每列（x = -9..8）下端 y（大于 17 表示无刘海）
##  lock   鬓发（脸两侧）下端 y；hairline 露额发型的前额发际线 y
const STYLES := {
	"twin_tails": {"puff": 2, "side": 3, "back": 1, "lock": 1,
		"bangs": [2, 2, 11, 13, 12, 14, 13, 11, 14, 13, 11, 13, 14, 12, 13, 11, 2, 2]},
	"ponytail": {"puff": 2, "side": 4, "back": 1, "lock": 2,
		"bangs": [3, 3, 10, 12, 14, 13, 12, 11, 14, 13, 11, 12, 13, 14, 12, 10, 3, 3]},
	"long": {"puff": 2, "side": 2, "back": 1, "lock": 1,
		"bangs": [2, 3, 6, 9, 10, 12, 13, 15, 18, 18, 15, 13, 12, 10, 9, 6, 3, 2]},
	"flowing": {"puff": 2, "side": 1, "back": 0, "lock": 0,
		"bangs": [1, 2, 5, 7, 9, 10, 11, 12, 12, 13, 13, 14, 14, 15, 16, 12, 6, 3]},
	"short": {"puff": 1, "side": 5, "back": 2, "lock": 5,
		"bangs": [6, 7, 12, 13, 12, 14, 13, 12, 14, 13, 12, 14, 13, 12, 13, 12, 7, 6]},
	"bun": {"puff": 0, "side": 9, "back": 3, "lock": 5, "hairline": 15,
		"bangs": [8, 8, 7, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 6, 8, 8]},
}
const STYLES_M := {
	"short": {"puff": 1, "side": 9, "back": 3, "lock": 8, "spiky": true,
		"bangs": [9, 9, 13, 14, 12, 14, 13, 15, 14, 13, 15, 13, 14, 12, 14, 13, 9, 9]},
	"bun": {"puff": 0, "side": 9, "back": 3, "lock": 8, "hairline": 16,
		"bangs": [9, 9, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 18, 9, 9]},
	"ponytail": {"puff": 1, "side": 7, "back": 2, "lock": 6,
		"bangs": [7, 7, 11, 13, 12, 14, 13, 15, 16, 16, 15, 13, 14, 12, 13, 11, 7, 7]},
	"long": {"puff": 1, "side": 3, "back": 1, "lock": 3,
		"bangs": [4, 5, 8, 11, 12, 13, 14, 16, 18, 18, 16, 14, 13, 12, 11, 8, 5, 4]},
	"flowing": {"puff": 2, "side": 2, "back": 0, "lock": 2,
		"bangs": [3, 4, 7, 9, 11, 12, 13, 14, 16, 18, 18, 15, 14, 13, 11, 8, 4, 3]},
	"twin_tails": {"puff": 1, "side": 4, "back": 1, "lock": 4,
		"bangs": [4, 4, 10, 12, 13, 12, 14, 12, 13, 13, 12, 14, 12, 13, 12, 10, 4, 4]},
}


static func style_of(s: CharSpec) -> Dictionary:
	var st := s.hair_style
	if not s.female and STYLES_M.has(st):
		return STYLES_M[st]
	return STYLES.get(st, STYLES["twin_tails"])


# ================================================================ 发色

## 一根发丝的颜色：strand 为发丝编号，y 为高度（天使环），edge 为是否在外层
static var _sc_spec: CharSpec = null
static var _sc_memo: Dictionary = {}


static func strand_col(s: CharSpec, strand: int, y: int, outer: bool = true) -> Color:
	var band := 3
	if outer:
		band = 1 if y == 15 else (2 if y == 16 else 0)
	var mk := strand * 4 + band
	if _sc_spec != s:
		_sc_spec = s
		_sc_memo.clear()
	elif _sc_memo.has(mk):
		return _sc_memo[mk]
	var c := _strand_col(s, strand, y, outer)
	_sc_memo[mk] = c
	return c


static func _strand_col(s: CharSpec, strand: int, y: int, outer: bool) -> Color:
	var h := VoxCanvas.h1(strand * 7 + 3)
	var k: float = [0.80, 0.88, 0.94, 1.0, 1.0, 1.05, 1.1, 0.97][h & 7]
	var c := VoxCanvas.tone(s.hair, k)
	var hs := (h >> 4) % 11
	if hs == 0:
		c = c.lerp(s.hair2, 0.7)
	elif hs < 3:
		c = c.lerp(s.hair2, 0.3)
	# 天使环（头顶偏前的一圈高光）
	if outer and (y == 15 or y == 16) and (h >> 8) % 3 != 0:
		c = c.lerp(s.hair2.lightened(0.15), 0.42 if y == 15 else 0.25)
	return c


static func _dark(s: CharSpec) -> Color:
	return Color(s.hair.r * 0.55, s.hair.g * 0.5, s.hair.b * 0.55)


# ================================================================ 头帽

static func paint_cap(cv: VoxCanvas, s: CharSpec) -> void:
	var st := style_of(s)
	var puff: int = st["puff"]
	var side_y: int = st["side"]
	var back_y: int = st["back"]
	var lock_y: int = st["lock"]
	var bangs: Array = st["bangs"]
	var hairline: int = int(st.get("hairline", 11))
	var has_mark := str(s.a.get("mark", "none")) != "none"
	var dark := _dark(s)
	# 1) 头颅表面染发：顶、两侧、后脑、额头（刘海后方）
	for z in range(-8, 8):
		for x in range(-8, 8):
			cv.put(x, 17, z, strand_col(s, x, 17))
	for y in range(2, 17):
		for z in range(-7, 8):
			if y >= side_y or z > 1:
				cv.put(-8, y, z, strand_col(s, 100 + z, y))
				cv.put(7, y, z, strand_col(s, 200 + z, y))
		for x in range(-8, 8):
			cv.put(x, y, 7, strand_col(s, 300 + x, y))
	# 前额：有刘海遮挡处画暗色（刘海缝隙里透出的头发阴影），无刘海处按发际线画梳向后的头发
	for x in range(-8, 8):
		var tip_f: int = bangs[x + 9]
		if has_mark and (x == -1 or x == 0):
			tip_f = maxi(tip_f, 15)
		for y in range(hairline, 17):
			if tip_f <= 17:
				if y >= tip_f:
					cv.put(x, y, -8, dark if y < 16 else strand_col(s, x, y))
			else:
				cv.put(x, y, -8, strand_col(s, x, y))
	# 2) 第一层：顶 y=18、两侧 x=-9/8、后 z=8
	for z in range(-8, 9):
		for x in range(-8, 8):
			cv.put(x, 18, z, strand_col(s, x, 18))
	for z in range(-8, 9):
		var ylo := side_y if z < 3 else mini(side_y, back_y + 2)
		for y in range(ylo, 18):
			cv.put(-9, y, z, strand_col(s, 400 + z, y))
			cv.put(8, y, z, strand_col(s, 500 + z, y))
	for x in range(-9, 9):
		var yb := back_y + (VoxCanvas.h1(x + 77) % 2)
		for y in range(yb, 18):
			cv.put(x, y, 8, strand_col(s, 600 + x, y))
	# 3) 第二层（蓬松）
	if puff >= 2:
		for z in range(-7, 8):
			for x in range(-7, 7):
				if (absi(x + 0) >= 7 or z <= -7 or z >= 7) and VoxCanvas.h3(x, 19, z) % 3 == 0:
					continue
				cv.put(x, 19, z, strand_col(s, x, 19))
		for z in range(-7, 8):
			for y in range(maxi(side_y + 6, 9), 18):
				if (y == 17 or z == -7 or z == 7) and VoxCanvas.h3(z, y, 5) % 2 == 0:
					continue
				cv.put(-10, y, z, strand_col(s, 400 + z, y))
				cv.put(9, y, z, strand_col(s, 500 + z, y))
		for x in range(-8, 8):
			var yb2 := maxi(back_y + 4, 4) - (VoxCanvas.h1(x + 31) % 3)
			for y in range(yb2, 18):
				if (y == 17 or x == -8 or x == 7) and VoxCanvas.h3(x, y, 9) % 2 == 0:
					continue
				cv.put(x, y, 9, strand_col(s, 600 + x, y))
		# 后脑隆起（第三层），让后脑勺更圆
		for x in range(-6, 6):
			for y in range(8, 17):
				if (y == 16 or y == 8 or x == -6 or x == 5) and VoxCanvas.h3(x, y, 10) % 2 == 0:
					continue
				cv.put(x, y, 10, strand_col(s, 600 + x, y))
		# 顶部再隆起一层
		for z in range(-5, 7):
			for x in range(-5, 5):
				if (x == -5 or x == 4 or z == -5 or z == 6) and VoxCanvas.h3(x, 20, z) % 2 == 0:
					continue
				cv.put(x, 20, z, strand_col(s, x, 20))
	elif puff == 1:
		for z in range(-6, 7):
			for x in range(-6, 6):
				if VoxCanvas.h3(x, 19, z) % 4 != 0:
					cv.put(x, 19, z, strand_col(s, x, 19))
	# 4) 刘海（z=-9），蓬松发型再加一层 z=-10
	for i in bangs.size():
		var x := i - 9
		var tip: int = bangs[i]
		if has_mark and (x == -1 or x == 0) and tip < 15:
			tip = 15
		if tip > 17:
			continue
		for y in range(tip, 19):
			var c := strand_col(s, 700 + x, y)
			if y == tip:
				c = VoxCanvas.tone(c, 0.92)
			cv.put(x, y, -9, c)
		if puff >= 2 and x >= -8 and x <= 7:
			var t2 := maxi(tip + 3, 14) + (VoxCanvas.h1(x + 5) % 2)
			for y in range(t2, 19):
				cv.put(x, y, -10, strand_col(s, 800 + x, y))
	# 5) 鬓发：脸两侧垂下的发束（厚 2~3）
	for side: int in [-1, 1]:
		var xo := -9 if side < 0 else 8
		var xi := -8 if side < 0 else 7
		for y in range(lock_y, 18):
			for z in range(-9, -5):
				cv.put(xo, y, z, strand_col(s, 900 + side * 10 + z, y))
			if y < 16:
				cv.put(xi, y, -9, strand_col(s, 950 + side * 10, y))
		if puff >= 2:
			for y in range(lock_y + 3, 17):
				cv.put(xo + side, y, -8, strand_col(s, 980 + side, y))
				cv.put(xo + side, y, -7, strand_col(s, 981 + side, y))
	if st.get("spiky", false):
		_spikes(cv, s)


## 男式短发：头顶随机发簇
static func _spikes(cv: VoxCanvas, s: CharSpec) -> void:
	for i in 9:
		var h := VoxCanvas.h1(i * 31 + 7)
		var x := -6 + (h % 12)
		var z := -6 + ((h >> 5) % 12)
		var hgt := 1 + ((h >> 9) % 2)
		for y in range(19, 19 + hgt):
			cv.put(x, y, z, strand_col(s, x, y))
			cv.put(x + 1, y, z, strand_col(s, x + 1, y))
			if y == 19:
				cv.put(x, y, z + 1, strand_col(s, x, y))


# ================================================================ 发饰与特殊发型（头网格内）

static func paint_extras(cv: VoxCanvas, s: CharSpec) -> void:
	var gold := s.gold
	var ghi := s.gold_hi
	var gsh := s.gold_sh
	match s.hair_style:
		"twin_tails":
			for side: int in [-1, 1]:
				var x0 := -12 if side < 0 else 9
				cv.box(Vector3i(x0, 14, 0), Vector3i(x0 + 2, 17, 4), gold)
				cv.box(Vector3i(x0, 17, 0), Vector3i(x0 + 2, 17, 4), ghi)
				cv.box(Vector3i(x0, 14, 0), Vector3i(x0 + 2, 14, 4), gsh)
				var gx := x0 if side < 0 else x0 + 2
				cv.put(gx, 15, 1, s.gem)
				cv.put(gx, 16, 1, VoxelGrid.glow(s.gem.lightened(0.3), 0.3))
				cv.put(gx, 15, 3, s.gem)
		"ponytail":
			# 发根金环
			cv.box(Vector3i(-2, 13, 9), Vector3i(1, 17, 11), gold)
			cv.box(Vector3i(-2, 17, 9), Vector3i(1, 17, 11), ghi)
			cv.put(-1, 15, 11, s.gem)
			cv.put(0, 15, 11, s.gem)
		"long":
			cv.box(Vector3i(-11, 13, -4), Vector3i(-10, 15, -2), gold)
			cv.put(-11, 14, -3, s.gem)
		"flowing":
			# 后脑半冠
			for x in range(-6, 6):
				cv.put(x, 17, 10, gold if (x + 6) % 3 else ghi)
				cv.put(x, 16, 10, gsh)
			cv.put(-1, 17, 10, s.gem)
			cv.put(0, 17, 10, s.gem)
			cv.box(Vector3i(-1, 18, 10), Vector3i(0, 18, 10), ghi)
		"bun":
			_bun(cv, s)
		"short":
			if s.female:
				cv.box(Vector3i(-10, 14, -6), Vector3i(-10, 15, -3), gold)
				cv.put(-10, 15, -5, s.gem)


static func _bun(cv: VoxCanvas, s: CharSpec) -> void:
	var c := Vector3(-0.0, 21.0, 1.0)
	var r := Vector3(4.2, 3.2, 4.2) if s.female else Vector3(3.6, 3.0, 3.6)
	var l := Vector3i((c - r).floor())
	var h := Vector3i((c + r).ceil())
	for z in range(l.z, h.z + 1):
		for y in range(l.y, h.y + 1):
			for x in range(l.x, h.x + 1):
				var d := (Vector3(x + 0.5, y + 0.5, z + 0.5) - c) / r
				if d.length_squared() <= 1.0:
					# 发髻：按环绕角分发丝
					var ang := int(floor((atan2(z + 0.5 - c.z, x + 0.5 - c.x) + PI) / TAU * 14.0))
					cv.put(x, y, z, strand_col(s, 1200 + ang, y - 4))
	# 髻根与头顶的连接
	for z in range(-3, 5):
		for x in range(-4, 4):
			cv.put(x, 18, z, strand_col(s, x, 18))
	# 发冠 / 金环
	var gold := s.gold
	for z in range(-3, 5):
		for x in range(-4, 4):
			if x == -4 or x == 3 or z == -3 or z == 4:
				cv.put(x, 19, z, gold)
				if not s.female and (x + z) % 2 == 0:
					cv.put(x, 20, z, s.gold_hi)
	if not s.female:
		# 男式小冠：前方立起的冠片
		cv.box(Vector3i(-2, 20, -3), Vector3i(1, 23, -3), gold)
		cv.box(Vector3i(-1, 24, -3), Vector3i(0, 24, -3), s.gold_hi)
		cv.put(-1, 21, -4, s.gem)
		cv.put(0, 21, -4, s.gem)
	# 发簪（横穿发髻）
	for x in range(-8, 8):
		cv.put(x, 21, 1, s.gold_hi if x < -6 else s.gold)
	cv.put(-9, 21, 1, s.gem)
	cv.put(-9, 22, 1, s.gem.lightened(0.2))
	cv.put(-9, 20, 1, s.gem.darkened(0.2))


# ================================================================ 龙角（头网格内）

static func paint_horns(cv: VoxCanvas, s: CharSpec) -> void:
	var base := Color("e8dcc0")
	var tipc := s.hair2.lerp(Color("f0c060"), 0.5)
	for side: int in [-1, 1]:
		var p := Vector3(-5.0 if side < 0 else 4.0, 18.0, -3.0)
		var pts: Array[Vector3] = []
		# 主干：向上后方弯曲
		for i in 12:
			var t := i / 11.0
			pts.append(p + Vector3(side * (1.5 * t), 7.5 * t, 5.0 * t * t))
		for i in pts.size():
			var t := i / float(pts.size() - 1)
			var c := base.lerp(tipc, t)
			var q: Vector3 = pts[i]
			var rr := 1.2 * (1.0 - t) + 0.4
			cv.ellipsoid(q + Vector3(0.5, 0.5, 0.5), Vector3(rr, rr, rr), c)
		# 分叉
		var b0: Vector3 = pts[5]
		for i in 5:
			var t := i / 4.0
			cv.ellipsoid(b0 + Vector3(side * 2.5 * t + 0.5, 1.5 * t + 0.5, -1.5 * t + 0.5), Vector3(0.7, 0.7, 0.7), base.lerp(tipc, 0.4 + t * 0.6))


# ================================================================ 弹簧发束

## 生成一段发束画布：沿 -Y 延伸 length 格（顶部向上重叠 2 格以遮住关节）
## r0/r1：顶/底截面半径（x, z）；bulge：中段鼓起；ragged：末端参差（0 = 平齐）
static func bundle(s: CharSpec, length: int, r0: Vector2, r1: Vector2, bulge: float, ragged: int, seed: int, layered: bool = true) -> VoxCanvas:
	var rmax := maxf(maxf(r0.x, r1.x), maxf(r0.y, r1.y)) * (1.0 + bulge) + 1.0
	var R := int(ceil(rmax))
	var cv := VoxCanvas.new(Vector3i(-R, -length, -R), Vector3i(R - 1, 2, R - 1))
	# 按环绕角划分发丝（竖向条纹）；每根发丝有固定的半径起伏（竖脊）、长度（参差发尖）与颜色
	var n_sec := 12
	var sec_ridge := PackedFloat32Array()
	var sec_end := PackedInt32Array()
	var sec_col: Array[Color] = []
	for i in n_sec:
		var hs := VoxCanvas.h1(i * 13 + seed * 101)
		sec_ridge.append((float(hs & 3) - 1.2) * (0.32 if layered else 0.15))
		sec_end.append(length - 1 - ((hs >> 4) % (ragged + 1) if ragged > 0 else 0))
		sec_col.append(strand_col(s, i + seed * 37, 0, false))
	# 预计算每列 (x,z) 的角度扇区
	var W := 2 * R
	var col_sec := PackedInt32Array()
	col_sec.resize(W * W)
	for z in range(-R, R):
		for x in range(-R, R):
			var ang := atan2(z + 0.5, x + 0.5)
			col_sec[(z + R) * W + (x + R)] = int(floor((ang + PI) / TAU * n_sec)) % n_sec
	for yi in range(-2, length):
		var y := -yi
		var t := clampf(float(yi) / float(maxi(length - 1, 1)), 0.0, 1.0)
		var r := r0.lerp(r1, t) * (1.0 + bulge * sin(PI * t))
		if yi < 0:
			r *= 0.9
		var shade := 1.0 - 0.14 * t
		for z in range(-R, R):
			for x in range(-R, R):
				var sec := col_sec[(z + R) * W + (x + R)]
				var e := sec_end[sec]
				if yi > e:
					continue
				var rr := r + Vector2(sec_ridge[sec], sec_ridge[sec])
				# 发尖收细
				if ragged > 0 and yi > e - 4:
					rr *= 1.0 - 0.18 * float(yi - (e - 4))
				var dx := (x + 0.5) / maxf(rr.x, 0.3)
				var dz := (z + 0.5) / maxf(rr.y, 0.3)
				var d2 := dx * dx + dz * dz
				if d2 > 1.0:
					continue
				var c := sec_col[sec]
				if d2 < 0.4:
					c = VoxCanvas.tone(c, 0.8)
				cv.put(x, y, z, VoxCanvas.tone(c, shade))
	return cv


## 创建一根弹簧骨骼节点（spring_dir 默认向下；网格沿 -Y）
static func spring_bone(parent: Node3D, bone_name: String, pos_vox: Vector3, rot_deg: Vector3, length_vox: float, stiff: float, limit: float, gravity: float = 0.0) -> Node3D:
	var n := Node3D.new()
	n.name = bone_name
	n.position = pos_vox * VOXEL
	n.rotation_degrees = rot_deg
	n.set_meta("spring_length", maxf(length_vox * VOXEL, 0.05))
	n.set_meta("spring_stiffness", stiff)
	n.set_meta("spring_limit", limit)
	if gravity > 0.0:
		n.set_meta("spring_gravity", gravity)
	parent.add_child(n)
	return n


## mirror：镜像实例（scale.x = -1），左右对称部件只生成一次网格
static func attach_mesh(bone: Node3D, mesh: ArrayMesh, mesh_name: String = "Mesh", mirror: bool = false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = mesh
	if mirror:
		mi.scale = Vector3(-1, 1, 1)
	bone.add_child(mi)
	return mi


## 根据发型在 head 下创建弹簧发束（双马尾/马尾/长发/披发）
static func build_springs(head: Node3D, s: CharSpec, key: String) -> void:
	match s.hair_style:
		"twin_tails":
			for side: int in [-1, 1]:
				var sn := "l" if side < 0 else "r"
				var sc := 1.0 if s.female else 0.8
				var b0 := spring_bone(head, "hair_tail_%s_0" % sn, Vector3(side * 11.0, 16.5, 2.5), Vector3(0, 0, side * 76), 9, 0.2, 25, 0.0)
				attach_mesh(b0, VoxMesh.cached("tt0|%s" % key, func() -> ArrayMesh:
					return VoxMesh.build_one(bundle(s, 10, Vector2(2.8, 3.6) * sc, Vector2(3.6, 4.8) * sc, 0.05, 0, 12), VOXEL)), "Mesh", side < 0)
				var b1 := spring_bone(b0, "hair_tail_%s_1" % sn, Vector3(0, -9, 0), Vector3(0, 0, -side * 60), 14, 0.12, 40, 0.2)
				attach_mesh(b1, VoxMesh.cached("tt1|%s" % key, func() -> ArrayMesh:
					return VoxMesh.build_one(bundle(s, 15, Vector2(3.7, 4.9) * sc, Vector2(3.5, 4.7) * sc, 0.06, 0, 22), VOXEL)), "Mesh", side < 0)
				var b2 := spring_bone(b1, "hair_tail_%s_2" % sn, Vector3(0, -14, 0), Vector3(0, 0, side * 6), 16, 0.1, 45, 0.15)
				attach_mesh(b2, VoxMesh.cached("tt2|%s" % key, func() -> ArrayMesh:
					return VoxMesh.build_one(bundle(s, 17 if s.female else 11, Vector2(3.5, 4.7) * sc, Vector2(1.6, 2.2) * sc, 0.04, 6, 32), VOXEL)), "Mesh", side < 0)
		"ponytail":
			var male := not s.female
			var p0 := spring_bone(head, "hair_pony_0", Vector3(0, 15.5, 10.0), Vector3(-40, 0, 0), 7, 0.2, 25)
			attach_mesh(p0, VoxMesh.cached("pt0|" + key, func() -> ArrayMesh:
				return VoxMesh.build_one(bundle(s, 7, Vector2(2.6, 2.4), Vector2(3.2, 2.8), 0.1, 0, 41), VOXEL)))
			var p1 := spring_bone(p0, "hair_pony_1", Vector3(0, -7, 0), Vector3(52, 0, 0), 14, 0.12, 40, 0.5)
			attach_mesh(p1, VoxMesh.cached("pt1|" + key, func() -> ArrayMesh:
				return VoxMesh.build_one(bundle(s, 14, Vector2(3.3, 2.9), Vector2(3.4, 2.8), 0.1, 0, 42), VOXEL)))
			var p2 := spring_bone(p1, "hair_pony_2", Vector3(0, -14, 0), Vector3(6, 0, 0), 14, 0.1, 45, 0.3)
			attach_mesh(p2, VoxMesh.cached("pt2|" + key, func() -> ArrayMesh:
				return VoxMesh.build_one(bundle(s, 10 if male else 15, Vector2(3.3, 2.8), Vector2(1.4, 1.2), 0.05, 5, 43), VOXEL)))
		"long":
			_back_panel(head, s, key, "hair_back", 0.0, 16, 30 if s.female else 20, 1)
			_side_locks(head, s, key, 13 if s.female else 8)
		"flowing":
			for i in 3:
				var xo := -6.5 + i * 6.5
				_back_panel(head, s, key, "hair_back_%d" % i, xo, 8, (38 if i == 1 else 34) if s.female else 26, 2 + i)
			_side_locks(head, s, key, 18 if s.female else 12)
		"bun":
			if s.female:
				# 发簪流苏
				var tb := spring_bone(head, "hair_tassel", Vector3(-9.5, 20.5, 1.5), Vector3.ZERO, 8, 0.15, 40)
				var cv := VoxCanvas.new(Vector3i(-1, -9, -1), Vector3i(0, 1, 0))
				cv.box(Vector3i(-1, -1, -1), Vector3i(0, 0, 0), s.gold)
				cv.box(Vector3i(-1, -7, -1), Vector3i(0, -2, 0), s.gem, 0.08)
				cv.box(Vector3i(-1, -9, -1), Vector3i(0, -8, 0), s.gem.darkened(0.2))
				attach_mesh(tb, VoxMesh.build_one(cv, VOXEL))


## 后背长发片：宽 width（x 中心 xo）、长 length；分两段弹簧链
static func _back_panel(head: Node3D, s: CharSpec, key: String, bname: String, xo: float, width: int, length: int, seed: int) -> void:
	var l0 := length / 2
	var l1 := length - l0
	var b0 := spring_bone(head, bname + "_0", Vector3(xo, 5.0, 8.0), Vector3(9, 0, 0), l0, 0.16, 25, 0.3)
	attach_mesh(b0, VoxMesh.cached("bp0|%s|%s|%d|%d" % [key, bname, width, length], func() -> ArrayMesh:
		return VoxMesh.build_one(_panel(s, width, l0, 0, seed), VOXEL)))
	var b1 := spring_bone(b0, bname + "_1", Vector3(0, -l0, 0), Vector3(4, 0, 0), l1, 0.1, 40, 0.4)
	attach_mesh(b1, VoxMesh.cached("bp1|%s|%s|%d|%d" % [key, bname, width, length], func() -> ArrayMesh:
		return VoxMesh.build_one(_panel(s, width, l1, 5, seed + 10), VOXEL)))


## 发片：宽 width、厚 3、长 length，发丝纵向，末端参差
static func _panel(s: CharSpec, width: int, length: int, ragged: int, seed: int) -> VoxCanvas:
	var hw := width / 2
	var cv := VoxCanvas.new(Vector3i(-hw - 1, -length, -1), Vector3i(hw, 2, 4))
	for x in range(-hw, hw):
		var sid := x + seed * 53
		var hs := VoxCanvas.h1(sid)
		var end := length - (hs % (ragged + 1) if ragged > 0 else 0)
		# 发片两侧收窄；每根发丝厚度固定（形成竖向发脊）
		var edge := absf(x + 0.5) / float(hw)
		var th := (2 if edge < 0.8 else 1) + (hs >> 3) % 2
		var c := strand_col(s, sid, 0, false)
		for yi in range(-2, end):
			var y := -yi
			var t := float(yi) / float(length)
			var tk := th
			if ragged > 0 and yi > end - 4:
				tk = maxi(th - 1, 1)
			var cc := VoxCanvas.tone(c, 1.0 - 0.12 * t)
			for z in range(0, tk + 1):
				cv.put(x, y, z, cc if z > 0 else VoxCanvas.tone(cc, 0.8))
	return cv


## 胸前鬓发（两根弹簧发束）
static func _side_locks(head: Node3D, s: CharSpec, key: String, length: int) -> void:
	for side: int in [-1, 1]:
		var sn := "l" if side < 0 else "r"
		var b := spring_bone(head, "hair_side_" + sn, Vector3(side * 9.0, 3.5, -6.5), Vector3(-6, 0, side * 4), length, 0.14, 35, 0.4)
		attach_mesh(b, VoxMesh.cached("sl|%s|%d" % [key, length], func() -> ArrayMesh:
			return VoxMesh.build_one(bundle(s, length, Vector2(1.5, 1.5), Vector2(1.0, 1.1), 0.1, 2, 62, false), VOXEL)), "Mesh", side < 0)


# ================================================================ 兽耳（弹簧骨骼，网格沿 +Y）

static func build_ears(head: Node3D, s: CharSpec, ears: String, key: String) -> void:
	if ears != "fox" and ears != "cat":
		return
	for side: int in [-1, 1]:
		var sn := "l" if side < 0 else "r"
		var fox := ears == "fox"
		var e := Node3D.new()
		e.name = "ear_" + sn
		e.position = Vector3(side * (5.0 if fox else 5.5), 18.0, 0.5) * VOXEL
		e.rotation_degrees = Vector3(-8, 0, -side * (14.0 if fox else 18.0))
		e.set_meta("spring_length", 0.25)
		e.set_meta("spring_stiffness", 0.3)
		e.set_meta("spring_limit", 12.0)
		e.set_meta("spring_dir", Vector3.UP)
		head.add_child(e)
		attach_mesh(e, VoxMesh.cached("ear|%s|%s" % [ears, key], func() -> ArrayMesh:
			return VoxMesh.build_one(_ear(s, fox, 1), VOXEL)), "Mesh", side < 0)


static func _ear(s: CharSpec, fox: bool, side: int) -> VoxCanvas:
	var h := 15 if fox else 8
	var w := 8 if fox else 7
	var cv := VoxCanvas.new(Vector3i(-5, -2, -4), Vector3i(4, h, 3))
	var outer := s.ear_color
	var tipc := VoxCanvas.tone(outer, 0.55)
	var fur := Color(0.98, 0.96, 0.94)
	var pink := Color(0.96, 0.78, 0.76)
	for y in range(-1, h):
		var t := float(maxi(y, 0)) / float(h)
		var half := (w * 0.5) * (1.0 - t) + 0.35
		var dz0 := -2 if t < 0.5 else -1
		var dz1 := 1 if t < 0.6 else 0
		for x in range(-5, 5):
			if absf(x + 0.5) > half:
				continue
			for z in range(dz0, dz1 + 1):
				var c := outer
				if t > 0.72:
					c = tipc
				c = VoxCanvas.tone(c, 0.94 + 0.1 * float(VoxCanvas.h3(x, y, z) & 3) / 3.0)
				cv.put(x, y, z, c)
		# 前面内侧白毛（狐）/粉色（猫）
		var inner_half := half - 1.3
		if inner_half > 0.2 and t < 0.8:
			for x in range(-5, 5):
				if absf(x + 0.5) <= inner_half:
					var ic := fur if fox else pink
					if not fox and absf(x + 0.5) < inner_half - 0.8:
						ic = pink.darkened(0.08)
					if fox and t > 0.45:
						ic = fur.lerp(pink, 0.25)
					cv.put(x, y, dz0, ic)
	# 耳根白色绒毛
	if fox:
		for x in range(-4, 4):
			cv.put(x, -1, -3, fur)
			cv.put(x, 0, -3, fur if (x + 10) % 2 == 0 else fur.darkened(0.05))
			if x > -4 and x < 3:
				cv.put(x, 1, -3, fur)
				cv.put(x, -2, -2, fur)
	return cv


# ================================================================ 狐尾（hips 下的弹簧链）

static func build_tail(hips: Node3D, s: CharSpec, kind: String, key: String) -> void:
	if kind != "fox":
		return
	var fur := s.ear_color
	var tipc := Color(0.98, 0.96, 0.94)
	var z0 := s.torso_d / 2.0 + 1.5
	var rots := [Vector3(-62, 0, 0), Vector3(22, 0, 0), Vector3(-8, 0, 0), Vector3(-26, 0, 0)]
	var lens := [7, 8, 8, 8]
	var radii := [Vector2(1.8, 2.8), Vector2(3.4, 4.0), Vector2(4.2, 4.4), Vector2(3.6, 1.0)]
	var parent := hips
	for i in 4:
		var b := spring_bone(parent, "tail_%d" % i, Vector3(0, -2.0, z0) if i == 0 else Vector3(0, -lens[i - 1], 0), rots[i], lens[i], 0.16 - i * 0.02, 35, 0.15)
		var r0: Vector2 = radii[i]
		var r1: Vector2 = radii[i + 1] if i < 3 else Vector2(1.0, 1.0)
		var idx := i
		attach_mesh(b, VoxMesh.cached("tail|%s|%d" % [key, i], func() -> ArrayMesh:
			return VoxMesh.build_one(_tail_seg(fur, tipc, lens[idx], Vector2(r0.x, r0.x), Vector2(r1.x, r1.x), idx), VOXEL)))
		parent = b


static func _tail_seg(fur: Color, tipc: Color, length: int, r0: Vector2, r1: Vector2, idx: int) -> VoxCanvas:
	var R := int(ceil(maxf(r0.x, r1.x) + 1.5))
	var cv := VoxCanvas.new(Vector3i(-R, -length, -R), Vector3i(R - 1, 2, R - 1))
	for yi in range(-2, length):
		var t := clampf(float(yi) / float(length), 0.0, 1.0)
		var r := lerpf(r0.x, r1.x, t)
		for z in range(-R, R):
			for x in range(-R, R):
				var d := Vector2(x + 0.5, z + 0.5).length()
				var rr := r + (0.6 if VoxCanvas.h3(x, yi, z) % 3 == 0 else 0.0)
				if d > rr:
					continue
				var tt := (idx + t) / 4.0
				var c := fur if tt < 0.72 else tipc
				if tt > 0.66 and tt < 0.72 and VoxCanvas.h3(x, yi, z) % 2 == 0:
					c = tipc
				c = VoxCanvas.tone(c, 0.92 + 0.12 * float(VoxCanvas.h3(z, yi, x) & 3) / 3.0)
				cv.put(x, -yi, z, c)
	return cv
