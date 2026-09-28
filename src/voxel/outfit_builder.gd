class_name OutfitBuilder
## 身体与服饰绘制：每个骨骼一张画布（身体 + 服饰外层合并，内部面自动剔除）。
## 服饰：armor（参考图战甲）、robe（道袍：交领、宽袖、长下摆）、martial（劲装：收身、护腕、绑腿）。
## 裙甲/下摆为 cloth_ 弹簧骨骼（hips 下），meta "follow" 让其随腿摆动（见 HumanoidRig）。
##
## 坐标均为骨骼局部体素坐标，约定见 CharSpec。躯干/腿深度为奇数时画布 shift 半格居中。

const VOXEL := 0.025


# ================================================================ 小工具

static func lo_of(w: int) -> int:
	return -(w / 2)


static func hi_of(w: int) -> int:
	return -(w / 2) + w - 1


static func half_shift(w: int) -> float:
	return -0.5 if w % 2 == 1 else 0.0


## 金属块：顶面高光、底边暗
static func metal(cv: VoxCanvas, a: Vector3i, b: Vector3i, s: CharSpec) -> void:
	cv.box(a, b, s.gold, 0.05)
	var y0 := mini(a.y, b.y)
	var y1 := maxi(a.y, b.y)
	cv.box(Vector3i(a.x, y1, a.z), Vector3i(b.x, y1, b.z), s.gold_hi)
	if y1 > y0:
		cv.box(Vector3i(a.x, y0, a.z), Vector3i(b.x, y0, b.z), VoxCanvas.mixc(s.gold, s.gold_sh, 0.6))


static func gem(cv: VoxCanvas, x: int, y: int, z: int, s: CharSpec, big: bool = false) -> void:
	cv.put(x, y, z, VoxelGrid.glow(s.gem, 0.25))
	if big:
		cv.put(x + 1, y, z, s.gem)
		cv.put(x, y - 1, z, s.gem.darkened(0.25))
		cv.put(x + 1, y - 1, z, s.gem.darkened(0.35))
		cv.put(x, y, z, VoxelGrid.glow(s.gem.lightened(0.35), 0.3))


static func leather(s: CharSpec) -> Color:
	return s.c2


## 褶皱布料色：按列加深，模拟竖褶
static func fold(c: Color, x: int, period: int = 3) -> Color:
	var m := posmod(x, period)
	return VoxCanvas.tone(c, 0.86 if m == 0 else (1.04 if m == 1 else 1.0))


# ================================================================ 躯干（spine）

static func torso(s: CharSpec) -> VoxCanvas:
	# 躯干 18 行：腰 y 0..5，胸 y 6..17（顶面即肩线）
	var zl := lo_of(s.torso_d)
	var zh := hi_of(s.torso_d)
	var cw := s.chest_w / 2
	var ww := s.waist_w / 2
	var cv := VoxCanvas.new(Vector3i(-cw - 3, -2, zl - 5), Vector3i(cw + 2, 19, zh + 3))
	cv.shift = Vector3(0, 0, half_shift(s.torso_d))
	# 身体
	cv.box(Vector3i(-ww, 0, zl), Vector3i(ww - 1, 5, zh), s.skin)
	cv.box(Vector3i(-cw, 6, zl), Vector3i(cw - 1, 17, zh), s.skin)
	if s.female:
		cv.box(Vector3i(-cw + 1, 4, zl), Vector3i(cw - 2, 5, zh), s.skin)
	# 腹部阴影与肚脐
	for x in range(-ww, ww):
		cv.put(x, 0, zl, VoxCanvas.tone(s.skin, 0.95))
	cv.put(-1, 3, zl, s.skin.lerp(s.skin_sh, 0.6))
	cv.put(0, 3, zl, s.skin.lerp(s.skin_sh, 0.3))
	if not s.female:
		for y in [2, 5]:
			for x in [-3, -2, 1, 2]:
				cv.put(x, y, zl, s.skin.lerp(s.skin_sh, 0.25))
	# 锁骨阴影
	for x in [-4, -3, 2, 3]:
		cv.put(x, 16, zl, s.skin.lerp(s.skin_sh, 0.3))
	# 胸部（女性，含蓄）
	if s.female and s.chest > 0.05:
		var d := 1 if s.chest < 0.66 else 2
		for x in range(-cw + 1, cw - 1):
			if x == -1 or x == 0:
				continue
			for y in range(9, 14):
				cv.put(x, y, zl - 1, s.skin)
			if d >= 2 and absi(x) >= 2 and absi(x + 1) <= 5:
				for y in range(10, 13):
					cv.put(x, y, zl - 2, s.skin)
		for x in range(-cw + 1, cw - 1):
			cv.put(x, 9, zl - 1, s.skin.lerp(s.skin_sh, 0.4))
	match s.outfit:
		"robe":
			_torso_robe(cv, s, zl, zh, cw, ww)
		"martial":
			_torso_martial(cv, s, zl, zh, cw, ww)
		_:
			if s.female:
				_torso_armor_f(cv, s, zl, zh, cw, ww)
			else:
				_torso_armor_m(cv, s, zl, zh, cw, ww)
	return cv


static func _torso_armor_f(cv: VoxCanvas, s: CharSpec, zl: int, zh: int, cw: int, ww: int) -> void:
	var lc := s.c2
	var front := zl - (2 if s.chest > 0.05 else 1)
	# 胸甲环带（y 9..15）
	for y in range(9, 16):
		for z in range(zl - 1, zh + 2):
			for x in range(-cw - 1, cw + 1):
				if x == -cw - 1 or x == cw or z == zl - 1 or z == zh + 1:
					cv.put(x, y, z, VoxCanvas.tone(lc, 0.92 + 0.14 * float(VoxCanvas.h3(x, y, z) & 3) / 3.0))
	# 罩杯前凸
	for x in range(-cw + 1, cw - 1):
		for y in range(10, 15):
			for z in range(front, zl - 1):
				cv.put(x, y, z, VoxCanvas.tone(lc, 0.92 + 0.14 * float(VoxCanvas.h3(x, y, z) & 3) / 3.0))
	# 金边（上下）
	for x in range(-cw - 1, cw + 1):
		for z in range(front, zh + 2):
			if cv.solid(x, 15, z):
				cv.put(x, 15, z, s.gold_hi if z <= zl - 1 else s.gold)
			if cv.solid(x, 9, z):
				cv.put(x, 9, z, s.gold)
	# 罩杯上的金色卷纹
	for side: int in [-1, 1]:
		var pts := [[2, 13], [3, 13], [4, 13], [4, 12], [2, 11], [3, 11], [4, 11]]
		for p in pts:
			var x: int = -1 - p[0] if side < 0 else p[0]
			cv.put(x, p[1], front, s.gold)
	# 中缝金扣 + 宝石
	metal(cv, Vector3i(-1, 9, front - 1), Vector3i(0, 15, front - 1), s)
	gem(cv, -1, 12, front - 2, s)
	cv.put(0, 12, front - 2, s.gem)
	# 颈前吊带
	for y in range(15, 18):
		cv.put(-1, y, zl - 1, s.gold)
		cv.put(0, y, zl - 1, s.gold)
	# 下胸小垂饰
	cv.put(-1, 8, front - 1, s.gold)
	cv.put(0, 8, front - 1, s.gold)
	cv.put(-1, 7, front - 1, s.gem)


static func _torso_armor_m(cv: VoxCanvas, s: CharSpec, zl: int, zh: int, cw: int, ww: int) -> void:
	var lc := s.c2
	# 内衬红布（腰部）
	for y in range(0, 3):
		for z in range(zl - 1, zh + 2):
			for x in range(-ww - 1, ww + 1):
				if x == -ww - 1 or x == ww or z == zl - 1 or z == zh + 1:
					cv.put(x, y, z, fold(s.c1, x + z))
	# 胸甲（整片）
	for y in range(3, 18):
		var hw := cw if y >= 6 else ww
		for z in range(zl - 1, zh + 2):
			for x in range(-hw - 1, hw + 1):
				if x == -hw - 1 or x == hw or z == zl - 1 or z == zh + 1 or y == 17:
					cv.put(x, y, z, VoxCanvas.tone(lc, 0.9 + 0.16 * float(VoxCanvas.h3(x, y, z) & 3) / 3.0))
	# 胸板（前凸）+ 金边
	for x in range(-cw + 1, cw - 1):
		for y in range(10, 17):
			cv.put(x, y, zl - 2, VoxCanvas.tone(lc, 1.05 + 0.08 * float(VoxCanvas.h3(x, y, 1) & 1)))
	for x in range(-cw + 1, cw - 1):
		cv.put(x, 16, zl - 2, s.gold_hi)
		cv.put(x, 10, zl - 2, s.gold)
	for y in range(10, 17):
		cv.put(-cw + 1, y, zl - 2, s.gold)
		cv.put(cw - 2, y, zl - 2, s.gold)
	# 胸前兽面金饰
	metal(cv, Vector3i(-3, 11, zl - 3), Vector3i(2, 15, zl - 3), s)
	cv.put(-2, 13, zl - 4, VoxelGrid.glow(s.gem, 0.3))
	cv.put(1, 13, zl - 4, VoxelGrid.glow(s.gem, 0.3))
	cv.box(Vector3i(-1, 11, zl - 4), Vector3i(0, 12, zl - 4), s.gold_sh)
	cv.put(-3, 16, zl - 3, s.gold_hi)
	cv.put(2, 16, zl - 3, s.gold_hi)
	# 腹部甲片：横向札甲
	for y in range(3, 10):
		for x in range(-ww, ww):
			if y % 2 == 1:
				cv.put(x, y, zl - 1, VoxCanvas.tone(lc, 0.72))
			elif posmod(x + y / 2, 3) == 0:
				cv.put(x, y, zl - 1, s.gold_sh.lerp(s.gold, 0.5))
	# 领口金边
	for x in range(-cw - 1, cw + 1):
		for z in range(zl - 1, zh + 2):
			if cv.solid(x, 17, z) and (x <= -3 or x >= 2 or z >= zh):
				cv.put(x, 17, z, s.gold)
	for x in range(-3, 3):
		cv.put(x, 17, zl - 1, s.c1)
		cv.put(x, 18, zh, s.gold)


static func _torso_robe(cv: VoxCanvas, s: CharSpec, zl: int, zh: int, cw: int, ww: int) -> void:
	# 外袍：比身体宽 1 格
	var inner := s.c2.lerp(Color(0.95, 0.94, 0.9), 0.75)
	for y in range(0, 18):
		var hw := (cw if y >= 6 else ww) + 1
		for z in range(zl - 1, zh + 2):
			for x in range(-hw, hw):
				if x == -hw or x == hw - 1 or z == zl - 1 or z == zh + 1 or y == 17:
					cv.put(x, y, z, fold(s.c1, x - z, 4))
	if s.female and s.chest > 0.05:
		for x in range(-cw + 1, cw - 1):
			if x == -1 or x == 0:
				continue
			for y in range(9, 14):
				cv.put(x, y, zl - 2, fold(s.c1, x, 4))
	# 交领（右衽）：领缘从颈左侧斜向右腰
	for y in range(6, 18):
		var t := float(17 - y) / 11.0
		var xc := int(round(lerpf(-2.0, 6.0, t)))
		for dx in 3:
			var x := xc - dx
			var zf := zl - 1
			if cv.solid(x, y, zl - 2):
				zf = zl - 2
			cv.put(x, y, zf, s.c3 if dx < 2 else s.c3.darkened(0.25))
		if y >= 12:
			# 露出内衬（中衣）
			for x in range(-1, xc - 2):
				cv.put(x, y, zl - 1, inner)
	# 另一侧领缘
	for y in range(13, 18):
		var x2 := -1 - (17 - y) / 2
		cv.put(x2, y, zl - 1, s.c3)
	# 后领
	for x in range(-3, 3):
		cv.put(x, 17, zh + 1, s.c3)
	# 腰带（宽）
	var sash := s.c2
	for y in range(0, 4):
		var hw2 := ww + 2
		for z in range(zl - 2, zh + 3):
			for x in range(-hw2, hw2):
				if x == -hw2 or x == hw2 - 1 or z == zl - 2 or z == zh + 2:
					var c := sash if y > 0 and y < 3 else s.c3
					cv.put(x, y, z, VoxCanvas.tone(c, 0.95 + 0.1 * float(VoxCanvas.h3(x, y, z) & 1)))
	# 结（左前）
	cv.box(Vector3i(-5, 0, zl - 3), Vector3i(-3, 2, zl - 3), s.c3)
	cv.put(-4, 1, zl - 4, s.c3.darkened(0.2))


static func _torso_martial(cv: VoxCanvas, s: CharSpec, zl: int, zh: int, cw: int, ww: int) -> void:
	# 收身短衣：直接染色身体表面
	for y in range(0, 18):
		var hw := cw if y >= 6 else ww
		for z in range(zl, zh + 1):
			for x in range(-hw, hw):
				if cv.solid(x, y, z):
					cv.put(x, y, z, fold(s.c1, x + z, 5))
	if s.female and s.chest > 0.05:
		for x in range(-cw + 1, cw - 1):
			for y in range(9, 14):
				for z in range(zl - 2, zl):
					if cv.solid(x, y, z):
						cv.put(x, y, z, s.c1)
	# 交领
	for y in range(8, 18):
		var t := float(17 - y) / 9.0
		var xc := int(round(lerpf(-1.0, 4.0, t)))
		for dx in 2:
			var x := xc - dx
			var z := zl
			if cv.solid(x, y, zl - 1):
				z = zl - 1
			if cv.solid(x, y, zl - 2):
				z = zl - 2
			cv.put(x, y, z, s.c3)
	# 衣襟边线
	for y in range(0, 8):
		cv.put(4, y, zl, VoxCanvas.tone(s.c1, 0.78))
	for y in range(14, 18):
		cv.put(-1 - (17 - y) / 2, y, zl, s.c3)
	# 皮腰带 + 带扣
	for y in range(0, 3):
		for z in range(zl - 1, zh + 2):
			for x in range(-ww - 1, ww + 1):
				if x == -ww - 1 or x == ww or z == zl - 1 or z == zh + 1:
					cv.put(x, y, z, VoxCanvas.tone(s.c2, 0.9 + 0.15 * float(VoxCanvas.h3(x, y, z) & 3) / 3.0))
	metal(cv, Vector3i(-2, 0, zl - 2), Vector3i(1, 2, zl - 2), s)
	cv.put(-1, 1, zl - 3, s.gold_sh)
	cv.put(0, 1, zl - 3, s.gold_sh)


## 颈部饰物（画在头网格的颈上）
static func paint_neck(cv: VoxCanvas, s: CharSpec) -> void:
	var hn := s.neck_w / 2
	match s.outfit:
		"armor":
			if s.female:
				for x in range(-hn - 1, hn + 1):
					for z in range(-hn - 1, hn + 1):
						if x == -hn - 1 or x == hn or z == -hn - 1 or z == hn:
							cv.put(x, 0, z, s.gold)
							cv.put(x, 1, z, s.gold_sh.lerp(s.gold, 0.5) if (x + z) % 2 == 0 else s.gold)
				cv.put(-1, 0, -hn - 2, s.gem)
				cv.put(0, 0, -hn - 2, s.gem)
				cv.put(-1, -1, -hn - 2, s.gold)
				cv.put(0, -1, -hn - 2, s.gold)
			else:
				for x in range(-hn - 1, hn + 1):
					for z in range(-hn - 1, hn + 1):
						if x == -hn - 1 or x == hn or z == -hn - 1 or z == hn:
							cv.put(x, 0, z, s.c1)
		"robe":
			for x in range(-hn - 1, hn + 1):
				for z in range(-hn - 1, hn + 1):
					if (x == -hn - 1 or x == hn or z == hn) and z > -hn - 1:
						cv.put(x, 0, z, s.c3)


# ================================================================ 骨盆（hips）

static func pelvis(s: CharSpec) -> VoxCanvas:
	var zl := lo_of(s.torso_d)
	var zh := hi_of(s.torso_d)
	var hw := s.hip_w / 2
	var cv := VoxCanvas.new(Vector3i(-hw - 4, -9, zl - 4), Vector3i(hw + 3, 5, zh + 4))
	cv.shift = Vector3(0, 0, half_shift(s.torso_d))
	var under := s.c2
	if s.outfit == "armor" and s.female:
		under = s.c1
	elif s.outfit == "martial":
		under = s.c2
	cv.box(Vector3i(-hw, -4, zl), Vector3i(hw - 1, 3, zh), under, 0.03)
	if s.female:
		cv.box(Vector3i(-hw + 1, 3, zl), Vector3i(hw - 2, 4, zh), s.skin)
	match s.outfit:
		"robe":
			for y in range(-6, 4):
				for z in range(zl - 1, zh + 2):
					for x in range(-hw - 1, hw + 1):
						if x == -hw - 1 or x == hw or z == zl - 1 or z == zh + 1:
							cv.put(x, y, z, fold(s.c1, x - z, 4))
		"martial":
			for y in range(-3, 4):
				for z in range(zl - 1, zh + 2):
					for x in range(-hw - 1, hw + 1):
						if x == -hw - 1 or x == hw or z == zl - 1 or z == zh + 1:
							cv.put(x, y, z, fold(s.c1, x + z, 5))
			for x in range(-hw - 1, hw + 1):
				cv.put(x, -3, zl - 1, s.c3)
				cv.put(x, -3, zh + 1, s.c3)
		_:
			_pelvis_armor(cv, s, zl, zh, hw)
	return cv


static func _pelvis_armor(cv: VoxCanvas, s: CharSpec, zl: int, zh: int, hw: int) -> void:
	# 短裙（红）
	for y in range(-5, 1):
		var out := 1 if y > -3 else 2
		for z in range(zl - out, zh + out + 1):
			for x in range(-hw - out, hw + out):
				if x == -hw - out or x == hw + out - 1 or z == zl - out or z == zh + out:
					cv.put(x, y, z, fold(s.c1, x + z, 3))
	# 腰带：皮 + 金钉 + 上下金边
	for y in range(0, 4):
		for z in range(zl - 1, zh + 2):
			for x in range(-hw - 1, hw + 1):
				if x == -hw - 1 or x == hw or z == zl - 1 or z == zh + 1:
					var c := VoxCanvas.tone(s.c2, 0.88 + 0.18 * float(VoxCanvas.h3(x, y, z) & 3) / 3.0)
					if y == 3:
						c = s.gold_hi
					elif y == 0:
						c = s.gold
					elif y == 2 and posmod(x + z, 3) == 0:
						c = s.gold_hi
					cv.put(x, y, z, c)
	# 兽首带扣
	var fz := zl - 2
	metal(cv, Vector3i(-3, -1, fz), Vector3i(2, 4, fz), s)
	metal(cv, Vector3i(-2, 0, fz - 1), Vector3i(1, 3, fz - 1), s)
	cv.put(-2, 2, fz - 1, VoxelGrid.glow(s.gem, 0.35))
	cv.put(1, 2, fz - 1, VoxelGrid.glow(s.gem, 0.35))
	cv.put(-1, 0, fz - 1, s.gold_sh)
	cv.put(0, 0, fz - 1, s.gold_sh)
	cv.put(-1, 4, fz, s.gold_hi)
	cv.put(0, 4, fz, s.gold_hi)
	cv.put(-3, 4, fz, s.gold_hi)
	cv.put(2, 4, fz, s.gold_hi)


# ================================================================ 手臂

static func upper_arm(s: CharSpec, side: int) -> VoxCanvas:
	var xl := lo_of(s.arm_w)
	var xh := hi_of(s.arm_w)
	var zl := lo_of(s.arm_d)
	var zh := hi_of(s.arm_d)
	var cv := VoxCanvas.new(Vector3i(xl - 5, -14, zl - 3), Vector3i(xh + 5, 5, zh + 3))
	cv.shift = Vector3(half_shift(s.arm_w), 0, half_shift(s.arm_d))
	cv.box(Vector3i(xl, -12, zl), Vector3i(xh, 1, zh), s.skin)
	var outx := xh if side > 0 else xl   # 外侧
	match s.outfit:
		"robe":
			for y in range(-12, 2):
				var o := 1 if y > -6 else 2
				for z in range(zl - o, zh + o + 1):
					for x in range(xl - o, xh + o + 1):
						if x == xl - o or x == xh + o or z == zl - o or z == zh + o or y == 1:
							cv.put(x, y, z, fold(s.c1, z + y / 3, 4))
		"martial":
			var y0 := -12 if not s.female else -6
			for y in range(y0, 2):
				for z in range(zl, zh + 1):
					for x in range(xl, xh + 1):
						if cv.solid(x, y, z):
							cv.put(x, y, z, fold(s.c1, z, 5))
			for z in range(zl - 1, zh + 2):
				for x in range(xl - 1, xh + 2):
					if x == xl - 1 or x == xh + 1 or z == zl - 1 or z == zh + 1:
						cv.put(x, y0, z, s.c3)
		_:
			if not s.female:
				for y in range(-12, 2):
					for z in range(zl, zh + 1):
						for x in range(xl, xh + 1):
							cv.put(x, y, z, fold(s.c1, z, 3))
			_pauldron(cv, s, side, xl, xh, zl, zh)
			# 臂环
			if s.female:
				for z in range(zl - 1, zh + 2):
					for x in range(xl - 1, xh + 2):
						if x == xl - 1 or x == xh + 1 or z == zl - 1 or z == zh + 1:
							cv.put(x, -9, z, s.gold)
							cv.put(x, -10, z, s.gold_sh.lerp(s.gold, 0.5))
	return cv


## 肩甲：三层叠片，外侧逐层下移外扩
static func _pauldron(cv: VoxCanvas, s: CharSpec, side: int, xl: int, xh: int, zl: int, zh: int) -> void:
	var lc := s.c2
	var big := 0 if s.female else 1
	for layer in 3:
		var y1 := 3 - layer * 3
		var y0 := y1 - 2
		var ext := 1 + layer + big
		var xa: int
		var xb: int
		if side > 0:
			xa = xl + layer * 2 - 1
			xb = xh + ext
		else:
			xa = xl - ext
			xb = xh - layer * 2 + 1
		for y in range(y0, y1 + 1):
			for z in range(zl - 1 - big, zh + 2 + big):
				for x in range(xa, xb + 1):
					var c := VoxCanvas.tone(lc, 0.88 + 0.18 * float(VoxCanvas.h3(x, y, z) & 3) / 3.0)
					if y == y0:
						c = s.gold
					elif y == y1 and layer == 0:
						c = s.gold_hi if (x + z) % 4 != 0 else s.gold
					cv.put(x, y, z, c)
		# 顶层外侧金框 + 宝石
		if layer == 0:
			var ox := xb if side > 0 else xa
			for y in range(y0, y1 + 1):
				for z in [zl - 1 - big, zh + 1 + big]:
					cv.put(ox, y, z, s.gold)
			gem(cv, ox + side, y0 + 1, 0, s)
			cv.put(ox + side, y0 + 1, -1, s.gold)
			cv.put(ox + side, y0 + 1, 1, s.gold)
			cv.put(ox + side, y0 + 2, 0, s.gold)
			cv.put(ox + side, y0, 0, s.gold)


static func forearm(s: CharSpec, side: int) -> VoxCanvas:
	var xl := lo_of(s.arm_w)
	var xh := hi_of(s.arm_w)
	var zl := lo_of(s.arm_d)
	var zh := hi_of(s.arm_d)
	var cv := VoxCanvas.new(Vector3i(xl - 5, -17, zl - 5), Vector3i(xh + 5, 3, zh + 5))
	cv.shift = Vector3(half_shift(s.arm_w), 0, half_shift(s.arm_d))
	cv.box(Vector3i(xl, -9, zl), Vector3i(xh, 1, zh), s.skin)
	# 手腕略细
	cv.clear(Vector3i(xl, -9, zl), Vector3i(xl, -8, zl))
	cv.clear(Vector3i(xh, -9, zh), Vector3i(xh, -8, zh))
	match s.outfit:
		"robe":
			# 宽袖：外扩 2~3 格，袖口金边，袖囊下垂到腕下
			for y in range(-10, 2):
				var o := 2 if y > -4 else 3
				var zb := zh + o + (2 if y < -6 else 0)
				for z in range(zl - o, zb + 1):
					for x in range(xl - o, xh + o + 1):
						var edge := x == xl - o or x == xh + o or z == zl - o or z == zb or y == 1
						if not edge:
							continue
						var c := fold(s.c1, z + x, 4)
						if y <= -9:
							c = s.c3 if y == -10 else s.c3.darkened(0.15)
						cv.put(x, y, z, c)
			# 袖囊（后侧下垂）
			for y in range(-15, -10):
				for z in range(zh, zh + 6):
					for x in range(xl - 3, xh + 4):
						if (x == xl - 3 or x == xh + 3 or z == zh + 5 or y == -15) and not (y > -12 and z < zh + 2):
							cv.put(x, y, z, s.c3 if y == -15 else fold(s.c1, z + x, 4))
			# 袖口内衬
			for z in range(zl - 2, zh + 3):
				for x in range(xl - 2, xh + 3):
					if cv.get_raw(x, -10, z) == 0 and not (x >= xl and x <= xh and z >= zl and z <= zh):
						cv.put(x, -9, z, s.c2.darkened(0.3))
		"martial":
			_bracer(cv, s, side, xl, xh, zl, zh, false)
		_:
			_bracer(cv, s, side, xl, xh, zl, zh, true)
	return cv


static func _bracer(cv: VoxCanvas, s: CharSpec, side: int, xl: int, xh: int, zl: int, zh: int, armor: bool) -> void:
	var lc := s.c2
	for y in range(-8, 0):
		for z in range(zl - 1, zh + 2):
			for x in range(xl - 1, xh + 2):
				if x == xl - 1 or x == xh + 1 or z == zl - 1 or z == zh + 1:
					var c := VoxCanvas.tone(lc, 0.88 + 0.18 * float(VoxCanvas.h3(x, y, z) & 3) / 3.0)
					if y == -1 or y == -8:
						c = s.gold if armor else s.c3
					elif not armor and y % 3 == 0:
						c = s.c3.darkened(0.2)
					cv.put(x, y, z, c)
	if armor:
		# 外侧金色护板
		var ox := (xh + 2) if side > 0 else (xl - 2)
		for y in range(-7, -1):
			for z in range(zl, zh + 1):
				var edge := y == -7 or y == -2 or z == zl or z == zh
				cv.put(ox, y, z, s.gold if edge else VoxCanvas.tone(lc, 0.8))
		cv.put(ox, -4, 0, s.gem)
		cv.put(ox, -5, 0, s.gem.darkened(0.3))


static func hand(s: CharSpec, side: int) -> VoxCanvas:
	var w := s.hand_w
	var xl := lo_of(w)
	var xh := hi_of(w)
	var cv := VoxCanvas.new(Vector3i(xl - 1, -4, xl - 1), Vector3i(xh + 1, 3, xh + 1))
	cv.shift = Vector3(half_shift(w), 0, half_shift(w))
	cv.box(Vector3i(xl, -3, xl), Vector3i(xh, 2, xh), s.skin, 0.02)
	var sh := s.skin.lerp(s.skin_sh, 0.5)
	# 指节缝（握拳）：内侧（掌心朝身体）画几道横缝
	var inx := xl if side > 0 else xh
	for y in [-2, 0]:
		for z in range(xl, xh + 1):
			cv.put(inx, y, z, sh)
	# 拇指：前方包住握把
	cv.box(Vector3i(xl + 1, -1, xl - 1), Vector3i(xh - 1, 1, xl - 1), s.skin)
	cv.put(xl + 1, 0, xl - 1, sh)
	# 指背暗部
	for z in range(xl, xh + 1):
		cv.put(inx, -3, z, sh)
	if s.outfit == "armor":
		var ox := xh if side > 0 else xl
		for y in range(0, 3):
			for z in range(xl, xh + 1):
				cv.put(ox, y, z, VoxCanvas.tone(s.c2, 0.9))
		for z in range(xl, xh + 1):
			for x in range(xl, xh + 1):
				cv.put(x, 2, z, VoxCanvas.tone(s.c2, 0.95))
	return cv


# ================================================================ 腿

static func thigh(s: CharSpec, side: int) -> VoxCanvas:
	# 大腿：y -15..1（顶部伸入骨盆以遮住髋关节）
	var xl := lo_of(s.leg_w)
	var xh := hi_of(s.leg_w)
	var zl := lo_of(s.leg_d)
	var zh := hi_of(s.leg_d)
	var cv := VoxCanvas.new(Vector3i(xl - 3, -17, zl - 3), Vector3i(xh + 3, 4, zh + 3))
	cv.shift = Vector3(half_shift(s.leg_w), 0, half_shift(s.leg_d))
	cv.box(Vector3i(xl, -15, zl), Vector3i(xh, 1, zh), s.skin)
	match s.outfit:
		"robe":
			for y in range(-15, 2):
				for z in range(zl, zh + 1):
					for x in range(xl, xh + 1):
						cv.put(x, y, z, fold(s.c2, x + z, 4))
		"martial":
			for y in range(-15, 2):
				var o := 1 if y < -5 else 0
				for z in range(zl - o, zh + o + 1):
					for x in range(xl - o, xh + o + 1):
						cv.put(x, y, z, fold(s.c2.lerp(s.c1, 0.25), x + z, 4))
		_:
			if not s.female:
				for y in range(-15, 2):
					for z in range(zl, zh + 1):
						for x in range(xl, xh + 1):
							cv.put(x, y, z, fold(s.c2.lerp(Color(0.1, 0.08, 0.07), 0.3), x + z, 3))
			else:
				# 大腿：膝上略暗（靠近靴口的阴影）+ 内侧阴影
				for z in range(zl, zh + 1):
					for x in range(xl, xh + 1):
						cv.put(x, -15, z, s.skin.lerp(s.skin_sh, 0.3))
				var inx := xh if side < 0 else xl
				for y in range(-14, 0):
					cv.put(inx, y, zl, s.skin.lerp(s.skin_sh, 0.15))
	return cv


static func shin(s: CharSpec, side: int) -> VoxCanvas:
	# 小腿：y -15..0（膝在 0，脚底在 -15），脚向前伸出
	var xl := lo_of(s.leg_w)
	var xh := hi_of(s.leg_w)
	var zl := lo_of(s.leg_d)
	var zh := hi_of(s.leg_d)
	var cv := VoxCanvas.new(Vector3i(xl - 3, -16, zl - 7), Vector3i(xh + 3, 5, zh + 3))
	cv.shift = Vector3(half_shift(s.leg_w), 0, half_shift(s.leg_d))
	cv.box(Vector3i(xl, -15, zl), Vector3i(xh, 1, zh), s.skin)
	cv.box(Vector3i(xl, -15, zl - 3), Vector3i(xh, -13, zl - 1), s.skin)
	match s.outfit:
		"robe":
			_shin_robe(cv, s, xl, xh, zl, zh)
		"martial":
			_shin_martial(cv, s, xl, xh, zl, zh)
		_:
			_boot_armor(cv, s, side, xl, xh, zl, zh)
	return cv


## 战靴：宽大靴筒（横向叠层皮革）、前金框护板、金色护膝 + 红宝石、厚底金线
static func _boot_armor(cv: VoxCanvas, s: CharSpec, side: int, xl: int, xh: int, zl: int, zh: int) -> void:
	var lc := s.c2
	var dark := VoxCanvas.tone(lc, 0.66)
	# 内侧（靠近另一条腿）不外扩，避免两靴相撞
	var ix0 := xl - (1 if side < 0 else 0)
	var ix1 := xh + (1 if side > 0 else 0)
	# 靴筒：自膝下到踝；每 3 行一道叠层暗线
	for y in range(-12, 0):
		for z in range(zl - 1, zh + 2):
			for x in range(ix0, ix1 + 1):
				var c := VoxCanvas.tone(lc, 0.88 + 0.2 * float(VoxCanvas.h3(x, y, z) & 3) / 3.0)
				if posmod(y, 3) == 0:
					c = dark
				cv.put(x, y, z, c)
	# 靴口外翻（y -1..0）
	var ox0 := ix0 - (1 if side < 0 else 0)
	var ox1 := ix1 + (1 if side > 0 else 0)
	for y in range(-1, 1):
		for z in range(zl - 2, zh + 3):
			for x in range(ox0, ox1 + 1):
				if x == ox0 or x == ox1 or z == zl - 2 or z == zh + 2:
					cv.put(x, y, z, VoxCanvas.tone(lc, 0.95) if y == 0 else s.gold)
	# 靴头与厚底：y -15..-12，向前 4
	for y in range(-15, -11):
		for z in range(zl - 5, zh + 2):
			for x in range(ix0, ix1 + 1):
				var c2 := VoxCanvas.tone(lc, 0.9 + 0.15 * float(VoxCanvas.h3(x, y, z) & 3) / 3.0)
				if y == -15:
					c2 = VoxCanvas.tone(lc, 0.5)
				elif y == -14:
					c2 = s.gold
				cv.put(x, y, z, c2)
	# 踝部金带
	for z in range(zl - 1, zh + 2):
		for x in range(ix0, ix1 + 1):
			cv.put(x, -12, z, s.gold)
	for x in range(ix0, ix1 + 1):
		cv.put(x, -12, zl - 5, s.gold_hi)
	# 前护板：细金框 + 深色皮面
	var fz := zl - 2
	for y in range(-11, -2):
		for x in range(xl, xh + 1):
			var edge := x == xl or x == xh or y == -11
			cv.put(x, y, fz, s.gold if edge else VoxCanvas.tone(lc, 0.72 + 0.08 * float(VoxCanvas.h3(x, y, 3) & 1)))
	# 护膝：金板 + 宝石
	var cx := 0 if (xh - xl) % 2 == 0 else -1
	metal(cv, Vector3i(xl, -2, fz - 1), Vector3i(xh, 2, fz), s)
	cv.put(cx, 0, fz - 2, VoxelGrid.glow(s.gem, 0.3))
	if (xh - xl) % 2 == 1:
		cv.put(cx + 1, 0, fz - 2, s.gem)
	cv.put(cx, 1, fz - 2, s.gold)
	cv.put(cx, -1, fz - 2, s.gold_sh)
	if (xh - xl) % 2 == 1:
		cv.put(cx + 1, 1, fz - 2, s.gold)
		cv.put(cx + 1, -1, fz - 2, s.gold_sh)
	# 外侧金扣
	var ex := ix1 + 1 if side > 0 else ix0 - 1
	cv.put(ex, -6, 0, s.gold)
	cv.put(ex, -7, 0, s.gold_sh)
	cv.put(ex, -6, -1, s.gold)


static func _shin_robe(cv: VoxCanvas, s: CharSpec, xl: int, xh: int, zl: int, zh: int) -> void:
	for y in range(-12, 2):
		for z in range(zl, zh + 1):
			for x in range(xl, xh + 1):
				cv.put(x, y, z, fold(s.c2, x + z, 4))
	var shoe := s.c2.darkened(0.55)
	for y in range(-15, -11):
		for z in range(zl - 3, zh + 1):
			for x in range(xl, xh + 1):
				cv.put(x, y, z, shoe)
	# 云头鞋尖（饰边色）
	cv.box(Vector3i(xl + 1, -13, zl - 4), Vector3i(xh - 1, -12, zl - 4), s.c3)
	cv.box(Vector3i(xl + 1, -12, zl - 3), Vector3i(xh - 1, -11, zl - 3), s.c3)
	for z in range(zl - 3, zh + 1):
		for x in range(xl, xh + 1):
			cv.put(x, -15, z, Color(0.9, 0.88, 0.84))


static func _shin_martial(cv: VoxCanvas, s: CharSpec, xl: int, xh: int, zl: int, zh: int) -> void:
	var trouser := s.c2.lerp(s.c1, 0.25)
	for y in range(-3, 2):
		for z in range(zl - 1, zh + 2):
			for x in range(xl - 1, xh + 2):
				cv.put(x, y, z, fold(trouser, x + z, 4))
	# 绑腿：浅色布条斜纹
	var wrap := Color(0.9, 0.87, 0.8).lerp(s.c3, 0.15)
	for y in range(-12, -3):
		for z in range(zl, zh + 1):
			for x in range(xl, xh + 1):
				# 斜向缠绕的布条：每 3 行一道暗缝，随绕行方向错位
				var d := posmod(y * 2 + (x - z) / 3, 6)
				var c := wrap if d > 1 else (wrap.darkened(0.2) if d == 0 else wrap.darkened(0.08))
				cv.put(x, y, z, c)
	# 靴
	var boot := s.c2.darkened(0.45)
	for y in range(-15, -11):
		for z in range(zl - 4, zh + 2):
			for x in range(xl - 1, xh + 2):
				if z >= zl - 1 or y <= -13:
					cv.put(x, y, z, VoxCanvas.tone(boot, 0.92 + 0.14 * float(VoxCanvas.h3(x, y, z) & 1)))
	for z in range(zl - 1, zh + 2):
		for x in range(xl - 1, xh + 2):
			if x == xl - 1 or x == xh + 1 or z == zl - 1 or z == zh + 1:
				cv.put(x, -11, z, s.c3.darkened(0.2))


# ================================================================ 下摆 / 裙甲（弹簧）

## 生成平面布片：宽 w（x 从 x0 起）、长 len、厚 1（z=0），painter(x, yi) -> Color 或透明
static func _panel_canvas(w: int, length: int, x0: int, thick: int = 1) -> VoxCanvas:
	return VoxCanvas.new(Vector3i(x0 - 1, -length - 1, -3), Vector3i(x0 + w, 2, thick + 1))


static func build_cloth(hips: Node3D, s: CharSpec, key: String) -> void:
	var zf := -s.torso_d / 2.0
	var zb := s.torso_d / 2.0
	var hw := s.hip_w / 2.0
	match s.outfit:
		"robe":
			_robe_panels(hips, s, key, zf, zb, hw)
		"martial":
			_martial_panels(hips, s, key, zf, zb, hw)
		_:
			_armor_panels(hips, s, key, zf, zb, hw)


static func _cloth_bone(parent: Node3D, bone_name: String, pos: Vector3, rot: Vector3, length: float, stiff: float, limit: float, follow: String, legs: String, weight: float) -> Node3D:
	var b := HairStyles.spring_bone(parent, bone_name, pos, rot, length, stiff, limit)
	b.set_meta("follow", follow)
	b.set_meta("follow_legs", legs)
	b.set_meta("follow_weight", weight)
	return b


static func _armor_panels(hips: Node3D, s: CharSpec, key: String, zf: float, zb: float, hw: float) -> void:
	# 前中长护裆甲（棕底金框 + 菱形宝石）
	var tab_len := 11 if s.female else 15
	var b := _cloth_bone(hips, "cloth_front", Vector3(0, -0.5, zf - 2.5), Vector3(4, 0, 0), tab_len, 0.2, 50, "front", "both", 0.9)
	HairStyles.attach_mesh(b, VoxMesh.cached("ctab|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-5, -tab_len - 1, -2), Vector3i(4, 1, 1))
		for y in range(-tab_len, 1):
			for x in range(-4, 4):
				var edge := x == -4 or x == 3 or y == -tab_len
				cv.put(x, y, 0, VoxCanvas.tone(s.c2, 0.85 + 0.2 * float(VoxCanvas.h3(x, y, 0) & 3) / 3.0))
				if edge:
					cv.put(x, y, -1, s.gold if y > -tab_len else s.gold_sh.lerp(s.gold, 0.5))
		# 菱形金框宝石
		var cy := -tab_len + 5
		for p in [[0, 2], [-1, 1], [0, 1], [-2, 0], [1, 0], [-1, -1], [0, -1], [-1, 2], [0, -2], [-1, -2]]:
			cv.put(p[0], cy + p[1], -1, s.gold)
		cv.put(-1, cy, -1, VoxelGrid.glow(s.gem, 0.3))
		cv.put(0, cy, -1, s.gem)
		cv.put(-1, cy + 1, -1, s.gem.darkened(0.2))
		cv.put(0, cy - 1, -1, s.gem.darkened(0.3))
		cv.shift = Vector3(0.0, 0, 0)
		return VoxMesh.build_one(cv, VOXEL)))
	# 前左/前右红裙片（金边 + 金花）
	for side: int in [-1, 1]:
		var sn := "l" if side < 0 else "r"
		var pl := 8 if s.female else 11
		var bp := _cloth_bone(hips, "cloth_front_" + sn, Vector3(side * (hw - 1.5), -0.5, zf - 1.5), Vector3(3, 0, side * 7), pl, 0.2, 45, "front", "l" if side < 0 else "r", 0.85)
		HairStyles.attach_mesh(bp, VoxMesh.cached("cfr|%s" % key, func() -> ArrayMesh:
			var cv := VoxCanvas.new(Vector3i(-4, -pl - 1, -2), Vector3i(3, 1, 1))
			for y in range(-pl, 1):
				for x in range(-3, 3):
					var edge := x == -3 or x == 2 or y == -pl
					var c := fold(s.c1, x, 3)
					if edge:
						c = s.gold
					cv.put(x, y, 0, c)
			# 金花纹
			var fy := -pl + 3
			for p in [[-1, 0], [0, 0], [-1, 1], [0, -1], [-2, 0], [1, 0], [-1, -1], [0, 1]]:
				if absi(p[0]) + absi(p[1]) <= 2:
					cv.put(p[0], fy + p[1], -1, s.gold)
			cv.put(-1, fy, -1, s.gold_hi)
			return VoxMesh.build_one(cv, VOXEL)), "Mesh", side < 0)
	# 两侧棕色护腿甲
	for side: int in [-1, 1]:
		var sn2 := "l" if side < 0 else "r"
		var sl := 8 if s.female else 12
		var bs := _cloth_bone(hips, "cloth_side_" + sn2, Vector3(side * (hw + 2.5), -0.5, 0), Vector3(0, 0, side * 14), sl, 0.2, 40, "side", "l" if side < 0 else "r", 0.9)
		HairStyles.attach_mesh(bs, VoxMesh.cached("csd|%s" % key, func() -> ArrayMesh:
			var cv := VoxCanvas.new(Vector3i(-2, -sl - 1, -5), Vector3i(1, 1, 4))
			for y in range(-sl, 1):
				for z in range(-4, 4):
					var edge := z == -4 or z == 3 or y == -sl
					cv.put(0, y, z, s.gold if edge else VoxCanvas.tone(s.c2, 0.85 + 0.2 * float(VoxCanvas.h3(0, y, z) & 3) / 3.0))
					if not edge and (z == -3 or z == 2):
						cv.put(0, y, z, s.c1)
				if y == -sl + 4 or y == -sl + 5:
					cv.put(1, y, -1, s.gold)
					cv.put(1, y, 0, s.gold)
			return VoxMesh.build_one(cv, VOXEL)), "Mesh", side < 0)
	# 后片
	for side: int in [-1, 1]:
		var sn3 := "l" if side < 0 else "r"
		var bl := 8 if s.female else 13
		var bb := _cloth_bone(hips, "cloth_back_" + sn3, Vector3(side * 3.5, -0.5, zb + 1.5), Vector3(-4, 0, side * 5), bl, 0.2, 45, "back", "l" if side < 0 else "r", 0.85)
		HairStyles.attach_mesh(bb, VoxMesh.cached("cbk|%s" % key, func() -> ArrayMesh:
			var cv := VoxCanvas.new(Vector3i(-5, -bl - 1, -2), Vector3i(4, 1, 2))
			for y in range(-bl, 1):
				for x in range(-4, 3):
					var edge := x == -4 or x == 2 or y == -bl
					cv.put(x, y, 0, s.gold if edge else fold(s.c1, x, 3))
			return VoxMesh.build_one(cv, VOXEL)), "Mesh", side < 0)


static func _robe_panels(hips: Node3D, s: CharSpec, key: String, zf: float, zb: float, hw: float) -> void:
	var length := 24
	var inner := s.c2.lerp(Color(0.95, 0.94, 0.9), 0.5)
	for side: int in [-1, 1]:
		var sn := "l" if side < 0 else "r"
		var leg := "l" if side < 0 else "r"
		# 前摆（含半个侧面，包住髋部）
		var bf := _cloth_bone(hips, "cloth_robe_f" + sn, Vector3(0, -3.0, zf - 1.5), Vector3(5, 0, 0), length, 0.18, 55, "front", leg, 0.95)
		HairStyles.attach_mesh(bf, VoxMesh.cached("crf|%s|%s" % [key, sn], func() -> ArrayMesh:
			return VoxMesh.build_one(_robe_panel(s, side, true, length, int(hw), int(zb - zf), inner), VOXEL)))
		var bb := _cloth_bone(hips, "cloth_robe_b" + sn, Vector3(0, -3.0, zb + 1.5), Vector3(-5, 0, 0), length, 0.18, 55, "back", leg, 0.9)
		HairStyles.attach_mesh(bb, VoxMesh.cached("crb|%s|%s" % [key, sn], func() -> ArrayMesh:
			return VoxMesh.build_one(_robe_panel(s, side, false, length, int(hw), int(zb - zf), inner), VOXEL)))
	# 玉佩（左腰）
	var bj := _cloth_bone(hips, "cloth_pendant", Vector3(-hw + 1.0, 0.0, zf - 3.0), Vector3(0, 0, 0), 10, 0.14, 50, "front", "l", 0.6)
	HairStyles.attach_mesh(bj, VoxMesh.cached("cpd|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-3, -13, -2), Vector3i(2, 1, 1))
		cv.box(Vector3i(-1, -4, 0), Vector3i(0, 0, 0), s.c3)
		var jade := Color("62c49a")
		cv.box(Vector3i(-2, -8, 0), Vector3i(1, -5, 0), jade, 0.06)
		cv.put(-1, -6, 0, jade.darkened(0.3))
		cv.put(0, -7, 0, jade.lightened(0.3))
		cv.box(Vector3i(-1, -12, 0), Vector3i(0, -9, 0), s.gem, 0.06)
		return VoxMesh.build_one(cv, VOXEL)))


## 道袍下摆片：front 为前片；side -1 左 / 1 右；向下逐渐外扩
static func _robe_panel(s: CharSpec, side: int, front: bool, length: int, hw: int, depth: int, inner: Color) -> VoxCanvas:
	var W := hw + 3
	var D := depth / 2 + 5
	var cv := VoxCanvas.new(Vector3i(-W - 2, -length - 1, -3), Vector3i(W + 1, 2, D + 2))
	var zdir := 1 if front else -1
	for yi in range(-1, length):
		var y := -yi
		var flare := yi / 7
		var xa := 0 if side > 0 else -(hw + 1 + flare)
		var xb := (hw + flare) if side > 0 else -1
		if front and side > 0:
			xa = -1   # 右前片压在左前片下，稍微重叠
		var hem := yi >= length - 2
		var c_row := s.c3 if hem else Color(0, 0, 0, 0)
		# 前/后平面（z=0，前片的 z 向内为 +z，后片为 -z）
		for x in range(xa, xb + 1):
			var c := fold(s.c1, x, 4)
			if hem:
				c = c_row if yi == length - 1 else s.c3.darkened(0.15)
			var open_edge := front and ((side < 0 and x == -1) or (side > 0 and x == -1))
			if open_edge and not hem:
				c = s.c3
			cv.put(x, y, 0, VoxCanvas.tone(c, 1.0 - 0.1 * float(yi) / length))
		# 侧面包边（沿 z 向身体中线延伸半个深度）
		var sx := xa if side < 0 else xb
		for k in range(1, D - 1):
			var z := k * zdir
			var c2 := fold(s.c1, k + 1, 4)
			if hem:
				c2 = s.c3 if yi == length - 1 else s.c3.darkened(0.15)
			cv.put(sx, y, z, VoxCanvas.tone(c2, 0.95 - 0.1 * float(yi) / length))
	# 内衬：下摆内侧一行
	return cv


static func _martial_panels(hips: Node3D, s: CharSpec, key: String, zf: float, zb: float, hw: float) -> void:
	for side: int in [-1, 1]:
		var sn := "l" if side < 0 else "r"
		var leg := "l" if side < 0 else "r"
		var fl := 10
		var bf := _cloth_bone(hips, "cloth_front_" + sn, Vector3(side * (hw * 0.5), -2.5, zf - 1.5), Vector3(4, 0, side * 5), fl, 0.2, 50, "front", leg, 0.9)
		HairStyles.attach_mesh(bf, VoxMesh.cached("cmf|%s" % key, func() -> ArrayMesh:
			var cv := VoxCanvas.new(Vector3i(-5, -fl - 1, -2), Vector3i(4, 1, 1))
			var w := int(hw)
			for y in range(-fl, 1):
				for x in range(-w / 2 - 1, w / 2 + 1):
					var edge := y == -fl or x == -w / 2 - 1
					cv.put(x, y, 0, s.c3 if edge else fold(s.c1, x, 5))
			return VoxMesh.build_one(cv, VOXEL)), "Mesh", side < 0)
		var bl := 13
		var bb := _cloth_bone(hips, "cloth_back_" + sn, Vector3(side * (hw * 0.5), -2.5, zb + 1.5), Vector3(-6, 0, side * 4), bl, 0.18, 50, "back", leg, 0.9)
		HairStyles.attach_mesh(bb, VoxMesh.cached("cmb|%s" % key, func() -> ArrayMesh:
			var cv := VoxCanvas.new(Vector3i(-6, -bl - 1, -2), Vector3i(5, 1, 1))
			var w := int(hw)
			for y in range(-bl, 1):
				for x in range(-w / 2 - 1, w / 2 + 1):
					var edge := y == -bl or x == w / 2
					cv.put(x, y, 0, s.c3 if edge else fold(s.c1, x, 5))
			return VoxMesh.build_one(cv, VOXEL)), "Mesh", side < 0)
	# 腰带结的飘带
	var bs := _cloth_bone(hips, "cloth_sash", Vector3(-hw - 1.5, 3.0, zf + 1.0), Vector3(0, 0, -8), 12, 0.14, 50, "side", "l", 0.5)
	HairStyles.attach_mesh(bs, VoxMesh.cached("cms|" + key, func() -> ArrayMesh:
		var cv := VoxCanvas.new(Vector3i(-2, -13, -3), Vector3i(1, 1, 2))
		for y in range(-12, 1):
			var c := s.c3 if y > -11 else s.c3.darkened(0.2)
			cv.put(0, y, 0, c)
			cv.put(0, y, -1, c.darkened(0.1))
			if y > -6:
				cv.put(0, y, 1, c.darkened(0.05))
		return VoxMesh.build_one(cv, VOXEL)))
