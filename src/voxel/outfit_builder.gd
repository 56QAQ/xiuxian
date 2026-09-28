class_name OutfitBuilder
## 身体与服饰绘制（2× 精度）：每个骨骼一张画布（身体 + 服饰外层合并，内部面自动剔除）。
## 服饰：armor（参考图战甲：皮甲 + 金饰边 + 卷草金纹 + 刻面宝石 + 铆钉）、
##       robe（道袍：交领右衽、云纹刺绣饰边、宽袖、宽腰带 + 玉佩流苏、长下摆）、
##       martial（劲装：收身短衣、皮腰带、护腕、绑腿、飘带）。
## 做法：先画有形体的身体（圆角、收腰、胸、锁骨），服饰用 wrap_layer() 在身体外包一层（自动贴合形体），
##       再按行改色画饰边、盖印图案、加铆钉/宝石。
## 裙甲/下摆为 cloth_ 弹簧骨骼（hips 下），meta "follow" 让其随腿摆动（见 HumanoidRig）。
## 坐标均为骨骼局部体素坐标（0.0125m），约定见 CharSpec。
## 注意：绘制函数在工作线程中调用，图案表一律用 static var。

const VOXEL := 0.0125

const F_FRONT := 1
const F_BACK := 2
const F_LEFT := 4
const F_RIGHT := 8
const F_ALL := 15

## 祥云纹（9×6）：c 线条，h 高光
static var CLOUD: Array = [
	"..ccc....",
	".c...c.c.",
	"c..h..c.c",
	"c.c.c..c.",
	".c...cc..",
	"..ccc....",
]
## 卷草纹（C 形卷，5×5），用于甲片金纹
static var SCROLL: Array = [
	".ggg.",
	"g...g",
	"g.g..",
	"g..g.",
	".gg..",
]
## 菱形宝石金框（7×7）
static var DIAMOND: Array = [
	"...g...",
	"..gHg..",
	".gGEeg.",
	"gGEEEsg",
	".gEEsg.",
	"..gsg..",
	"...g...",
]
## 兽首带扣（12×10）：g 金、h 亮金、s 暗金、d 深、e 眼（宝石）
static var BEAST: Array = [
	".hh......hh.",
	"hggh....hggh",
	"hgggghhgggg.",
	".gdgggggdg..",
	".gegsggsegg.",
	".ggggddgggg.",
	"..gsgggsgg..",
	"..gdhhhhdg..",
	"...gsddsg...",
	"....gggg....",
]


# ================================================================ 小工具

static func lo_of(w: int) -> int:
	return -(w / 2)


static func hi_of(w: int) -> int:
	return -(w / 2) + w - 1


static func half_shift(w: int) -> float:
	return -0.5 if w % 2 == 1 else 0.0


## 金属块：顶面高光、底边暗
static func metal(cv: VoxCanvas, a: Vector3i, b: Vector3i, s: CharSpec) -> void:
	cv.set_mat(VoxCanvas.M_GOLD)
	cv.box(a, b, s.gold)
	var y0 := mini(a.y, b.y)
	var y1 := maxi(a.y, b.y)
	cv.box(Vector3i(a.x, y1, a.z), Vector3i(b.x, y1, b.z), s.gold_hi)
	if y1 > y0:
		cv.box(Vector3i(a.x, y0, a.z), Vector3i(b.x, y0, b.z), s.gold_sh)


## 宝石（size 1 单颗发光；2/3 刻面：左上高光、右下暗角）
static func gem(cv: VoxCanvas, x: int, y: int, z: int, s: CharSpec, size: int = 1) -> void:
	HairStyles.gem_at(cv, s, x, y, z, size, s.gem)


## 褶皱布料色：按列加深，模拟竖褶
static func fold(c: Color, x: int, period: int = 3) -> Color:
	var m := posmod(x, period * 2)
	if m == 0:
		return VoxCanvas.tone(c, 0.84)
	if m == 1 or m == period * 2 - 1:
		return VoxCanvas.tone(c, 0.93)
	if m == period:
		return VoxCanvas.tone(c, 1.05)
	return c


## 在已有形体外包一层（厚 1）：每行对每列找最外侧实体，在其外侧写入。
## pick(x, y, z, face) -> Color；face：1 前 2 后 4 左 8 右。只写空位。x_rng 限定扫描的 x 范围。
static func wrap_layer(cv: VoxCanvas, y0: int, y1: int, pick: Callable, faces: int = F_ALL, x_rng: Vector2i = Vector2i(-9999, 9999)) -> void:
	var d := cv.data
	var sx := cv.sx
	var sxy := cv.sxy
	var lx := cv.lo.x
	var lz := cv.lo.z
	var xa := maxi(cv.lo.x + 1, x_rng.x)
	var xb := mini(cv.hi.x - 1, x_rng.y)
	var za := cv.lo.z + 1
	var zb := cv.hi.z - 1
	var nx := xb - xa + 1
	if nx <= 0:
		return
	var zmin := PackedInt32Array()
	var zmax := PackedInt32Array()
	zmin.resize(nx)
	zmax.resize(nx)
	for y in range(maxi(y0, cv.lo.y + 1), mini(y1, cv.hi.y - 1) + 1):
		var yo := sx * (y - cv.lo.y + 1) - lx + 1
		zmin.fill(99999)
		zmax.fill(-99999)
		var pts: Array[Vector4i] = []
		for z in range(za, zb + 1):
			var row := yo + sxy * (z - lz + 1)
			var xmn := 99999
			var xmx := -99999
			for x in range(xa, xb + 1):
				if d[row + x] != 0:
					if xmn == 99999:
						xmn = x
					xmx = x
					var i := x - xa
					if zmin[i] == 99999:
						zmin[i] = z
					zmax[i] = z
			if xmn <= xmx:
				if faces & F_LEFT:
					pts.append(Vector4i(xmn - 1, y, z, F_LEFT))
				if faces & F_RIGHT:
					pts.append(Vector4i(xmx + 1, y, z, F_RIGHT))
		if faces & (F_FRONT | F_BACK):
			for i in nx:
				if zmin[i] > zmax[i]:
					continue
				if faces & F_FRONT:
					pts.append(Vector4i(xa + i, y, zmin[i] - 1, F_FRONT))
				if faces & F_BACK:
					pts.append(Vector4i(xa + i, y, zmax[i] + 1, F_BACK))
		for p in pts:
			if cv.get_raw(p.x, p.y, p.z) == 0:
				cv.put(p.x, p.y, p.z, pick.call(p.x, p.y, p.z, p.w))


## 把某行中材质为 from_mat 的体素改色（饰边）；from_mat = -1 表示所有非皮肤体素
static func recolor_row(cv: VoxCanvas, y: int, from_mat: int, c: Color, to_mat: int) -> void:
	if y < cv.lo.y or y > cv.hi.y:
		return
	var d := cv.data
	var v := VoxCanvas.encm(c, to_mat)
	var yo := cv.sx * (y - cv.lo.y + 1)
	for z in range(cv.lo.z, cv.hi.z + 1):
		var row := yo + cv.sxy * (z - cv.lo.z + 1) - cv.lo.x + 1
		for x in range(cv.lo.x, cv.hi.x + 1):
			var r := d[row + x]
			if r == 0:
				continue
			var m := (r >> 4) & 15
			if m == VoxCanvas.M_SKIN:
				continue
			if from_mat >= 0 and m != from_mat:
				continue
			d[row + x] = v


## 某行最前面的体素 z（x 列）；无则返回 99999
static func front_z(cv: VoxCanvas, x: int, y: int) -> int:
	if x < cv.lo.x or x > cv.hi.x or y < cv.lo.y or y > cv.hi.y:
		return 99999
	var d := cv.data
	var base := (x - cv.lo.x + 1) + cv.sx * (y - cv.lo.y + 1)
	for z in range(cv.lo.z, cv.hi.z + 1):
		if d[base + cv.sxy * (z - cv.lo.z + 1)] != 0:
			return z
	return 99999


static func back_z(cv: VoxCanvas, x: int, y: int) -> int:
	if x < cv.lo.x or x > cv.hi.x or y < cv.lo.y or y > cv.hi.y:
		return -99999
	var d := cv.data
	var base := (x - cv.lo.x + 1) + cv.sx * (y - cv.lo.y + 1)
	for z in range(cv.hi.z, cv.lo.z - 1, -1):
		if d[base + cv.sxy * (z - cv.lo.z + 1)] != 0:
			return z
	return -99999


## 在前表面上盖印（每格落在该列最前体素上；raise=1 时再向外凸一格）
static func stamp_front(cv: VoxCanvas, rows: Array, pal: Dictionary, x0: int, ytop: int, raise: int = 0) -> void:
	for r in rows.size():
		var row: String = rows[r]
		for j in row.length():
			var ch := row[j]
			if not pal.has(ch):
				continue
			var x := x0 + j
			var y := ytop - r
			var fz := front_z(cv, x, y)
			if fz > 9000:
				continue
			var pv: Array = pal[ch]
			cv.putm(x, y, fz - raise, pv[0], int(pv[1]))


## 在后表面上盖印（从背后看为正向）
static func stamp_back(cv: VoxCanvas, rows: Array, pal: Dictionary, x0: int, ytop: int, raise: int = 0) -> void:
	for r in rows.size():
		var row: String = rows[r]
		for j in row.length():
			var ch := row[j]
			if not pal.has(ch):
				continue
			var x := x0 + (row.length() - 1 - j)
			var y := ytop - r
			var bz := back_z(cv, x, y)
			if bz < -9000:
				continue
			var pv: Array = pal[ch]
			cv.putm(x, y, bz + raise, pv[0], int(pv[1]))


## 金色调色板（盖印用）
static func gold_pal(s: CharSpec) -> Dictionary:
	return {
		"g": [s.gold, VoxCanvas.M_GOLD], "h": [s.gold_hi, VoxCanvas.M_GOLD], "s": [s.gold_sh, VoxCanvas.M_GOLD],
		"d": [s.gold_dk, VoxCanvas.M_GOLD], "G": [s.gold_hi, VoxCanvas.M_GOLD],
		"e": [VoxCanvas.glow(s.gem, 0.4), VoxCanvas.M_GEM], "E": [s.gem, VoxCanvas.M_GEM],
		"H": [VoxCanvas.glow(s.gem_hi, 0.5), VoxCanvas.M_GEM], "c": [s.gold, VoxCanvas.M_GOLD],
	}


## 一排铆钉：前表面 y 行，每 step 列一颗（外凸 1 格）
static func rivets_front(cv: VoxCanvas, s: CharSpec, y: int, x0: int, x1: int, step: int) -> void:
	for x in range(x0, x1 + 1, step):
		var fz := front_z(cv, x, y)
		if fz < 9000:
			cv.putm(x, y, fz - 1, s.gold_hi, VoxCanvas.M_GOLD)


# ================================================================ 躯干（spine）

static func torso(s: CharSpec) -> VoxCanvas:
	# 躯干 36 行：腰 y 0..11，胸 y 12..35（顶面即肩线）
	var zl := lo_of(s.torso_d)
	var zh := hi_of(s.torso_d)
	var cw := s.chest_w / 2
	var ww := s.waist_w / 2
	var cv := VoxCanvas.new(Vector3i(-cw - 8, -4, zl - 10), Vector3i(cw + 7, 40, zh + 8))
	cv.shift = Vector3(0, 0, half_shift(s.torso_d))
	_body_torso(cv, s, zl, zh, cw, ww)
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


## 身体：收腰、圆角、肩线收圆、胸、锁骨、肚脐、腹肌（男）
static func _body_torso(cv: VoxCanvas, s: CharSpec, zl: int, zh: int, cw: int, ww: int) -> void:
	cv.set_mat(VoxCanvas.M_SKIN)
	var side_c := s.skin.lerp(s.skin_sh, 0.3)
	for y in range(0, 36):
		var hw := cw
		if y < 12:
			hw = ww
			if s.female and y >= 4 and y <= 9:
				hw -= 1
		elif y < 18:
			hw = int(round(lerpf(ww, cw, float(y - 11) / 7.0)))
		var z0 := zl
		var z1 := zh
		if y >= 34:
			hw -= y - 33
			z0 += 1
			z1 -= 1
		for z in range(z0, z1 + 1):
			for x in range(-hw, hw):
				var ex := x == -hw or x == hw - 1
				var ez := z == z0 or z == z1
				if ex and ez:
					continue
				cv.put(x, y, z, side_c if ex else s.skin)
	# 胸（女）
	if s.female and s.chest > 0.05:
		var dz := 1.6 + s.chest * 2.2
		for side: int in [-1, 1]:
			var cx := side * 5.4 - 0.5 + 0.5
			cv.ellipsoid(Vector3(cx, 23.5, zl + 0.8), Vector3(5.4, 4.8, dz), s.skin)
			# 下缘阴影
			for x in range(int(cx) - 5, int(cx) + 5):
				var fz := front_z(cv, x, 19)
				if fz < zl:
					cv.put(x, 19, fz, s.skin.lerp(s.skin_sh, 0.45))
		for y in range(20, 28):
			var fz2 := front_z(cv, -1, y)
			if fz2 < 9000:
				cv.put(-1, y, fz2, s.skin.lerp(s.skin_sh, 0.35))
				cv.put(0, y, fz2, s.skin.lerp(s.skin_sh, 0.35))
	elif not s.female:
		# 胸肌
		for x in range(-cw + 3, cw - 3):
			if x == -1 or x == 0:
				continue
			for y in range(24, 32):
				cv.put(x, y, zl - 1, s.skin if y > 24 else s.skin.lerp(s.skin_sh, 0.4))
		# 腹肌
		for y in [6, 11, 16]:
			for x in range(-6, 6):
				if x != -1 and x != 0:
					cv.put(x, y, zl, s.skin.lerp(s.skin_sh, 0.3))
		for y in range(4, 21):
			cv.put(-1, y, zl, s.skin.lerp(s.skin_sh, 0.22))
	# 肚脐、锁骨
	cv.put(-1, 6, zl, s.skin_dk.lerp(s.skin_sh, 0.4))
	cv.put(0, 6, zl, s.skin.lerp(s.skin_sh, 0.5))
	cv.put(-1, 7, zl, s.skin.lerp(s.skin_sh, 0.3))
	for x in range(3, 10):
		cv.put(-1 - x, 33 - (x / 4), zl, s.skin.lerp(s.skin_sh, 0.3))
		cv.put(x, 33 - (x / 4), zl, s.skin.lerp(s.skin_sh, 0.3))


static func _torso_armor_f(cv: VoxCanvas, s: CharSpec, zl: int, zh: int, cw: int, ww: int) -> void:
	var lc := s.c2
	var lc_hi := s.c2_hi
	# 胸甲：皮革包住胸部（y 19..30），上下金边 + 铆钉
	cv.set_mat(VoxCanvas.M_LEATHER)
	wrap_layer(cv, 19, 30, func(x: int, y: int, z: int, f: int) -> Color:
		var k := 0.9 + 0.12 * VoxCanvas.hf(x >> 1, y >> 1, z >> 1)
		if f == F_FRONT and y >= 27:
			k *= 1.06
		return VoxCanvas.tone(lc, k))
	# 中缝略凹（两罩杯分开）
	for y in range(20, 30):
		for x in [-1, 0]:
			var fz := front_z(cv, x, y)
			if fz < zl - 1:
				cv.clear_at(x, y, fz)
	for y in [19, 20, 29, 30]:
		recolor_row(cv, y, VoxCanvas.M_LEATHER, s.gold if (y == 20 or y == 29) else s.gold_sh, VoxCanvas.M_GOLD)
	recolor_row(cv, 30, VoxCanvas.M_GOLD, s.gold_hi, VoxCanvas.M_GOLD)
	rivets_front(cv, s, 20, -cw + 1, cw - 2, 4)
	# 罩杯上的金色卷草纹（左右镜像）
	var gp := gold_pal(s)
	for side: int in [-1, 1]:
		var x0 := -9 if side < 0 else 4
		var rows: Array = SCROLL if side > 0 else _mirror_rows(SCROLL)
		stamp_front(cv, rows, gp, x0, 27, 0)
	# 中央：金框 + 刻面宝石扣
	metal(cv, Vector3i(-2, 21, zl - 5), Vector3i(1, 28, zl - 5), s)
	gem(cv, -1, 26, zl - 6, s, 2)
	cv.putm(-2, 24, zl - 6, s.gold_hi, VoxCanvas.M_GOLD)
	cv.putm(1, 24, zl - 6, s.gold_hi, VoxCanvas.M_GOLD)
	# 肩带（皮 + 金边）自罩杯上缘斜向肩后
	cv.set_mat(VoxCanvas.M_LEATHER)
	for side: int in [-1, 1]:
		for y in range(31, 36):
			var xs := (-7 - (y - 31) / 2) if side < 0 else (6 + (y - 31) / 2)
			for dx in 3:
				var x := xs + dx * side
				var fz := front_z(cv, x, y)
				if fz < 9000:
					cv.put(x, y, fz - 1, lc_hi if dx == 1 else s.gold)
				var bz := back_z(cv, x, y)
				if bz > -9000:
					cv.put(x, y, bz + 1, lc)
	# 下胸小垂饰（金链 + 宝石）
	cv.set_mat(VoxCanvas.M_GOLD)
	for y in range(15, 19):
		cv.put(-1, y, front_z(cv, -1, 19) , s.gold if y % 2 else s.gold_hi)
	gem(cv, -1, 15, front_z(cv, -1, 15) - 1, s, 1)
	# 腰间细金链（斜挂）
	for x in range(-ww, ww):
		var y2 := 3 + int(round(absf(x + 0.5) * 0.18))
		var fz3 := front_z(cv, x, y2)
		if fz3 < 9000 and (x & 1) == 0:
			cv.putm(x, y2, fz3 - 1, s.gold_hi if (x & 3) == 0 else s.gold, VoxCanvas.M_GOLD)
	# 背后：胸甲后带 + 交叉背带
	cv.set_mat(VoxCanvas.M_LEATHER)
	for k in 10:
		for side: int in [-1, 1]:
			var x := side * (1 + k)
			var y := 30 + (k / 2) if k < 10 else 35
			var bz2 := back_z(cv, x, mini(y, 35))
			if bz2 > -9000:
				cv.put(x, mini(y, 35), bz2 + 1, lc)


static func _mirror_rows(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		out.append((r as String).reverse())
	return out


static func _torso_armor_m(cv: VoxCanvas, s: CharSpec, zl: int, zh: int, cw: int, ww: int) -> void:
	var lc := s.c2
	# 内衬（腰部红布）
	cv.set_mat(VoxCanvas.M_CLOTH)
	wrap_layer(cv, 0, 5, func(x: int, y: int, z: int, f: int) -> Color: return fold(s.c1, x + z, 2))
	# 胸甲整片：皮革外壳
	cv.set_mat(VoxCanvas.M_LEATHER)
	wrap_layer(cv, 6, 36, func(x: int, y: int, z: int, f: int) -> Color:
		return VoxCanvas.tone(lc, 0.88 + 0.14 * VoxCanvas.hf(x >> 1, y >> 1, z >> 1)))
	# 胸板：前凸一层 + 金边
	for x in range(-cw + 3, cw - 3):
		for y in range(20, 34):
			var fz := front_z(cv, x, y)
			var edge := x == -cw + 3 or x == cw - 4 or y == 20 or y == 33
			cv.putm(x, y, fz - 1, s.gold if edge else VoxCanvas.tone(lc, 1.08), VoxCanvas.M_GOLD if edge else VoxCanvas.M_LEATHER)
	# 兽面金饰
	var gp := gold_pal(s)
	stamp_front(cv, BEAST, gp, -6, 31, 1)
	# 腹部札甲：错缝小甲片（每片 4×3），片缝深、片顶亮，片角金钉
	for y in range(7, 20):
		var row := (19 - y) / 3
		var ry := posmod(19 - y, 3)
		for x in range(-ww - 1, ww + 1):
			var fz2 := front_z(cv, x, y)
			if fz2 > 9000:
				continue
			var px := posmod(x + (2 if row % 2 else 0), 4)
			var c := VoxCanvas.tone(lc, 1.0)
			var m := VoxCanvas.M_LEATHER
			if ry == 2 or px == 0:
				c = VoxCanvas.tone(lc, 0.62)
			elif ry == 0:
				c = VoxCanvas.tone(lc, 1.15)
			if ry == 1 and px == 2:
				c = s.gold_sh.lerp(s.gold, 0.5)
				m = VoxCanvas.M_GOLD
			cv.putm(x, y, fz2, c, m)
	# 金边：胸甲下缘、领口
	recolor_row(cv, 6, VoxCanvas.M_LEATHER, s.gold, VoxCanvas.M_GOLD)
	recolor_row(cv, 36, VoxCanvas.M_LEATHER, s.gold, VoxCanvas.M_GOLD)
	rivets_front(cv, s, 6, -ww, ww - 1, 4)
	# 领口红布
	cv.set_mat(VoxCanvas.M_CLOTH)
	for x in range(-5, 5):
		cv.put(x, 36, zl - 1, s.c1)
		cv.put(x, 37, zl, s.c1_sh)


static func _torso_robe(cv: VoxCanvas, s: CharSpec, zl: int, zh: int, cw: int, ww: int) -> void:
	var inner := s.c2.lerp(Color(0.95, 0.94, 0.9), 0.78)
	# 中衣（白）：包身体一层
	cv.set_mat(VoxCanvas.M_CLOTH)
	wrap_layer(cv, 0, 36, func(x: int, y: int, z: int, f: int) -> Color: return VoxCanvas.tone(inner, 0.96 + 0.04 * float(x & 1)))
	# 外袍：再包一层（竖褶）
	cv.set_mat(VoxCanvas.M_SILK)
	wrap_layer(cv, 0, 36, func(x: int, y: int, z: int, f: int) -> Color:
		var c := fold(s.c1, x - z, 3)
		if f == F_BACK:
			c = VoxCanvas.tone(c, 0.95)
		return c)
	# 交领（右衽）：领缘从颈左侧斜向右腰（饰边宽 5：外 1 暗、内 3 饰边色 + 云纹点缀、再 1 内衬）
	var trim := s.c3
	var trim_sh := VoxCanvas.tone(s.c3, 0.72)
	for y in range(8, 37):
		var t := float(36 - y) / 28.0
		var xc := int(round(lerpf(-3.0, 11.0, t)))
		for dx in 6:
			var x := xc - dx
			var fz := front_z(cv, x, y)
			if fz > 9000:
				continue
			var c := trim
			var m := VoxCanvas.M_SILK
			if dx == 0 or dx == 4:
				c = trim_sh
			elif dx == 2 and posmod(y, 4) == 0:
				c = s.gold_hi
				m = VoxCanvas.M_GOLD
			elif dx == 5:
				c = inner
			cv.putm(x, y, fz, c, m)
		# 领缘外侧的外袍（交叠处）再凸 1 格
		var fz0 := front_z(cv, xc + 1, y)
		if fz0 < 9000:
			cv.putm(xc + 1, y, fz0 - 1, fold(s.c1, xc + 1, 3), VoxCanvas.M_SILK)
		if y >= 24:
			# 露出中衣
			for x in range(-2, xc - 5):
				var fz2 := front_z(cv, x, y)
				if fz2 < 9000:
					cv.putm(x, y, fz2, inner, VoxCanvas.M_CLOTH)
	# 另一侧领缘（左襟压在下面，只露上段）
	for y in range(28, 37):
		var x2 := -2 - (36 - y) / 2
		for dx in 3:
			var fz3 := front_z(cv, x2 - dx, y)
			if fz3 < 9000:
				cv.putm(x2 - dx, y, fz3, trim if dx < 2 else trim_sh, VoxCanvas.M_SILK)
	# 后领
	for x in range(-6, 6):
		var bz := back_z(cv, x, 36)
		cv.putm(x, 36, bz, trim, VoxCanvas.M_SILK)
		cv.putm(x, 37, bz, trim_sh, VoxCanvas.M_SILK)
	# 背后大祥云刺绣
	var cp := {"c": [s.c3, VoxCanvas.M_SILK], "h": [s.gold_hi, VoxCanvas.M_GOLD]}
	stamp_back(cv, CLOUD, cp, -5, 28, 0)
	# 胸前小云纹（左胸）
	stamp_front(cv, CLOUD, cp, -cw + 1, 30, 0)
	# 宽腰带（y 0..8）：上下饰边、中段织纹
	var sash := s.c2
	cv.set_mat(VoxCanvas.M_SILK)
	wrap_layer(cv, 0, 8, func(x: int, y: int, z: int, f: int) -> Color:
		if y == 0 or y == 8:
			return s.c3
		if y == 1 or y == 7:
			return VoxCanvas.tone(sash, 0.75)
		return VoxCanvas.tone(sash, 0.95 + 0.1 * float(((x + y) >> 1) & 1)))
	# 腰带正中：玉扣（圆形玉璧）
	var fzc := front_z(cv, -1, 4)
	cv.set_mat(VoxCanvas.M_JADE)
	var jade := Color("6ccca4")
	for y in range(1, 8):
		for x in range(-4, 4):
			var d := Vector2(x + 0.5, y - 4.0).length()
			if d <= 3.4:
				var c := jade if d > 1.2 else jade.darkened(0.35)
				if d > 2.6:
					c = jade.lightened(0.15)
				cv.put(x, y, fzc - 1, c)


static func _torso_martial(cv: VoxCanvas, s: CharSpec, zl: int, zh: int, cw: int, ww: int) -> void:
	# 收身短衣：包身体一层（竖褶细）
	cv.set_mat(VoxCanvas.M_CLOTH)
	wrap_layer(cv, 0, 36, func(x: int, y: int, z: int, f: int) -> Color:
		return fold(s.c1, x + z, 4))
	# 交领（窄）
	for y in range(14, 37):
		var t := float(36 - y) / 22.0
		var xc := int(round(lerpf(-2.0, 8.0, t)))
		for dx in 4:
			var x := xc - dx
			var fz := front_z(cv, x, y)
			if fz > 9000:
				continue
			cv.putm(x, y, fz, s.c3 if dx > 0 and dx < 3 else VoxCanvas.tone(s.c3, 0.75), VoxCanvas.M_CLOTH)
	for y in range(28, 37):
		var x2 := -2 - (36 - y) / 2
		var fz2 := front_z(cv, x2, y)
		if fz2 < 9000:
			cv.putm(x2, y, fz2, s.c3, VoxCanvas.M_CLOTH)
			cv.putm(x2 - 1, y, fz2, VoxCanvas.tone(s.c3, 0.75), VoxCanvas.M_CLOTH)
	# 衣襟边线 + 盘扣
	for y in range(9, 14):
		var fz3 := front_z(cv, 8, y)
		if fz3 < 9000:
			cv.putm(8, y, fz3, VoxCanvas.tone(s.c1, 0.72), VoxCanvas.M_CLOTH)
	for y in [30, 25, 20]:
		var xb := int(round(lerpf(-2.0, 8.0, float(36 - y) / 22.0)))
		var fz4 := front_z(cv, xb + 1, y)
		if fz4 < 9000:
			cv.putm(xb + 1, y, fz4 - 1, s.c3, VoxCanvas.M_CLOTH)
			cv.putm(xb + 2, y, fz4 - 1, s.c3, VoxCanvas.M_CLOTH)
	# 皮腰带 + 带扣（y 0..5）
	cv.set_mat(VoxCanvas.M_LEATHER)
	wrap_layer(cv, 0, 5, func(x: int, y: int, z: int, f: int) -> Color:
		if y == 0 or y == 5:
			return VoxCanvas.tone(s.c2, 0.7)
		return VoxCanvas.tone(s.c2, 0.92 + 0.14 * VoxCanvas.hf(x >> 1, y, z)))
	var fzb := front_z(cv, -1, 2)
	metal(cv, Vector3i(-4, 0, fzb - 1), Vector3i(3, 5, fzb - 1), s)
	cv.putm(-2, 2, fzb - 2, s.gold_dk, VoxCanvas.M_GOLD)
	cv.putm(1, 2, fzb - 2, s.gold_dk, VoxCanvas.M_GOLD)
	cv.putm(-1, 3, fzb - 2, s.gold_hi, VoxCanvas.M_GOLD)
	cv.putm(0, 3, fzb - 2, s.gold_hi, VoxCanvas.M_GOLD)
	# 胸前小绣纹
	var cp := {"c": [s.c3, VoxCanvas.M_CLOTH], "h": [s.c3.lightened(0.2), VoxCanvas.M_CLOTH]}
	stamp_back(cv, CLOUD, cp, -5, 30, 0)


## 颈部饰物（画在头网格的颈上）
static func paint_neck(cv: VoxCanvas, s: CharSpec) -> void:
	var hn := s.neck_w / 2
	match s.outfit:
		"armor":
			if s.female:
				# 金项圈：两层 + 竖纹 + 前方垂饰宝石
				cv.set_mat(VoxCanvas.M_GOLD)
				for x in range(-hn - 1, hn + 1):
					for z in range(-hn, hn + 2):
						if x == -hn - 1 or x == hn or z == -hn or z == hn + 1:
							cv.put(x, 0, z, s.gold_sh)
							cv.put(x, 1, z, s.gold if (x + z) % 2 == 0 else s.gold_hi)
							cv.put(x, 2, z, s.gold_sh)
				for x in range(-2, 2):
					cv.put(x, -1, -hn - 1, s.gold)
					cv.put(x, -2, -hn - 1, s.gold if x == -2 or x == 1 else s.gold_hi)
				HairStyles.gem_at(cv, s, -1, -1, -hn - 2, 2, s.gem)
			else:
				cv.set_mat(VoxCanvas.M_CLOTH)
				for x in range(-hn - 1, hn + 1):
					for z in range(-hn, hn + 2):
						if x == -hn - 1 or x == hn or z == -hn or z == hn + 1:
							cv.put(x, -1, z, s.c1)
							cv.put(x, 0, z, s.c1_sh)
		"robe":
			# 立领（饰边色）
			cv.set_mat(VoxCanvas.M_SILK)
			for x in range(-hn - 1, hn + 1):
				for z in range(-hn, hn + 2):
					if (x == -hn - 1 or x == hn or z == hn + 1) and z > -hn:
						cv.put(x, -1, z, s.c3)
						cv.put(x, 0, z, VoxCanvas.tone(s.c3, 0.85))


# ================================================================ 骨盆（hips）

static func pelvis(s: CharSpec) -> VoxCanvas:
	var zl := lo_of(s.torso_d)
	var zh := hi_of(s.torso_d)
	var hw := s.hip_w / 2
	var cv := VoxCanvas.new(Vector3i(-hw - 9, -20, zl - 9), Vector3i(hw + 8, 11, zh + 9))
	cv.shift = Vector3(0, 0, half_shift(s.torso_d))
	var under := s.c2
	if s.outfit == "armor" and s.female:
		under = s.c1
	cv.set_mat(VoxCanvas.M_CLOTH)
	for y in range(-8, 8):
		var w := hw
		if y > 3:
			w = hw - (y - 3) / 2
		for z in range(zl, zh + 1):
			for x in range(-w, w):
				if (x == -w or x == w - 1) and (z == zl or z == zh):
					continue
				cv.put(x, y, z, fold(under, x + z, 3))
	if s.female:
		cv.set_mat(VoxCanvas.M_SKIN)
		for y in range(5, 8):
			var w2 := hw - (y - 3) / 2 - 1
			cv.box(Vector3i(-w2, y, zl), Vector3i(w2 - 1, y, zh), s.skin)
	match s.outfit:
		"robe":
			cv.set_mat(VoxCanvas.M_SILK)
			wrap_layer(cv, -12, 7, func(x: int, y: int, z: int, f: int) -> Color: return fold(s.c1, x - z, 3))
			# 腰带下缘延续
			wrap_layer(cv, 5, 7, func(x: int, y: int, z: int, f: int) -> Color: return VoxCanvas.tone(s.c2, 0.95), F_ALL)
		"martial":
			cv.set_mat(VoxCanvas.M_CLOTH)
			wrap_layer(cv, -6, 7, func(x: int, y: int, z: int, f: int) -> Color: return fold(s.c1, x + z, 4))
			recolor_row(cv, -6, VoxCanvas.M_CLOTH, s.c3, VoxCanvas.M_CLOTH)
			recolor_row(cv, -5, VoxCanvas.M_CLOTH, VoxCanvas.tone(s.c3, 0.8), VoxCanvas.M_CLOTH)
		_:
			_pelvis_armor(cv, s, zl, zh, hw)
	return cv


static func _pelvis_armor(cv: VoxCanvas, s: CharSpec, zl: int, zh: int, hw: int) -> void:
	# 短裙（主色，横向两层褶）
	cv.set_mat(VoxCanvas.M_CLOTH)
	wrap_layer(cv, -10, 1, func(x: int, y: int, z: int, f: int) -> Color:
		return fold(s.c1, x + z, 2) if y > -10 else s.c1_sh)
	wrap_layer(cv, -8, 0, func(x: int, y: int, z: int, f: int) -> Color:
		var c := fold(s.c1, x + z + 1, 2)
		return VoxCanvas.tone(c, 1.05) if y > -3 else c)
	# 腰带：皮 + 金钉 + 上下金边（y 0..8）
	cv.set_mat(VoxCanvas.M_LEATHER)
	wrap_layer(cv, 0, 8, func(x: int, y: int, z: int, f: int) -> Color:
		return VoxCanvas.tone(s.c2, 0.86 + 0.18 * VoxCanvas.hf(x >> 1, y >> 1, z >> 1)))
	recolor_row(cv, 8, VoxCanvas.M_LEATHER, s.gold_hi, VoxCanvas.M_GOLD)
	recolor_row(cv, 7, VoxCanvas.M_LEATHER, s.gold, VoxCanvas.M_GOLD)
	recolor_row(cv, 1, VoxCanvas.M_LEATHER, s.gold, VoxCanvas.M_GOLD)
	recolor_row(cv, 0, VoxCanvas.M_LEATHER, s.gold_sh, VoxCanvas.M_GOLD)
	rivets_front(cv, s, 4, -hw - 1, hw, 4)
	# 兽首带扣（大金饰，前凸 2 层）+ 宝石眼
	var gp := gold_pal(s)
	var fz := front_z(cv, -1, 4)
	metal(cv, Vector3i(-7, -1, fz - 1), Vector3i(6, 9, fz - 1), s)
	stamp_front(cv, BEAST, gp, -6, 9, 1)
	# 带扣下垂的小金牌
	cv.set_mat(VoxCanvas.M_GOLD)
	for y in range(-4, -1):
		for x in range(-2, 2):
			cv.put(x, y, fz - 2, s.gold if y > -4 else s.gold_sh)
	cv.put(-1, -3, fz - 3, s.gold_hi)
	cv.put(0, -3, fz - 3, s.gold_hi)
	# 背后皮带扣环
	var bz := back_z(cv, -1, 4)
	metal(cv, Vector3i(-3, 1, bz + 1), Vector3i(2, 7, bz + 1), s)


# ================================================================ 手臂

static func upper_arm(s: CharSpec, side: int) -> VoxCanvas:
	var xl := lo_of(s.arm_w)
	var xh := hi_of(s.arm_w)
	var zl := lo_of(s.arm_d)
	var zh := hi_of(s.arm_d)
	var cv := VoxCanvas.new(Vector3i(xl - 10, -28, zl - 7), Vector3i(xh + 10, 11, zh + 7))
	cv.shift = Vector3(half_shift(s.arm_w), 0, half_shift(s.arm_d))
	cv.set_mat(VoxCanvas.M_SKIN)
	cv.rbox(Vector3i(xl, -24, zl), Vector3i(xh, 3, zh), s.skin, 2)
	# 三角肌略鼓
	cv.rbox(Vector3i(xl - (1 if side < 0 else 0), -6, zl), Vector3i(xh + (1 if side > 0 else 0), 1, zh), s.skin, 2)
	var inx := xl if side > 0 else xh   # 内侧（贴身）
	for y in range(-22, 2):
		for z in range(zl + 1, zh):
			cv.put(inx, y, z, s.skin.lerp(s.skin_sh, 0.25))
	match s.outfit:
		"robe":
			# 宽袖：两层（外层向下外扩），袖面竖褶
			cv.set_mat(VoxCanvas.M_SILK)
			wrap_layer(cv, -24, 3, func(x: int, y: int, z: int, f: int) -> Color: return fold(s.c1, z + x, 3))
			wrap_layer(cv, -24, 1, func(x: int, y: int, z: int, f: int) -> Color: return fold(s.c1, z + x + 1, 3) if y < -8 else VoxCanvas.tone(s.c1, 1.03))
		"martial":
			var y0 := -24 if not s.female else -12
			cv.set_mat(VoxCanvas.M_CLOTH)
			wrap_layer(cv, y0, 3, func(x: int, y: int, z: int, f: int) -> Color: return fold(s.c1, z, 4))
			recolor_row(cv, y0, VoxCanvas.M_CLOTH, s.c3, VoxCanvas.M_CLOTH)
			recolor_row(cv, y0 + 1, VoxCanvas.M_CLOTH, VoxCanvas.tone(s.c3, 0.8), VoxCanvas.M_CLOTH)
		_:
			if not s.female:
				cv.set_mat(VoxCanvas.M_CLOTH)
				wrap_layer(cv, -24, 3, func(x: int, y: int, z: int, f: int) -> Color: return fold(s.c1, z, 2))
			else:
				# 金臂环（两道 + 宝石）
				cv.set_mat(VoxCanvas.M_GOLD)
				wrap_layer(cv, -18, -15, func(x: int, y: int, z: int, f: int) -> Color:
					return s.gold_hi if y == -15 else (s.gold_sh if y == -18 else s.gold))
				var ox := xh + 2 if side > 0 else xl - 2
				gem(cv, ox, -16, 0, s, 1)
			_pauldron(cv, s, side, xl, xh, zl, zh)
	return cv


## 肩甲：三层叠片（皮革 + 金边），外侧逐层下移外扩；顶层外侧金框 + 刻面宝石 + 卷草纹
static func _pauldron(cv: VoxCanvas, s: CharSpec, side: int, xl: int, xh: int, zl: int, zh: int) -> void:
	var lc := s.c2
	var big := 0 if s.female else 2
	for layer in 3:
		var y1 := 7 - layer * 5
		var y0 := y1 - 4
		var ext := 2 + layer * 2 + big
		var xa: int
		var xb: int
		if side > 0:
			xa = xl + layer * 3 - 2
			xb = xh + ext
		else:
			xa = xl - ext
			xb = xh - layer * 3 + 2
		for y in range(y0, y1 + 1):
			for z in range(zl - 2 - big / 2, zh + 3 + big / 2):
				for x in range(xa, xb + 1):
					# 圆角：外缘上角削去
					var outer := x == (xb if side > 0 else xa)
					if outer and y == y1 and (z == zl - 2 - big / 2 or z == zh + 2 + big / 2):
						continue
					var c := VoxCanvas.tone(lc, 0.88 + 0.16 * VoxCanvas.hf(x >> 1, y >> 1, z >> 1))
					var m := VoxCanvas.M_LEATHER
					if y == y0:
						c = s.gold_sh
						m = VoxCanvas.M_GOLD
					elif y == y0 + 1:
						c = s.gold
						m = VoxCanvas.M_GOLD
					elif y == y1 and layer == 0:
						c = s.gold_hi if (x + z) % 4 != 0 else s.gold
						m = VoxCanvas.M_GOLD
					cv.putm(x, y, z, c, m)
		# 顶层：外侧金框 + 宝石
		if layer == 0:
			var ox := xb if side > 0 else xa
			var zc := (zl + zh) / 2
			for y in range(y0, y1 + 1):
				for z in [zl - 2 - big / 2, zh + 2 + big / 2]:
					cv.putm(ox, y, z, s.gold, VoxCanvas.M_GOLD)
			# 外侧面：金框菱形 + 宝石
			for p in [[0, 2], [-1, 1], [1, 1], [-2, 0], [2, 0], [-1, -1], [1, -1], [0, -2]]:
				cv.putm(ox + side, y0 + 2 + int(p[1]), zc + int(p[0]), s.gold if p[1] >= 0 else s.gold_sh, VoxCanvas.M_GOLD)
			cv.putm(ox + side, y0 + 2, zc, VoxCanvas.glow(s.gem, 0.35), VoxCanvas.M_GEM)
			cv.putm(ox + side * 2, y0 + 2, zc, VoxCanvas.glow(s.gem_hi, 0.4), VoxCanvas.M_GEM)
			cv.putm(ox + side, y0 + 3, zc, s.gem, VoxCanvas.M_GEM)
			cv.putm(ox + side, y0 + 1, zc, s.gem_sh, VoxCanvas.M_GEM)
		# 各层前缘铆钉
		for x in range(xa + 1, xb, 3):
			cv.putm(x, y0 + 1, zl - 3 - big / 2, s.gold_hi, VoxCanvas.M_GOLD)


static func forearm(s: CharSpec, side: int) -> VoxCanvas:
	var xl := lo_of(s.arm_w)
	var xh := hi_of(s.arm_w)
	var zl := lo_of(s.arm_d)
	var zh := hi_of(s.arm_d)
	var cv := VoxCanvas.new(Vector3i(xl - 10, -34, zl - 10), Vector3i(xh + 10, 6, zh + 12))
	cv.shift = Vector3(half_shift(s.arm_w), 0, half_shift(s.arm_d))
	cv.set_mat(VoxCanvas.M_SKIN)
	cv.rbox(Vector3i(xl, -18, zl), Vector3i(xh, 3, zh), s.skin, 2)
	# 手腕略细
	cv.clear(Vector3i(xl, -18, zl), Vector3i(xh, -15, zl))
	cv.clear(Vector3i(xl, -18, zh), Vector3i(xh, -15, zh))
	match s.outfit:
		"robe":
			_sleeve_robe(cv, s, side, xl, xh, zl, zh)
		"martial":
			_bracer(cv, s, side, xl, xh, zl, zh, false)
		_:
			_bracer(cv, s, side, xl, xh, zl, zh, true)
	return cv


## 道袍宽袖：外扩袖筒 + 下垂袖囊 + 袖口饰边（云纹点缀）+ 内衬
static func _sleeve_robe(cv: VoxCanvas, s: CharSpec, side: int, xl: int, xh: int, zl: int, zh: int) -> void:
	cv.set_mat(VoxCanvas.M_SILK)
	for y in range(-20, 4):
		var o := 3 if y > -8 else 5
		var zb := zh + o + (5 if y < -12 else (2 if y < -6 else 0))
		for z in range(zl - o, zb + 1):
			for x in range(xl - o, xh + o + 1):
				var edge := x == xl - o or x == xh + o or z == zl - o or z == zb or y == 3
				if not edge:
					continue
				# 圆角
				if (x == xl - o or x == xh + o) and (z == zl - o or z == zb):
					continue
				var c := fold(s.c1, z + x, 3)
				var m := VoxCanvas.M_SILK
				if y <= -18:
					# 袖口饰边：下缘深、中间饰边色、上缘一道细金点
					c = VoxCanvas.tone(s.c3, 0.72) if y == -20 else (s.c3 if y == -19 else s.c1_sh)
					if y == -18 and posmod(x + z, 4) == 0:
						c = s.gold
						m = VoxCanvas.M_GOLD
				cv.putm(x, y, z, c, m)
	# 袖囊（后侧下垂）
	for y in range(-30, -20):
		for z in range(zh, zh + 11):
			for x in range(xl - 5, xh + 6):
				var edge2 := x == xl - 5 or x == xh + 5 or z == zh + 10 or y == -30
				if not edge2:
					continue
				if y > -24 and z < zh + 4:
					continue
				var c2 := s.c3 if y == -30 else fold(s.c1, z + x, 3)
				cv.putm(x, y, z, c2, VoxCanvas.M_SILK)
	# 袖口内衬（暗）
	for z in range(zl - 4, zh + 5):
		for x in range(xl - 4, xh + 5):
			if cv.get_raw(x, -20, z) == 0 and not (x >= xl and x <= xh and z >= zl and z <= zh):
				cv.putm(x, -19, z, s.c2.darkened(0.45), VoxCanvas.M_CLOTH)


## 护腕：皮革 + 金/饰边带 + 外侧金护板（刻面宝石）或缠布斜纹
static func _bracer(cv: VoxCanvas, s: CharSpec, side: int, xl: int, xh: int, zl: int, zh: int, armor: bool) -> void:
	var lc := s.c2
	cv.set_mat(VoxCanvas.M_LEATHER)
	wrap_layer(cv, -17, -1, func(x: int, y: int, z: int, f: int) -> Color:
		if armor:
			return VoxCanvas.tone(lc, 0.86 + 0.16 * VoxCanvas.hf(x >> 1, y >> 1, z >> 1))
		# 缠布：斜向布条
		var d := posmod(y * 2 + (x - z), 8)
		var wrapc := Color(0.9, 0.87, 0.8).lerp(s.c3, 0.2)
		return wrapc if d > 1 else wrapc.darkened(0.2 if d == 0 else 0.1))
	if armor:
		for y in [-1, -2, -16, -17]:
			recolor_row(cv, y, VoxCanvas.M_LEATHER, s.gold if (y == -2 or y == -16) else s.gold_sh, VoxCanvas.M_GOLD)
		recolor_row(cv, -1, VoxCanvas.M_GOLD, s.gold_hi, VoxCanvas.M_GOLD)
		# 外侧金护板：金框 + 暗皮面 + 卷草 + 宝石
		var ox := (xh + 2) if side > 0 else (xl - 2)
		for y in range(-14, -3):
			for z in range(zl, zh + 1):
				var edge := y == -14 or y == -4 or z == zl or z == zh
				var c := s.gold if edge else VoxCanvas.tone(lc, 0.72 + 0.06 * float((y + z) & 1))
				cv.putm(ox, y, z, c, VoxCanvas.M_GOLD if edge else VoxCanvas.M_LEATHER)
		var zc := (zl + zh) / 2
		for p in [[-3, -6], [-3, -7], [-2, -8], [2, -6], [2, -7], [1, -8], [-2, -11], [1, -11], [-3, -12], [2, -12]]:
			cv.putm(ox, int(p[1]), zc + int(p[0]), s.gold_sh, VoxCanvas.M_GOLD)
		HairStyles.gem_at(cv, s, ox + side, -8, zc - 1, 2, s.gem)
		if side < 0:
			pass
	else:
		for y in [-1, -17]:
			recolor_row(cv, y, VoxCanvas.M_LEATHER, VoxCanvas.tone(s.c3, 0.8), VoxCanvas.M_CLOTH)


static func hand(s: CharSpec, side: int) -> VoxCanvas:
	var w := s.hand_w
	var xl := lo_of(w)
	var xh := hi_of(w)
	var cv := VoxCanvas.new(Vector3i(xl - 3, -9, xl - 3), Vector3i(xh + 3, 7, xh + 3))
	cv.shift = Vector3(half_shift(w), 0, half_shift(w))
	cv.set_mat(VoxCanvas.M_SKIN)
	cv.rbox(Vector3i(xl, -6, xl), Vector3i(xh, 5, xh), s.skin, 1)
	var sh := s.skin.lerp(s.skin_sh, 0.55)
	var dk := s.skin.lerp(s.skin_dk, 0.5)
	# 握拳：掌心一侧（朝身体）的指缝（四指沿 Z 排列）、指节（下缘外侧亮）
	var inx := xl if side > 0 else xh
	var outx := xh if side > 0 else xl
	for z in range(xl, xh + 1):
		for y in range(-6, 1):
			var fz := posmod(z - xl, 3)
			if fz == 0:
				cv.put(inx, y, z, dk)
			elif y == -6:
				cv.put(inx, y, z, sh)
	for z in range(xl, xh + 1):
		cv.put(outx, -6, z, s.skin_hi if posmod(z - xl, 3) == 1 else sh)
		cv.put(outx, -5, z, s.skin_hi if posmod(z - xl, 3) == 1 else s.skin)
	# 拇指：前方包住握把
	cv.box(Vector3i(xl + 2, -3, xl - 2), Vector3i(xh - 2, 2, xl - 1), s.skin)
	cv.put(xl + 2, -1, xl - 2, sh)
	cv.put(xh - 2, 2, xl - 2, s.skin_hi)
	# 指甲（拇指尖）
	cv.put(xl + 3, -3, xl - 2, s.skin.lerp(Color(1, 0.85, 0.85), 0.4))
	if s.outfit == "armor":
		# 露指手套：手背皮革 + 金边
		cv.set_mat(VoxCanvas.M_LEATHER)
		for y in range(0, 6):
			for z in range(xl, xh + 1):
				cv.put(outx, y, z, VoxCanvas.tone(s.c2, 0.9 + 0.08 * float((y + z) & 1)))
		for z in range(xl, xh + 1):
			for x in range(xl, xh + 1):
				cv.put(x, 5, z, VoxCanvas.tone(s.c2, 0.95))
				if x == xl or x == xh or z == xl or z == xh:
					cv.putm(x, 4, z, s.gold, VoxCanvas.M_GOLD)
	return cv


# ================================================================ 腿

static func thigh(s: CharSpec, side: int) -> VoxCanvas:
	# 大腿：y -30..3（顶部伸入骨盆以遮住髋关节）
	var xl := lo_of(s.leg_w)
	var xh := hi_of(s.leg_w)
	var zl := lo_of(s.leg_d)
	var zh := hi_of(s.leg_d)
	var cv := VoxCanvas.new(Vector3i(xl - 6, -34, zl - 6), Vector3i(xh + 6, 8, zh + 6))
	cv.shift = Vector3(half_shift(s.leg_w), 0, half_shift(s.leg_d))
	cv.set_mat(VoxCanvas.M_SKIN)
	# 大腿上粗下细
	for y in range(-30, 4):
		var shrink := 1 if y < -20 else 0
		var xa := xl + (shrink if side > 0 else 0)
		var xb := xh - (shrink if side < 0 else 0)
		for z in range(zl + shrink, zh - shrink + 1):
			for x in range(xa, xb + 1):
				if (x == xa or x == xb) and (z == zl + shrink or z == zh - shrink):
					continue
				cv.put(x, y, z, s.skin)
	match s.outfit:
		"robe":
			cv.set_mat(VoxCanvas.M_CLOTH)
			for y in range(-30, 4):
				for z in range(zl - 1, zh + 2):
					for x in range(xl - 1, xh + 2):
						if cv.solid(x, y, z) or x == xl - 1 or x == xh + 1 or z == zl - 1 or z == zh + 1:
							cv.put(x, y, z, fold(s.c2, x + z, 3))
		"martial":
			cv.set_mat(VoxCanvas.M_CLOTH)
			wrap_layer(cv, -30, 3, func(x: int, y: int, z: int, f: int) -> Color: return fold(s.c2.lerp(s.c1, 0.25), x + z, 3))
			wrap_layer(cv, -30, -12, func(x: int, y: int, z: int, f: int) -> Color: return fold(s.c2.lerp(s.c1, 0.25), x + z + 1, 3))
		_:
			if not s.female:
				cv.set_mat(VoxCanvas.M_CLOTH)
				wrap_layer(cv, -30, 3, func(x: int, y: int, z: int, f: int) -> Color: return fold(s.c2.lerp(Color(0.1, 0.08, 0.07), 0.3), x + z, 2))
			else:
				# 大腿：膝上阴影 + 内侧阴影 + 腿环（金）
				for z in range(zl, zh + 1):
					for x in range(xl, xh + 1):
						if cv.solid(x, -30, z):
							cv.put(x, -30, z, s.skin.lerp(s.skin_sh, 0.35))
						if cv.solid(x, -29, z):
							cv.put(x, -29, z, s.skin.lerp(s.skin_sh, 0.15))
				var inx := xh if side < 0 else xl
				for y in range(-28, 0):
					for z in range(zl + 1, zh):
						if cv.solid(inx, y, z):
							cv.put(inx, y, z, s.skin.lerp(s.skin_sh, 0.2))
	return cv


static func shin(s: CharSpec, side: int) -> VoxCanvas:
	# 小腿：y -30..1（膝在 0，脚底在 -30），脚向前伸出
	var xl := lo_of(s.leg_w)
	var xh := hi_of(s.leg_w)
	var zl := lo_of(s.leg_d)
	var zh := hi_of(s.leg_d)
	var cv := VoxCanvas.new(Vector3i(xl - 6, -32, zl - 14), Vector3i(xh + 6, 10, zh + 6))
	cv.shift = Vector3(half_shift(s.leg_w), 0, half_shift(s.leg_d))
	cv.set_mat(VoxCanvas.M_SKIN)
	cv.rbox(Vector3i(xl + 1, -30, zl + 1), Vector3i(xh - 1, 2, zh - 1), s.skin, 1)
	cv.rbox(Vector3i(xl + 1, -30, zl - 6), Vector3i(xh - 1, -26, zl), s.skin, 1)
	match s.outfit:
		"robe":
			_shin_robe(cv, s, xl, xh, zl, zh)
		"martial":
			_shin_martial(cv, s, xl, xh, zl, zh)
		_:
			_boot_armor(cv, s, side, xl, xh, zl, zh)
	return cv


## 战靴：宽大靴筒（横向叠层皮革 + 皮带扣）、前金框护板、金色护膝 + 刻面宝石、厚底金线、翻口
static func _boot_armor(cv: VoxCanvas, s: CharSpec, side: int, xl: int, xh: int, zl: int, zh: int) -> void:
	var lc := s.c2
	var dark := VoxCanvas.tone(lc, 0.62)
	# 内侧（靠近另一条腿）不外扩，避免两靴相撞
	var ix0 := xl - (2 if side < 0 else 0)
	var ix1 := xh + (2 if side > 0 else 0)
	cv.set_mat(VoxCanvas.M_LEATHER)
	# 靴筒：膝下到踝；每 6 行一道叠层暗线，叠层下缘略外凸
	for y in range(-24, 0):
		var ph := posmod(y, 6)
		var ext := 1 if ph == 1 else 0
		for z in range(zl - 1 - ext, zh + 2 + ext):
			for x in range(ix0 - ext, ix1 + 1 + ext):
				if (x == ix0 - ext or x == ix1 + ext) and (z == zl - 1 - ext or z == zh + 1 + ext):
					continue
				var c := VoxCanvas.tone(lc, 0.9 + 0.16 * VoxCanvas.hf(x >> 1, y >> 1, z >> 1))
				if ph == 0:
					c = dark
				elif ph == 1:
					c = VoxCanvas.tone(lc, 1.12)
				cv.put(x, y, z, c)
	# 外侧皮带扣（两道）
	var ex := ix1 + 2 if side > 0 else ix0 - 2
	for yb in [-8, -17]:
		for z in range(zl, zh + 1):
			cv.putm(ex, yb, z, VoxCanvas.tone(lc, 0.7), VoxCanvas.M_LEATHER)
			cv.putm(ex, yb + 1, z, VoxCanvas.tone(lc, 0.8), VoxCanvas.M_LEATHER)
		metal(cv, Vector3i(ex + side, yb - 1, -2), Vector3i(ex + side, yb + 2, 1), s)
		cv.putm(ex + side, yb, -1, s.gold_dk, VoxCanvas.M_GOLD)
		cv.putm(ex + side, yb + 1, 0, s.gold_dk, VoxCanvas.M_GOLD)
	# 靴口外翻（y -1..1）：皮 + 金边
	for y in range(-1, 2):
		for z in range(zl - 3, zh + 4):
			for x in range(ix0 - 2, ix1 + 3):
				var edge := x == ix0 - 2 or x == ix1 + 2 or z == zl - 3 or z == zh + 3
				if not edge:
					continue
				cv.putm(x, y, z, s.gold if y == -1 else (s.gold_hi if y == 1 else VoxCanvas.tone(lc, 0.95)), VoxCanvas.M_GOLD if y != 0 else VoxCanvas.M_LEATHER)
	# 靴头与厚底：y -30..-24，向前 8
	for y in range(-30, -23):
		for z in range(zl - 9, zh + 2):
			for x in range(ix0, ix1 + 1):
				# 靴尖圆头
				if z < zl - 7 and (x == ix0 or x == ix1):
					continue
				if z == zl - 9 and y > -27:
					continue
				var c2 := VoxCanvas.tone(lc, 0.92 + 0.14 * VoxCanvas.hf(x >> 1, y >> 1, z >> 1))
				var m := VoxCanvas.M_LEATHER
				if y <= -29:
					c2 = VoxCanvas.tone(lc, 0.45)
				elif y == -28:
					c2 = s.gold
					m = VoxCanvas.M_GOLD
				cv.putm(x, y, z, c2, m)
	# 踝部金带
	cv.set_mat(VoxCanvas.M_GOLD)
	for z in range(zl - 1, zh + 2):
		for x in range(ix0, ix1 + 1):
			cv.put(x, -24, z, s.gold)
			cv.put(x, -25, z, s.gold_sh)
	for x in range(ix0, ix1 + 1):
		var fz := front_z(cv, x, -24)
		cv.put(x, -24, fz, s.gold_hi)
	# 前护板：细金框 + 深色皮面 + 卷草纹
	var fz2 := zl - 3
	for y in range(-22, -3):
		for x in range(xl + 1, xh):
			var edge := x == xl + 1 or x == xh - 1 or y == -22
			var c := s.gold if edge else VoxCanvas.tone(lc, 0.7 + 0.06 * float((x + y) & 1))
			cv.putm(x, y, fz2, c, VoxCanvas.M_GOLD if edge else VoxCanvas.M_LEATHER)
	var gp := gold_pal(s)
	stamp_front(cv, SCROLL, gp, -3 + (0 if side > 0 else 0), -8, 0)
	# 护膝：金板（上凸）+ 宝石 + 两侧翼
	var cx := -1
	metal(cv, Vector3i(xl, -4, fz2 - 2), Vector3i(xh, 4, fz2), s)
	for x in range(xl + 1, xh):
		cv.putm(x, 5, fz2, s.gold_hi, VoxCanvas.M_GOLD)
	HairStyles.gem_at(cv, s, cx, 1, fz2 - 3, 2, s.gem)
	for x in [xl, xh]:
		cv.putm(x, 0, fz2 - 3, s.gold_sh, VoxCanvas.M_GOLD)


static func _shin_robe(cv: VoxCanvas, s: CharSpec, xl: int, xh: int, zl: int, zh: int) -> void:
	cv.set_mat(VoxCanvas.M_CLOTH)
	for y in range(-24, 3):
		for z in range(zl, zh + 1):
			for x in range(xl, xh + 1):
				if (x == xl or x == xh) and (z == zl or z == zh):
					continue
				cv.put(x, y, z, fold(s.c2, x + z, 3))
	# 布鞋：鞋面（暗）+ 白底 + 云头鞋尖（饰边色）
	var shoe := s.c2.darkened(0.55)
	for y in range(-30, -23):
		for z in range(zl - 6, zh + 1):
			for x in range(xl + 1, xh):
				if z < zl - 4 and (x == xl + 1 or x == xh - 1):
					continue
				cv.put(x, y, z, shoe if y > -30 else Color(0.92, 0.9, 0.86))
	cv.set_mat(VoxCanvas.M_SILK)
	for x in range(xl + 2, xh - 1):
		cv.put(x, -26, zl - 8, s.c3)
		cv.put(x, -25, zl - 8, s.c3)
		cv.put(x, -24, zl - 7, s.c3)
		cv.put(x, -23, zl - 6, VoxCanvas.tone(s.c3, 0.85))
	cv.put(-1, -24, zl - 8, s.c3.lightened(0.2))
	cv.put(0, -24, zl - 8, s.c3.lightened(0.2))
	for x in range(xl + 1, xh):
		cv.put(x, -24, zl, VoxCanvas.tone(s.c3, 0.8))


static func _shin_martial(cv: VoxCanvas, s: CharSpec, xl: int, xh: int, zl: int, zh: int) -> void:
	var trouser := s.c2.lerp(s.c1, 0.25)
	cv.set_mat(VoxCanvas.M_CLOTH)
	for y in range(-6, 3):
		for z in range(zl - 1, zh + 2):
			for x in range(xl - 1, xh + 2):
				if (x == xl - 1 or x == xh + 1) and (z == zl - 1 or z == zh + 1):
					continue
				cv.put(x, y, z, fold(trouser, x + z, 3))
	# 绑腿：浅色布条斜向缠绕（每 3 行一道暗缝，随绕行方向错位）
	var wrapc := Color(0.9, 0.87, 0.8).lerp(s.c3, 0.15)
	for y in range(-24, -6):
		for z in range(zl, zh + 1):
			for x in range(xl, xh + 1):
				if (x == xl or x == xh) and (z == zl or z == zh):
					continue
				var d := posmod(y * 2 + (x - z), 10)
				var c := wrapc if d > 2 else (wrapc.darkened(0.22) if d == 0 else wrapc.darkened(0.08))
				cv.put(x, y, z, c)
	# 靴
	var boot := s.c2.darkened(0.45)
	cv.set_mat(VoxCanvas.M_LEATHER)
	for y in range(-30, -23):
		for z in range(zl - 8, zh + 2):
			for x in range(xl - 1, xh + 2):
				if z < zl - 6 and (x == xl - 1 or x == xh + 1):
					continue
				if z >= zl - 1 or y <= -26:
					cv.put(x, y, z, VoxCanvas.tone(boot, 0.9 + 0.14 * VoxCanvas.hf(x >> 1, y >> 1, z >> 1)) if y > -30 else boot.darkened(0.4))
	for z in range(zl - 1, zh + 2):
		for x in range(xl - 1, xh + 2):
			if x == xl - 1 or x == xh + 1 or z == zl - 1 or z == zh + 1:
				cv.putm(x, -23, z, VoxCanvas.tone(s.c3, 0.8), VoxCanvas.M_CLOTH)
				cv.putm(x, -22, z, VoxCanvas.tone(s.c3, 0.65), VoxCanvas.M_CLOTH)


# ================================================================ 下摆 / 裙甲（弹簧）

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


static func _p(key: String, maker: Callable) -> Array:
	return CharacterBuilder.part(key, maker)


static func _armor_panels(hips: Node3D, s: CharSpec, key: String, zf: float, zb: float, hw: float) -> void:
	# 前中长护裆甲（皮面金框 + 菱形宝石 + 卷草）
	var tab_len := 22 if s.female else 30
	var b := _cloth_bone(hips, "cloth_front", Vector3(0, -1.0, zf - 5.0), Vector3(4, 0, 0), tab_len, 0.2, 50, "front", "both", 0.9)
	HairStyles.attach_mesh(b, _p("ctab|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-9, -tab_len - 2, -4), Vector3i(8, 2, 2))
		cv.set_mat(VoxCanvas.M_LEATHER)
		for y in range(-tab_len, 2):
			var hw2 := 7 if y > -tab_len + 3 else 7 - (-tab_len + 3 - y)
			for x in range(-hw2, hw2):
				var edge := x == -hw2 or x == hw2 - 1 or y == -tab_len or y == 1
				cv.put(x, y, 0, VoxCanvas.tone(s.c2, 0.85 + 0.16 * VoxCanvas.hf(x >> 1, y >> 1, 0)))
				cv.put(x, y, 1, VoxCanvas.tone(s.c2, 0.7))
				if edge:
					cv.putm(x, y, -1, s.gold if y > -tab_len else s.gold_sh, VoxCanvas.M_GOLD)
		# 菱形金框宝石
		var gp := gold_pal(s)
		cv.stamp(DIAMOND, _pal_arr(gp), Vector3i(-4, -tab_len + 13, -1), Vector3i(1, 0, 0), Vector3i(0, -1, 0))
		cv.stamp(SCROLL, _pal_arr(gp), Vector3i(-3, -2, -1), Vector3i(1, 0, 0), Vector3i(0, -1, 0))
		return cv))
	# 前左/前右主色裙片（金边 + 金花 + 竖褶）
	for side: int in [-1, 1]:
		var sn := "l" if side < 0 else "r"
		var pl := 16 if s.female else 22
		var bp := _cloth_bone(hips, "cloth_front_" + sn, Vector3(side * (hw - 3.0), -1.0, zf - 3.5), Vector3(3, 0, side * 7), pl, 0.2, 45, "front", "l" if side < 0 else "r", 0.85)
		HairStyles.attach_mesh(bp, _p("cfr|%s" % key, func() -> Variant:
			var cv := VoxCanvas.new(Vector3i(-8, -pl - 2, -4), Vector3i(7, 2, 2))
			cv.set_mat(VoxCanvas.M_CLOTH)
			for y in range(-pl, 1):
				for x in range(-6, 6):
					var edge := x == -6 or x == 5 or y == -pl
					var c := fold(s.c1, x, 2)
					var m := VoxCanvas.M_CLOTH
					if edge:
						c = s.gold if y > -pl else s.gold_sh
						m = VoxCanvas.M_GOLD
					elif x == -5 or x == 4 or y == -pl + 1:
						c = s.c1_sh
					cv.putm(x, y, 0, c, m)
					cv.putm(x, y, 1, VoxCanvas.tone(s.c1, 0.7), VoxCanvas.M_CLOTH)
			# 金花纹（四瓣 + 中心）
			var fy := -pl + 6
			for p in [[0, 2], [-1, 1], [0, 1], [-2, 0], [1, 0], [-1, -1], [0, -1], [0, -2], [-1, 2], [-1, -2], [-3, 0], [2, 0]]:
				cv.putm(int(p[0]), fy + int(p[1]), -1, s.gold, VoxCanvas.M_GOLD)
			cv.putm(-1, fy, -1, s.gold_hi, VoxCanvas.M_GOLD)
			cv.putm(0, fy, -1, s.gold_hi, VoxCanvas.M_GOLD)
			return cv), "Mesh", side < 0)
	# 两侧皮护腿甲（主色镶条 + 金边 + 金扣）
	for side: int in [-1, 1]:
		var sn2 := "l" if side < 0 else "r"
		var sl := 16 if s.female else 24
		var bs := _cloth_bone(hips, "cloth_side_" + sn2, Vector3(side * (hw + 5.0), -1.0, 0), Vector3(0, 0, side * 14), sl, 0.2, 40, "side", "l" if side < 0 else "r", 0.9)
		HairStyles.attach_mesh(bs, _p("csd|%s" % key, func() -> Variant:
			var cv := VoxCanvas.new(Vector3i(-3, -sl - 2, -10), Vector3i(3, 2, 9))
			cv.set_mat(VoxCanvas.M_LEATHER)
			for y in range(-sl, 1):
				for z in range(-8, 8):
					var edge := z == -8 or z == 7 or y == -sl
					var c := VoxCanvas.tone(s.c2, 0.85 + 0.16 * VoxCanvas.hf(0, y >> 1, z >> 1))
					var m := VoxCanvas.M_LEATHER
					if edge:
						c = s.gold
						m = VoxCanvas.M_GOLD
					elif z == -6 or z == 5:
						c = s.c1
						m = VoxCanvas.M_CLOTH
					cv.putm(0, y, z, c, m)
					cv.putm(-1, y, z, VoxCanvas.tone(s.c2, 0.7), VoxCanvas.M_LEATHER)
				if y == -sl + 8 or y == -sl + 9:
					for z2 in range(-2, 2):
						cv.putm(1, y, z2, s.gold if y == -sl + 9 else s.gold_sh, VoxCanvas.M_GOLD)
			cv.putm(1, -sl + 5, -1, VoxCanvas.glow(s.gem, 0.35), VoxCanvas.M_GEM)
			return cv), "Mesh", side < 0)
	# 后片
	for side: int in [-1, 1]:
		var sn3 := "l" if side < 0 else "r"
		var bl := 16 if s.female else 26
		var bb := _cloth_bone(hips, "cloth_back_" + sn3, Vector3(side * 7.0, -1.0, zb + 3.5), Vector3(-4, 0, side * 5), bl, 0.2, 45, "back", "l" if side < 0 else "r", 0.85)
		HairStyles.attach_mesh(bb, _p("cbk|%s" % key, func() -> Variant:
			var cv := VoxCanvas.new(Vector3i(-9, -bl - 2, -3), Vector3i(8, 2, 3))
			cv.set_mat(VoxCanvas.M_CLOTH)
			for y in range(-bl, 1):
				for x in range(-7, 6):
					var edge := x == -7 or x == 5 or y == -bl
					cv.putm(x, y, 0, s.gold if edge else fold(s.c1, x, 2), VoxCanvas.M_GOLD if edge else VoxCanvas.M_CLOTH)
					cv.putm(x, y, -1, VoxCanvas.tone(s.c1, 0.7), VoxCanvas.M_CLOTH)
			return cv), "Mesh", side < 0)


## 调色板 {字符: [色, 材质]} → VoxCanvas.stamp 可用的格式（同）
static func _pal_arr(p: Dictionary) -> Dictionary:
	return p


static func _robe_panels(hips: Node3D, s: CharSpec, key: String, zf: float, zb: float, hw: float) -> void:
	var length := 48
	for side: int in [-1, 1]:
		var sn := "l" if side < 0 else "r"
		var leg := "l" if side < 0 else "r"
		# 前摆（含半个侧面，包住髋部）
		var bf := _cloth_bone(hips, "cloth_robe_f" + sn, Vector3(0, -6.0, zf - 3.0), Vector3(5, 0, 0), length, 0.18, 55, "front", leg, 0.95)
		HairStyles.attach_mesh(bf, _p("crf|%s|%s" % [key, sn], func() -> Variant:
			return _robe_panel(s, side, true, length, int(hw), int(zb - zf))))
		var bb := _cloth_bone(hips, "cloth_robe_b" + sn, Vector3(0, -6.0, zb + 3.0), Vector3(-5, 0, 0), length, 0.18, 55, "back", leg, 0.9)
		HairStyles.attach_mesh(bb, _p("crb|%s|%s" % [key, sn], func() -> Variant:
			return _robe_panel(s, side, false, length, int(hw), int(zb - zf))))
	# 玉佩 + 流苏（左腰）
	var bj := _cloth_bone(hips, "cloth_pendant", Vector3(-hw + 2.0, 2.0, zf - 6.0), Vector3(0, 0, 0), 20, 0.14, 50, "front", "l", 0.6)
	HairStyles.attach_mesh(bj, _p("cpd|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-5, -28, -3), Vector3i(4, 2, 2))
		cv.set_mat(VoxCanvas.M_SILK)
		# 丝绳 + 结
		for y in range(-6, 1):
			cv.put(-1 + (y & 1), y, 0, s.c3)
		cv.box(Vector3i(-2, -8, 0), Vector3i(1, -7, 0), s.c3)
		# 玉佩（圆环玉璧）
		cv.set_mat(VoxCanvas.M_JADE)
		var jade := Color("62c49a")
		for y in range(-17, -8):
			for x in range(-5, 5):
				var d := Vector2(x + 0.5, y + 12.5).length()
				if d <= 4.4 and d >= 1.3:
					var c := jade
					if d > 3.5:
						c = jade.lightened(0.18)
					elif (x + y) % 3 == 0:
						c = jade.darkened(0.2)
					cv.put(x, y, 0, c)
		# 流苏
		cv.set_mat(VoxCanvas.M_SILK)
		cv.box(Vector3i(-1, -19, -1), Vector3i(0, -18, 0), s.gem)
		for y in range(-27, -19):
			for x in range(-2, 2):
				if (x + y) % 2 == 0 or y > -22:
					cv.put(x, y, 0, VoxCanvas.tone(s.gem, 0.85 + 0.2 * float((x + y) & 1)))
		return cv))
	# 腰带飘带（右后）
	var bs := _cloth_bone(hips, "cloth_sash", Vector3(hw + 2.0, 4.0, zf + 4.0), Vector3(0, 0, 8), 26, 0.14, 50, "side", "r", 0.5)
	HairStyles.attach_mesh(bs, _p("crs|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-3, -30, -5), Vector3i(2, 2, 4))
		cv.set_mat(VoxCanvas.M_SILK)
		for y in range(-28, 1):
			for z in range(-3, 3):
				if y < -25 and z == 0:
					continue
				var c := VoxCanvas.tone(s.c2, 0.95 - 0.2 * float(-y) / 28.0)
				if z == -3 or z == 2:
					c = s.c3
				cv.put(0, y, z, c)
		return cv))


## 道袍下摆片：front 为前片；side -1 左 / 1 右；向下逐渐外扩；饰边 + 下摆祥云
static func _robe_panel(s: CharSpec, side: int, front: bool, length: int, hw: int, depth: int) -> VoxCanvas:
	var W := hw + 6
	var D := depth / 2 + 8
	var cv := VoxCanvas.new(Vector3i(-W - 3, -length - 2, -5), Vector3i(W + 2, 3, D + 3))
	cv.set_mat(VoxCanvas.M_SILK)
	var zdir := 1 if front else -1
	var hem_h := 5
	for yi in range(-2, length):
		var y := -yi
		var flare := yi / 8
		var xa := 0 if side > 0 else -(hw + 2 + flare)
		var xb := (hw + 1 + flare) if side > 0 else -1
		if front and side > 0:
			xa = -3   # 右前片压在左前片下，稍微重叠
		var hem := yi >= length - hem_h
		var shade := 1.0 - 0.1 * float(yi) / length
		# 前/后平面（z=0，前片的 z 向内为 +z，后片为 -z）
		for x in range(xa, xb + 1):
			var c := fold(s.c1, x, 3)
			if hem:
				var hy := yi - (length - hem_h)
				c = s.c3 if hy == 1 or hy == 3 else (VoxCanvas.tone(s.c3, 0.75) if hy == 0 else VoxCanvas.tone(s.c3, 0.9))
				if hy == 4:
					c = VoxCanvas.tone(s.c3, 0.7)
				if hy == 2 and posmod(x, 4) == 0:
					c = s.gold_hi
			var open_edge := front and x == (-1 if side < 0 else -3)
			if open_edge and not hem:
				c = s.c3
			var open_edge2 := front and x == (-2 if side < 0 else -2)
			if open_edge2 and not hem:
				c = VoxCanvas.tone(s.c3, 0.8)
			cv.put(x, y, 0, VoxCanvas.tone(c, shade))
		# 侧面包边（沿 z 向身体中线延伸半个深度）
		var sx := xa if side < 0 else xb
		for k in range(1, D - 1):
			var z := k * zdir
			var c2 := fold(s.c1, k + 1, 3)
			if hem:
				c2 = s.c3 if yi == length - 1 else VoxCanvas.tone(s.c3, 0.85)
			cv.put(sx, y, z, VoxCanvas.tone(c2, (0.95 if front else 0.92) * shade))
	# 下摆上方的祥云刺绣
	var cp := {"c": [s.c3, VoxCanvas.M_SILK], "h": [s.gold_hi, VoxCanvas.M_GOLD]}
	var cx := (3 if side > 0 else -12)
	var cy := -length + hem_h + 11
	for r in CLOUD.size():
		var row: String = CLOUD[r]
		for j in row.length():
			var ch := row[j]
			if not cp.has(ch):
				continue
			var x := cx + (j if side > 0 else row.length() - 1 - j)
			var y := cy - r
			if cv.solid(x, y, 0):
				var pv: Array = cp[ch]
				cv.putm(x, y, -1 if front else 1, pv[0], int(pv[1]))
	return cv


static func _martial_panels(hips: Node3D, s: CharSpec, key: String, zf: float, zb: float, hw: float) -> void:
	for side: int in [-1, 1]:
		var sn := "l" if side < 0 else "r"
		var leg := "l" if side < 0 else "r"
		var fl := 20
		var bf := _cloth_bone(hips, "cloth_front_" + sn, Vector3(side * (hw * 0.5), -5.0, zf - 3.0), Vector3(4, 0, side * 5), fl, 0.2, 50, "front", leg, 0.9)
		HairStyles.attach_mesh(bf, _p("cmf|%s" % key, func() -> Variant:
			var cv := VoxCanvas.new(Vector3i(-10, -fl - 2, -3), Vector3i(9, 2, 2))
			cv.set_mat(VoxCanvas.M_CLOTH)
			var w := int(hw)
			for y in range(-fl, 1):
				for x in range(-w / 2 - 1, w / 2 + 1):
					var edge := y == -fl or x == -w / 2 - 1
					var c := s.c3 if edge else fold(s.c1, x, 4)
					if y == -fl + 1 and not edge:
						c = VoxCanvas.tone(s.c3, 0.8)
					cv.put(x, y, 0, c)
					cv.put(x, y, 1, VoxCanvas.tone(s.c1, 0.72))
			return cv), "Mesh", side < 0)
		var bl := 26
		var bb := _cloth_bone(hips, "cloth_back_" + sn, Vector3(side * (hw * 0.5), -5.0, zb + 3.0), Vector3(-6, 0, side * 4), bl, 0.18, 50, "back", leg, 0.9)
		HairStyles.attach_mesh(bb, _p("cmb|%s" % key, func() -> Variant:
			var cv := VoxCanvas.new(Vector3i(-12, -bl - 2, -3), Vector3i(11, 2, 2))
			cv.set_mat(VoxCanvas.M_CLOTH)
			var w := int(hw)
			for y in range(-bl, 1):
				for x in range(-w / 2 - 1, w / 2 + 1):
					var edge := y == -bl or x == w / 2
					cv.put(x, y, 0, s.c3 if edge else fold(s.c1, x, 4))
					cv.put(x, y, -1, VoxCanvas.tone(s.c1, 0.72))
			return cv), "Mesh", side < 0)
	# 腰带结的飘带（两条，末端燕尾）
	var bs := _cloth_bone(hips, "cloth_sash", Vector3(-hw - 3.0, 6.0, zf + 2.0), Vector3(0, 0, -8), 24, 0.14, 50, "side", "l", 0.5)
	HairStyles.attach_mesh(bs, _p("cms|" + key, func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-3, -28, -6), Vector3i(2, 2, 4))
		cv.set_mat(VoxCanvas.M_CLOTH)
		for y in range(-26, 1):
			for z in range(-4, 2):
				if y < -23 and (z == -2 or z == -1):
					continue
				if z == 1 and y < -12:
					continue
				var c := s.c3 if y > -22 else VoxCanvas.tone(s.c3, 0.8)
				cv.put(0, y, z, VoxCanvas.tone(c, 0.9 + 0.1 * float(z & 1)))
		# 结
		cv.box(Vector3i(-1, -1, -3), Vector3i(1, 1, 0), VoxCanvas.tone(s.c3, 0.85))
		return cv))
