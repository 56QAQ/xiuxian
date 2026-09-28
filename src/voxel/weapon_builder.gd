class_name WeaponBuilder
## 体素兵器生成（2× 精度，VOXEL = 0.0125m）。握把在原点、刃沿本地 -Z；返回节点带 meta "tip_length"（米，刃尖到握把的距离）。
##
## visual 字段（均可选）：
##   kind   sword 剑 / saber 刀 / spear 枪 / fist 拳套
##   length 刃长或枪长（旧体素单位 0.025m，与 items.json 一致；内部 ×2）；blade / guard / grip 颜色；flag 旗面颜色（仅枪，有则为旗枪）
##   glow   元素 id（metal/wood/water/fire/earth）：刃上发光符文与刃口，颜色取 Elem.color_of
##   detail 0 朴素 / 1 标准（剑穗、红缨、柄首）/ 2 精致（宝石、金饰、符文）；
##          缺省时由 grade（0~5）推导，否则有 glow 为 2、无为 1
##
## 挂接：WeaponBuilder.attach_to_rig(rig, visual) —— 自动处理拳套（左右手各一只）并设置 rig.stance。
## 拳套也可手动挂：rig.attach_to_hand(build(v, "r"), "r")；rig.attach_to_hand(build(v, "l"), "l")。
## 剑穗、枪缨、旗面挂在 WeaponSway 节点下，会随挥动与重力摆动。
## 网格按 visual 缓存（VoxMesh.part，两级 LOD）；绘制在工作线程中进行，表格用 static var。

const VOXEL := 0.0125
const OLD := 2   ## 旧单位（0.025m）→ 本模块体素

## 旗面字形（13×13）
static var GLYPHS: Dictionary = {
	"fire": ["......#......", "..#...#...#..", "..#...#...#..", ".#....#....#.", ".#....#....#.", "......#......", ".....#.#.....",
		".....#.#.....", "....#...#....", "...#.....#...", "..#.......#..", ".#.........#.", "#...........#"],
	"metal": ["......#......", ".....#.#.....", "....#...#....", "...#.....#...", "..#########..", "......#......", "..#########..",
		"......#......", ".#...#.#...#.", "..#..#.#..#..", "...#.#.#.#...", "......#......", "#############"],
	"wood": ["......#......", "......#......", "#############", "......#......", ".....###.....", "....#.#.#....", "...#..#..#...",
		"..#...#...#..", ".#....#....#.", "#.....#.....#", "......#......", "......#......", "......#......"],
	"water": ["......#......", "......#......", "......#...#..", "####..#..#...", "...#..#.#....", "...#..##.....", "..#...#.#....",
		"..#...#..#...", ".#....#...#..", "#.....#....#.", "......#.....#", "....#.#......", ".....##......"],
	"earth": [".............", "......#......", "......#......", "......#......", "......#......", ".###########.", "......#......",
		"......#......", "......#......", "......#......", "......#......", "#############", "............."],
	"none": ["......#......", ".....#.#.....", "....#...#....", "...#.###.#...", "..#.#...#.#..", ".#.#..#..#.#.", "#.#..#.#..#.#",
		".#.#..#..#.#.", "..#.#...#.#..", "...#.###.#...", "....#...#....", ".....#.#.....", "......#......"],
}


static func detail_of(visual: Dictionary) -> int:
	if visual.has("detail"):
		return clampi(int(visual["detail"]), 0, 2)
	if visual.has("grade"):
		var g := int(visual["grade"])
		return 0 if g <= 0 else (1 if g <= 2 else 2)
	return 2 if str(visual.get("glow", "")) != "" else 1


static func glow_color(visual: Dictionary) -> Color:
	var g := str(visual.get("glow", ""))
	if g == "" or g == "none":
		return Color(0, 0, 0, 0)
	return Elem.color_of(g)


## 生成兵器。hand 仅对拳套有意义："r" 右手 / "l" 左手（镜像）
static func build(visual: Dictionary, hand: String = "r") -> Node3D:
	var kind := str(visual.get("kind", "sword"))
	var root := Node3D.new()
	root.name = "Weapon"
	root.set_meta("kind", kind)
	# 在主线程中先算好所有需要的颜色（绘制在工作线程中进行）
	var v := visual.duplicate(true)
	v["_gc"] = glow_color(visual)
	v["_det"] = detail_of(visual)
	var key := "wpn|%s|" % kind + str(visual)
	match kind:
		"fist":
			_build_fist(root, v, hand, key)
		"spear":
			_build_spear(root, v, key)
		"saber":
			_build_saber(root, v, key)
		_:
			_build_sword(root, v, key)
	return root


## 把兵器挂到角色手上并设置持械姿势（拳套挂两只手）
static func attach_to_rig(rig: CharacterRig, visual: Dictionary, _in_build: bool = false) -> void:
	var kind := str(visual.get("kind", "fist"))
	# 立即摘下旧挂件（attach_to_hand 用 queue_free，本帧内 weapon_tip() 仍会找到旧兵器）
	for h in ["l", "r"]:
		var hand := rig.bone("hand_" + h)
		if hand == null:
			continue
		for c in hand.get_children():
			if c.has_meta("attachment"):
				hand.remove_child(c)
				c.queue_free()
	if kind == "fist":
		rig.attach_to_hand(build(visual, "r"), "r")
		rig.attach_to_hand(build(visual, "l"), "l")
	else:
		rig.attach_to_hand(build(visual), "r")
	rig.stance = kind


static func _add(parent: Node3D, key: String, maker: Callable, mesh_name: String = "Mesh", mirror: bool = false) -> MeshInstance3D:
	return VoxMesh.attach(parent, VoxMesh.part(key, maker, VOXEL), mesh_name, mirror, CharacterBuilder._lod)


static func _cols(visual: Dictionary, blade_def: String, guard_def: String, grip_def: String) -> Array[Color]:
	return [
		CharacterBuilder.col(visual.get("blade", blade_def), Color(blade_def)),
		CharacterBuilder.col(visual.get("guard", guard_def), Color(guard_def)),
		CharacterBuilder.col(visual.get("grip", grip_def), Color(grip_def)),
	]


## 缠柄：交错菱纹（4×4 截面，四角削圆）
static func _grip(cv: VoxCanvas, z0: int, z1: int, grip: Color, r: int = 2) -> void:
	cv.set_mat(VoxCanvas.M_LEATHER)
	var dark := VoxCanvas.tone(grip, 0.62)
	var lite := VoxCanvas.tone(grip, 1.22)
	for z in range(z0, z1 + 1):
		for y in range(-r, r):
			for x in range(-r, r):
				if (x == -r or x == r - 1) and (y == -r or y == r - 1):
					continue
				var k := posmod(z + (x + y) * 2, 4)
				cv.put(x, y, z, lite if k == 0 else (dark if k == 2 else grip))


## 金色系：高光/暗部
static func _gold3(c: Color) -> Array[Color]:
	return [c, c.lerp(Color(1, 0.97, 0.85), 0.5), Color(c.r * 0.6, c.g * 0.5, c.b * 0.4)]


static func _gem(cv: VoxCanvas, x: int, y: int, z: int, c: Color) -> void:
	cv.putm(x, y, z, VoxCanvas.glow(c, 0.45), VoxCanvas.M_GEM)


# ================================================================ 剑

static func _build_sword(root: Node3D, v: Dictionary, key: String) -> void:
	var c := _cols(v, "#d8dde6", "#c89a30", "#4a2a1a")
	var blade := c[0]
	var guard := c[1]
	var grip := c[2]
	var det: int = v["_det"]
	var gc: Color = v["_gc"]
	var length := int(v.get("length", 36)) * OLD
	var tip_z := -length - 12
	_add(root, key + "|body", func() -> Variant:
		var g3 := _gold3(guard)
		var ghi := g3[1]
		var gsh := g3[2]
		var cv := VoxCanvas.new(Vector3i(-5, -12, tip_z - 2), Vector3i(4, 11, 16))
		# 柄首：云头 + 宝石（精致）
		cv.set_mat(VoxCanvas.M_GOLD)
		cv.box(Vector3i(-2, -2, 7), Vector3i(1, 1, 10), guard)
		if det >= 1:
			cv.rbox(Vector3i(-3, -4, 9), Vector3i(2, 3, 11), guard, 1)
			cv.box(Vector3i(-2, -3, 12), Vector3i(1, 2, 12), ghi)
			cv.box(Vector3i(-1, -1, 13), Vector3i(0, 0, 13), ghi)
			for y in [-4, 3]:
				cv.put(-3, y, 10, gsh)
				cv.put(2, y, 10, gsh)
			if det >= 2:
				_gem(cv, -3, -1, 10, gc if gc.a > 0 else Color("e8283a"))
				_gem(cv, 2, 0, 10, gc if gc.a > 0 else Color("e8283a"))
		_grip(cv, -6, 6, grip)
		# 柄箍
		cv.set_mat(VoxCanvas.M_GOLD)
		for z in [-7, 7]:
			for y in range(-2, 2):
				for x in range(-2, 2):
					cv.put(x, y, z, ghi if y == 1 else guard)
		# 护手：沿刃宽方向（Y）展开的剑格，两端云头上翘
		var gw := 6 if det == 0 else (8 if det == 1 else 10)
		for y in range(-gw, gw):
			var ay := absf(y + 0.5)
			var th := 2 if ay < gw - 2 else 1
			for z in range(-10, -7):
				for x in range(-3, 3):
					if absi(x * 2 + 1) > th * 2 + 1:
						continue
					var cc := guard
					if z == -10:
						cc = ghi
					elif z == -8:
						cc = gsh
					cv.put(x, y, z, cc)
			# 端头云卷（向刃方向卷起）
			if ay > gw - 2:
				for x in range(-2, 2):
					cv.put(x, y, -11, ghi)
					cv.put(x, y, -12, guard)
		# 剑格中央：兽面凸饰 + 宝石
		cv.box(Vector3i(-4, -3, -10), Vector3i(3, 2, -8), guard)
		cv.box(Vector3i(-4, -3, -10), Vector3i(3, -3, -8), gsh)
		if det >= 2:
			var gemc := gc if gc.a > 0 else Color("e8283a")
			_gem(cv, -4, -1, -9, gemc)
			_gem(cv, -4, 0, -9, gemc.lightened(0.3))
			_gem(cv, 3, -1, -9, gemc)
			_gem(cv, 3, 0, -9, gemc.lightened(0.3))
			# 吞口金舌
			cv.box(Vector3i(-2, -3, -14), Vector3i(1, 2, -11), guard)
			cv.box(Vector3i(-1, -2, -15), Vector3i(0, 1, -15), ghi)
		# 剑身：宽 8（沿 Y），脊厚 3；中脊高光 + 血槽；刃口亮；末 12 格收成剑尖
		cv.set_mat(VoxCanvas.M_STEEL)
		var ridge := blade.lerp(Color(1, 1, 1), 0.5)
		var edge := blade.lerp(Color(1, 1, 1), 0.3)
		var flat := VoxCanvas.tone(blade, 0.9)
		var groove := VoxCanvas.tone(blade, 0.62)
		var z_start := -11 if det < 2 else -15
		for z in range(tip_z, z_start + 1):
			var from_tip := z - tip_z
			var half := 4
			if from_tip < 12:
				half = int(ceil(4.0 * float(from_tip + 1) / 12.0))
			# 剑身中段微收（腰）
			for y in range(-half, half):
				var ay := absf(y + 0.5)
				var col := flat
				var th := 1
				if ay < 1.0:
					col = ridge
					th = 2
				elif ay < 2.0:
					col = groove if from_tip > 16 and z < z_start - 4 else blade
					th = 2 if from_tip > 16 else 1
				if ay > half - 1.0:
					col = edge
					th = 0
				cv.put(0, y, z, col)
				if th >= 1:
					cv.put(-1, y, z, VoxCanvas.tone(col, 0.9))
				if th >= 2:
					cv.put(1, y, z, VoxCanvas.tone(col, 0.82))
			if half <= 0:
				cv.put(0, 0, z, ridge)
		# 发光符文（血槽中）与刃口
		if gc.a > 0:
			var g := VoxCanvas.glow(gc.lightened(0.25), 0.95)
			var g2 := VoxCanvas.glow(gc, 0.7)
			cv.set_mat(VoxCanvas.M_FLAME)
			for z in range(tip_z + 16, z_start - 5):
				var ph := posmod(z, 10)
				if ph < 5:
					# 符文：交替的短画（像篆字笔画）
					var yy := -1 if (ph == 0 or ph == 4) else (-2 if ph == 2 else -1)
					cv.put(0, yy, z, g if ph != 2 else g2)
					cv.put(0, yy + 2, z, g2 if ph == 1 or ph == 3 else g)
			for z in range(tip_z, tip_z + 6):
				cv.put(0, 0, z, VoxCanvas.glow(gc.lightened(0.45), 1.0))
				cv.put(0, -1, z, VoxCanvas.glow(gc.lightened(0.3), 0.9))
		cv.shift = Vector3(0.5, 0, 0)
		return cv)
	# 剑穗
	if det >= 1:
		var tassel_col := Color("c8202a") if gc.a == 0 else gc.darkened(0.2)
		_tassel(root, key, Vector3(0, -1.0, 13.0), tassel_col, guard, 22 if det >= 2 else 16, det >= 2)
	root.set_meta("tip_length", float(-tip_z) * VOXEL)


## 剑穗：绳 + 中国结 + 玉珠 + 丝穗（WeaponSway 摆动）
static func _tassel(root: Node3D, key: String, pos_vox: Vector3, col: Color, bead: Color, length: int, fancy: bool) -> void:
	var sw := WeaponSway.new()
	sw.name = "Tassel"
	sw.mode = "pendulum"
	sw.stiffness = 14.0
	sw.damping = 3.0
	sw.position = pos_vox * VOXEL
	root.add_child(sw)
	_add(sw, key + "|tassel", func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-4, -length - 4, -4), Vector3i(3, 2, 3))
		cv.set_mat(VoxCanvas.M_SILK)
		# 挂绳
		for y in range(-3, 1):
			cv.put(0, y, 0, VoxCanvas.tone(col, 0.85))
		# 中国结（菱形镂空）
		var knot := ["..#..", ".#.#.", "#.#.#", ".#.#.", "..#.."]
		cv.stamp(knot, {"#": col}, Vector3i(-2, -4, 0), Vector3i(1, 0, 0), Vector3i(0, -1, 0))
		cv.stamp(knot, {"#": VoxCanvas.tone(col, 0.8)}, Vector3i(-2, -4, -1), Vector3i(1, 0, 0), Vector3i(0, -1, 0))
		# 珠
		cv.set_mat(VoxCanvas.M_JADE if not fancy else VoxCanvas.M_GOLD)
		var bc := Color("7fd0a8") if not fancy else bead
		cv.box(Vector3i(-1, -11, -1), Vector3i(0, -9, 0), bc)
		cv.put(-1, -9, -1, bc.lightened(0.3))
		if fancy:
			cv.box(Vector3i(-2, -10, -1), Vector3i(1, -10, 0), bc)
		# 丝穗：向下散开，逐根明暗
		cv.set_mat(VoxCanvas.M_SILK)
		for x in range(-2, 2):
			for z in range(-2, 2):
				var ln := length - 12 - (VoxCanvas.h3(x, 0, z) % 3)
				for k in ln:
					var y := -12 - k
					var sp := 1 if k > ln - 5 and (x == -2 or x == 1 or z == -2 or z == 1) else 0
					var xx := x + (sp * (1 if x > -1 else -1) if (x == -2 or x == 1) else 0)
					var zz := z + (sp * (1 if z > -1 else -1) if (z == -2 or z == 1) else 0)
					cv.put(xx, y, zz, VoxCanvas.tone(col, 0.82 + 0.26 * float(VoxCanvas.h3(x, 1, z) & 3) / 3.0 - 0.1 * float(k) / ln))
		# 穗头金箍
		cv.set_mat(VoxCanvas.M_GOLD)
		for x in range(-2, 2):
			for z in range(-2, 2):
				cv.put(x, -12, z, bead)
		return cv)


# ================================================================ 刀

static func _build_saber(root: Node3D, v: Dictionary, key: String) -> void:
	var c := _cols(v, "#c8ccd4", "#8a6a3a", "#2a1a10")
	var blade := c[0]
	var guard := c[1]
	var grip := c[2]
	var det: int = v["_det"]
	var gc: Color = v["_gc"]
	var length := int(v.get("length", 34)) * OLD
	var tip_z := -length - 10
	_add(root, key + "|body", func() -> Variant:
		var g3 := _gold3(guard)
		var ghi := g3[1]
		var gsh := g3[2]
		var cv := VoxCanvas.new(Vector3i(-5, -16, tip_z - 2), Vector3i(4, 20, 20))
		# 环首
		cv.set_mat(VoxCanvas.M_GOLD)
		if det >= 1:
			for a in 40:
				var ang := a * TAU / 40.0
				var py := int(round(sin(ang) * 5.0))
				var pz := 14 + int(round(cos(ang) * 4.2))
				for x in range(-1, 1):
					cv.put(x, py, pz, guard if x == 0 else gsh)
				cv.put(0, py, pz, ghi if a % 5 == 0 else guard)
			if det >= 2:
				_gem(cv, 0, 0, 14, gc if gc.a > 0 else Color("e8283a"))
				_gem(cv, -1, 0, 14, gc if gc.a > 0 else Color("e8283a"))
		else:
			cv.box(Vector3i(-2, -2, 8), Vector3i(1, 1, 10), guard)
		cv.box(Vector3i(-2, -2, 8), Vector3i(1, 1, 9), gsh)
		_grip(cv, -6, 7, grip)
		# 刀镡（椭圆盘，外缘亮、内有镂空点）
		cv.set_mat(VoxCanvas.M_GOLD)
		for y in range(-6, 7):
			for x in range(-4, 4):
				var e := (x + 0.5) * (x + 0.5) / 16.0 + float(y * y) / 38.0
				if e <= 1.0:
					cv.put(x, y, -8, guard if e < 0.7 else ghi)
					cv.put(x, y, -9, gsh if e < 0.7 else guard)
					if e > 0.35 and e < 0.5 and (x + y) % 3 == 0:
						cv.put(x, y, -9, g3[2].darkened(0.3))
		# 刀身：单刃（刃口朝 -Y），刀背加厚，向刀尖渐宽并平滑上翘，末端斜切成尖
		cv.set_mat(VoxCanvas.M_STEEL)
		var back := VoxCanvas.tone(blade, 0.68)
		var edge := blade.lerp(Color(1, 1, 1), 0.55)
		var flat := VoxCanvas.tone(blade, 0.92)
		for z in range(tip_z, -9):
			var t := float(-10 - z) / float(length)          # 0 护手 → 1 刀尖
			var curve := t * t * 5.0
			var y_top_f := 2.0 + curve
			var w := 8.0 + t * 3.0
			var from_tip := z - tip_z
			var y_bot_f := y_top_f - w
			if from_tip < 14:
				y_bot_f = y_top_f - w * float(from_tip) / 14.0
			var y_top := int(round(y_top_f))
			var y_bot := int(round(y_bot_f)) + 1
			if y_bot > y_top:
				y_bot = y_top
			for y in range(y_bot, y_top + 1):
				var col := flat
				var thick := 1
				if y >= y_top - 1:
					col = back
					thick = 2
				elif y <= y_bot + 1:
					col = edge
					thick = 0
				elif y == y_top - 3 and from_tip > 16:
					col = VoxCanvas.tone(blade, 0.7)   # 血槽
				cv.put(0, y, z, col)
				if thick >= 1:
					cv.put(-1, y, z, VoxCanvas.tone(col, 0.9))
				if thick >= 2:
					cv.put(1, y, z, VoxCanvas.tone(col, 0.85))
			# 刀背金错纹（精致）
			if det >= 2 and from_tip > 20 and posmod(z, 6) < 3:
				cv.putm(0, y_top, z, g3[0], VoxCanvas.M_GOLD)
			if gc.a > 0:
				cv.putm(0, y_bot, z, VoxCanvas.glow(gc.lightened(0.3), 0.85), VoxCanvas.M_FLAME)
				if posmod(z, 9) < 2 and from_tip > 10:
					cv.putm(0, y_top - 4, z, VoxCanvas.glow(gc, 0.75), VoxCanvas.M_FLAME)
		if det >= 2:
			_gem(cv, -4, 0, -8, gc if gc.a > 0 else Color("e8283a"))
			_gem(cv, 3, 0, -8, gc if gc.a > 0 else Color("e8283a"))
		cv.shift = Vector3(0.5, 0, 0)
		return cv)
	if det >= 1:
		_tassel(root, key, Vector3(0, -5.0, 15.0), Color("c8202a") if gc.a == 0 else gc.darkened(0.2), guard, 16, det >= 2)
	root.set_meta("tip_length", float(-tip_z) * VOXEL)


# ================================================================ 枪 / 旗枪

static func _build_spear(root: Node3D, v: Dictionary, key: String) -> void:
	var c := _cols(v, "#d0d4dc", "#c02020", "#5a2a1a")
	var blade := c[0]
	var guard := c[1]
	var grip := c[2]
	var det: int = v["_det"]
	var gc: Color = v["_gc"]
	var length := int(v.get("length", 80)) * OLD
	var butt := 44                         # 握点到枪尾的距离
	var head_z := -(length - butt)         # 枪头根部（z，负向为前）
	var gold := guard if guard.s < 0.5 or absf(guard.h - 0.12) < 0.08 else Color("e0b040")
	var widths: Array = [2, 3, 5, 6, 7, 8, 8, 8, 8, 7, 7, 6, 6, 5, 5, 4, 4, 3, 3, 2, 2, 1, 1]
	var tip := head_z - 6 - widths.size()
	_add(root, key + "|body", func() -> Variant:
		var g3 := _gold3(gold)
		var ghi := g3[1]
		var gsh := g3[2]
		var cv := VoxCanvas.new(Vector3i(-8, -10, tip - 3), Vector3i(7, 9, butt + 10))
		# 枪杆（4×4 圆角），漆面细微明暗，每隔 32 格一道金箍
		cv.set_mat(VoxCanvas.M_JADE if grip.s > 0.35 else VoxCanvas.M_LEATHER)
		for z in range(head_z, butt + 1):
			for y in range(-2, 2):
				for x in range(-2, 2):
					if (x == -2 or x == 1) and (y == -2 or y == 1):
						continue
					var col := VoxCanvas.tone(grip, 0.9 + 0.16 * float(y == 1) - 0.1 * float(y == -2) + 0.04 * float(posmod(z, 13) == 0))
					cv.put(x, y, z, col)
		# 握持段缠绳
		cv.set_mat(VoxCanvas.M_LEATHER)
		for z in range(-10, 12):
			for y in range(-2, 2):
				for x in range(-2, 2):
					if (x == -2 or x == 1) and (y == -2 or y == 1):
						continue
					var k := posmod(z + x + y, 4)
					if k < 2:
						cv.put(x, y, z, VoxCanvas.tone(grip, 0.55 if k == 0 else 0.7))
		cv.set_mat(VoxCanvas.M_GOLD)
		for zb in range(butt - 6, head_z, -32):
			for y in range(-3, 3):
				for x in range(-3, 3):
					if (x == -3 or x == 2) and (y == -3 or y == 2):
						continue
					cv.put(x, y, zb, gold)
					cv.put(x, y, zb - 1, ghi if y >= 1 else gold)
		# 枪尾金镦（逐级收尖）
		cv.rbox(Vector3i(-3, -3, butt - 2), Vector3i(2, 2, butt + 2), gold, 1)
		cv.box(Vector3i(-2, -2, butt + 3), Vector3i(1, 1, butt + 5), ghi)
		cv.box(Vector3i(-1, -1, butt + 6), Vector3i(0, 0, butt + 7), gold)
		# 枪头：金箍 + 吞口（兽口）
		cv.rbox(Vector3i(-3, -3, head_z - 2), Vector3i(2, 2, head_z + 4), gold, 1)
		cv.box(Vector3i(-3, -3, head_z + 4), Vector3i(2, 2, head_z + 4), ghi)
		cv.box(Vector3i(-3, -3, head_z - 2), Vector3i(2, -3, head_z + 4), gsh)
		if det >= 2:
			# 吞口两翼（云头）+ 兽眼宝石
			for y in range(-8, 8):
				var ay := absi(y * 2 + 1)
				var zz := head_z - 4 - (1 if ay > 11 else 0)
				cv.box(Vector3i(-1, y, zz), Vector3i(0, y, zz + 1), gold if ay < 13 else ghi)
			var gemc := gc if gc.a > 0 else Color("e8283a")
			_gem(cv, -3, -1, head_z, gemc)
			_gem(cv, -3, 0, head_z, gemc.lightened(0.3))
			_gem(cv, 2, -1, head_z, gemc)
			_gem(cv, 2, 0, head_z, gemc.lightened(0.3))
		# 枪刃：柳叶形，宽沿 Y，中脊高光，两侧刃口亮
		cv.set_mat(VoxCanvas.M_STEEL)
		var ridge := blade.lerp(Color(1, 1, 1), 0.5)
		var edge := blade.lerp(Color(1, 1, 1), 0.3)
		var zt := head_z - 5
		for i in widths.size():
			var w: int = widths[i]
			var z := zt - i
			for y in range(-w, w):
				var ay := absf(y + 0.5)
				var col := VoxCanvas.tone(blade, 0.9)
				var th := 1
				if ay < 1.0:
					col = ridge
					th = 2
				elif ay > w - 1.0:
					col = edge
					th = 0
				cv.put(0, y, z, col)
				if th >= 1:
					cv.put(-1, y, z, VoxCanvas.tone(col, 0.9))
				if th >= 2:
					cv.put(1, y, z, VoxCanvas.tone(col, 0.84))
			if gc.a > 0 and w >= 3:
				cv.putm(0, -w, z, VoxCanvas.glow(gc.lightened(0.25), 0.85), VoxCanvas.M_FLAME)
				cv.putm(0, w - 1, z, VoxCanvas.glow(gc.lightened(0.25), 0.85), VoxCanvas.M_FLAME)
		cv.put(0, 0, tip, ridge)
		cv.put(0, -1, tip, ridge)
		if gc.a > 0:
			cv.putm(0, 0, tip, VoxCanvas.glow(gc.lightened(0.5), 1.0), VoxCanvas.M_FLAME)
			for z in range(head_z + 8, head_z + 28, 5):
				cv.putm(-3, 0, z, VoxCanvas.glow(gc, 0.8), VoxCanvas.M_FLAME)
				cv.putm(2, -1, z, VoxCanvas.glow(gc, 0.8), VoxCanvas.M_FLAME)
		return cv)
	# 红缨（挂在枪头下）
	if det >= 1 and not v.has("flag"):
		_spear_tassel(root, key, Vector3(0, -1.0, head_z + 6), Color("d02028") if gc.a == 0 else gc.lerp(Color("d02028"), 0.4))
	if v.has("flag"):
		_banner(root, v, key, head_z + 8, gold, gc)
	root.set_meta("tip_length", float(-tip) * VOXEL)


## 枪缨：从吞口处向后下方散开的一簇红缨（多根 1 体素丝）
static func _spear_tassel(root: Node3D, key: String, pos_vox: Vector3, col: Color) -> void:
	var sw := WeaponSway.new()
	sw.name = "Tassel"
	sw.mode = "pendulum"
	sw.stiffness = 12.0
	sw.damping = 3.5
	sw.max_angle = 60.0
	sw.position = pos_vox * VOXEL
	root.add_child(sw)
	_add(sw, key + "|stassel", func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-9, -22, -7), Vector3i(8, 3, 14))
		cv.set_mat(VoxCanvas.M_SILK)
		for i in 44:
			var h := VoxCanvas.h1(i + 5)
			var a := i * TAU / 44.0 + float(h & 7) * 0.05
			var rr := 1.5 + float((h >> 3) & 3) * 0.6
			var dx := cos(a) * rr
			var dz := sin(a) * rr + 1.5
			var ln := 10 + h % 9
			for k in ln:
				var p := Vector3(dx * (1.0 + k * 0.14), -k - 0.5, dz * (1.0 + k * 0.1) + k * 0.4)
				cv.put(int(floor(p.x)), int(floor(p.y)), int(floor(p.z)), VoxCanvas.tone(col, 0.8 + 0.3 * float(h & 3) / 3.0 - 0.12 * float(k) / ln))
		cv.box(Vector3i(-3, -1, -2), Vector3i(2, 2, 3), VoxCanvas.tone(col, 0.9))
		return cv)


## 旗面：挂在枪杆上（沿 +Z 方向从 z0 起向枪尾延伸），向本地 -Y 下垂；金边、菱形金框与字、火焰边
static func _banner(root: Node3D, v: Dictionary, key: String, z0: int, gold: Color, gc: Color) -> void:
	var flag := CharacterBuilder.col(v.get("flag", "#c81e1e"), Color("c81e1e"))
	var elem := str(v.get("glow", "none"))
	var W := 40      # 沿杆方向
	var H := 60      # 下垂长度
	var sw := WeaponSway.new()
	sw.name = "Banner"
	sw.mode = "hinge"
	sw.stiffness = 7.0
	sw.damping = 3.0
	sw.max_angle = 70.0
	sw.flutter = 4.0
	sw.position = Vector3(0, -2.0, z0) * VOXEL
	root.add_child(sw)
	var flame := gc.a > 0
	var glyph: Array = GLYPHS.get(elem, GLYPHS["none"])
	_add(sw, key + "|banner", func() -> Variant:
		var cv := VoxCanvas.new(Vector3i(-5, -H - 26, -3), Vector3i(4, 4, W + 24))
		var g3 := _gold3(gold)
		var ghi := g3[1]
		var gsh := g3[2]
		var dark := VoxCanvas.tone(flag, 0.68)
		# 旗面（z 0..W-1 沿杆向后，y 0..-H+1 向下），带波浪（x 方向起伏）
		for z in range(0, W):
			var wave := int(round(sin(z * 0.22) * 1.4))
			for yi in range(0, H):
				var y := -yi
				var col := VoxCanvas.tone(flag, 0.95 + 0.08 * float(VoxCanvas.h3(z >> 1, yi >> 1, 1) & 1))
				# 布纹：横向细纹 + 波谷暗
				if yi % 14 == 13:
					col = VoxCanvas.tone(flag, 0.88)
				col = VoxCanvas.tone(col, 1.0 + 0.06 * sin(z * 0.22 + 1.2))
				var m := VoxCanvas.M_SILK
				var bz := mini(z, W - 1 - z)
				var by := mini(yi, H - 1 - yi)
				var b := mini(bz, by)
				if b <= 1:
					col = gold if b == 1 else gsh
					m = VoxCanvas.M_GOLD
				elif b == 2 or b == 3:
					col = dark
				elif b == 4 and (z + yi) % 2 == 0:
					col = VoxCanvas.tone(gold, 0.85)
					m = VoxCanvas.M_GOLD
				cv.putm(wave, y, z, col, m)
		# 挂环（金）
		for z in [2, W / 2, W - 3]:
			cv.set_mat(VoxCanvas.M_GOLD)
			cv.box(Vector3i(-2, 0, z), Vector3i(1, 3, z + 1), gold)
			cv.box(Vector3i(-2, 4, z), Vector3i(1, 4, z + 1), ghi)
		# 菱形金框（双线）+ 字
		var cz := W / 2
		var cy := -H / 2 + 2
		var R := 16
		cv.set_mat(VoxCanvas.M_GOLD)
		for z in range(0, W):
			var wave2 := int(round(sin(z * 0.22) * 1.4))
			for yi in range(0, H):
				var y := -yi
				var d := absi(z - cz) + absi(y - cy)
				if d == R or d == R - 1 or d == R - 4:
					var fc2 := gold if d != R - 1 else ghi
					cv.put(wave2 - 1, y, z, fc2)
					cv.put(wave2 + 1, y, z, fc2)
		for r in 13:
			var row: String = glyph[r]
			for k in 13:
				if row[k] == "#":
					var z2 := cz - 6 + k
					var y2 := cy + 6 - r
					var wave3 := int(round(sin(z2 * 0.22) * 1.4))
					var gcol := VoxCanvas.glow(ghi, 0.2) if flame else gold
					cv.put(wave3 - 1, y2, z2, gcol)
					# 背面镜像（从另一侧看字不反）
					var z3 := cz + 6 - k
					cv.put(int(round(sin(z3 * 0.22) * 1.4)) + 1, y2, z3, gcol)
		# 火焰边：沿下缘与靠枪头一侧（z=0 边）向外窜出的发光火舌（前后两层，长短交错）
		if flame:
			cv.set_mat(VoxCanvas.M_FLAME)
			var fc := [Color("a01808"), Color("d8300a"), Color("ff6a14"), Color("ffa628"), Color("ffe070"), Color("fff6c0")]
			for i in range(0, W + H):
				for layer: int in [0, 1, 2]:
					var h := VoxCanvas.h1(i * 7 + 3 + layer * 101)
					if layer > 0 and h % 3 == 0:
						continue
					var ln := 6 + h % 14 + (8 if (h >> 5) % 5 == 0 else 0)
					var base: Vector3
					var dir: Vector3
					if i < W:
						base = Vector3(0, -H + 2, i)
						dir = Vector3(0, -1, 0.5).normalized()
					else:
						var yi2 := i - W
						base = Vector3(0, -yi2, 1)
						dir = Vector3(0, -0.4, -1).normalized()
					var px0 := int(round(sin(base.z * 0.22) * 1.4)) + (layer - 1)
					for k in ln:
						var t := float(k) / float(ln)
						var p := base + dir * (k + 1) + Vector3(0, 0, sin(k * 0.6 + i) * 0.9)
						var ci := clampi(int(t * 5.6), 0, 5)
						var col2: Color = fc[ci]
						cv.put(px0, int(floor(p.y)), int(floor(p.z)), VoxCanvas.glow(col2, 0.35 + 0.65 * t))
		else:
			# 无元素：金色流苏下缘
			cv.set_mat(VoxCanvas.M_SILK)
			for z in range(1, W - 1):
				var fl := 3 + (z % 3)
				for k in fl:
					cv.put(0, -H - k, z, gold if k < fl - 1 else ghi)
		return cv)
	# 火星（静态点缀）
	if flame:
		var mk := func() -> Variant:
			var sp := VoxCanvas.new(Vector3i(-3, -H - 34, -6), Vector3i(3, 0, W + 16))
			sp.set_mat(VoxCanvas.M_FLAME)
			for i in 14:
				var h2 := VoxCanvas.h1(i * 11 + 1)
				sp.put(0, -H - 8 - h2 % 22, 2 + (h2 >> 4) % (W + 4), VoxCanvas.glow(Color("ffc040"), 1.0))
			return sp
		_add(sw, key + "|sparks", mk, "Sparks")


# ================================================================ 拳套

static func _build_fist(root: Node3D, v: Dictionary, hand: String, key: String) -> void:
	var det: int = v["_det"]
	var gc: Color = v["_gc"]
	var metal := v.has("guard") or det >= 2
	var guard := CharacterBuilder.col(v.get("guard", "#c89a30"), Color("c89a30"))
	var grip := CharacterBuilder.col(v.get("grip", "#e8e0d0"), Color("e8e0d0"))
	var wrapc := grip if not metal else CharacterBuilder.col(v.get("grip", "#4a2a1a"), Color("4a2a1a"))
	var mi := _add(root, key + "|fist", func() -> Variant:
		# 拳套：包住拳头（拳心在原点，女 10³ / 男 12³ 的拳头）与手腕；外壳 x/z -7..6
		var cv := VoxCanvas.new(Vector3i(-10, -14, -10), Vector3i(9, 18, 9))
		cv.set_mat(VoxCanvas.M_LEATHER if metal else VoxCanvas.M_CLOTH)
		for y in range(-8, 13):
			for z in range(-7, 7):
				for x in range(-7, 7):
					var shell := x == -7 or x == 6 or z == -7 or z == 6 or y == -8
					if not shell:
						continue
					if (x == -7 or x == 6) and (z == -7 or z == 6):
						continue
					# 缠布：斜向交错条纹（每条 3 格）
					var k := posmod(y * 2 + (x + z + 14) / 2, 6)
					var col := wrapc
					if k == 0:
						col = VoxCanvas.tone(wrapc, 0.72)
					elif k == 1:
						col = VoxCanvas.tone(wrapc, 0.88)
					elif k == 3:
						col = VoxCanvas.tone(wrapc, 1.06)
					cv.put(x, y, z, col)
		# 腕口内衬
		for z in range(-6, 6):
			for x in range(-6, 6):
				cv.put(x, 10, z, VoxCanvas.tone(wrapc, 0.42))
		# 指缝（掌心一侧，-X）
		for y in [-6, -2, 2]:
			for z in range(-5, 5):
				cv.put(-7, y, z, VoxCanvas.tone(wrapc, 0.66))
		if metal:
			var g3 := _gold3(guard)
			var ghi := g3[1]
			var gsh := g3[2]
			cv.set_mat(VoxCanvas.M_GOLD)
			# 手背护板（外侧 +X）：金框 + 暗纹
			for y in range(-6, 9):
				for z in range(-5, 5):
					var edge := y == -6 or y == 8 or z == -5 or z == 4
					cv.put(7, y, z, guard if edge else (gsh if (y + z) % 3 == 0 else guard.lerp(gsh, 0.35)))
			for z in range(-5, 5):
				cv.put(7, 9, z, ghi)
			# 指节护甲（拳面：下方）+ 凸钉
			for z in range(-7, 7):
				for x in range(-7, 7):
					if (x == -7 or x == 6) and (z == -7 or z == 6):
						continue
					cv.put(x, -9, z, guard if (x + z) % 2 == 0 else gsh)
			for x in [-5, -1, 3]:
				for z in [-4, 2]:
					cv.put(x, -10, z, ghi)
					cv.put(x + 1, -10, z, ghi)
					cv.put(x, -10, z + 1, guard)
					cv.put(x + 1, -10, z + 1, guard)
			# 腕甲（两道）
			for y in [11, 12]:
				for z in range(-8, 8):
					for x in range(-8, 8):
						if x == -8 or x == 7 or z == -8 or z == 7:
							cv.put(x, y, z, ghi if y == 12 else guard)
			var gem_c := gc if gc.a > 0 else Color("e8283a")
			cv.putm(8, 1, -1, VoxCanvas.glow(gem_c, 0.5), VoxCanvas.M_GEM)
			cv.putm(8, 1, 0, VoxCanvas.glow(gem_c.lightened(0.3), 0.55), VoxCanvas.M_GEM)
			cv.putm(8, 0, -1, gem_c.darkened(0.25), VoxCanvas.M_GEM)
			cv.putm(8, 0, 0, VoxCanvas.glow(gem_c, 0.4), VoxCanvas.M_GEM)
			if gc.a > 0:
				cv.set_mat(VoxCanvas.M_FLAME)
				for x in [-5, -1, 3]:
					cv.put(x, -10, -4, VoxCanvas.glow(gc.lightened(0.2), 0.9))
				cv.put(7, 5, -4, VoxCanvas.glow(gc, 0.8))
				cv.put(7, -4, 3, VoxCanvas.glow(gc, 0.8))
		else:
			# 红绳绑扎于腕 + 垂下的绳头
			cv.set_mat(VoxCanvas.M_SILK)
			var cord := Color("c02028")
			for y in [10, 11]:
				for z in range(-7, 7):
					for x in range(-7, 7):
						if x == -7 or x == 6 or z == -7 or z == 6:
							cv.put(x, y, z, cord if y == 10 else cord.darkened(0.2))
			for k in 5:
				cv.put(6, 9 - k, -8, cord.lightened(0.1 * float(k & 1)))
		cv.shift = Vector3(0, 0, 0)
		return cv)
	if hand == "l":
		mi.scale = Vector3(-1, 1, 1)
		var l1 := root.get_node_or_null("Mesh_lod1") as MeshInstance3D
		if l1 != null:
			l1.scale = Vector3(-1, 1, 1)
	root.set_meta("tip_length", 0.12)
