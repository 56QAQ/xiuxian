class_name FacePainter
## 头部绘制（2× 精度）：颈、头颅（32³，削棱 + 收下颌）、五官（动漫眼、眉、鼻、唇、腮红）、额心花钿、人耳/尖耳、
## 闭眼（眨眼）贴片。头网格前面为 z=-16 面（面朝 -Z）；脸部行 y 4..35（4 = 下巴，35 = 头顶）。
##
## 眼睛为程序化生成：每种眼型给出“上睑线行 top[] / 下睑线行 bot[]”（按列，从内眼角到外眼角；
## 行 0 = 眼框顶 y=EYE_TOP，向下增加）、虹膜/瞳孔椭圆、外眼角睫毛翼。由此绘出：
##   上睫毛线（外侧加粗 2 行）+ 睫毛翼 + 双眼皮褶线、眼白（上睑下阴影）、
##   虹膜（上暗下亮三段渐变 + 暗色虹膜环 + 下部亮斑）、竖椭圆瞳孔、两个高光（大：上外，小：下内）、下睑线与下睫毛。
## 注意：会在工作线程中调用，表格一律用 static var。

const EYE_TOP := 21       ## 眼框顶行 y
const EYE_INNER := -5     ## 左眼（-X 侧）内眼角 x；右眼镜像

## 眼型（女）：W 宽；top/bot 每列的上/下睑线行；ic 虹膜中心（列, 行）、ir 半径；pr 瞳孔半径；wing 睫毛翼 [列, 行]
static var EYE_SHAPES: Dictionary = {
	"almond": {"W": 10, "top": [5, 4, 3, 2, 1, 1, 1, 1, 1, 2], "bot": [7, 8, 9, 9, 9, 9, 9, 9, 8, 6],
		"ic": Vector2(4.7, 5.3), "ir": Vector2(3.35, 4.4), "pr": Vector2(1.25, 2.0), "wing": [[10, 1], [11, 0], [10, 2]]},
	"round": {"W": 10, "top": [4, 2, 1, 1, 0, 0, 0, 0, 1, 2], "bot": [7, 9, 10, 10, 10, 10, 10, 10, 9, 7],
		"ic": Vector2(4.6, 5.4), "ir": Vector2(3.7, 4.8), "pr": Vector2(1.35, 2.1), "wing": [[10, 2], [10, 3]]},
	"sharp": {"W": 11, "top": [5, 4, 4, 3, 3, 2, 2, 2, 1, 1, 0], "bot": [6, 7, 8, 8, 8, 8, 8, 7, 7, 5, 3],
		"ic": Vector2(4.9, 5.2), "ir": Vector2(3.1, 3.7), "pr": Vector2(1.1, 1.8), "wing": [[11, -1], [12, -2], [11, 0]]},
	"droopy": {"W": 10, "top": [3, 2, 1, 1, 1, 1, 1, 2, 3, 4], "bot": [7, 8, 9, 9, 9, 9, 9, 9, 9, 8],
		"ic": Vector2(4.4, 5.6), "ir": Vector2(3.45, 4.5), "pr": Vector2(1.25, 2.0), "wing": [[10, 5], [10, 6]]},
}

## 眉形（从内到外 12 列）：每列 [底行偏移, 厚度]，底行相对 EYE_TOP+3
static var BROWS: Array = [
	[[1, 2], [1, 2], [1, 2], [2, 2], [2, 2], [2, 2], [2, 2], [2, 1], [2, 1], [1, 1], [1, 1], [0, 1]],   # 平眉
	[[0, 3], [0, 3], [1, 3], [1, 3], [2, 3], [2, 2], [3, 2], [3, 2], [4, 2], [4, 1], [5, 1], [5, 1]],   # 剑眉
	[[0, 1], [1, 2], [2, 2], [2, 2], [3, 2], [3, 1], [3, 1], [3, 1], [2, 1], [2, 1], [1, 1], [0, 1]],   # 柳叶眉
]


## 男式眉（更平直、眉尾上挑）
static var BROWS_M: Array = [
	[[0, 2], [0, 2], [0, 2], [0, 2], [0, 2], [0, 2], [1, 2], [1, 2], [1, 2], [1, 1], [1, 1], [1, 1]],   # 平眉
	[[0, 2], [0, 3], [0, 3], [1, 3], [1, 2], [2, 2], [2, 2], [3, 2], [3, 2], [4, 1], [4, 1], [5, 1]],   # 剑眉
	[[0, 1], [0, 2], [1, 2], [1, 2], [1, 2], [2, 2], [2, 2], [2, 1], [2, 1], [1, 1], [1, 1], [0, 1]],   # 柳叶眉
]


static func paint_head(cv: VoxCanvas, s: CharSpec) -> void:
	cv.set_mat(VoxCanvas.M_SKIN)
	# 颈（略靠后，前缘有下巴投影）
	var hn := s.neck_w / 2
	cv.box(Vector3i(-hn, -3, -hn + 1), Vector3i(hn - 1, 5, hn), s.skin_sh)
	for x in range(-hn, hn):
		cv.put(x, 4, -hn + 1, s.skin_dk.lerp(s.skin_sh, 0.4))
		cv.put(x, 3, -hn + 1, s.skin_dk.lerp(s.skin_sh, 0.7))
	# 头颅
	cv.box(Vector3i(-16, 4, -16), Vector3i(15, 35, 15), s.skin)
	# 竖棱削角（后侧大、前侧小）
	for y in range(4, 36):
		for k in 2:
			cv.clear_at(-16 + k, y, 15 - (1 - k))
			cv.clear_at(15 - k, y, 15 - (1 - k))
		cv.clear_at(-16, y, -16)
		cv.clear_at(15, y, -16)
	# 下颌收窄：下部几行向内收（女性更尖）
	var taper: Array = [5, 4, 3, 2, 1, 1] if s.female else [3, 2, 2, 1, 1, 0]
	for i in taper.size():
		var y := 4 + i
		var t: int = taper[i]
		for z in range(-16, 2):
			for k in t:
				cv.clear_at(-16 + k, y, z)
				cv.clear_at(15 - k, y, z)
		# 下巴底面前缘再削一格
		if i == 0:
			for x in range(-16, 16):
				cv.clear_at(x, 4, -16)
	# 脸颊边缘略暗（圆润感），下巴下缘阴影
	for y in range(5, 30):
		var e0 := 0
		var e1 := 0
		for x in range(-16, 0):
			if cv.solid(x, y, -16):
				e0 = x
				break
		for x in range(15, -1, -1):
			if cv.solid(x, y, -16):
				e1 = x
				break
		cv.put(e0, y, -16, s.skin.lerp(s.skin_sh, 0.3))
		cv.put(e1, y, -16, s.skin.lerp(s.skin_sh, 0.3))
	for x in range(-12, 12):
		if cv.solid(x, 5, -16):
			cv.put(x, 5, -16, s.skin.lerp(s.skin_sh, 0.25))
		elif cv.solid(x, 5, -15):
			cv.put(x, 5, -15, s.skin.lerp(s.skin_sh, 0.25))
	paint_face(cv, s)


static func paint_face(cv: VoxCanvas, s: CharSpec) -> void:
	paint_eyes(cv, s, -16)
	# 眉
	var bstyle := clampi(int(s.a.get("brow_style", 0)), 0, 2)
	var brow: Array = BROWS[bstyle] if s.female else BROWS_M[bstyle]
	cv.set_mat(VoxCanvas.M_HAIR)
	var bc := s.brow
	var bhi := s.brow.lerp(s.hair, 0.5)
	var by0 := EYE_TOP + 3 + (0 if s.female else -1)
	for side: int in [-1, 1]:
		for j in brow.size():
			var spec: Array = brow[j]
			var th: int = spec[1]
			var x := EYE_INNER + 1 - j
			if side > 0:
				x = -1 - x
			for k in th:
				var yy := by0 + int(spec[0]) + k
				cv.put(x, yy, -16, bc if k < th - 1 or th == 1 else bhi)
	cv.set_mat(VoxCanvas.M_SKIN)
	# 鼻：极小的鼻尖凸起（受光面亮、下方有 AO 阴影）+ 侧影
	cv.put(-1, 11, -17, s.skin_hi)
	cv.put(0, 11, -17, s.skin.lerp(s.skin_sh, 0.2))
	cv.put(0, 10, -16, s.skin.lerp(s.skin_sh, 0.45))
	cv.put(-1, 12, -16, s.skin_hi)
	# 口
	if s.female:
		cv.put(-3, 8, -16, s.skin.lerp(s.lip, 0.3))
		cv.put(-2, 8, -16, s.lip.darkened(0.12))
		cv.put(-1, 8, -16, s.lip.darkened(0.25))
		cv.put(0, 8, -16, s.lip.darkened(0.25))
		cv.put(1, 8, -16, s.lip.darkened(0.12))
		cv.put(2, 8, -16, s.skin.lerp(s.lip, 0.3))
		cv.put(-1, 7, -16, s.lip.lightened(0.12))
		cv.put(0, 7, -16, s.lip.lightened(0.08))
	else:
		var ml := s.skin.lerp(Color(0.55, 0.3, 0.28), 0.55)
		for x in range(-3, 3):
			cv.put(x, 8, -16, ml if absi(x * 2 + 1) < 5 else s.skin.lerp(ml, 0.45))
		cv.put(-1, 7, -16, s.skin.lerp(s.skin_sh, 0.3))
		cv.put(0, 7, -16, s.skin.lerp(s.skin_sh, 0.3))
	# 腮红：柔和椭圆 + 三道斜线
	var bl_amt := 1.0 if s.female else 0.35
	for side: int in [-1, 1]:
		var cx := -10.5 if side < 0 else 9.5
		for y in range(9, 13):
			for x in range(int(cx) - 4, int(cx) + 5):
				var dx := (x + 0.5 - cx) / 4.2
				var dy := (y + 0.5 - 10.8) / 1.9
				var d := dx * dx + dy * dy
				if d <= 1.0 and cv.solid(x, y, -16) and cv.get_mat(x, y, -16) == VoxCanvas.M_SKIN:
					cv.put(x, y, -16, s.skin.lerp(s.blush, (0.75 - d * 0.45) * bl_amt))
		if s.female:
			for k in 3:
				var x0 := int(cx) - 2 + k * 2
				cv.put(x0, 10, -16, s.blush.darkened(0.08))
				cv.put(x0 + 1, 11, -16, s.blush.darkened(0.04))
	# 额心花钿
	paint_mark(cv, s, str(s.a.get("mark", "none")))


## 眼睛：z 为绘制平面（脸面 -16；闭眼贴片 0）
static func paint_eyes(cv: VoxCanvas, s: CharSpec, z: int) -> void:
	var sh: Dictionary = EYE_SHAPES.get(s.eye_style, EYE_SHAPES["almond"])
	var W: int = sh["W"]
	var top: Array = (sh["top"] as Array).duplicate()
	var bot: Array = (sh["bot"] as Array).duplicate()
	var ic: Vector2 = sh["ic"]
	var ir: Vector2 = sh["ir"]
	var pr: Vector2 = sh["pr"]
	if not s.female:
		# 男：眼高收窄、虹膜略小
		for j in W:
			top[j] = int(top[j]) + (1 if j >= 2 and j <= W - 3 else 0)
			bot[j] = int(bot[j]) - (1 if j >= 1 and j <= W - 2 else 0)
		ir *= 0.9
		pr *= 0.9
		ic.y += 0.3
	var ec := s.eye
	var c_lash := s.lash
	var c_lash2 := s.lash.lerp(s.skin, 0.35)
	var c_lashr := s.lash.lerp(Color(0.6, 0.25, 0.25), 0.45).lerp(s.skin, 0.25)
	var c_w := Color(0.97, 0.96, 0.95)
	var c_ws := Color(0.8, 0.8, 0.9)
	var c_d := Color(ec.r * 0.34, ec.g * 0.28, ec.b * 0.34)
	var c_m := ec.lerp(c_d, 0.45)
	var c_i := ec
	var c_b := _iris_light(ec)
	var c_ring := Color(ec.r * 0.22, ec.g * 0.18, ec.b * 0.24)
	var c_p := Color(ec.r * 0.12, ec.g * 0.08, ec.b * 0.12)
	var c_crease := s.skin.lerp(s.skin_dk, 0.35)
	for side: int in [-1, 1]:
		for j in W:
			var x := EYE_INNER - j
			if side > 0:
				x = -1 - x
			var tr: int = top[j]
			var br: int = bot[j]
			# 双眼皮褶线（女性，中段）
			if s.female and j >= 3 and j <= W - 2:
				cv.putm(x, EYE_TOP - tr + 3, z, c_crease, VoxCanvas.M_SKIN)
			# 上睫毛线：外侧两行
			cv.putm(x, EYE_TOP - tr, z, c_lash, VoxCanvas.M_HAIR)
			if j >= 3 or (s.female and j >= 2):
				cv.putm(x, EYE_TOP - tr + 1, z, c_lash if j >= 4 else c_lash2, VoxCanvas.M_HAIR)
			# 睁开的部分
			for r in range(tr + 1, br):
				var y := EYE_TOP - r
				var dx := (j + 0.5 - ic.x) / ir.x
				var dy := (r + 0.5 - ic.y) / ir.y
				var d2 := dx * dx + dy * dy
				var c := c_w
				if d2 <= 1.0:
					# 虹膜：上暗 → 中 → 下亮；边缘暗环
					var t := clampf((r + 0.5 - (ic.y - ir.y)) / (2.0 * ir.y), 0.0, 1.0)
					if t < 0.3:
						c = c_d
					elif t < 0.55:
						c = c_m
					elif t < 0.78:
						c = c_i
					else:
						c = c_b
					if d2 > 0.72:
						c = c.lerp(c_ring, 0.55)
					var px := (j + 0.5 - ic.x) / pr.x
					var py := (r + 0.5 - (ic.y - 0.3)) / pr.y
					if px * px + py * py <= 1.0:
						c = c_p
				elif r == tr + 1:
					c = c_ws
				cv.putm(x, y, z, c, VoxCanvas.M_EYE)
			# 下睑：内侧淡、外侧有下睫毛
			var lc := s.skin.lerp(s.skin_dk, 0.35) if j < W / 2 else c_lashr
			if s.female or j >= W / 2:
				cv.putm(x, EYE_TOP - br, z, lc, VoxCanvas.M_SKIN)
		# 高光：大（上外 2×2）+ 小（下内 1 格），以及虹膜下部亮点
		var hx := int(floor(ic.x + 1.1))
		var hy := int(floor(ic.y - 2.4))
		for k in 4:
			var j2 := hx + (k & 1)
			var r2 := hy + (k >> 1)
			if r2 > int(top[clampi(j2, 0, W - 1)]):
				_put_side(cv, side, j2, r2, z, Color(1, 1, 1, 0.9) if k != 3 else Color(0.92, 0.94, 1.0, 0.92))
		var sx2 := int(floor(ic.x - 1.8))
		var sy2 := int(floor(ic.y + 2.2))
		_put_side(cv, side, sx2, sy2, z, Color(1, 1, 1, 0.94))
		_put_side(cv, side, int(floor(ic.x + 0.6)), int(floor(ic.y + ir.y - 1.2)), z, c_b.lightened(0.35))
		# 睫毛翼
		for wpt in sh["wing"]:
			var wj: int = wpt[0]
			var wr: int = wpt[1] + (1 if not s.female else 0)
			if not s.female and wj > W:
				continue
			var x3 := EYE_INNER - wj
			if side > 0:
				x3 = -1 - x3
			cv.putm(x3, EYE_TOP - wr, z, c_lash, VoxCanvas.M_HAIR)
		# 外侧上方两根分叉睫毛（女）
		if s.female:
			var tj := W - 3
			var x4 := EYE_INNER - tj
			if side > 0:
				x4 = -1 - x4
			cv.putm(x4, EYE_TOP - int(top[tj]) + 2, z, c_lash2, VoxCanvas.M_HAIR)


static func _put_side(cv: VoxCanvas, side: int, j: int, r: int, z: int, c: Color) -> void:
	var x := EYE_INNER - j
	if side > 0:
		x = -1 - x
	if cv.get_mat(x, EYE_TOP - r, z) == VoxCanvas.M_EYE:
		cv.putm(x, EYE_TOP - r, z, c, VoxCanvas.M_EYE)


## 虹膜下部亮色：暖色偏金黄，冷色提亮，暗色（黑瞳）偏灰蓝
static func _iris_light(ec: Color) -> Color:
	if ec.v < 0.35:
		return ec.lerp(Color(0.62, 0.64, 0.76), 0.45)
	if ec.h < 0.17 or ec.h > 0.93:
		return ec.lerp(Color(1.0, 0.95, 0.6), 0.42)
	return ec.lightened(0.36)


static func paint_mark(cv: VoxCanvas, s: CharSpec, mark: String) -> void:
	var mc := s.mark_color
	var hi := mc.lightened(0.3)
	var sh := mc.darkened(0.25)
	cv.set_mat(VoxCanvas.M_CLOTH)
	var y0 := 27
	var pal := {"m": mc, "h": hi, "s": sh, "g": VoxCanvas.glow(mc.lightened(0.35), 0.45), "G": VoxCanvas.glow(Color(1.0, 0.95, 0.7), 0.7)}
	var rows: Array = []
	match mark:
		"dot":
			rows = [".mm.", "mhmm", "mmms", ".ss."]
		"lotus":
			rows = ["...h...", "..mhm..", "h.mmm.h", "mm.m.mm", ".mmmmm.", "..sss.."]
		"flame":
			rows = ["...m..", "..mh..", ".m.hm.", ".mhgm.", "mhggm.", ".mGGm.", "..mm.."]
		"crescent":
			rows = [".hmm.", "hm...", "m....", "mm...", ".smm."]
		"tear":
			rows = ["..h..", ".mhm.", ".mmm.", "mmgmm", ".mms."]
		_:
			return
	var w: int = (rows[0] as String).length()
	var x0 := -(w / 2)
	cv.stamp(rows, pal, Vector3i(x0, y0 + rows.size() - 1, -16), Vector3i(1, 0, 0), Vector3i(0, -1, 0))
	cv.set_mat(VoxCanvas.M_SKIN)


## 人耳 / 尖耳（画在头网格上，发型之前绘制，发型可覆盖）
static func paint_ears(cv: VoxCanvas, s: CharSpec, ears: String) -> void:
	var sk := s.skin
	var sh := s.skin_sh
	cv.set_mat(VoxCanvas.M_SKIN)
	match ears:
		"human":
			for side: int in [-1, 1]:
				var x := -17 if side < 0 else 16
				cv.box(Vector3i(x, 14, -2), Vector3i(x, 21, 3), sk)
				cv.box(Vector3i(x + side, 15, -1), Vector3i(x + side, 20, 2), sk)
				for y in range(16, 20):
					cv.put(x + side, y, 0, sh)
					cv.put(x + side, y, 1, s.skin_dk.lerp(sh, 0.5))
		"elf":
			for side: int in [-1, 1]:
				for k in 12:
					var x := (-17 - k) if side < 0 else (16 + k)
					var y0 := 14 + k / 2
					var y1 := 20 + k
					if k >= 8:
						y0 = 18 + k / 2
					var c := sk if k < 10 else sk.lerp(sh, 0.3)
					cv.box(Vector3i(x, y0, 0), Vector3i(x, mini(y1, 32), 2), c)
					if k > 1 and k < 9:
						cv.box(Vector3i(x, y0 + 2, 0), Vector3i(x, y1 - 2, 0), sh.lerp(s.skin_dk, 0.3))
				# 耳饰：小金环
				var xr := -19 if side < 0 else 18
				cv.putm(xr, 14, 1, s.gold, VoxCanvas.M_GOLD)
				cv.putm(xr, 13, 1, s.gold_hi, VoxCanvas.M_GOLD)
				cv.putm(xr, 12, 1, s.gem, VoxCanvas.M_GEM)


## 闭眼贴片：与眼睛同位置的皮肤 + 闭合睫毛弧线（由 HumanoidRig 眨眼时显示）
static func paint_blink(cv: VoxCanvas, s: CharSpec) -> void:
	var sh: Dictionary = EYE_SHAPES.get(s.eye_style, EYE_SHAPES["almond"])
	var W: int = sh["W"]
	var top: Array = sh["top"]
	var bot: Array = sh["bot"]
	for side: int in [-1, 1]:
		for j in W:
			var x := EYE_INNER - j
			if side > 0:
				x = -1 - x
			var tr: int = top[j]
			var br: int = bot[j]
			for r in range(tr, br + 1):
				cv.putm(x, EYE_TOP - r, 0, s.skin, VoxCanvas.M_SKIN)
			# 闭合线：沿下睑上方 2 行，外侧加粗
			var lr := br - 2
			cv.putm(x, EYE_TOP - lr, 0, s.lash, VoxCanvas.M_HAIR)
			if j >= W / 2 and s.female:
				cv.putm(x, EYE_TOP - lr + 1, 0, s.lash.lerp(s.skin, 0.4), VoxCanvas.M_HAIR)
		# 外眼角小翼
		var x2 := EYE_INNER - W
		if side > 0:
			x2 = -1 - x2
		cv.putm(x2, EYE_TOP - int(bot[W - 1]) + 1, 0, s.lash, VoxCanvas.M_HAIR)
