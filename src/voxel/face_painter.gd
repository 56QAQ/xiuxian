class_name FacePainter
## 头部绘制：颈、头颅（16³）、五官（眼、眉、口、腮红）、额心花钿、人耳/尖耳、闭眼（眨眼）贴片。
## 头网格前面为 z=-8 面（面朝 -Z）；fy = y - 2 为脸部行号（0 = 下巴，15 = 头顶）。
## 眼睛图案按“角色左眼（-X 侧，正视时位于画面右侧）”书写：字符串从内眼角到外眼角，行从上到下。
##   L 睫毛  l 淡睫毛  W 眼白  D 虹膜暗部  I 虹膜  B 虹膜亮部  P 瞳孔  H 高光  s 下眼睑阴影  . 不绘制

const EYES := {
	"almond": [
		"lLLLLL",
		"WDDHD.",
		"WIPPI.",
		".IBBI.",
		"..ss..",
	],
	"round": [
		".lLLl.",
		"LDHDDL",
		"WIPPIW",
		"WIBBHW",
		".BBBB.",
	],
	"sharp": [
		"...LLL",
		"lLDHDL",
		"WIPPB.",
		".sss..",
	],
	"almond_m": [
		"lLLLL",
		"WDHDL",
		"WIPB.",
		".sss.",
	],
	"round_m": [
		".lLLl",
		"LDHDL",
		"WIPIW",
		".BBB.",
	],
	"sharp_m": [
		".lLLLL",
		"lDHDL.",
		"WIPB..",
		"..ss..",
	],
}

## 眉形（从内到外；第一行在眼睛上方 2 格，第二行上方 1 格；b 眉毛）
const BROWS := [
	[".bbbb.", "......"],
	["bbbbb", "....."],
	["..bbbb", "bbb..."],
]
const BROWS_M := [
	[".bbbbb", "b....."],
	["bbbbbb", "......"],
	["...bbbb", "bbbb..."],
]


static func paint_head(cv: VoxCanvas, s: CharSpec) -> void:
	# 颈
	var hn := s.neck_w / 2
	cv.box(Vector3i(-hn, -1, -hn), Vector3i(hn - 1, 2, hn - 1), s.skin_sh, 0.02)
	# 头颅
	cv.box(Vector3i(-8, 2, -8), Vector3i(7, 17, 7), s.skin)
	# 脸下缘略暗（下巴阴影），下颌圆角
	for x in range(-8, 8):
		cv.put(x, 2, -8, VoxCanvas.tone(s.skin, 0.97))
	cv.clear_at(-8, 2, -8)
	cv.clear_at(7, 2, -8)
	if s.female:
		cv.clear_at(-8, 3, -8)
		cv.clear_at(7, 3, -8)
		cv.clear_at(-8, 2, -7)
		cv.clear_at(7, 2, -7)
	paint_face(cv, s)


static func paint_face(cv: VoxCanvas, s: CharSpec) -> void:
	var ap := s.a
	var style := str(ap.get("eye_style", "almond"))
	if not EYES.has(style):
		style = "almond"
	var pat: Array = EYES[style + ("" if s.female else "_m")]
	var ec := s.eye
	# 虹膜渐变：上暗下亮（亮部偏暖）
	var cols := {
		"L": s.lash,
		"l": s.lash.lerp(s.skin, 0.35),
		"W": Color(0.97, 0.96, 0.95),
		"D": Color(ec.r * 0.42, ec.g * 0.36, ec.b * 0.40),
		"I": ec,
		"B": _iris_light(ec),
		"P": Color(ec.r * 0.28, ec.g * 0.2, ec.b * 0.22),
		"H": Color(1, 1, 1),
		"s": s.skin.lerp(s.skin_sh, 0.55),
	}
	var inner := -3
	var top := 10  # 眼睛第一行（睫毛）的 y
	for side: int in [-1, 1]:
		for r in pat.size():
			var row: String = pat[r]
			for j in row.length():
				var ch := row.substr(j, 1)
				if ch == ".":
					continue
				var x := inner - j
				if side > 0:
					x = -1 - x
				cv.put(x, top - r, -8, cols[ch])
	# 眉
	var bstyle := clampi(int(ap.get("brow_style", 0)), 0, 2)
	var brow: Array = (BROWS if s.female else BROWS_M)[bstyle]
	var bc := s.hair.darkened(0.35).lerp(s.lash, 0.3)
	for side: int in [-1, 1]:
		for r in brow.size():
			var row: String = brow[r]
			for j in row.length():
				if row.substr(j, 1) != "b":
					continue
				var x := -2 - j
				if side > 0:
					x = -1 - x
				cv.put(x, top + 2 - r, -8, bc)
	# 口
	var mouth := Color(0.72, 0.32, 0.34) if s.female else Color(0.62, 0.34, 0.32)
	if s.female:
		cv.put(-1, 4, -8, mouth)
		cv.put(0, 4, -8, s.skin.lerp(mouth, 0.45))
	else:
		cv.put(-2, 4, -8, s.skin.lerp(mouth, 0.4))
		cv.put(-1, 4, -8, mouth)
		cv.put(0, 4, -8, mouth)
		cv.put(1, 4, -8, s.skin.lerp(mouth, 0.4))
	# 鼻（极淡的阴影）
	cv.put(0, 6, -8, s.skin.lerp(s.skin_sh, 0.35))
	# 腮红
	if s.female:
		var blush := s.skin.lerp(Color(1.0, 0.45, 0.5), 0.28)
		for x in [-6, -5, 4, 5]:
			cv.put(x, 5, -8, blush)
	# 额心花钿
	paint_mark(cv, s, str(ap.get("mark", "none")))


## 虹膜下部亮色：暖色偏金黄，冷色提亮，暗色（黑瞳）偏灰蓝
static func _iris_light(ec: Color) -> Color:
	if ec.v < 0.35:
		return ec.lerp(Color(0.62, 0.64, 0.76), 0.4)
	if ec.h < 0.17 or ec.h > 0.93:
		return ec.lerp(Color(1.0, 0.95, 0.6), 0.38)
	return ec.lightened(0.32)


static func paint_mark(cv: VoxCanvas, s: CharSpec, mark: String) -> void:
	var mc := s.mark_color
	match mark:
		"dot":
			cv.put(-1, 13, -8, mc)
			cv.put(0, 13, -8, mc)
			cv.put(-1, 14, -8, mc.lightened(0.15))
			cv.put(0, 14, -8, mc.lightened(0.15))
		"lotus":
			# 三瓣莲：中瓣 + 两侧瓣
			var hi := mc.lightened(0.25)
			for p in [[-1, 15], [0, 15], [-1, 14], [0, 14], [-2, 13], [1, 13], [-1, 13], [0, 13], [-3, 14], [2, 14], [-1, 12], [0, 12]]:
				cv.put(p[0], p[1], -8, mc)
			cv.put(-1, 15, -8, hi)
			cv.put(0, 15, -8, hi)
		"flame":
			var g := VoxelGrid.glow(mc.lightened(0.2), 0.35)
			for p in [[-1, 12], [0, 12], [-1, 13], [0, 13], [-2, 14], [0, 14], [-1, 15], [1, 15], [0, 16]]:
				cv.put(p[0], p[1], -8, mc)
			cv.put(-1, 13, -8, g)
			cv.put(0, 13, -8, g)


## 人耳 / 尖耳（画在头网格上，发型之前绘制，发型可覆盖）
static func paint_ears(cv: VoxCanvas, s: CharSpec, ears: String) -> void:
	var sk := s.skin
	var sh := s.skin_sh
	match ears:
		"human":
			for side: int in [-1, 1]:
				var x := -9 if side < 0 else 8
				cv.box(Vector3i(x, 7, -1), Vector3i(x, 10, 1), sk)
				cv.put(x, 8, 0, sh)
				cv.put(x, 9, 0, sh)
		"elf":
			for side: int in [-1, 1]:
				for k in 6:
					var x := (-9 - k) if side < 0 else (8 + k)
					var y0 := 7 + k / 2
					var y1 := 10 + k
					if k >= 4:
						y0 = 9 + k / 2
					cv.box(Vector3i(x, y0, 0), Vector3i(x, mini(y1, 16), 1), sk if k < 5 else sk.lerp(sh, 0.3))
					if k > 0 and k < 4:
						cv.put(x, y0 + 1, 0, sh)


## 闭眼贴片：与眼睛同位置的皮肤 + 睫毛弧线（由 HumanoidRig 眨眼时显示）
static func paint_blink(cv: VoxCanvas, s: CharSpec) -> void:
	var style := str(s.a.get("eye_style", "almond"))
	if not EYES.has(style):
		style = "almond"
	var pat: Array = EYES[style + ("" if s.female else "_m")]
	var inner := -3
	var top := 10
	for side: int in [-1, 1]:
		for r in pat.size():
			var row: String = pat[r]
			for j in row.length():
				var ch := row.substr(j, 1)
				if ch == "." or ch == "s":
					continue
				var x := inner - j
				if side > 0:
					x = -1 - x
				var c := s.skin
				if r == pat.size() - 2 or (r == pat.size() - 3 and ch == "L"):
					c = s.lash
				cv.put(x, top - r, 0, c)
