class_name WeaponBuilder
## 体素兵器生成。握把在原点、刃沿本地 -Z；返回节点带 meta "tip_length"（米，刃尖到握把的距离）。
##
## visual 字段（均可选）：
##   kind   sword 剑 / saber 刀 / spear 枪 / fist 拳套
##   length 刃长或枪长（体素）；blade / guard / grip 颜色；flag 旗面颜色（仅枪，有则为旗枪）
##   glow   元素 id（metal/wood/water/fire/earth）：刃上发光符文与刃口，颜色取 Elem.color_of
##   detail 0 朴素 / 1 标准（剑穗、红缨、柄首）/ 2 精致（宝石、金饰、符文）；
##          缺省时由 grade（0~5）推导，否则有 glow 为 2、无为 1
##
## 挂接：WeaponBuilder.attach_to_rig(rig, visual) —— 自动处理拳套（左右手各一只）并设置 rig.stance。
## 拳套也可手动挂：rig.attach_to_hand(build(v, "r"), "r")；rig.attach_to_hand(build(v, "l"), "l")。
## 剑穗、枪缨、旗面挂在 WeaponSway 节点下，会随挥动与重力摆动。

const VOXEL := 0.025


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
	match kind:
		"fist":
			_build_fist(root, visual, hand)
		"spear":
			_build_spear(root, visual)
		"saber":
			_build_saber(root, visual)
		_:
			_build_sword(root, visual)
	return root


## 把兵器挂到角色手上并设置持械姿势（拳套挂两只手）
static func attach_to_rig(rig: CharacterRig, visual: Dictionary) -> void:
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


static func _add_mesh(parent: Node3D, cv: VoxCanvas, mesh_name: String = "Mesh") -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = VoxMesh.build_one(cv, VOXEL)
	parent.add_child(mi)
	return mi


static func _cols(visual: Dictionary, blade_def: String, guard_def: String, grip_def: String) -> Array[Color]:
	return [
		CharacterBuilder.col(visual.get("blade", blade_def), Color(blade_def)),
		CharacterBuilder.col(visual.get("guard", guard_def), Color(guard_def)),
		CharacterBuilder.col(visual.get("grip", grip_def), Color(grip_def)),
	]


## 缠柄：交错菱纹
static func _grip(cv: VoxCanvas, z0: int, z1: int, grip: Color, r: int = 1) -> void:
	var dark := VoxCanvas.tone(grip, 0.7)
	var lite := VoxCanvas.tone(grip, 1.18)
	for z in range(z0, z1 + 1):
		for y in range(-r, r):
			for x in range(-r, r):
				var k := posmod(z + x + y, 3)
				cv.put(x, y, z, lite if k == 0 else (dark if k == 1 else grip))


# ================================================================ 剑

static func _build_sword(root: Node3D, v: Dictionary) -> void:
	var c := _cols(v, "#d8dde6", "#c89a30", "#4a2a1a")
	var blade := c[0]
	var guard := c[1]
	var grip := c[2]
	var det := detail_of(v)
	var gc := glow_color(v)
	var length := int(v.get("length", 36))
	var ghi := guard.lerp(Color(1, 0.97, 0.85), 0.45)
	var gsh := VoxCanvas.tone(guard, 0.62)
	var cv := VoxCanvas.new(Vector3i(-3, -6, -length - 8), Vector3i(2, 5, 6))
	# 柄首
	cv.box(Vector3i(-1, -1, 4), Vector3i(0, 0, 5), guard)
	if det >= 1:
		cv.box(Vector3i(-2, -2, 4), Vector3i(1, 1, 4), guard)
		cv.box(Vector3i(-1, -1, 6), Vector3i(0, 0, 6), ghi)
	_grip(cv, -3, 3, grip)
	# 护手：沿刃宽方向（Y）展开的剑格
	var gw := 3 if det == 0 else (4 if det == 1 else 5)
	cv.box(Vector3i(-2, -gw, -5), Vector3i(1, gw - 1, -4), guard)
	cv.box(Vector3i(-2, -gw, -4), Vector3i(1, gw - 1, -4), gsh)
	cv.box(Vector3i(-1, gw - 1, -6), Vector3i(0, gw, -4), ghi)
	cv.box(Vector3i(-1, -gw - 1, -6), Vector3i(0, -gw, -4), ghi)
	if det >= 2:
		cv.put(-2, 0, -5, VoxelGrid.glow(gc if gc.a > 0 else Color("e8283a"), 0.4))
		cv.put(1, -1, -5, VoxelGrid.glow(gc if gc.a > 0 else Color("e8283a"), 0.4))
		cv.box(Vector3i(-1, -2, -7), Vector3i(0, 1, -6), guard)
	# 剑身：宽 4（沿 Y），厚 1；中脊高光；末 5 格收成剑尖
	var bl := blade
	var ridge := blade.lerp(Color(1, 1, 1), 0.45)
	var edge := VoxCanvas.tone(blade, 0.86)
	var z_start := -6 if det < 2 else -8
	var tip_z := -length - 6
	for z in range(tip_z, z_start + 1):
		var from_tip := z - tip_z
		var half := 2
		if from_tip < 2:
			half = 0
		elif from_tip < 4:
			half = 1
		for y in range(-half, half):
			var col := bl
			if y == -half or y == half - 1:
				col = edge
			if half >= 1 and (y == -1 or y == 0):
				col = ridge if y == 0 else bl
			cv.put(0, y, z, col)
			if half >= 2 and (y == -1 or y == 0):
				cv.put(-1, y, z, VoxCanvas.tone(col, 0.92))
		if half == 0:
			cv.put(0, 0, z, ridge)
	# 发光符文 / 刃口
	if gc.a > 0:
		var g := VoxelGrid.glow(gc.lightened(0.2), 0.9)
		for z in range(tip_z + 4, z_start - 1):
			if posmod(z, 4) == 0:
				cv.put(0, 0, z, g)
				cv.put(-1, 0, z, g)
			elif posmod(z, 4) == 1:
				cv.put(0, -1, z, VoxelGrid.glow(gc, 0.6))
		for z in range(tip_z, tip_z + 3):
			cv.put(0, 0, z, VoxelGrid.glow(gc.lightened(0.4), 1.0))
	cv.shift = Vector3(0.5, 0, 0)
	_add_mesh(root, cv)
	# 剑穗
	if det >= 1:
		var tassel_col := Color("c8202a") if gc.a == 0 else gc.darkened(0.2)
		_tassel(root, Vector3(0, -0.5, 5.5), tassel_col, guard, 9 if det >= 2 else 7)
	root.set_meta("tip_length", float(length + 6) * VOXEL)


static func _tassel(root: Node3D, pos_vox: Vector3, col: Color, bead: Color, length: int) -> void:
	var sw := WeaponSway.new()
	sw.name = "Tassel"
	sw.mode = "pendulum"
	sw.stiffness = 14.0
	sw.damping = 3.0
	sw.position = pos_vox * VOXEL
	root.add_child(sw)
	var cv := VoxCanvas.new(Vector3i(-2, -length - 2, -2), Vector3i(1, 1, 1))
	cv.box(Vector3i(0, -1, 0), Vector3i(0, 0, 0), bead)
	cv.box(Vector3i(-1, -3, -1), Vector3i(0, -2, 0), bead)
	for y in range(-length, -3):
		var spread := 1 if y < -length + 3 else 0
		for x in range(-1 - spread, 1 + spread):
			for z in range(-1 - spread, 1 + spread):
				if (x + z + y) % 2 == 0 or spread == 0:
					cv.put(x, y, z, VoxCanvas.tone(col, 0.9 + 0.2 * float(VoxCanvas.h3(x, y, z) & 1)))
	_add_mesh(sw, cv)


# ================================================================ 刀

static func _build_saber(root: Node3D, v: Dictionary) -> void:
	var c := _cols(v, "#c8ccd4", "#8a6a3a", "#2a1a10")
	var blade := c[0]
	var guard := c[1]
	var grip := c[2]
	var det := detail_of(v)
	var gc := glow_color(v)
	var length := int(v.get("length", 34))
	var ghi := guard.lerp(Color(1, 0.97, 0.85), 0.4)
	var cv := VoxCanvas.new(Vector3i(-3, -8, -length - 8), Vector3i(2, 10, 9))
	# 环首
	if det >= 1:
		for a in 12:
			var ang := a * TAU / 12.0
			cv.put(0, int(round(sin(ang) * 2.5)), 7 + int(round(cos(ang) * 2.0)), guard)
			cv.put(-1, int(round(sin(ang) * 2.5)), 7 + int(round(cos(ang) * 2.0)), VoxCanvas.tone(guard, 0.8))
	else:
		cv.box(Vector3i(-1, -1, 4), Vector3i(0, 0, 5), guard)
	_grip(cv, -3, 4, grip)
	# 刀镡（椭圆盘）
	for y in range(-3, 4):
		for x in range(-2, 2):
			if (x + 0.5) * (x + 0.5) / 4.0 + (y + 0.0) * (y + 0.0) / 10.0 <= 1.0:
				cv.put(x, y, -4, guard)
				cv.put(x, y, -5, ghi if y > 0 else guard)
	# 刀身：单刃（刃口朝 -Y），刀背加厚，向刀尖渐宽并平滑上翘，末端斜切成尖
	var back := VoxCanvas.tone(blade, 0.7)
	var edge := blade.lerp(Color(1, 1, 1), 0.5)
	var tip_z := -length - 5
	for z in range(tip_z, -5):
		var t := float(-5 - z) / float(length)          # 0 护手 → 1 刀尖
		var curve := t * t * 2.5
		var y_top_f := 1.0 + curve
		var w := 4.0 + t * 1.5
		var from_tip := z - tip_z
		var y_bot_f := y_top_f - w
		if from_tip < 7:
			# 刀尖：刃口斜向上收到刀背
			y_bot_f = y_top_f - w * float(from_tip) / 7.0
		var y_top := int(round(y_top_f))
		var y_bot := int(round(y_bot_f)) + 1
		if y_bot > y_top:
			y_bot = y_top
		for y in range(y_bot, y_top + 1):
			var col := blade
			if y == y_top:
				col = back
			elif y == y_bot:
				col = edge
			cv.put(0, y, z, col)
			if y == y_top:
				cv.put(-1, y, z, back)
		if gc.a > 0:
			cv.put(0, y_bot, z, VoxelGrid.glow(gc.lightened(0.25), 0.8))
			if posmod(z, 5) == 0 and from_tip > 4:
				cv.put(0, y_top - 2, z, VoxelGrid.glow(gc, 0.7))
	# 血槽
	for z in range(-length + 4, -7):
		var t2 := float(-5 - z) / float(length)
		var cy := int(round(1.0 + t2 * t2 * 2.5)) - 1
		cv.put(0, cy, z, VoxCanvas.tone(blade, 0.8))
	if det >= 2:
		cv.put(-2, 0, -4, VoxelGrid.glow(gc if gc.a > 0 else Color("e8283a"), 0.4))
		cv.put(1, 0, -4, VoxelGrid.glow(gc if gc.a > 0 else Color("e8283a"), 0.4))
	cv.shift = Vector3(0.5, 0, 0)
	_add_mesh(root, cv)
	if det >= 1:
		_tassel(root, Vector3(0, -2.5, 7.5), Color("c8202a") if gc.a == 0 else gc.darkened(0.2), guard, 7)
	root.set_meta("tip_length", float(length + 5) * VOXEL)


# ================================================================ 枪 / 旗枪

static func _build_spear(root: Node3D, v: Dictionary) -> void:
	var c := _cols(v, "#d0d4dc", "#c02020", "#5a2a1a")
	var blade := c[0]
	var guard := c[1]
	var grip := c[2]
	var det := detail_of(v)
	var gc := glow_color(v)
	var length := int(v.get("length", 80))
	var butt := 22                         # 握点到枪尾的距离
	var head_z := -(length - butt)         # 枪头根部（z，负向为前）
	var gold := guard if guard.s < 0.5 or absf(guard.h - 0.12) < 0.08 else Color("e0b040")
	var ghi := gold.lerp(Color(1, 0.97, 0.85), 0.45)
	var cv := VoxCanvas.new(Vector3i(-4, -5, head_z - 16), Vector3i(3, 4, butt + 5))
	# 枪杆（2×2），每隔 16 格一道金箍，杆身细微明暗
	for z in range(head_z, butt + 1):
		for y in range(-1, 1):
			for x in range(-1, 1):
				var col := VoxCanvas.tone(grip, 0.92 + 0.14 * float((x + y + 2) % 2) + 0.05 * float(posmod(z, 7) == 0))
				cv.put(x, y, z, col)
	for zb in range(butt - 3, head_z, -16):
		cv.box(Vector3i(-2, -2, zb), Vector3i(1, 1, zb), gold)
	# 枪尾金镦
	cv.box(Vector3i(-2, -2, butt - 1), Vector3i(1, 1, butt + 1), gold)
	cv.box(Vector3i(-1, -1, butt + 2), Vector3i(0, 0, butt + 3), ghi)
	cv.put(0, 0, butt + 4, ghi)
	# 枪头：金箍 + 吞口
	cv.box(Vector3i(-2, -2, head_z - 1), Vector3i(1, 1, head_z + 2), gold)
	cv.box(Vector3i(-2, -2, head_z + 2), Vector3i(1, 1, head_z + 2), ghi)
	if det >= 2:
		# 吞口两翼
		cv.box(Vector3i(-1, -4, head_z - 2), Vector3i(0, 3, head_z - 2), gold)
		cv.put(-1, 3, head_z - 3, ghi)
		cv.put(-1, -4, head_z - 3, ghi)
		cv.put(-2, 0, head_z, VoxelGrid.glow(gc if gc.a > 0 else Color("e8283a"), 0.4))
	# 枪刃：柳叶形，宽沿 Y，中脊
	var widths := [1, 2, 3, 3, 4, 4, 4, 3, 3, 2, 2, 1, 1]
	var ridge := blade.lerp(Color(1, 1, 1), 0.45)
	var edge := VoxCanvas.tone(blade, 0.85)
	var zt := head_z - 3
	for i in widths.size():
		var w: int = widths[widths.size() - 1 - i]
		var z := zt - i
		for y in range(-w, w):
			var col := blade
			if y == -w or y == w - 1:
				col = edge
			if y == -1 or y == 0:
				col = ridge
			cv.put(0, y, z, col)
			if y == -1 or y == 0:
				cv.put(-1, y, z, VoxCanvas.tone(col, 0.9))
		if gc.a > 0 and w >= 2:
			cv.put(0, -w, z, VoxelGrid.glow(gc.lightened(0.2), 0.8))
			cv.put(0, w - 1, z, VoxelGrid.glow(gc.lightened(0.2), 0.8))
	var tip := zt - widths.size()
	cv.put(0, 0, tip, ridge)
	cv.put(0, -1, tip, ridge)
	if gc.a > 0:
		cv.put(0, 0, tip, VoxelGrid.glow(gc.lightened(0.5), 1.0))
		for z in range(head_z + 4, head_z + 14, 3):
			cv.put(-2, 0, z, VoxelGrid.glow(gc, 0.8))
			cv.put(1, -1, z, VoxelGrid.glow(gc, 0.8))
	_add_mesh(root, cv)
	# 红缨（挂在枪头下）
	if det >= 1 and not v.has("flag"):
		_spear_tassel(root, Vector3(0, -0.5, head_z + 3), Color("d02028") if gc.a == 0 else gc.lerp(Color("d02028"), 0.4))
	if v.has("flag"):
		_banner(root, v, head_z + 4, gold, gc)
	root.set_meta("tip_length", float(-tip) * VOXEL)


## 枪缨：从吞口处向后下方散开的一簇红缨
static func _spear_tassel(root: Node3D, pos_vox: Vector3, col: Color) -> void:
	var sw := WeaponSway.new()
	sw.name = "Tassel"
	sw.mode = "pendulum"
	sw.stiffness = 12.0
	sw.damping = 3.5
	sw.max_angle = 60.0
	sw.position = pos_vox * VOXEL
	root.add_child(sw)
	var cv := VoxCanvas.new(Vector3i(-4, -10, -3), Vector3i(3, 2, 6))
	for i in 14:
		var h := VoxCanvas.h1(i + 5)
		var a := i * TAU / 14.0
		var dx := cos(a) * 2.0
		var dz := sin(a) * 2.0 + 1.0
		var ln := 5 + h % 4
		for k in ln:
			var p := Vector3(dx * (1.0 + k * 0.15), -k - 0.5, dz * (1.0 + k * 0.12) + k * 0.3)
			cv.put(int(floor(p.x)), int(floor(p.y)), int(floor(p.z)), VoxCanvas.tone(col, 0.85 + 0.25 * float(h & 3) / 3.0))
	cv.box(Vector3i(-2, -1, -1), Vector3i(1, 1, 2), VoxCanvas.tone(col, 0.9))
	_add_mesh(sw, cv)


## 字形（7×7），用于旗面
const GLYPHS := {
	"fire": ["...#...", "#..#..#", ".#.#.#.", "...#...", "..#.#..", ".#...#.", "#.....#"],
	"metal": ["...#...", "..#.#..", ".#####.", "...#...", ".#####.", ".#.#.#.", "#######"],
	"wood": ["...#...", "#######", "...#...", "..###..", ".#.#.#.", "#..#..#", "...#..."],
	"water": ["...#...", "...#.#.", "##.##..", ".#.#...", ".#.##..", "#..#.#.", "..##..#"],
	"earth": ["...#...", "...#...", ".#####.", "...#...", "...#...", "...#...", "#######"],
	"none": ["...#...", "..#.#..", ".#...#.", "#.###.#", "...#...", "..#.#..", ".#...#."],
}


## 旗面：挂在枪杆上（沿 -Z 方向从 z0 起向枪尾延伸），向本地 -Y 下垂；金边、菱形金框与字、火焰边
static func _banner(root: Node3D, v: Dictionary, z0: int, gold: Color, gc: Color) -> void:
	var flag := CharacterBuilder.col(v.get("flag", "#c81e1e"), Color("c81e1e"))
	var elem := str(v.get("glow", "none"))
	var W := 20      # 沿杆方向
	var H := 30      # 下垂长度
	var sw := WeaponSway.new()
	sw.name = "Banner"
	sw.mode = "hinge"
	sw.stiffness = 7.0
	sw.damping = 3.0
	sw.max_angle = 70.0
	sw.flutter = 4.0
	sw.position = Vector3(0, -1.0, z0) * VOXEL
	root.add_child(sw)
	var flame := gc.a > 0
	var cv := VoxCanvas.new(Vector3i(-3, -H - 12, -2), Vector3i(2, 2, W + 12))
	var ghi := gold.lerp(Color(1, 0.97, 0.85), 0.45)
	var dark := VoxCanvas.tone(flag, 0.72)
	# 旗面（z 0..W-1 沿杆向后，y 0..-H+1 向下），带轻微波浪（x 方向起伏）
	for z in range(0, W):
		var wave := int(round(sin(z * 0.45) * 0.8))
		for yi in range(0, H):
			var y := -yi
			var col := VoxCanvas.tone(flag, 0.95 + 0.1 * float(VoxCanvas.h3(z, yi, 1) & 1))
			if yi % 7 == 6:
				col = VoxCanvas.tone(flag, 0.88)
			# 金边（2 格）+ 暗红内线
			var bz := mini(z, W - 1 - z)
			var by := mini(yi, H - 1 - yi)
			var b := mini(bz, by)
			if b == 0:
				col = gold
			elif b == 1:
				col = dark
			elif b == 2 and (z == 2 or z == W - 3 or yi == 2 or yi == H - 3):
				col = VoxCanvas.tone(gold, 0.85)
			cv.put(wave, y, z, col)
	# 挂环（金）
	for z in [1, W / 2, W - 2]:
		cv.box(Vector3i(-1, 0, z), Vector3i(0, 1, z), gold)
		cv.put(-1, 2, z, ghi)
		cv.put(0, 2, z, ghi)
	# 菱形金框 + 字
	var cz := W / 2
	var cy := -H / 2 + 1
	var R := 8
	for z in range(0, W):
		for yi in range(0, H):
			var y := -yi
			var d := absi(z - cz) + absi(y - cy)
			if d == R or d == R - 1:
				var wave2 := int(round(sin(z * 0.45) * 0.8))
				var fc2 := gold if d == R else VoxCanvas.tone(gold, 0.8)
				cv.put(wave2 - 1, y, z, fc2)
				cv.put(wave2 + 1, y, z, fc2)
	var glyph: Array = GLYPHS.get(elem, GLYPHS["none"])
	for r in 7:
		var row: String = glyph[r]
		for k in 7:
			if row.substr(k, 1) == "#":
				var z2 := cz - 3 + k
				var y2 := cy + 3 - r
				var wave3 := int(round(sin(z2 * 0.45) * 0.8))
				var gcol := VoxelGrid.glow(ghi, 0.15) if flame else gold
				cv.put(wave3 - 1, y2, z2, gcol)
				# 背面镜像（从另一侧看字不反）
				var z3 := cz + 3 - k
				cv.put(int(round(sin(z3 * 0.45) * 0.8)) + 1, y2, z3, gcol)
	# 火焰边：沿下缘与靠枪头一侧（z=0 边）向外窜出的发光火舌（前后两层，长短交错）
	if flame:
		var fc := [Color("a01808"), Color("e0400c"), Color("ff7a18"), Color("ffc030"), Color("fff0a0")]
		for i in range(0, W + H):
			for layer: int in [0, 1]:
				var h := VoxCanvas.h1(i * 7 + 3 + layer * 101)
				var ln := 3 + h % 8 + (3 if (h >> 5) % 4 == 0 else 0)
				if layer == 1 and h % 2 == 0:
					continue
				var base: Vector3
				var dir: Vector3
				if i < W:
					base = Vector3(0, -H + 1, i)
					dir = Vector3(0, -1, 0.45).normalized()
				else:
					var yi2 := i - W
					base = Vector3(0, -yi2, 0)
					dir = Vector3(0, -0.35, -1).normalized()
				var px0 := int(round(sin(base.z * 0.45) * 0.8)) + (layer * 2 - 1 if layer == 1 else 0)
				for k in ln:
					var t := float(k) / float(ln)
					var p := base + dir * (k + 1) + Vector3(0, 0, sin(k * 0.9 + i) * 0.5)
					var ci := clampi(int(t * 4.6), 0, 4)
					var col2: Color = fc[ci]
					cv.put(px0, int(floor(p.y)), int(floor(p.z)), VoxelGrid.glow(col2, 0.3 + 0.65 * t))
	else:
		# 无元素：金色流苏下缘
		for z in range(0, W):
			if z % 2 == 0:
				cv.put(0, -H, z, gold)
				cv.put(0, -H - 1, z, ghi)
	_add_mesh(sw, cv)
	# 火星（静态点缀）
	if flame:
		var sp := VoxCanvas.new(Vector3i(-2, -H - 16, -4), Vector3i(2, 0, W + 8))
		for i in 7:
			var h2 := VoxCanvas.h1(i * 11 + 1)
			sp.put(0, -H - 4 - h2 % 10, 2 + (h2 >> 4) % (W - 2), VoxelGrid.glow(Color("ffc040"), 1.0))
		_add_mesh(sw, sp, "Sparks")


# ================================================================ 拳套

static func _build_fist(root: Node3D, v: Dictionary, hand: String) -> void:
	var det := detail_of(v)
	var gc := glow_color(v)
	var metal := v.has("guard") or det >= 2
	var guard := CharacterBuilder.col(v.get("guard", "#c89a30"), Color("c89a30"))
	var grip := CharacterBuilder.col(v.get("grip", "#e8e0d0"), Color("e8e0d0"))
	var wrap := grip if not metal else CharacterBuilder.col(v.get("grip", "#4a2a1a"), Color("4a2a1a"))
	# 拳套：包住拳头（拳心在原点，女 5³ / 男 6³ 的拳头）与手腕；宽 7（x -3..3，半格居中）
	var cv := VoxCanvas.new(Vector3i(-5, -7, -5), Vector3i(5, 9, 5))
	cv.shift = Vector3(-0.5, 0, -0.5)
	for y in range(-4, 7):
		for z in range(-3, 4):
			for x in range(-3, 4):
				var shell := x == -3 or x == 3 or z == -3 or z == 3 or y == -4
				if not shell:
					continue
				var k := posmod(y + (x + z + 6) / 3, 3)
				var col := wrap if k > 0 else VoxCanvas.tone(wrap, 0.8)
				if k == 1:
					col = VoxCanvas.tone(wrap, 1.05)
				cv.put(x, y, z, col)
	# 腕口内衬（空手展示时不显得中空；佩戴时被小臂遮住）
	for z in range(-2, 3):
		for x in range(-2, 3):
			cv.put(x, 5, z, VoxCanvas.tone(wrap, 0.45))
	# 指缝（掌心一侧，-X）
	for y in [-3, -1, 1]:
		for z in range(-2, 3):
			cv.put(-3, y, z, VoxCanvas.tone(wrap, 0.7))
	if metal:
		var ghi := guard.lerp(Color(1, 0.97, 0.85), 0.45)
		var gsh := VoxCanvas.tone(guard, 0.65)
		# 手背护板（外侧 +X）
		for y in range(-3, 4):
			for z in range(-2, 3):
				cv.put(4, y, z, guard if (y + z) % 3 != 0 else gsh)
		for z in range(-2, 3):
			cv.put(4, 4, z, ghi)
		# 指节护甲（拳面：下方）+ 凸钉
		for z in range(-3, 4):
			for x in range(-3, 4):
				cv.put(x, -5, z, guard if (x + z) % 2 == 0 else gsh)
		for x in [-2, 0, 2]:
			cv.put(x, -6, -1, ghi)
			cv.put(x, -6, 1, ghi)
		# 腕甲
		for z in range(-4, 5):
			for x in range(-4, 5):
				if x == -4 or x == 4 or z == -4 or z == 4:
					cv.put(x, 5, z, guard)
					cv.put(x, 6, z, ghi)
		var gem_c := gc if gc.a > 0 else Color("e8283a")
		cv.put(5, 0, 0, VoxelGrid.glow(gem_c, 0.5))
		cv.put(5, 1, 0, VoxelGrid.glow(gem_c.darkened(0.2), 0.4))
		if gc.a > 0:
			for x in [-2, 0, 2]:
				cv.put(x, -6, -1, VoxelGrid.glow(gc.lightened(0.2), 0.9))
			cv.put(4, 2, -2, VoxelGrid.glow(gc, 0.8))
			cv.put(4, -2, 2, VoxelGrid.glow(gc, 0.8))
	else:
		# 红绳绑扎于腕
		var cord := Color("c02028")
		for z in range(-3, 4):
			for x in range(-3, 4):
				if x == -3 or x == 3 or z == -3 or z == 3:
					cv.put(x, 5, z, cord)
		cv.put(3, 4, -4, cord)
		cv.put(3, 3, -4, cord.lightened(0.15))
	var mi := _add_mesh(root, cv)
	if hand == "l":
		mi.scale = Vector3(-1, 1, 1)
	root.set_meta("tip_length", 0.12)
