class_name HairStyles
## 发型（2× 精度）：头顶发帽（头网格内，超椭球发量 + 逐发丝着色）+ 分层刘海（每绺尖梢、两层前后错落）+ 鬓发
## + 天使环高光 + 弹簧发束（双马尾、马尾、长发、披发、麻花辫的发尾链）+ 金饰。
## 另负责兽耳（狐/猫，弹簧骨骼 ear_l/r）、狐尾、龙角（头网格内）。
##
## 头部局部坐标见 FacePainter：头颅 x -16..15，y 4..35，z -16..15；刘海在 z=-17（上段加厚到 -19）。
## 发色：每根发丝（1 体素宽）有独立明暗（CharSpec.strand 表），每 5~6 根一道暗缝分出发绺，
## 少量挑染 hair_color2，额前一圈天使环高光。
## 注意：绘制函数在工作线程中调用，表格一律用 static var。

const VOXEL := 0.0125

## 刘海每绺：[中心 x, 宽, 尖端 y, 尖端横向偏移, 层(0 贴脸 z=-17 / 1 外层 z=-18)]
static var BANGS: Dictionary = {
	"full": [[-13.6, 6, 21, -1.6, 0], [-9.0, 6, 24, -0.9, 0], [-4.6, 6, 22, -0.3, 0], [-0.5, 5, 19, 0.0, 0], [3.6, 6, 22, 0.3, 0],
		[8.0, 6, 24, 0.9, 0], [12.6, 6, 21, 1.6, 0],
		[-11.2, 7, 28, -0.6, 1], [-2.6, 7, 27, -0.2, 1], [5.6, 7, 28, 0.4, 1], [13.4, 6, 29, 0.8, 1]],
	"curtain": [[-14.0, 5, 13, -1.0, 0], [-10.8, 5, 16, -1.2, 0], [-7.6, 5, 21, -1.5, 0], [-4.6, 4, 26, -1.2, 0], [-1.8, 3, 30, -0.8, 0],
		[1.2, 3, 30, 0.8, 0], [3.8, 4, 26, 1.2, 0], [6.8, 5, 21, 1.5, 0], [10.0, 5, 16, 1.2, 0], [13.2, 5, 13, 1.0, 0],
		[-9.5, 7, 25, -1.0, 1], [8.5, 7, 25, 1.0, 1]],
	"swept": [[-14.2, 5, 24, 1.0, 0], [-10.6, 5, 26, 2.0, 0], [-7.2, 5, 25, 2.5, 0], [-3.8, 5, 23, 2.8, 0], [-0.4, 5, 22, 2.6, 0],
		[3.0, 5, 20, 2.0, 0], [6.4, 5, 18, 1.5, 0], [9.8, 5, 16, 1.0, 0], [13.2, 5, 14, 0.6, 0],
		[-8.0, 8, 29, 2.0, 1], [0.5, 8, 27, 2.5, 1], [8.5, 7, 24, 1.5, 1]],
	"blunt": [[-14.0, 4, 24, 0.0, 0], [-10.5, 4, 25, 0.0, 0], [-7.0, 4, 24, 0.0, 0], [-3.5, 4, 25, 0.0, 0], [0.0, 4, 24, 0.0, 0],
		[3.5, 4, 25, 0.0, 0], [7.0, 4, 24, 0.0, 0], [10.5, 4, 25, 0.0, 0], [14.0, 4, 24, 0.0, 0],
		[-9.0, 8, 28, 0.0, 1], [0.0, 8, 28, 0.0, 1], [9.0, 8, 28, 0.0, 1]],
	"spiky": [[-13.5, 5, 26, -2.0, 0], [-9.5, 5, 24, -1.5, 0], [-5.5, 5, 26, -0.8, 0], [-1.5, 5, 23, 0.5, 0], [2.5, 5, 25, 1.2, 0],
		[6.5, 5, 24, 1.8, 0], [10.5, 5, 26, 2.2, 0], [14.0, 4, 27, 2.0, 0],
		[-7.5, 7, 29, -1.5, 1], [4.5, 7, 29, 1.5, 1]],
	"parted_m": [[-13.5, 5, 22, -1.0, 0], [-9.8, 5, 24, -1.3, 0], [-6.2, 5, 27, -1.2, 0], [-2.8, 4, 30, -0.8, 0],
		[2.0, 4, 30, 0.8, 0], [5.4, 5, 27, 1.2, 0], [9.0, 5, 24, 1.3, 0], [12.8, 5, 22, 1.0, 0]],
	"wisps": [[-13.8, 3, 17, -0.6, 0], [13.0, 3, 17, 0.6, 0]],
	"none": [],
}

## 发型参数：
##  r      发量超椭球半径（x, y, z），中心 (-0.5, cy, cz)；n 指数（越大越方）
##  side   两侧（耳前）下缘 y；back 后脑下缘 y；hairline 额前发际线 y（刘海之上）
##  bangs  刘海预设；lock 鬓发下端 y（大于 30 表示无）；fringe_line 额头暗发区下缘
static var STYLES: Dictionary = {
	"twin_tails": {"r": Vector3(19.2, 18.5, 19.6), "cy": 21.0, "cz": 0.5, "n": 3.3, "side": 10, "back": 2, "bangs": "full", "lock": 5},
	"ponytail": {"r": Vector3(18.8, 18.2, 19.3), "cy": 21.0, "cz": 0.5, "n": 3.3, "side": 12, "back": 4, "bangs": "full", "lock": 7},
	"long": {"r": Vector3(19.4, 18.6, 19.7), "cy": 20.5, "cz": 0.5, "n": 3.4, "side": 4, "back": 4, "bangs": "curtain", "lock": 2},
	"flowing": {"r": Vector3(19.8, 19.0, 20.1), "cy": 20.5, "cz": 0.6, "n": 3.2, "side": 3, "back": 3, "bangs": "swept", "lock": 0},
	"short": {"r": Vector3(19.0, 18.2, 19.3), "cy": 20.0, "cz": 0.6, "n": 3.4, "side": 9, "back": 6, "bangs": "blunt", "lock": 9, "bob": true},
	"bun": {"r": Vector3(17.4, 16.8, 17.8), "cy": 20.0, "cz": 0.5, "n": 5.0, "side": 18, "back": 9, "bangs": "wisps", "lock": 31, "hairline": 31},
	"double_bun": {"r": Vector3(18.4, 17.6, 18.7), "cy": 20.5, "cz": 0.5, "n": 3.6, "side": 14, "back": 5, "bangs": "full", "lock": 9},
	"braid": {"r": Vector3(18.8, 18.2, 19.3), "cy": 21.0, "cz": 0.5, "n": 3.3, "side": 11, "back": 4, "bangs": "curtain", "lock": 6},
}
static var STYLES_M: Dictionary = {
	"short": {"r": Vector3(18.2, 17.4, 18.8), "cy": 20.5, "cz": 0.4, "n": 4.5, "side": 18, "back": 10, "bangs": "spiky", "lock": 16, "spiky": true},
	"bun": {"r": Vector3(17.2, 16.8, 17.6), "cy": 20.0, "cz": 0.5, "n": 5.0, "side": 18, "back": 10, "bangs": "none", "lock": 31, "hairline": 32},
	"ponytail": {"r": Vector3(18.2, 17.0, 18.8), "cy": 20.5, "cz": 0.5, "n": 4.5, "side": 14, "back": 9, "bangs": "parted_m", "lock": 12},
	"long": {"r": Vector3(18.6, 17.2, 19.2), "cy": 20.5, "cz": 0.5, "n": 4.2, "side": 6, "back": 5, "bangs": "parted_m", "lock": 5},
	"flowing": {"r": Vector3(19.2, 17.8, 19.6), "cy": 20.5, "cz": 0.6, "n": 3.8, "side": 5, "back": 4, "bangs": "swept", "lock": 4},
	"twin_tails": {"r": Vector3(18.4, 17.2, 19.0), "cy": 20.5, "cz": 0.5, "n": 4.2, "side": 12, "back": 8, "bangs": "parted_m", "lock": 10},
	"double_bun": {"r": Vector3(17.6, 16.9, 18.0), "cy": 20.0, "cz": 0.5, "n": 5.0, "side": 18, "back": 10, "bangs": "none", "lock": 31, "hairline": 32},
	"braid": {"r": Vector3(18.2, 17.0, 18.8), "cy": 20.5, "cz": 0.5, "n": 4.5, "side": 14, "back": 9, "bangs": "parted_m", "lock": 12},
}


static func style_of(s: CharSpec) -> Dictionary:
	var st := s.hair_style
	if not s.female and STYLES_M.has(st):
		return STYLES_M[st]
	return STYLES.get(st, STYLES["twin_tails"])


# ================================================================ 发色

## 头帽上某处发丝的颜色：sid 发丝编号，y 高度（竖向渐变与天使环），outer 是否外层
static func hair_col(s: CharSpec, sid: int, y: int, ring_y: float) -> Color:
	return hair_col_from(s, hair_base(s, sid), sid, y, ring_y)


## 发丝基色（发丝明暗 × 发绺明暗 × 绺缝），与高度无关，可按 sid 缓存
static func hair_base(s: CharSpec, sid: int) -> Color:
	var m := posmod(sid, 6)
	var c := VoxCanvas.tone(s.strand_c(sid), CharSpec.lock_tone(floori(sid / 6.0)))
	# 每 6 根一道发绺暗缝
	if m == 0:
		c = c.lerp(s.hair_line, 0.5)
	elif m == 1 or m == 5:
		c = VoxCanvas.tone(c, 0.92)
	return c


static func hair_col_from(s: CharSpec, base: Color, sid: int, y: int, ring_y: float) -> Color:
	# 竖向渐变：上亮下暗
	var c := VoxCanvas.tone(base, clampf(0.8 + (y - 4) * 0.009, 0.8, 1.08))
	# 天使环（额前一圈高光，发绺暗缝处断开）
	var dy := y - ring_y
	if dy >= -1.0 and dy < 1.5 and posmod(sid, 6) != 0 and (VoxCanvas.h1(sid * 3 + 1) & 3) != 0:
		c = c.lerp(s.hair_hi.lightened(0.12), 0.55 if dy >= 0.0 and dy < 1.0 else 0.28)
	return c


# ================================================================ 头帽

static func paint_cap(cv: VoxCanvas, s: CharSpec) -> void:
	var st := style_of(s)
	cv.set_mat(VoxCanvas.M_HAIR)
	var r: Vector3 = st["r"]
	var n: float = st["n"]
	var cy: float = st["cy"]
	var cz: float = st["cz"]
	var side_y: int = st["side"]
	var back_y: int = st["back"]
	var hairline: int = int(st.get("hairline", 30))
	var has_mark := str(s.a.get("mark", "none")) != "none"
	var bangs: Array = BANGS.get(str(st["bangs"]), [])
	var fringe := bangs.size() > 4
	var y_lo := mini(side_y, back_y)
	var y_hi := int(ceil(cy + r.y))
	# 两遍法：先用占位值填满发量（直接写数据索引，极快），最后只给暴露在外的体素算发丝颜色
	var d := cv.data
	var PH := VoxCanvas.encm(Color8(1, 2, 3), VoxCanvas.M_HAIR)
	var fill := PackedInt32Array()
	var lx := cv.lo.x
	var bxo := 1 - lx
	# 1) 发量：超椭球（上半穹顶、下半直筒），逐行求 x 范围
	for z in range(maxi(int(floor(cz - r.z)), cv.lo.z), mini(int(ceil(cz + r.z)), cv.hi.z) + 1):
		var az := absf((z + 0.5 - cz) / r.z)
		var pz := pow(az, n)
		if pz > 1.0:
			continue
		var zo := cv.sxy * (z - cv.lo.z + 1)
		for y in range(maxi(y_lo, cv.lo.y), mini(y_hi, cv.hi.y) + 1):
			var py := pow(absf((y + 0.5 - cy) / r.y), n) if y + 0.5 > cy else 0.0
			var rem := 1.0 - pz - py
			if rem < 0.0:
				continue
			# 前额与脸：z 在头颅前半部且低于发际线的只留给刘海/鬓发；有刘海的发型额前整片留给刘海
			if z < -9 and y < hairline:
				continue
			if fringe and z < -16 and y < 37:
				continue
			# 两侧下缘：耳前 side_y，脑后 back_y，之间渐变
			var lim := side_y
			if z > 2:
				lim = back_y if z > 9 else int(lerpf(side_y, back_y, (z - 2) / 7.0))
			if y < lim:
				continue
			var xm := r.x * pow(rem, 1.0 / n)
			var x0 := maxi(int(floor(-0.5 - xm)), lx)
			var x1 := mini(int(ceil(-0.5 + xm)) - 1, cv.hi.x)
			var row := bxo + cv.sx * (y - cv.lo.y + 1) + zo
			if y >= 4 and y < 35 and z > -16 and z < 15:
				# 头颅内部的行：只填头颅之外的两段 + 头颅两侧表面
				for x in range(x0, mini(x1, -16) + 1):
					d[row + x] = PH
					fill.append(row + x)
				for x in range(maxi(x0, 15), x1 + 1):
					d[row + x] = PH
					fill.append(row + x)
				continue
			var in_sk := y < 36 and z >= -16 and z <= 15
			for x in range(x0, x1 + 1):
				if in_sk and x > -16 and x < 15 and d[row + x] == 0:
					continue
				d[row + x] = PH
				fill.append(row + x)
	# 头颅上缘棱角（发量圆角没盖住的皮肤）也填成头发
	var sk := VoxCanvas.M_SKIN
	for z in range(-15, 16):
		for y in range(28, 36):
			var lim2 := side_y if z <= 2 else back_y
			if y < lim2:
				continue
			for x in [-16, -15, 14, 15]:
				var i := cv.ix(x, y, z)
				if d[i] != 0 and ((d[i] >> 4) & 15) == sk:
					d[i] = PH
					fill.append(i)
	for x in range(-16, 16):
		for z in range(-15, 16):
			for y in [35, 34]:
				var i2 := cv.ix(x, y, z)
				if d[i2] != 0 and ((d[i2] >> 4) & 15) == sk:
					d[i2] = PH
					fill.append(i2)
		for y in range(maxi(back_y, 4), 36):
			for z in [15, 14]:
				var i3 := cv.ix(x, y, z)
				if d[i3] != 0 and ((d[i3] >> 4) & 15) == sk:
					d[i3] = PH
					fill.append(i3)
	# 第二遍：暴露体素着色，内部填暗色
	var v_in := cv.e(s.hair_dk)
	var sx := cv.sx
	var sxy := cv.sxy
	var bases := {}
	for i in fill:
		if d[i] != PH:
			continue
		if d[i + 1] != 0 and d[i - 1] != 0 and d[i + sx] != 0 and d[i - sx] != 0 and d[i + sxy] != 0 and d[i - sxy] != 0:
			d[i] = v_in
			continue
		var zi := i / sxy
		var rm := i - zi * sxy
		var yi := rm / sx
		var x := rm - yi * sx + lx - 1
		var y := yi + cv.lo.y - 1
		var z := zi + cv.lo.z - 1
		var ring_y := 29.5 + clampf((z + 16) * 0.12, 0.0, 3.5)
		var sid := _sid(x, y, z)
		var base: Variant = bases.get(sid)
		if base == null:
			base = hair_base(s, sid)
			bases[sid] = base
		d[i] = cv.e(hair_col_from(s, base, sid, y, ring_y))
	# 前额暗发（刘海缝隙中透出的深色头发），花钿处留空
	for x in range(-16, 16):
		for y in range(hairline - 3, 36):
			if has_mark and x >= -4 and x <= 3 and y < 33:
				continue
			if cv.solid(x, y, -16):
				cv.put(x, y, -16, s.hair_dk if y < 33 else hair_col(s, x + 700, y, 99.0))
	# 2) 刘海
	var top_y := int(cy + r.y * 0.8)
	for i in bangs.size():
		var bl: Array = bangs[i]
		var bx: float = bl[0]
		var tip: int = bl[2]
		if has_mark and absf(bx + 0.5) < 3.5:
			tip = maxi(tip, 33)
		var layer: int = bl[4]
		_lock(cv, s, bx, float(bl[1]), top_y, tip, float(bl[3]), -17 - layer, 700 + i * 11, layer)
	# 3) 鬓发：耳前垂下的发绺（两层，尖梢）
	var lock_y: int = st["lock"]
	if lock_y <= 30:
		for side: int in [-1, 1]:
			var xo := -18.0 if side < 0 else 17.0
			for zi in 3:
				var z := -17 + zi * 2
				var tipy := lock_y + zi * 3 + (VoxCanvas.h1(zi + side * 5) % 3)
				_side_lock(cv, s, xo, 3.4, 33, tipy, -side * 0.6, z, 2, 900 + side * 40 + zi * 7)
	if st.get("spiky", false):
		_spikes(cv, s)
	if st.get("bob", false) and s.female:
		# 波波头：发尾向内收的一圈
		for x in range(-19, 19):
			for z in range(-12, 18):
				var ex := x <= -17 or x >= 16 or z >= 16
				if ex and cv.solid(x, side_y + 1, z):
					cv.put(x, side_y, z, hair_col(s, _sid(x, side_y, z), side_y, 99.0).darkened(0.1))
	# 呆毛（女：双马尾/长发/披发/辫子）
	if s.female and s.hair_style in ["twin_tails", "long", "flowing", "braid"]:
		var ax := -3
		for k in 7:
			var t := k / 6.0
			var px := ax + int(round(t * 3.0))
			var py := y_hi - 1 + int(round(sin(t * PI * 0.8) * 5.0))
			cv.put(px, py, -6 + int(t * 2), hair_col(s, 1500 + k / 3, 40, 99.0))
			cv.put(px, py + 1, -6 + int(t * 2), hair_col(s, 1501, 40, 99.0))


## 头帽表面发丝编号：侧/后/前按环绕角（约 1 体素一根），头顶按以发旋为中心的放射角
static func _sid(x: int, y: int, z: int) -> int:
	if y >= 34:
		var ang := atan2(z + 0.5 - 5.0, x + 0.5)
		return int(floor((ang + PI) * 13.0)) + 300
	return int(floor((atan2(z + 0.5, x + 0.5) + PI) * 19.0))


## 一绺刘海：从 y_top 垂到 tip，宽 w，尖端向 bend 方向弯。每格落在“该处已有头发/脸面的最前方再向外一格”，
## 所以刘海从头顶发量表面流下、盖在额头上；外层（layer 1）后画，自然叠在内层之前。
## 着色：整绺一个基调（lock_tone），两侧边缘一列偏暗、左 1/3 处一列偏亮，发丝细微明暗，尖端渐暗。
static func _lock(cv: VoxCanvas, s: CharSpec, cx: float, w: float, y_top: int, tip: int, bend: float, z: int, sid0: int, layer: int) -> void:
	var span := maxf(float(y_top - tip), 1.0)
	var lt := CharSpec.lock_tone(sid0 + layer * 3) * (1.04 if layer == 1 else 1.0)
	for y in range(tip, y_top + 1):
		var t := float(y_top - y) / span        # 0 顶 → 1 尖
		var hw := maxf(w * 0.5 * (1.0 - pow(t, 2.6) * 0.8), 0.55)
		var xc := cx + bend * t * t
		for x in range(int(floor(xc - hw)), int(ceil(xc + hw)) + 1):
			var off := x + 0.5 - xc
			if absf(off) > hw:
				continue
			var sid := sid0 + x
			var c := VoxCanvas.tone(s.strand_c(sid), lt * (1.04 - 0.22 * t * t))
			var rel := off / maxf(hw, 0.5)
			if rel > 0.55 and hw > 1.0:
				c = c.lerp(s.hair_line, 0.55)
			elif rel < -0.62 and hw > 1.0:
				c = c.lerp(s.hair_line, 0.3)
			elif rel > -0.5 and rel < -0.05 and t < 0.75:
				c = c.lerp(s.hair_hi, 0.25)
			# 天使环
			if y >= 29 and y <= 30 and (VoxCanvas.h1(sid) & 3) != 0:
				c = c.lerp(s.hair_hi.lightened(0.12), 0.5 if y == 30 else 0.3)
			# 落点：自头顶发量平滑过渡到贴额（上段外凸 3 格），并在已有头发之前；背后填实成一整片
			var zf := z - int(round(3.0 * smoothstep(25.0, 36.0, float(y))))
			for zz in range(-26, zf + 1):
				if cv.get_raw(x, y, zz) != 0:
					zf = mini(zf, zz - 1)
					break
			cv.put(x, y, zf, c)
			var cb := VoxCanvas.tone(c, 0.8)
			for zz in range(zf + 1, -16):
				if cv.get_raw(x, y, zz) != 0:
					break
				cv.put(x, y, zz, cb)


## 鬓发：竖向发绺（x 中心 cx、宽 w），z 平面，尖端内弯；depth 为向后的厚度
static func _side_lock(cv: VoxCanvas, s: CharSpec, cx: float, w: float, y_top: int, tip: int, bend: float, z: int, depth: int, sid0: int) -> void:
	var span := maxf(float(y_top - tip), 1.0)
	for y in range(tip, y_top + 1):
		var t := float(y_top - y) / span
		var hw := w * 0.5 * (1.0 - pow(t, 3.0) * 0.85)
		var xc := cx + bend * t * t * 2.0
		for x in range(int(floor(xc - hw)), int(ceil(xc + hw)) + 1):
			var off := absf(x + 0.5 - xc)
			if off > hw:
				continue
			var c := VoxCanvas.tone(s.strand_c(sid0 + x), 1.0 - 0.15 * t)
			if off > hw - 0.8:
				c = c.lerp(s.hair_line, 0.3)
			for k in depth:
				cv.put(x, y, z + k, c)


## 男式短发：头顶随机发簇（尖锥）
static func _spikes(cv: VoxCanvas, s: CharSpec) -> void:
	for i in 16:
		var h := VoxCanvas.h1(i * 31 + 7)
		var x := -12 + (h % 24)
		var z := -12 + ((h >> 5) % 26)
		var hgt := 2 + ((h >> 9) % 3)
		var lean := Vector2(float((h >> 12) % 3 - 1), float((h >> 14) % 3 - 1) * 0.5 + 0.8)
		var base := 36
		while base > 30 and not cv.solid(x, base, z):
			base -= 1
		for k in hgt + 1:
			var t := float(k) / float(hgt + 1)
			var rr := 2.2 * (1.0 - t) + 0.5
			var px := x + lean.x * k * 0.7
			var pz := z + lean.y * k * 0.7
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					if Vector2(dx, dz).length() <= rr:
						cv.put(int(px) + dx, base + 1 + k, int(pz) + dz, hair_col(s, _sid(int(px) + dx, 36, int(pz) + dz), 36, 99.0))


# ================================================================ 发饰与特殊发型（头网格内）

## 金饰小工具：金块（顶亮底暗）
static func _gold_box(cv: VoxCanvas, s: CharSpec, a: Vector3i, b: Vector3i) -> void:
	cv.set_mat(VoxCanvas.M_GOLD)
	cv.box(a, b, s.gold)
	cv.box(Vector3i(a.x, maxi(a.y, b.y), a.z), Vector3i(b.x, maxi(a.y, b.y), b.z), s.gold_hi)
	cv.box(Vector3i(a.x, mini(a.y, b.y), a.z), Vector3i(b.x, mini(a.y, b.y), b.z), s.gold_sh)


## 刻面宝石（2×2 或 3×3，带高光与暗角），平面 z，朝向 dz（-1 向前）
static func gem_at(cv: VoxCanvas, s: CharSpec, x: int, y: int, z: int, size: int, gem_c: Color) -> void:
	var hi := gem_c.lerp(Color(1, 1, 1), 0.6)
	var sh := Color(gem_c.r * 0.5, gem_c.g * 0.45, gem_c.b * 0.55)
	if size <= 1:
		cv.putm(x, y, z, VoxCanvas.glow(gem_c, 0.35), VoxCanvas.M_GEM)
		return
	# j 自上而下，i 自左而右：左上高光、右下暗角、对角线微亮
	for j in size:
		for i in size:
			var c := gem_c
			if i == 0 and j == 0:
				c = VoxCanvas.glow(hi, 0.5)
			elif i == size - 1 and j == size - 1:
				c = sh
			elif (i + j) == size - 1:
				c = VoxCanvas.glow(gem_c, 0.3)
			cv.putm(x + i, y - j, z, c, VoxCanvas.M_GEM)


static func paint_extras(cv: VoxCanvas, s: CharSpec) -> void:
	match s.hair_style:
		"twin_tails":
			for side: int in [-1, 1]:
				# 发根金扣：镂空方框 + 云头 + 宝石
				var x0 := -24 if side < 0 else 18
				_gold_box(cv, s, Vector3i(x0, 27, 0), Vector3i(x0 + 5, 34, 8))
				cv.set_mat(VoxCanvas.M_GOLD)
				var fx := x0 if side < 0 else x0 + 5
				for y in range(28, 34):
					for z in range(1, 8):
						var edge := y == 28 or y == 33 or z == 1 or z == 7
						if not edge:
							cv.put(fx, y, z, s.gold_sh if y > 29 else s.gold_dk)
				gem_at(cv, s, fx + side, 31, 3, 2, s.gem)
				cv.putm(fx + side, 29, 4, VoxCanvas.glow(s.gem_hi, 0.4), VoxCanvas.M_GEM)
				# 顶部卷云饰
				for k in 4:
					cv.put(x0 + 1 + k, 35, 2 + (k % 2) * 3, s.gold_hi)
				cv.put(x0 + 2, 36, 4, s.gold_hi)
				cv.put(x0 + 3, 36, 4, s.gold)
		"ponytail":
			# 发根金环（束发冠）+ 宝石 + 两侧翅饰
			_gold_box(cv, s, Vector3i(-5, 26, 18), Vector3i(4, 35, 22))
			cv.set_mat(VoxCanvas.M_GOLD)
			for x in range(-5, 5):
				cv.put(x, 30, 23, s.gold_dk)
				cv.put(x, 31, 23, s.gold_hi if x % 2 == 0 else s.gold)
			gem_at(cv, s, -1, 34, 23, 2, s.gem)
			for side: int in [-1, 1]:
				var wx := -7 if side < 0 else 6
				for k in 4:
					cv.put(wx + side * k, 28 + k, 20, s.gold if k < 3 else s.gold_hi)
					cv.put(wx + side * k, 29 + k, 20, s.gold_sh)
		"long":
			# 侧边发簪：金枝 + 垂珠
			cv.set_mat(VoxCanvas.M_GOLD)
			for k in 8:
				cv.put(-21 + k / 3, 29 + k / 2, -6 + k, s.gold if k % 3 else s.gold_hi)
			gem_at(cv, s, -22, 29, -7, 2, s.gem)
			cv.set_mat(VoxCanvas.M_JADE)
			for k in 3:
				cv.put(-22, 25 - k * 2, -6, Color("f4f0e8"))
		"flowing":
			# 后脑半冠：镂空金片 + 中央宝石 + 两侧垂链
			cv.set_mat(VoxCanvas.M_GOLD)
			for x in range(-12, 12):
				var hgt := 3 + int(2.0 * cos((x + 0.5) / 12.0 * PI * 0.5) * 2.0)
				for y in range(32, 32 + hgt):
					var c := s.gold
					if y == 32:
						c = s.gold_sh
					elif y == 31 + hgt:
						c = s.gold_hi
					elif (x + y) % 3 == 0:
						c = s.gold_dk
					cv.put(x, y, 20, c)
			gem_at(cv, s, -1, 37, 19, 2, s.gem)
			for side: int in [-1, 1]:
				gem_at(cv, s, -8 if side < 0 else 7, 35, 19, 1, s.gem)
		"bun":
			_bun(cv, s, Vector3(-0.5, 42.0, 2.0), 1.0, true)
		"double_bun":
			for side: int in [-1, 1]:
				_bun(cv, s, Vector3(side * 10.5 - 0.5, 39.0, 2.0), 0.72, false)
		"short":
			if s.female:
				# 侧边发夹：金条 + 宝石
				_gold_box(cv, s, Vector3i(-21, 27, -10), Vector3i(-20, 29, -3))
				gem_at(cv, s, -22, 29, -8, 2, s.gem)
		"braid":
			# 发根缎带结
			cv.set_mat(VoxCanvas.M_SILK)
			var rib := s.c1
			for x in range(-5, 5):
				for y in range(24, 30):
					if absi(x * 2 + 1) + absi(y - 27) * 2 <= 10:
						cv.put(x, y, 20, VoxCanvas.tone(rib, 0.9 + 0.1 * float((x + y) & 1)))
			gem_at(cv, s, -1, 28, 19, 2, s.gem)


## 发髻（中心 c、缩放 k）；crown=true 时加金冠与发簪
static func _bun(cv: VoxCanvas, s: CharSpec, c: Vector3, k: float, crown: bool) -> void:
	cv.set_mat(VoxCanvas.M_HAIR)
	var r := (Vector3(8.4, 6.6, 8.4) if s.female else Vector3(7.2, 6.0, 7.2)) * k
	var l := Vector3i((c - r).floor())
	var h := Vector3i((c + r).ceil())
	for z in range(l.z, h.z + 1):
		for y in range(l.y, h.y + 1):
			for x in range(l.x, h.x + 1):
				var d := (Vector3(x + 0.5, y + 0.5, z + 0.5) - c) / r
				if d.length_squared() <= 1.0:
					# 发髻：按环绕角分发丝（螺旋），深浅相间
					var ang := atan2(z + 0.5 - c.z, x + 0.5 - c.x)
					var sid := int(floor((ang + PI) / TAU * 40.0 + (y - c.y) * 1.5))
					var col := hair_col(s, sid + 1200, y - 8, 99.0)
					if d.y > 0.55:
						col = col.lerp(s.hair_hi, 0.25)
					cv.put(x, y, z, col)
	# 髻根与头顶的连接
	var rb := int(ceil(r.x * 0.55))
	for z in range(int(c.z) - rb, int(c.z) + rb):
		for x in range(int(c.x) - rb, int(c.x) + rb):
			for y in range(34, int(c.y)):
				if not cv.solid(x, y, z):
					cv.put(x, y, z, hair_col(s, _sid(x, y, z), y, 99.0))
	if not crown:
		# 双髻：缎带环
		cv.set_mat(VoxCanvas.M_SILK)
		var cy := int(c.y - r.y * 0.45)
		for a in 40:
			var ang2 := a * TAU / 40.0
			var px := int(floor(c.x + cos(ang2) * (r.x * 0.92 + 0.6)))
			var pz := int(floor(c.z + sin(ang2) * (r.z * 0.92 + 0.6)))
			cv.put(px, cy, pz, s.c1)
			cv.put(px, cy - 1, pz, VoxCanvas.tone(s.c1, 0.8))
		gem_at(cv, s, int(c.x) - 1, cy, int(c.z - r.z * 0.92) - 1, 1, s.gem)
		return
	# 发冠 / 金环
	cv.set_mat(VoxCanvas.M_GOLD)
	var cyb := int(c.y - r.y + 1)
	for a in 56:
		var ang3 := a * TAU / 56.0
		var px := int(floor(c.x + cos(ang3) * (r.x * 0.72)))
		var pz := int(floor(c.z + sin(ang3) * (r.z * 0.72)))
		cv.put(px, cyb, pz, s.gold)
		cv.put(px, cyb + 1, pz, s.gold_hi if a % 4 == 0 else s.gold)
		if not s.female and a % 7 == 0:
			cv.put(px, cyb + 2, pz, s.gold_hi)
	if not s.female:
		# 男式小冠：前方立起的冠片（云头纹）+ 宝石
		var fz := int(c.z - r.z * 0.72) - 1
		for y in range(cyb, cyb + 9):
			var hw := 4 - maxi(y - (cyb + 5), 0)
			for x in range(-hw, hw):
				var cc := s.gold
				if x == -hw or x == hw - 1:
					cc = s.gold_sh
				elif y == cyb + 8 - maxi(0, absi(x) - 1):
					cc = s.gold_hi
				cv.put(x, y, fz, cc)
		gem_at(cv, s, -1, cyb + 5, fz - 1, 2, s.gem)
	# 发簪（横穿发髻）+ 端头宝石
	for x in range(int(c.x - r.x - 6), int(c.x + r.x + 3)):
		var cc2 := s.gold_hi if x < int(c.x - r.x - 3) else s.gold
		cv.put(x, int(c.y), int(c.z), cc2)
		cv.put(x, int(c.y) + 1, int(c.z), s.gold_sh if x > int(c.x - r.x - 3) else s.gold)
	gem_at(cv, s, int(c.x - r.x - 8), int(c.y) + 1, int(c.z), 2, s.gem)


# ================================================================ 龙角（头网格内）

static func paint_horns(cv: VoxCanvas, s: CharSpec) -> void:
	# 鹿角状龙角：自额角向上、后弯，中段分叉；根部象牙色 → 角尖金色；环纹
	cv.set_mat(VoxCanvas.M_SCALE)
	var base := Color("efe4c8")
	var tipc := Color("e8b848").lerp(s.hair2, 0.25)
	for side: int in [-1, 1]:
		var sx := float(side)
		var p := Vector3(-8.0 if side < 0 else 7.0, 33.0, -9.0)
		var pts: Array[Vector3] = []
		for i in 32:
			var t := i / 31.0
			pts.append(p + Vector3(sx * (9.0 * t), 22.0 * t, 13.0 * t * t))
		for i in pts.size():
			var t := i / float(pts.size() - 1)
			var c := base.lerp(tipc, t * t)
			var q: Vector3 = pts[i]
			var rr := 3.4 * (1.0 - t) + 1.1
			if i % 5 == 2 and t < 0.75:
				cv.ellipsoid(q + Vector3(0.5, 0.5, 0.5), Vector3(rr + 0.45, 0.8, rr + 0.45), VoxCanvas.tone(c, 0.8))
			else:
				cv.ellipsoid(q + Vector3(0.5, 0.5, 0.5), Vector3(rr, rr, rr), c)
		# 前向分叉
		var b0: Vector3 = pts[12]
		for i in 14:
			var t := i / 13.0
			cv.ellipsoid(b0 + Vector3(sx * 5.0 * t + 0.5, 7.0 * t + 0.5, -5.0 * t + 0.5), Vector3(1.9, 1.9, 1.9) * (1.0 - t * 0.4), base.lerp(tipc, 0.35 + t * 0.65))
		# 后向小分叉
		var b1: Vector3 = pts[22]
		for i in 10:
			var t := i / 9.0
			cv.ellipsoid(b1 + Vector3(sx * 4.0 * t + 0.5, 2.8 * t + 0.5, 4.0 * t + 0.5), Vector3(1.5, 1.5, 1.5), base.lerp(tipc, 0.6 + t * 0.4))


# ================================================================ 弹簧发束

## 生成一段发束画布：沿 -Y 延伸 length 格（顶部向上重叠 3 格以遮住关节）
## r0/r1：顶/底截面半径（x, z）；bulge：中段鼓起；ragged：末端参差（发绺尖梢长度差）
## tier > 0：分层剪（每 tier 格一层，层底外扩、层顶略暗），形成层叠轮廓
static func bundle(s: CharSpec, length: int, r0: Vector2, r1: Vector2, bulge: float, ragged: int, seed: int, layered: bool = true, tier: int = 0) -> VoxCanvas:
	var rmax := maxf(maxf(r0.x, r1.x), maxf(r0.y, r1.y)) * (1.0 + bulge) + 2.0
	var R := int(ceil(rmax))
	var cv := VoxCanvas.new(Vector3i(-R, -length, -R), Vector3i(R - 1, 3, R - 1))
	cv.set_mat(VoxCanvas.M_HAIR)
	# 发绺：按环绕角分成 n_lock 绺，每绺有固定的半径起伏、长度（尖梢）与色调；绺内再按 1 体素分发丝
	var n_lock := 9
	var lock_ridge := PackedFloat32Array()
	var lock_end := PackedInt32Array()
	var lock_k := PackedFloat32Array()
	for i in n_lock:
		var hs := VoxCanvas.h1(i * 13 + seed * 101)
		lock_ridge.append((float(hs & 3) - 1.0) * (0.55 if layered else 0.3))
		lock_end.append(length - 1 - ((hs >> 4) % (ragged + 1) if ragged > 0 else 0))
		lock_k.append(0.92 + 0.1 * float((hs >> 8) & 3) / 3.0)
	var W := 2 * R
	var v_in := cv.e(s.hair_dk)
	var col_lock := PackedInt32Array()
	var col_frac := PackedFloat32Array()
	var col_sid := PackedInt32Array()
	col_lock.resize(W * W)
	col_frac.resize(W * W)
	col_sid.resize(W * W)
	for z in range(-R, R):
		for x in range(-R, R):
			var ang := atan2(z + 0.5, x + 0.5)
			var u := (ang + PI) / TAU * n_lock
			var li := int(floor(u)) % n_lock
			var ci := (z + R) * W + (x + R)
			col_lock[ci] = li
			col_frac[ci] = u - floor(u)
			col_sid[ci] = int(floor((ang + PI) / TAU * 46.0)) + seed * 37
	# 编码后的颜色表（按 列 × 明暗等级 × 是否绺缝 惰性计算），内层循环只做查表 + 直接写数据
	var tab := PackedInt32Array()
	tab.resize(W * W * 32)
	var d := cv.data
	for yi in range(-3, length):
		var y := -yi
		var t := clampf(float(yi) / float(maxi(length - 1, 1)), 0.0, 1.0)
		var r := r0.lerp(r1, t) * (1.0 + bulge * sin(PI * t))
		if yi < 0:
			r *= 0.9
		var shade := 1.0 - 0.16 * t
		if tier > 0 and yi >= 0:
			var ph := float(posmod(yi + seed, tier)) / float(tier - 1)
			r *= 0.88 + 0.14 * ph
			shade *= 0.9 + 0.1 * ph
		var rowy := cv.sx * (y - cv.lo.y + 1) + 1 - cv.lo.x
		for z in range(-R, R):
			var row := rowy + cv.sxy * (z - cv.lo.z + 1)
			for x in range(-R, R):
				var ci := (z + R) * W + (x + R)
				var li := col_lock[ci]
				var e := lock_end[li]
				if yi > e:
					continue
				var fr := col_frac[ci]
				# 绺与绺之间向内凹（分出发绺）
				var groove := 0.0
				if fr < 0.14 or fr > 0.86:
					groove = 0.55
				var rr := r + Vector2(lock_ridge[li] - groove, lock_ridge[li] - groove)
				# 发尖收细（每绺各自收成尖）
				if ragged > 0 and yi > e - 8:
					rr *= 1.0 - 0.1 * float(yi - (e - 8))
				var dx := (x + 0.5) / maxf(rr.x, 0.4)
				var dz := (z + 0.5) / maxf(rr.y, 0.4)
				var d2 := dx * dx + dz * dz
				if d2 > 1.0:
					continue
				if d2 < 0.42:
					# 内部（不可见）：直接写暗色
					d[row + x] = v_in
					continue
				var k := lock_k[li] * shade
				if groove <= 0.0 and d2 < 0.62:
					k *= 0.82
				var lv := clampi(int((k - 0.5) * 25.0), 0, 15)
				var ti := ci * 32 + lv * 2 + (1 if groove > 0.0 else 0)
				var v := tab[ti]
				if v == 0:
					var c := VoxCanvas.tone(s.strand_c(col_sid[ci]), 0.5 + (lv + 0.5) / 25.0)
					if groove > 0.0:
						c = c.lerp(s.hair_line, 0.4)
					v = cv.e(c)
					tab[ti] = v
				d[row + x] = v
	return cv


## 麻花辫一段：三股交织（每股是偏移的椭圆截面，沿长度相位旋转），末端可加发绳与散尾
static func braid_seg(s: CharSpec, length: int, r: float, phase: float, tail: bool) -> VoxCanvas:
	var R := int(ceil(r * 1.9)) + 2
	var cv := VoxCanvas.new(Vector3i(-R, -length - (10 if tail else 0), -R), Vector3i(R - 1, 3, R - 1))
	cv.set_mat(VoxCanvas.M_HAIR)
	var period := r * 3.6
	for yi in range(-3, length):
		var y := -yi
		for strand in 3:
			var a := (yi / period + phase) * TAU + strand * TAU / 3.0
			var ox := sin(a) * r * 0.55
			var oz := cos(a) * r * 0.32
			var sr := r * 0.62
			var front := cos(a) < 0.0
			for z in range(-R, R):
				for x in range(-R, R):
					var dx := (x + 0.5 - ox) / sr
					var dz := (z + 0.5 - oz) / (sr * 0.9)
					if dx * dx + dz * dz > 1.0:
						continue
					if cv.solid(x, y, z) and not front:
						continue
					var c := s.strand_c(strand * 17 + int(floor((x + 0.5 - ox) * 1.5)) + 40)
					var k := 0.86 + 0.18 * (0.5 + 0.5 * sin(a * 2.0 + 1.0))
					if dx * dx + dz * dz > 0.7:
						k *= 0.86
					cv.put(x, y, z, VoxCanvas.tone(c, k))
	if tail:
		# 发绳（缎带）+ 散开的发尾
		cv.set_mat(VoxCanvas.M_SILK)
		for z in range(-3, 3):
			for x in range(-3, 3):
				if Vector2(x + 0.5, z + 0.5).length() <= 2.8:
					cv.put(x, -length, z, s.c1)
					cv.put(x, -length - 1, z, VoxCanvas.tone(s.c1, 0.8))
		cv.set_mat(VoxCanvas.M_HAIR)
		for i in 10:
			var ang := i * TAU / 10.0
			var ln := 5 + VoxCanvas.h1(i + 3) % 5
			for k in ln:
				var t := float(k) / ln
				var px := int(floor(cos(ang) * (1.2 + t * 2.0)))
				var pz := int(floor(sin(ang) * (1.2 + t * 2.0)))
				cv.put(px, -length - 2 - k, pz, VoxCanvas.tone(s.strand_c(i + 90), 1.0 - 0.2 * t))
	return cv


## 创建一根弹簧骨骼节点（spring_dir 默认向下；网格沿 -Y）。pos_vox 为本模块体素（0.0125m）
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


## 挂部件网格对（LOD0 + LOD1）；mirror：镜像实例（scale.x = -1）
static func attach_mesh(bone: Node3D, pair: Array, mesh_name: String = "Mesh", mirror: bool = false) -> MeshInstance3D:
	return CharacterBuilder.mesh(bone, pair, mirror, mesh_name)


static func _part(key: String, maker: Callable) -> Array:
	return CharacterBuilder.part(key, maker)


## 根据发型在 head 下创建弹簧发束
static func build_springs(head: Node3D, s: CharSpec, key: String) -> void:
	match s.hair_style:
		"twin_tails":
			for side: int in [-1, 1]:
				var sn := "l" if side < 0 else "r"
				var sc := 1.0 if s.female else 0.8
				var b0 := spring_bone(head, "hair_tail_%s_0" % sn, Vector3(side * 22.0, 33.0, 5.0), Vector3(0, 0, side * 76), 18, 0.2, 25, 0.0)
				attach_mesh(b0, _part("tt0|%s" % key, func() -> Variant:
					return bundle(s, 20, Vector2(5.6, 7.2) * sc, Vector2(7.6, 10.0) * sc, 0.05, 0, 12, true, 10)), "Mesh", side < 0)
				var b1 := spring_bone(b0, "hair_tail_%s_1" % sn, Vector3(0, -18, 0), Vector3(0, 0, -side * 60), 28, 0.12, 40, 0.2)
				attach_mesh(b1, _part("tt1|%s" % key, func() -> Variant:
					return bundle(s, 30, Vector2(7.8, 10.2) * sc, Vector2(7.6, 10.0) * sc, 0.06, 0, 22, true, 10)), "Mesh", side < 0)
				var b2 := spring_bone(b1, "hair_tail_%s_2" % sn, Vector3(0, -28, 0), Vector3(0, 0, side * 6), 32, 0.1, 45, 0.15)
				attach_mesh(b2, _part("tt2|%s" % key, func() -> Variant:
					return bundle(s, 34 if s.female else 22, Vector2(7.6, 10.0) * sc, Vector2(3.0, 4.2) * sc, 0.04, 12, 32, true, 10)), "Mesh", side < 0)
		"ponytail":
			var male := not s.female
			var p0 := spring_bone(head, "hair_pony_0", Vector3(0, 31.0, 21.0), Vector3(-40, 0, 0), 14, 0.2, 25)
			attach_mesh(p0, _part("pt0|" + key, func() -> Variant:
				return bundle(s, 14, Vector2(5.0, 4.6), Vector2(6.4, 5.6), 0.1, 0, 41)))
			var p1 := spring_bone(p0, "hair_pony_1", Vector3(0, -14, 0), Vector3(52, 0, 0), 28, 0.12, 40, 0.5)
			attach_mesh(p1, _part("pt1|" + key, func() -> Variant:
				return bundle(s, 28, Vector2(6.6, 5.8), Vector2(7.0, 6.0), 0.1, 0, 42, true, 10)))
			var p2 := spring_bone(p1, "hair_pony_2", Vector3(0, -28, 0), Vector3(6, 0, 0), 28, 0.1, 45, 0.3)
			attach_mesh(p2, _part("pt2|" + key, func() -> Variant:
				return bundle(s, 20 if male else 30, Vector2(7.0, 6.0), Vector2(2.4, 2.0), 0.05, 10, 43, true, 10)))
		"long":
			_back_panel(head, s, key, "hair_back", 0.0, 32, 60 if s.female else 40, 1)
			_side_locks(head, s, key, 26 if s.female else 16)
		"flowing":
			for i in 3:
				var xo := -13.0 + i * 13.0
				_back_panel(head, s, key, "hair_back_%d" % i, xo, 16, (76 if i == 1 else 68) if s.female else 52, 2 + i)
			_side_locks(head, s, key, 36 if s.female else 24)
		"braid":
			var q0 := spring_bone(head, "hair_braid_0", Vector3(0, 20.0, 19.0), Vector3(-14, 0, 0), 22, 0.18, 25, 0.3)
			attach_mesh(q0, _part("br0|" + key, func() -> Variant: return braid_seg(s, 22, 4.2, 0.0, false)))
			var q1 := spring_bone(q0, "hair_braid_1", Vector3(0, -22, 0), Vector3(8, 0, 0), 22, 0.12, 40, 0.5)
			attach_mesh(q1, _part("br1|" + key, func() -> Variant: return braid_seg(s, 22, 3.9, 22.0 / (4.2 * 3.6), false)))
			var q2 := spring_bone(q1, "hair_braid_2", Vector3(0, -22, 0), Vector3(4, 0, 0), 30, 0.1, 45, 0.4)
			attach_mesh(q2, _part("br2|" + key, func() -> Variant: return braid_seg(s, 20 if s.female else 12, 3.5, 44.0 / (4.2 * 3.6), true)))
			if s.female:
				_side_locks(head, s, key, 14)
		"bun":
			if s.female:
				# 发簪流苏：金链 + 宝石串 + 丝穗
				var tb := spring_bone(head, "hair_tassel", Vector3(-20.5, 43.5, 2.5), Vector3.ZERO, 16, 0.15, 40)
				attach_mesh(tb, _part("tassel|" + key, func() -> Variant: return _tassel_canvas(s, 16)))
		"double_bun":
			# 两侧缎带飘带
			for side: int in [-1, 1]:
				var sn2 := "l" if side < 0 else "r"
				var rb := spring_bone(head, "hair_ribbon_" + sn2, Vector3(side * 17.0, 34.0, 4.0), Vector3(0, 0, side * 10), 20, 0.14, 40, 0.3)
				attach_mesh(rb, _part("ribbon|" + key, func() -> Variant: return _ribbon_canvas(s, 22)), "Mesh", side < 0)


## 发簪流苏画布（沿 -Y）
static func _tassel_canvas(s: CharSpec, length: int) -> VoxCanvas:
	var cv := VoxCanvas.new(Vector3i(-3, -length - 2, -3), Vector3i(2, 2, 2))
	cv.set_mat(VoxCanvas.M_GOLD)
	cv.box(Vector3i(-1, -2, -1), Vector3i(0, 1, 0), s.gold)
	for y in range(-6, -2):
		cv.put(-1 + (y & 1), y, 0, s.gold_hi)
	cv.set_mat(VoxCanvas.M_GEM)
	cv.box(Vector3i(-1, -9, -1), Vector3i(0, -7, 0), s.gem)
	cv.put(-1, -7, -1, VoxCanvas.glow(s.gem_hi, 0.4))
	cv.set_mat(VoxCanvas.M_SILK)
	for y in range(-length, -9):
		var spread := 1 if y < -length + 4 else 0
		for x in range(-1 - spread, 1 + spread):
			for z in range(-1 - spread, 1 + spread):
				cv.put(x, y, z, VoxCanvas.tone(s.c1, 0.85 + 0.2 * float(VoxCanvas.h3(x, y, z) & 1)))
	return cv


## 缎带飘带画布（沿 -Y，薄片，末端燕尾）
static func _ribbon_canvas(s: CharSpec, length: int) -> VoxCanvas:
	var cv := VoxCanvas.new(Vector3i(-4, -length - 1, -2), Vector3i(3, 2, 1))
	cv.set_mat(VoxCanvas.M_SILK)
	for y in range(-length, 2):
		var yi := -y
		for x in range(-3, 3):
			if yi > length - 3 and (x == -1 or x == 0) and yi > length - 3 + absi(x * 2 + 1) / 2:
				continue
			var c := VoxCanvas.tone(s.c1, 0.95 - 0.15 * float(yi) / length)
			if x == -3 or x == 2:
				c = s.c3
			cv.put(x, y, 0, c)
	return cv


## 后背长发片：宽 width（x 中心 xo）、长 length；分两段弹簧链
static func _back_panel(head: Node3D, s: CharSpec, key: String, bname: String, xo: float, width: int, length: int, seed: int) -> void:
	var l0 := length / 2
	var l1 := length - l0
	var b0 := spring_bone(head, bname + "_0", Vector3(xo, 10.0, 16.0), Vector3(9, 0, 0), l0, 0.16, 25, 0.3)
	attach_mesh(b0, _part("bp0|%s|%s|%d|%d" % [key, bname, width, length], func() -> Variant:
		return _panel(s, width, l0, 0, seed)))
	var b1 := spring_bone(b0, bname + "_1", Vector3(0, -l0, 0), Vector3(4, 0, 0), l1, 0.1, 40, 0.4)
	attach_mesh(b1, _part("bp1|%s|%s|%d|%d" % [key, bname, width, length], func() -> Variant:
		return _panel(s, width, l1, 10, seed + 10)))


## 发片：宽 width、厚 3~5、长 length，发丝纵向（1 体素一根），每 5 根一道绺缝；两侧向前弯包住后背；末端每绺尖梢
static func _panel(s: CharSpec, width: int, length: int, ragged: int, seed: int) -> VoxCanvas:
	var hw := width / 2
	var cv := VoxCanvas.new(Vector3i(-hw - 1, -length - 1, -4), Vector3i(hw, 3, 7))
	cv.set_mat(VoxCanvas.M_HAIR)
	var nlock := maxi(width / 5, 1)
	for x in range(-hw, hw):
		var sid := x + seed * 53
		var li := int(floor(float(x + hw) / 5.0))
		var lh := VoxCanvas.h1(li * 7 + seed * 3)
		var end := length - (lh % (ragged + 1) if ragged > 0 else 0)
		var in_lock := posmod(x + hw, 5)
		var lock_center := absf(in_lock - 2.0) / 2.5     # 0 绺中 → 1 绺边
		# 发片两侧收窄并向前弯
		var edge := absf(x + 0.5) / float(hw)
		var th := (3 if edge < 0.75 else 2) + (1 if lock_center < 0.5 else 0)
		var zoff := int(round(-pow(edge, 3.0) * 3.0))
		var c := s.strand_c(sid)
		if in_lock == 0:
			c = c.lerp(s.hair_line, 0.45)
		for yi in range(-3, end):
			var y := -yi
			var t := float(yi) / float(length)
			var tk := th
			# 每绺末端收成尖
			var rem := end - yi
			if ragged > 0 and rem < 6:
				if lock_center > float(rem) / 6.0:
					continue
				tk = maxi(th - 1, 1)
			var cc := VoxCanvas.tone(c, 1.0 - 0.14 * t)
			for z in range(0, tk + 1):
				cv.put(x, y, z + zoff, cc if z > 0 else VoxCanvas.tone(cc, 0.78))
	return cv


## 胸前鬓发（两根弹簧发束）
static func _side_locks(head: Node3D, s: CharSpec, key: String, length: int) -> void:
	for side: int in [-1, 1]:
		var sn := "l" if side < 0 else "r"
		var b := spring_bone(head, "hair_side_" + sn, Vector3(side * 18.0, 7.0, -13.0), Vector3(-6, 0, side * 4), length, 0.14, 35, 0.4)
		attach_mesh(b, _part("sl|%s|%d" % [key, length], func() -> Variant:
			return bundle(s, length, Vector2(3.0, 3.0), Vector2(1.8, 2.0), 0.1, 4, 62, false)), "Mesh", side < 0)


# ================================================================ 兽耳（弹簧骨骼，网格沿 +Y）

static func build_ears(head: Node3D, s: CharSpec, ears: String, key: String) -> void:
	if ears != "fox" and ears != "cat":
		return
	for side: int in [-1, 1]:
		var sn := "l" if side < 0 else "r"
		var fox := ears == "fox"
		var e := Node3D.new()
		e.name = "ear_" + sn
		e.position = Vector3(side * (10.0 if fox else 11.0), 36.0, 1.0) * VOXEL
		e.rotation_degrees = Vector3(-8, 0, -side * (14.0 if fox else 18.0))
		e.set_meta("spring_length", 0.25)
		e.set_meta("spring_stiffness", 0.3)
		e.set_meta("spring_limit", 12.0)
		e.set_meta("spring_dir", Vector3.UP)
		head.add_child(e)
		attach_mesh(e, _part("ear|%s|%s" % [ears, key], func() -> Variant:
			return _ear(s, fox)), "Mesh", side < 0)


static func _ear(s: CharSpec, fox: bool) -> VoxCanvas:
	var h := 30 if fox else 16
	var w := 16 if fox else 14
	var cv := VoxCanvas.new(Vector3i(-10, -4, -8), Vector3i(9, h + 1, 6))
	cv.set_mat(VoxCanvas.M_FUR)
	var outer := s.ear_color
	var tipc := VoxCanvas.tone(outer, 0.5)
	var fur := Color(0.98, 0.96, 0.94)
	var pink := Color(0.96, 0.76, 0.76)
	for y in range(-2, h):
		var t := float(maxi(y, 0)) / float(h)
		# 轮廓：外缘略外凸（狐耳饱满）
		var half := (w * 0.5) * (1.0 - t) * (1.0 + 0.18 * sin(t * PI)) + 0.6
		var dz0 := -4 if t < 0.45 else (-3 if t < 0.75 else -2)
		var dz1 := 2 if t < 0.55 else 1
		for x in range(-10, 10):
			if absf(x + 0.5) > half:
				continue
			for z in range(dz0, dz1 + 1):
				var c := outer
				if t > 0.7 + 0.06 * float(VoxCanvas.h1(x + 40) % 3):
					c = tipc
				# 竖向毛丝明暗
				c = VoxCanvas.tone(c, 0.9 + 0.14 * float(VoxCanvas.h1(x * 3 + 11) & 3) / 3.0)
				if absf(x + 0.5) > half - 1.0:
					c = VoxCanvas.tone(c, 0.88)
				cv.put(x, y, z, c)
		# 前面内侧：狐——白色绒毛（向前伸出成簇）；猫——粉色内耳
		var inner_half := half - 2.4
		if inner_half > 0.3 and t < 0.84:
			for x in range(-10, 10):
				var ax := absf(x + 0.5)
				if ax > inner_half:
					continue
				if fox:
					# 内耳白绒：竖向毛丝（每 2 列一道浅影），越往耳尖越偏粉灰
					var ic := fur.lerp(Color(0.9, 0.8, 0.78), clampf(t * 1.1, 0.0, 0.55))
					if (x & 1) == 0:
						ic = ic.darkened(0.05)
					cv.put(x, y, dz0, ic)
					# 绒毛簇：内缘一圈向前伸出 1 格（下半部），耳根处更厚
					if t < 0.5 and ax > inner_half - 1.2:
						cv.put(x, y, dz0 - 1, fur)
				else:
					var ic2 := pink if ax < inner_half - 1.2 else pink.lerp(outer, 0.3)
					cv.put(x, y, dz0, ic2.darkened(0.05 * float((y >> 1) & 1)))
	# 耳根白色绒毛（狐）：大簇向前下方翻出
	if fox:
		for x in range(-7, 7):
			for k in 3:
				var yy := -2 + k
				cv.put(x, yy, -5, fur if (x + k) % 3 != 0 else fur.darkened(0.06))
			if (VoxCanvas.h1(x + 7) & 1) == 0:
				cv.put(x, 0, -6, fur)
				cv.put(x, -1, -6, fur.darkened(0.04))
	return cv


# ================================================================ 狐尾（hips 下的弹簧链）

static func build_tail(hips: Node3D, s: CharSpec, kind: String, key: String) -> void:
	if kind != "fox":
		return
	var fur := s.ear_color
	var tipc := Color(0.98, 0.96, 0.94)
	var z0 := s.torso_d / 2.0 + 3.0
	var rots := [Vector3(-62, 0, 0), Vector3(22, 0, 0), Vector3(-8, 0, 0), Vector3(-26, 0, 0)]
	var lens := [14, 16, 16, 16]
	var radii := [3.6, 6.8, 8.4, 7.2]
	var parent := hips
	for i in 4:
		var b := spring_bone(parent, "tail_%d" % i, Vector3(0, -4.0, z0) if i == 0 else Vector3(0, -lens[i - 1], 0), rots[i], lens[i], 0.16 - i * 0.02, 35, 0.15)
		var r0: float = radii[i]
		var r1: float = radii[i + 1] if i < 3 else 2.0
		var idx := i
		var ln: int = lens[i]
		attach_mesh(b, _part("tail|%s|%d" % [key, i], func() -> Variant:
			return _tail_seg(fur, tipc, ln, r0, r1, idx)))
		parent = b


static func _tail_seg(fur: Color, tipc: Color, length: int, r0: float, r1: float, idx: int) -> VoxCanvas:
	var R := int(ceil(maxf(r0, r1) + 3.0))
	var cv := VoxCanvas.new(Vector3i(-R, -length - 2, -R), Vector3i(R - 1, 4, R - 1))
	cv.set_mat(VoxCanvas.M_FUR)
	for yi in range(-3, length + 1):
		var t := clampf(float(yi) / float(length), 0.0, 1.0)
		var r := lerpf(r0, r1, t)
		var tt := (idx + t) / 4.0
		for z in range(-R, R):
			for x in range(-R, R):
				var ang := atan2(z + 0.5, x + 0.5)
				# 毛簇：按角度分 10 簇，每簇半径起伏并随长度错位（簇尖）
				var tuft := int(floor((ang + PI) / TAU * 10.0))
				var th := VoxCanvas.h3(tuft, (yi + idx * 16 + tuft * 3) / 5, idx)
				var rr := r + float(th & 3) * 0.45 - 0.4
				var d := Vector2(x + 0.5, z + 0.5).length()
				if d > rr:
					continue
				var c := fur if tt < 0.74 else tipc
				if tt > 0.68 and tt < 0.74 and (th & 4) != 0:
					c = tipc
				if d > rr - 1.0:
					c = VoxCanvas.tone(c, 0.9)
				c = VoxCanvas.tone(c, 0.9 + 0.14 * float((th >> 3) & 3) / 3.0)
				cv.put(x, -yi, z, c)
	return cv
