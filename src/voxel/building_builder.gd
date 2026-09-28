class_name BuildingBuilder
## 中式宫殿建筑部件（基于 BuildingMesh 盒子累加，0.25 米体素对齐）。
## 约定：局部坐标 x 右、y 上、z 后，建筑正面朝 -Z；所有函数在 BuildingMesh 的当前局部坐标下绘制。
## 配色 pal（Dictionary）：roof 瓦、roof2 瓦当/脊、pillar 柱、wall 墙、trim 金饰、beam 彩画、stone 台基、wood 木作、door 门窗。

const V := 0.25

const DEFAULT_PAL := {
	"roof": Color(0.23, 0.25, 0.30),
	"roof2": Color(0.32, 0.34, 0.40),
	"pillar": Color(0.62, 0.14, 0.11),
	"wall": Color(0.92, 0.90, 0.85),
	"trim": Color(0.85, 0.68, 0.30),
	"beam": Color(0.20, 0.42, 0.44),
	"stone": Color(0.66, 0.65, 0.62),
	"stone2": Color(0.56, 0.55, 0.53),
	"wood": Color(0.42, 0.26, 0.16),
	"door": Color(0.48, 0.14, 0.10),
	"lantern": Color(1.0, 0.36, 0.18),
}


static func pal_with(over: Dictionary) -> Dictionary:
	var p := DEFAULT_PAL.duplicate()
	for k in over:
		p[k] = over[k]
	return p


static func col(p: Dictionary, key: String) -> Color:
	return p.get(key, DEFAULT_PAL.get(key, Color.MAGENTA))


static func snap(v: float) -> float:
	return roundf(v / V) * V


# ================================================================ 基础部件

## 石台基：中心 (cx, cz)，宽 w（x）深 d（z），高 h，带压沿石
static func platform(m: BuildingMesh, cx: float, cz: float, w: float, d: float, h: float, p: Dictionary) -> void:
	var s := col(p, "stone")
	var s2 := col(p, "stone2")
	m.box(Vector3(cx - w * 0.5, -0.5, cz - d * 0.5), Vector3(cx + w * 0.5, h - V, cz + d * 0.5), s2, true, true)
	m.box(Vector3(cx - w * 0.5 - V, h - V, cz - d * 0.5 - V), Vector3(cx + w * 0.5 + V, h, cz + d * 0.5 + V), s, true)


## 台阶：前沿中心 (cx, z_front)，向 -Z 延伸；宽 width，总高 height。附斜坡碰撞。
static func stairs(m: BuildingMesh, cx: float, z_front: float, width: float, height: float, p: Dictionary, rails: bool = true) -> void:
	var n := maxi(int(round(height / V)), 1)
	var sd := 0.5
	var s := col(p, "stone")
	for i in n:
		var z0 := z_front - (n - i) * sd
		var z1 := z_front - (n - i - 1) * sd
		m.box(Vector3(cx - width * 0.5, -0.25, z0), Vector3(cx + width * 0.5, (i + 1) * V, z1), s if i % 2 == 0 else s.darkened(0.06), false, true)
	if rails:
		var r := col(p, "stone2")
		for sx in [-1.0, 1.0]:
			var x: float = cx + sx * (width * 0.5 + V * 0.5)
			for i in n:
				var z0 := z_front - (n - i) * sd
				m.box(Vector3(x - V * 0.5, 0, z0), Vector3(x + V * 0.5, (i + 1) * V + 0.5, z0 + sd), r)
	m.ramp(Vector3(cx, 0.0, z_front - n * sd), Vector3(cx, height, z_front), width)


## 柱子（含柱础）
static func pillar(m: BuildingMesh, x: float, z: float, y0: float, h: float, p: Dictionary, size: float = 0.5, collide: bool = true) -> void:
	var s := col(p, "stone")
	m.box(Vector3(x - size * 0.5 - V, y0, z - size * 0.5 - V), Vector3(x + size * 0.5 + V, y0 + V, z + size * 0.5 + V), s)
	m.box(Vector3(x - size * 0.5, y0 + V, z - size * 0.5), Vector3(x + size * 0.5, y0 + h, z + size * 0.5), col(p, "pillar"), collide)


## 吊灯笼（自发光）
static func lantern(m: BuildingMesh, pos: Vector3, p: Dictionary, s: float = 1.0) -> void:
	var lc := VoxelGrid.glow(col(p, "lantern"), 0.85)
	var g := col(p, "trim")
	m.box(pos + Vector3(-0.05, 0.0, -0.05) * s, pos + Vector3(0.05, 0.6, 0.05) * s, Color(0.15, 0.1, 0.08))
	m.box(pos + Vector3(-0.2, -0.1, -0.2) * s, pos + Vector3(0.2, 0.0, 0.2) * s, g)
	m.box(pos + Vector3(-0.3, -0.75, -0.3) * s, pos + Vector3(0.3, -0.1, 0.3) * s, lc)
	m.box(pos + Vector3(-0.2, -0.85, -0.2) * s, pos + Vector3(0.2, -0.75, 0.2) * s, g)
	m.box(pos + Vector3(-0.04, -1.1, -0.04) * s, pos + Vector3(0.04, -0.85, 0.04) * s, Color(0.9, 0.7, 0.2))


## 格栅窗/门扇：在 z=const 平面（厚 V），范围 x0..x1, y0..y1
static func lattice(m: BuildingMesh, x0: float, x1: float, y0: float, y1: float, z: float, frame: Color, fill: Color) -> void:
	m.box(Vector3(x0, y0, z - V * 0.5), Vector3(x1, y1, z + V * 0.5), fill)
	# 外框与横竖棂条（略凸出）
	m.box(Vector3(x0, y0, z - V * 0.7), Vector3(x1, y0 + V * 0.5, z), frame)
	m.box(Vector3(x0, y1 - V * 0.5, z - V * 0.7), Vector3(x1, y1, z), frame)
	var n := maxi(int((x1 - x0) / 0.5), 1)
	for i in n + 1:
		var x := x0 + (x1 - x0) * i / n
		m.box(Vector3(x - 0.05, y0, z - V * 0.7), Vector3(x + 0.05, y1, z), frame)
	var rows := maxi(int((y1 - y0) / 0.5), 1)
	for j in range(1, rows):
		var y := y0 + (y1 - y0) * j / rows
		m.box(Vector3(x0, y - 0.04, z - V * 0.7), Vector3(x1, y + 0.04, z), frame)


# ================================================================ 屋顶

## 庑殿式/攒尖式阶梯屋顶，飞檐翘角。
## (cx, cz) 中心，hw/hd 为檐口外缘半宽/半深，y0 为檐口底，rise 为屋身高度。
## ridge=false 时为攒尖顶（四角收于一点，带宝顶）。skirt>0 时只画下部 skirt 比例（重檐的下檐）。
static func roof(m: BuildingMesh, cx: float, cz: float, hw: float, hd: float, y0: float, rise: float, p: Dictionary,
		ridge: bool = true, skirt: float = 0.0, curl: float = 1.0) -> void:
	var tile := col(p, "roof")
	var tile2 := col(p, "roof2")
	var gold := col(p, "trim")
	var layers := maxi(int(round(rise / V)), 2)
	var min_half := V
	var inset_max := hd - min_half
	var top_layer := layers if skirt <= 0.0 else maxi(int(layers * skirt), 2)
	var hwk := hw
	var hdk := hd
	for k in top_layer:
		var u := float(k) / float(layers)
		var inset := snap(inset_max * (1.0 - pow(1.0 - u, 1.7)))
		hwk = hw - inset
		hdk = hd - inset
		if not ridge:
			hwk = maxf(hwk, V)
		var y := y0 + k * V
		var c := tile if k % 2 == 0 else tile.darkened(0.1)
		if k == 0:
			c = tile2
		m.box(Vector3(cx - hwk, y, cz - hdk), Vector3(cx + hwk, y + V, cz + hdk), c, k < 2 and skirt <= 0.0)
		# 垂脊（四角小方块）
		if k > 0 and k < top_layer - 1:
			for sx in [-1.0, 1.0]:
				for sz in [-1.0, 1.0]:
					var px: float = cx + sx * (hwk - V * 0.5)
					var pz: float = cz + sz * (hdk - V * 0.5)
					m.box(Vector3(px - V * 0.5, y + V, pz - V * 0.5), Vector3(px + V * 0.5, y + 2.0 * V, pz + V * 0.5), tile2)
	# 飞檐：沿檐口靠近四角处逐级抬高，角端沿对角线连续向外上翘
	if curl > 0.0:
		var lift_max := clampf(minf(hw, hd) * 0.14, 0.5, 1.25) * curl
		var n_seg := 5
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				for i in n_seg:
					var t := float(i + 1) / n_seg
					var hh := snap(lift_max * t * t)
					if hh <= 0.0:
						continue
					# 沿 x 边（z = ±hd）
					var len_x: float = hw * 0.45 * (1.0 - t * 0.8)
					var x0: float = cx + sx * hw
					var x1: float = cx + sx * (hw - len_x)
					var zc: float = cz + sz * (hd - V * 0.5)
					m.box(Vector3(minf(x0, x1), y0, zc - V * 0.5), Vector3(maxf(x0, x1), y0 + V + hh, zc + V * 0.5), tile2)
					# 沿 z 边（x = ±hw）
					var len_z: float = hd * 0.45 * (1.0 - t * 0.8)
					var z0: float = cz + sz * hd
					var z1: float = cz + sz * (hd - len_z)
					var xc: float = cx + sx * (hw - V * 0.5)
					m.box(Vector3(xc - V * 0.5, y0, minf(z0, z1)), Vector3(xc + V * 0.5, y0 + V + hh, maxf(z0, z1)), tile2)
				# 角端翘起（相互重叠的方块链）
				var ox: float = cx + sx * (hw - V)
				var oz: float = cz + sz * (hd - V)
				for i in 6:
					var o: float = i * 0.22
					var yb := y0 + lift_max * 0.6 + i * i * 0.05 * curl + i * 0.1
					var sz2 := V * (1.1 - i * 0.08)
					var c2 := tile2 if i < 5 else gold
					m.box(Vector3(ox + sx * o - sz2, yb - V * 0.5, oz + sz * o - sz2), Vector3(ox + sx * o + sz2, yb + V * 1.2, oz + sz * o + sz2), c2)
				m.box(Vector3(ox - V, y0, oz - V), Vector3(ox + V, y0 + lift_max * 0.6 + V, oz + V), tile2)
	if skirt > 0.0:
		return
	var y_top := y0 + top_layer * V
	if ridge:
		# 正脊与鸱吻
		var rw := maxf(hwk, V * 2.0)
		m.box(Vector3(cx - rw - V, y_top, cz - V), Vector3(cx + rw + V, y_top + 2.0 * V, cz + V), tile2)
		m.box(Vector3(cx - rw, y_top + 2.0 * V, cz - V * 0.5), Vector3(cx + rw, y_top + 2.5 * V, cz + V * 0.5), tile)
		for sx in [-1.0, 1.0]:
			var ex: float = cx + sx * (rw + V)
			m.box(Vector3(ex - V, y_top, cz - V), Vector3(ex + V, y_top + 6.0 * V, cz + V), gold)
			m.box(Vector3(ex - sx * V * 2.5 - V * 0.5, y_top + 5.0 * V, cz - V * 0.5), Vector3(ex - sx * V * 0.5 + V * 0.5, y_top + 6.5 * V, cz + V * 0.5), gold)
		# 脊上宝珠
		m.box(Vector3(cx - V, y_top + 2.5 * V, cz - V), Vector3(cx + V, y_top + 4.5 * V, cz + V), gold)
	else:
		# 宝顶
		m.box(Vector3(cx - V * 1.5, y_top, cz - V * 1.5), Vector3(cx + V * 1.5, y_top + V, cz + V * 1.5), gold)
		m.box(Vector3(cx - V, y_top + V, cz - V), Vector3(cx + V, y_top + 4.0 * V, cz + V), gold)
		m.box(Vector3(cx - V * 0.5, y_top + 4.0 * V, cz - V * 0.5), Vector3(cx + V * 0.5, y_top + 7.0 * V, cz + V * 0.5), gold.lightened(0.2))


## 斗拱带：沿矩形（半宽 hw 半深 hd）一圈，高度 y，交替彩色与金色小方块
static func brackets(m: BuildingMesh, cx: float, cz: float, hw: float, hd: float, y: float, p: Dictionary) -> void:
	var beam := col(p, "beam")
	var gold := col(p, "trim")
	var wood := col(p, "wood")
	m.box(Vector3(cx - hw, y, cz - hd), Vector3(cx + hw, y + 0.5, cz + hd), beam)
	m.box(Vector3(cx - hw - V, y + 0.5, cz - hd - V), Vector3(cx + hw + V, y + 0.5 + V, cz + hd + V), gold)
	var nx := int(hw * 2.0 / 1.0)
	for i in nx + 1:
		var x := cx - hw + i * 1.0
		for sz in [-1.0, 1.0]:
			var z: float = cz + sz * (hd + V)
			m.box(Vector3(x - V, y + 0.5 + V, z - V), Vector3(x + V, y + 1.0, z + V), wood if i % 2 == 0 else beam)
	var nz := int(hd * 2.0 / 1.0)
	for i in nz + 1:
		var z := cz - hd + i * 1.0
		for sx in [-1.0, 1.0]:
			var x: float = cx + sx * (hw + V)
			m.box(Vector3(x - V, y + 0.5 + V, z - V), Vector3(x + V, y + 1.0, z + V), wood if i % 2 == 0 else beam)


# ================================================================ 建筑

## 殿堂：中心 (cx, cz)，墙体宽 w 深 d，台基高 ph，柱高 ch。
## opts: double(重檐) bool, porch(前廊深) float, plaque bool, lanterns bool, rise float, door_w float, windows bool
static func hall(m: BuildingMesh, cx: float, cz: float, w: float, d: float, ph: float, ch: float, p: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var porch: float = opts.get("porch", 1.5)
	var double: bool = opts.get("double", false)
	var rise: float = opts.get("rise", minf(w, d) * 0.32 + 1.0)
	var door_w: float = opts.get("door_w", minf(w * 0.3, 4.0))
	var stairs_w: float = opts.get("stairs_w", door_w + 1.0)
	var pw := w + 2.0 * V
	var pd := d + porch * 2.0
	# 台基
	if ph > 0.0:
		platform(m, cx, cz, pw + 2.0, pd + 2.0, ph, p)
		stairs(m, cx, cz - (pd + 2.0) * 0.5 - V, stairs_w, ph, p)
	var y0 := ph
	# 墙体（缩进于柱网内）
	var wall := col(p, "wall")
	var wx0 := cx - w * 0.5
	var wx1 := cx + w * 0.5
	var wz0 := cz - d * 0.5
	var wz1 := cz + d * 0.5
	var wt := 0.5
	# 下碱（墙裙）
	var skirt_c := col(p, "stone2")
	m.box(Vector3(wx0, y0, wz0), Vector3(wx1, y0 + 0.75, wz1), skirt_c, true)
	# 后墙与两侧墙
	m.box(Vector3(wx0, y0 + 0.75, wz1 - wt), Vector3(wx1, y0 + ch, wz1), wall, true)
	m.box(Vector3(wx0, y0 + 0.75, wz0), Vector3(wx0 + wt, y0 + ch, wz1), wall, true)
	m.box(Vector3(wx1 - wt, y0 + 0.75, wz0), Vector3(wx1, y0 + ch, wz1), wall, true)
	# 正面：门与窗（格栅），门洞可通行
	var door := col(p, "door")
	var frame := col(p, "wood")
	var dh := minf(ch - 0.75, 3.25)
	var zf := wz0 + V * 0.5
	# 门两侧墙体
	m.box(Vector3(wx0, y0 + 0.75, wz0), Vector3(cx - door_w * 0.5, y0 + ch, wz0 + wt), door, true)
	m.box(Vector3(cx + door_w * 0.5, y0 + 0.75, wz0), Vector3(wx1, y0 + ch, wz0 + wt), door, true)
	m.box(Vector3(cx - door_w * 0.5, y0 + dh, wz0), Vector3(cx + door_w * 0.5, y0 + ch, wz0 + wt), door)
	# 门框
	m.box(Vector3(cx - door_w * 0.5 - V, y0, wz0 - V * 0.5), Vector3(cx - door_w * 0.5, y0 + dh + V, wz0 + wt), frame)
	m.box(Vector3(cx + door_w * 0.5, y0, wz0 - V * 0.5), Vector3(cx + door_w * 0.5 + V, y0 + dh + V, wz0 + wt), frame)
	m.box(Vector3(cx - door_w * 0.5 - V, y0 + dh, wz0 - V * 0.5), Vector3(cx + door_w * 0.5 + V, y0 + dh + V, wz0 + wt), frame)
	# 室内地面（深色）
	m.box(Vector3(wx0 + wt, y0, wz0 + wt), Vector3(wx1 - wt, y0 + 0.05, wz1 - wt), col(p, "stone2").darkened(0.3))
	# 正面格栅窗（门两侧）
	var bay := (w - door_w) * 0.5
	var nb := maxi(int(bay / 2.5), 1)
	for side in [-1.0, 1.0]:
		for i in nb:
			var bx0: float
			var bx1: float
			if side < 0.0:
				bx0 = wx0 + wt + i * (bay - wt) / nb + 0.25
				bx1 = wx0 + wt + (i + 1) * (bay - wt) / nb - 0.25
			else:
				bx0 = cx + door_w * 0.5 + i * (bay - wt) / nb + 0.25
				bx1 = cx + door_w * 0.5 + (i + 1) * (bay - wt) / nb - 0.25
			lattice(m, bx0, bx1, y0 + 1.0, y0 + ch - 0.5, zf - V * 0.5, frame, Color(0.95, 0.85, 0.6) if i % 2 == 0 else Color(0.9, 0.8, 0.56))
	# 侧墙窗
	if opts.get("windows", true):
		var nwin := maxi(int(d / 4.0), 1)
		for i in nwin:
			var z0 := wz0 + (i + 0.5) * d / nwin - 0.75
			for sx in [-1.0, 1.0]:
				var x: float = (wx0 - V * 0.4) if sx < 0.0 else (wx1 + V * 0.4)
				m.box(Vector3(x - V * 0.3, y0 + 1.5, z0), Vector3(x + V * 0.3, y0 + ch - 1.0, z0 + 1.5), frame)
				m.box(Vector3(x - V * 0.4, y0 + 1.75, z0 + 0.25), Vector3(x + V * 0.4, y0 + ch - 1.25, z0 + 1.25), Color(0.25, 0.15, 0.1))
	# 柱网：前廊柱 + 四角 + 侧面
	var colx := w * 0.5 + V
	var colz := d * 0.5 + porch
	var ncol := maxi(int(round(w / 3.5)), 2)
	for i in ncol + 1:
		var x := cx - colx + i * (colx * 2.0) / ncol
		pillar(m, x, cz - colz + 0.25, y0, ch, p)
		pillar(m, x, cz + colz - 0.25, y0, ch, p)
	var nsz := maxi(int(round(d / 3.5)), 1)
	for i in range(1, nsz + 1):
		var z := cz - colz + 0.25 + i * (colz * 2.0 - 0.5) / (nsz + 1)
		pillar(m, cx - colx, z, y0, ch, p)
		pillar(m, cx + colx, z, y0, ch, p)
	# 额枋 + 斗拱
	var ey := y0 + ch
	brackets(m, cx, cz, colx + 0.25, colz, ey, p)
	var hw := colx + 1.75
	var hd := colz + 1.75
	var ry := ey + 1.0
	var top := ry
	if double:
		roof(m, cx, cz, hw, hd, ry, rise * 0.9, p, true, 0.32, 0.8)
		# 上层
		var uw := w * 0.5 - 0.5
		var ud := d * 0.5 - 0.25
		var uy := ry + snap(rise * 0.9 * 0.32) + V
		var uh := 2.25
		m.box(Vector3(cx - uw, uy - V, cz - ud), Vector3(cx + uw, uy + uh, cz + ud), wall)
		for i in maxi(int(uw * 2.0 / 2.0), 2):
			var x := cx - uw + 0.5 + i * 2.0
			if x + 1.0 > cx + uw:
				break
			m.box(Vector3(x, uy + 0.5, cz - ud - V * 0.5), Vector3(x + 1.25, uy + uh - 0.5, cz - ud), frame)
			m.box(Vector3(x, uy + 0.5, cz + ud), Vector3(x + 1.25, uy + uh - 0.5, cz + ud + V * 0.5), frame)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				pillar(m, cx + sx * uw, cz + sz * ud, uy - V, uh, p, 0.5, false)
		brackets(m, cx, cz, uw, ud, uy + uh, p)
		top = uy + uh + 1.0
		roof(m, cx, cz, uw + 1.75, ud + 1.75, top, rise, p, true)
	else:
		roof(m, cx, cz, hw, hd, ry, rise, p, opts.get("ridge", true))
	# 匾额
	if opts.get("plaque", true):
		var pz := cz - colz - V
		var gold := col(p, "trim")
		m.box(Vector3(cx - 1.5, ey - 0.25, pz - V), Vector3(cx + 1.5, ey + 1.25, pz), gold)
		m.box(Vector3(cx - 1.25, ey, pz - V * 1.4), Vector3(cx + 1.25, ey + 1.0, pz - V), col(p, "plaque") if p.has("plaque") else Color(0.12, 0.14, 0.22))
		# 金字笔画（抽象）
		for i in 3:
			m.box(Vector3(cx - 0.9 + i * 0.7, ey + 0.25, pz - V * 1.6), Vector3(cx - 0.6 + i * 0.7, ey + 0.75, pz - V * 1.4), gold)
	# 檐下灯笼
	if opts.get("lanterns", true):
		for sx in [-1.0, 1.0]:
			lantern(m, Vector3(cx + sx * (door_w * 0.5 + 1.25), ey + 0.5, cz - colz - 0.75), p)
	return {"top": top + rise, "door": Vector3(cx, y0, wz0), "front": cz - (pd + 2.0) * 0.5 - (ph / V) * 0.5}


## 塔（多层楼阁式）：底层宽 w，层数 floors
static func pagoda(m: BuildingMesh, cx: float, cz: float, w: float, floors: int, p: Dictionary) -> float:
	platform(m, cx, cz, w + 3.0, w + 3.0, 1.0, p)
	stairs(m, cx, cz - (w + 3.0) * 0.5 - V, 2.0, 1.0, p, false)
	var y := 1.0
	var wall := col(p, "wall")
	var frame := col(p, "wood")
	var half := w * 0.5
	for f in floors:
		var fh := 3.5 if f == 0 else 2.75
		m.box(Vector3(cx - half, y, cz - half), Vector3(cx + half, y + fh, cz + half), wall, f == 0)
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				pillar(m, cx + sx * half, cz + sz * half, y, fh, p, 0.5, false)
		# 四面门窗
		var dw := minf(half, 1.5)
		m.box(Vector3(cx - dw * 0.5, y + 0.25, cz - half - V * 0.5), Vector3(cx + dw * 0.5, y + fh - 0.5, cz - half), col(p, "door"))
		m.box(Vector3(cx - dw * 0.5, y + 0.25, cz + half), Vector3(cx + dw * 0.5, y + fh - 0.5, cz + half + V * 0.5), col(p, "door"))
		m.box(Vector3(cx - half - V * 0.5, y + 0.75, cz - dw * 0.5), Vector3(cx - half, y + fh - 0.75, cz + dw * 0.5), frame)
		m.box(Vector3(cx + half, y + 0.75, cz - dw * 0.5), Vector3(cx + half + V * 0.5, y + fh - 0.75, cz + dw * 0.5), frame)
		brackets(m, cx, cz, half, half, y + fh, p)
		var ry := y + fh + 1.0
		var last := f == floors - 1
		var rh := half + 1.5
		if last:
			roof(m, cx, cz, rh, rh, ry, half + 1.0, p, false)
			var top := ry + snap(half + 1.0) + 2.0
			# 塔刹
			var gold := col(p, "trim")
			for i in 5:
				var r := 0.5 - i * 0.07
				m.box(Vector3(cx - r, top + i * 0.5, cz - r), Vector3(cx + r, top + i * 0.5 + 0.25, cz + r), gold)
			m.box(Vector3(cx - 0.1, top, cz - 0.1), Vector3(cx + 0.1, top + 3.5, cz + 0.1), gold.darkened(0.2))
			return top + 3.5
		roof(m, cx, cz, rh, rh, ry, 1.0, p, false, 0.99, 0.8)
		# 挂铃
		for sx in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				m.box(Vector3(cx + sx * rh - 0.1, ry - 0.5, cz + sz * rh - 0.1), Vector3(cx + sx * rh + 0.1, ry, cz + sz * rh + 0.1), col(p, "trim"))
		y = ry + 1.25
		half = maxf(half - 0.5, 1.5)
	return y


## 亭：w 见方，柱高 h，攒尖顶；可带坐凳栏杆
static func pavilion(m: BuildingMesh, cx: float, cz: float, w: float, h: float, p: Dictionary, base_h: float = 0.5) -> void:
	platform(m, cx, cz, w + 1.0, w + 1.0, base_h, p)
	var half := w * 0.5
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			pillar(m, cx + sx * half, cz + sz * half, base_h, h, p)
	# 坐凳栏杆（三面）
	var wood := col(p, "pillar")
	for side in 3:
		match side:
			0:
				m.box(Vector3(cx - half, base_h + 0.25, cz + half - 0.25), Vector3(cx + half, base_h + 0.75, cz + half + 0.25), wood)
			1:
				m.box(Vector3(cx - half - 0.25, base_h + 0.25, cz - half), Vector3(cx - half + 0.25, base_h + 0.75, cz + half), wood)
			2:
				m.box(Vector3(cx + half - 0.25, base_h + 0.25, cz - half), Vector3(cx + half + 0.25, base_h + 0.75, cz + half), wood)
	# 楣子
	m.box(Vector3(cx - half, base_h + h - 0.5, cz - half - V), Vector3(cx + half, base_h + h, cz + half + V), col(p, "beam"))
	roof(m, cx, cz, half + 1.5, half + 1.5, base_h + h, half + 1.25, p, false)


## 牌坊（山门）：总宽 w，高 h，三间四柱，三顶
static func paifang(m: BuildingMesh, cx: float, cz: float, w: float, h: float, p: Dictionary) -> void:
	var xs := [-w * 0.5, -w * 0.18, w * 0.18, w * 0.5]
	var stone := col(p, "stone")
	for i in 4:
		var x: float = xs[i]
		var ph := h if (i == 1 or i == 2) else h * 0.78
		# 夹杆石
		m.box(Vector3(x - 0.75, 0, cz - 1.0), Vector3(x + 0.75, 1.5, cz + 1.0), stone, true)
		m.box(Vector3(x - 0.5, 1.5, cz - 0.75), Vector3(x + 0.5, 1.75, cz + 0.75), stone.lightened(0.08))
		m.box(Vector3(x - 0.375, 0, cz - 0.375), Vector3(x + 0.375, ph, cz + 0.375), col(p, "pillar"), true)
	var beam := col(p, "beam")
	var gold := col(p, "trim")
	# 中间（明间）
	var mx0: float = xs[1]
	var mx1: float = xs[2]
	m.box(Vector3(mx0, h - 2.5, cz - 0.375), Vector3(mx1, h - 1.75, cz + 0.375), beam)
	m.box(Vector3(mx0, h - 1.75, cz - 0.25), Vector3(mx1, h - 1.5, cz + 0.25), gold)
	m.box(Vector3(mx0 - 0.25, h - 0.75, cz - 0.5), Vector3(mx1 + 0.25, h, cz + 0.5), beam)
	# 匾
	m.box(Vector3(cx - 1.5, h - 1.75, cz - 0.6), Vector3(cx + 1.5, h - 0.25, cz - 0.375), gold)
	m.box(Vector3(cx - 1.25, h - 1.5, cz - 0.7), Vector3(cx + 1.25, h - 0.5, cz - 0.6), col(p, "plaque") if p.has("plaque") else Color(0.12, 0.14, 0.22))
	for i in 3:
		m.box(Vector3(cx - 0.9 + i * 0.7, h - 1.25, cz - 0.8), Vector3(cx - 0.6 + i * 0.7, h - 0.75, cz - 0.7), gold)
	brackets(m, cx, cz, (mx1 - mx0) * 0.5 + 0.25, 0.5, h, p)
	roof(m, cx, cz, (mx1 - mx0) * 0.5 + 2.0, 2.0, h + 1.0, 1.75, p, true, 0.0, 1.2)
	# 次间
	for sgn in [-1.0, 1.0]:
		var a: float = xs[0] if sgn < 0.0 else xs[2]
		var b: float = xs[1] if sgn < 0.0 else xs[3]
		var hh := h * 0.78
		m.box(Vector3(minf(a, b), hh - 1.75, cz - 0.3), Vector3(maxf(a, b), hh - 1.25, cz + 0.3), beam)
		m.box(Vector3(minf(a, b), hh - 0.5, cz - 0.4), Vector3(maxf(a, b), hh, cz + 0.4), beam)
		var scx := (a + b) * 0.5
		brackets(m, scx, cz, absf(b - a) * 0.5, 0.4, hh, p)
		roof(m, scx, cz, absf(b - a) * 0.5 + 1.25, 1.5, hh + 1.0, 1.25, p, true, 0.0, 1.0)


## 院墙：从 a 到 b（沿 x 或 z 轴），高 h，带瓦顶
static func wall(m: BuildingMesh, a: Vector2, b: Vector2, h: float, p: Dictionary, thick: float = 0.75) -> void:
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	var along_x := hi.x - lo.x >= hi.y - lo.y
	var t := thick * 0.5
	if along_x:
		lo.y -= t
		hi.y += t
	else:
		lo.x -= t
		hi.x += t
	var wallc := col(p, "wall2") if p.has("wall2") else col(p, "wall")
	m.box(Vector3(lo.x, -0.5, lo.y), Vector3(hi.x, 0.75, hi.y), col(p, "stone2"), true, true)
	m.box(Vector3(lo.x, 0.75, lo.y), Vector3(hi.x, h, hi.y), wallc, true)
	# 瓦顶
	var roofc := col(p, "roof")
	var e := 0.5
	if along_x:
		m.box(Vector3(lo.x - e, h, lo.y - e), Vector3(hi.x + e, h + V, hi.y + e), col(p, "roof2"))
		m.box(Vector3(lo.x - e * 0.5, h + V, lo.y - e * 0.5), Vector3(hi.x + e * 0.5, h + 2.0 * V, hi.y + e * 0.5), roofc)
		m.box(Vector3(lo.x, h + 2.0 * V, lo.y + t * 0.5), Vector3(hi.x, h + 3.0 * V, hi.y - t * 0.5), roofc.darkened(0.15))
	else:
		m.box(Vector3(lo.x - e, h, lo.y - e), Vector3(hi.x + e, h + V, hi.y + e), col(p, "roof2"))
		m.box(Vector3(lo.x - e * 0.5, h + V, lo.y - e * 0.5), Vector3(hi.x + e * 0.5, h + 2.0 * V, hi.y + e * 0.5), roofc)
		m.box(Vector3(lo.x + t * 0.5, h + 2.0 * V, lo.y), Vector3(hi.x - t * 0.5, h + 3.0 * V, hi.y), roofc.darkened(0.15))


## 青铜鼎（香炉），顶部余烬发光
static func cauldron(m: BuildingMesh, cx: float, cz: float, s: float, p: Dictionary, fire: Color = Color(1.0, 0.5, 0.15)) -> void:
	var bronze := Color(0.36, 0.30, 0.18)
	var bronze2 := Color(0.46, 0.40, 0.22)
	m.box(Vector3(cx - 1.5 * s, 0, cz - 1.5 * s), Vector3(cx + 1.5 * s, 0.25, cz + 1.5 * s), col(p, "stone"), true)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			m.box(Vector3(cx + sx * 0.8 * s - 0.2 * s, 0.25, cz + sz * 0.8 * s - 0.2 * s), Vector3(cx + sx * 0.8 * s + 0.2 * s, 1.0 * s, cz + sz * 0.8 * s + 0.2 * s), bronze)
	m.box(Vector3(cx - 1.1 * s, 1.0 * s, cz - 1.1 * s), Vector3(cx + 1.1 * s, 2.2 * s, cz + 1.1 * s), bronze, true)
	m.box(Vector3(cx - 1.25 * s, 2.0 * s, cz - 1.25 * s), Vector3(cx + 1.25 * s, 2.35 * s, cz + 1.25 * s), bronze2)
	m.box(Vector3(cx - 1.0 * s, 1.3 * s, cz - 1.15 * s), Vector3(cx + 1.0 * s, 1.8 * s, cz - 1.1 * s), col(p, "trim"))
	for sx in [-1.0, 1.0]:
		m.box(Vector3(cx + sx * 0.7 * s - 0.15 * s, 2.35 * s, cz - 0.15 * s), Vector3(cx + sx * 0.7 * s + 0.15 * s, 3.0 * s, cz + 0.15 * s), bronze2)
		m.box(Vector3(cx + sx * 0.7 * s - 0.15 * s, 2.85 * s, cz - 0.6 * s), Vector3(cx + sx * 0.7 * s + 0.15 * s, 3.0 * s, cz + 0.6 * s), bronze2)
	m.box(Vector3(cx - 0.9 * s, 2.2 * s, cz - 0.9 * s), Vector3(cx + 0.9 * s, 2.3 * s, cz + 0.9 * s), VoxelGrid.glow(fire, 0.9))
	m.box(Vector3(cx - 0.4 * s, 2.3 * s, cz - 0.4 * s), Vector3(cx + 0.4 * s, 2.6 * s, cz + 0.4 * s), VoxelGrid.glow(fire.lightened(0.3), 1.0))


## 市集摊位：桌 + 四杆 + 布篷 + 货物
static func stall(m: BuildingMesh, cx: float, cz: float, w: float, cloth: Color, p: Dictionary, seed_v: int = 0) -> void:
	var wood := col(p, "wood")
	var d := 2.0
	m.box(Vector3(cx - w * 0.5, 0.0, cz - d * 0.5), Vector3(cx + w * 0.5, 0.9, cz - d * 0.5 + 1.0), wood, true)
	m.box(Vector3(cx - w * 0.5 - V * 0.5, 0.9, cz - d * 0.5 - V * 0.5), Vector3(cx + w * 0.5 + V * 0.5, 1.0, cz - d * 0.5 + 1.0 + V * 0.5), wood.lightened(0.15))
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			m.box(Vector3(cx + sx * w * 0.5 - 0.1, 0, cz + sz * d * 0.5 - 0.1), Vector3(cx + sx * w * 0.5 + 0.1, 2.6 + (0.3 if sz > 0.0 else 0.0), cz + sz * d * 0.5 + 0.1), wood)
	# 布篷（阶梯斜面，条纹）
	for i in 4:
		var z0 := cz - d * 0.5 - 0.5 + i * 0.75
		var y := 2.6 + i * 0.12
		m.box(Vector3(cx - w * 0.5 - 0.3, y, z0), Vector3(cx + w * 0.5 + 0.3, y + 0.12, z0 + 0.8), cloth if i % 2 == 0 else cloth.lightened(0.35))
	# 货物
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var goods := [Color(0.9, 0.3, 0.2), Color(0.95, 0.8, 0.3), Color(0.4, 0.75, 0.4), Color(0.6, 0.5, 0.85), Color(0.85, 0.85, 0.8)]
	var x := cx - w * 0.5 + 0.2
	while x < cx + w * 0.5 - 0.4:
		var gw := rng.randf_range(0.25, 0.5)
		var gh := rng.randf_range(0.15, 0.45)
		var gc: Color = goods[rng.randi() % goods.size()]
		m.box(Vector3(x, 1.0, cz - d * 0.5 + 0.2), Vector3(x + gw, 1.0 + gh, cz - d * 0.5 + 0.7), gc)
		x += gw + 0.1


## 告示牌 / 任务榜：两柱 + 板 + 小顶 + 贴纸
static func notice_board(m: BuildingMesh, cx: float, cz: float, w: float, p: Dictionary, board: Color = Color(0.45, 0.3, 0.18)) -> void:
	var wood := col(p, "wood")
	for sx in [-1.0, 1.0]:
		m.box(Vector3(cx + sx * w * 0.5 - 0.15, 0, cz - 0.15), Vector3(cx + sx * w * 0.5 + 0.15, 3.2, cz + 0.15), wood, true)
	m.box(Vector3(cx - w * 0.5, 1.0, cz - 0.1), Vector3(cx + w * 0.5, 2.8, cz + 0.1), board, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(cx * 13.0 + cz * 7.0)
	for i in 6:
		var px := cx - w * 0.5 + 0.3 + (i % 3) * (w - 0.6) / 3.0
		var py := 1.25 + (i / 3) * 0.8
		var paper := Color(0.95, 0.92, 0.82) if i % 2 == 0 else Color(0.98, 0.85, 0.7)
		m.box(Vector3(px, py, cz - 0.15), Vector3(px + rng.randf_range(0.4, 0.6), py + rng.randf_range(0.45, 0.65), cz - 0.1), paper)
	roof(m, cx, cz, w * 0.5 + 0.5, 0.6, 3.2, 0.5, p, true, 0.0, 0.6)


## 店铺（两层）：宽 w 深 d，招牌颜色 sign
static func shop(m: BuildingMesh, cx: float, cz: float, w: float, d: float, p: Dictionary, sign: Color, seed_v: int = 0) -> void:
	var wood := col(p, "wood")
	var wall := col(p, "wall")
	var y1 := 3.5
	var y2 := 6.5
	m.box(Vector3(cx - w * 0.5 - 0.25, -0.5, cz - d * 0.5 - 0.25), Vector3(cx + w * 0.5 + 0.25, 0.25, cz + d * 0.5 + 0.25), col(p, "stone2"), true, true)
	# 一层：后墙 + 侧墙，前面开敞柜台
	m.box(Vector3(cx - w * 0.5, 0.25, cz + d * 0.5 - 0.5), Vector3(cx + w * 0.5, y1, cz + d * 0.5), wall, true)
	m.box(Vector3(cx - w * 0.5, 0.25, cz - d * 0.5), Vector3(cx - w * 0.5 + 0.5, y1, cz + d * 0.5), wall, true)
	m.box(Vector3(cx + w * 0.5 - 0.5, 0.25, cz - d * 0.5), Vector3(cx + w * 0.5, y1, cz + d * 0.5), wall, true)
	m.box(Vector3(cx - w * 0.5 + 0.5, 0.25, cz - d * 0.5 + 0.5), Vector3(cx + w * 0.5 - 0.5, 1.25, cz - d * 0.5 + 1.25), wood, true)
	m.box(Vector3(cx - w * 0.5 + 0.5, 0.25, cz - d * 0.5 + 1.25), Vector3(cx + w * 0.5 - 0.5, 0.3, cz + d * 0.5 - 0.5), wood.darkened(0.3))
	# 货架
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	for sh in 3:
		var y := 1.0 + sh * 0.75
		m.box(Vector3(cx - w * 0.5 + 0.75, y, cz + d * 0.5 - 1.0), Vector3(cx + w * 0.5 - 0.75, y + 0.12, cz + d * 0.5 - 0.5), wood)
		var x := cx - w * 0.5 + 0.9
		while x < cx + w * 0.5 - 1.0:
			var gw := rng.randf_range(0.2, 0.45)
			var gc := Color.from_hsv(rng.randf(), 0.5, 0.8)
			m.box(Vector3(x, y + 0.12, cz + d * 0.5 - 0.95), Vector3(x + gw, y + 0.12 + rng.randf_range(0.2, 0.45), cz + d * 0.5 - 0.6), gc)
			x += gw + 0.08
	for sx in [-1.0, 1.0]:
		pillar(m, cx + sx * (w * 0.5 - 0.25), cz - d * 0.5 + 0.25, 0.25, y1, p, 0.5)
	# 二层（出挑）
	m.box(Vector3(cx - w * 0.5 - 0.25, y1, cz - d * 0.5 - 0.5), Vector3(cx + w * 0.5 + 0.25, y1 + 0.5, cz + d * 0.5 + 0.25), wood, true)
	m.box(Vector3(cx - w * 0.5, y1 + 0.5, cz - d * 0.5 + 0.25), Vector3(cx + w * 0.5, y2, cz + d * 0.5), wall, true)
	var nwin := maxi(int(w / 2.0), 1)
	for i in nwin:
		var x0 := cx - w * 0.5 + 0.5 + i * (w - 1.0) / nwin + 0.2
		var x1 := cx - w * 0.5 + 0.5 + (i + 1) * (w - 1.0) / nwin - 0.2
		lattice(m, x0, x1, y1 + 1.0, y2 - 0.5, cz - d * 0.5 + 0.2, wood, Color(0.92, 0.82, 0.58))
	# 栏杆
	m.box(Vector3(cx - w * 0.5 - 0.25, y1 + 0.5, cz - d * 0.5 - 0.5), Vector3(cx + w * 0.5 + 0.25, y1 + 1.1, cz - d * 0.5 - 0.3), col(p, "pillar"))
	roof(m, cx, cz, w * 0.5 + 1.25, d * 0.5 + 1.25, y2, minf(w, d) * 0.3 + 0.75, p, true, 0.0, 0.8)
	# 竖招牌
	var sx2 := cx + w * 0.5 - 1.0
	m.box(Vector3(sx2 - 0.4, y1 - 2.4, cz - d * 0.5 - 0.35), Vector3(sx2 + 0.4, y1 - 0.2, cz - d * 0.5 - 0.15), sign)
	m.box(Vector3(sx2 - 0.3, y1 - 2.2, cz - d * 0.5 - 0.4), Vector3(sx2 + 0.3, y1 - 0.4, cz - d * 0.5 - 0.35), col(p, "trim"))
	lantern(m, Vector3(cx - w * 0.5 + 1.0, y1 - 0.2, cz - d * 0.5 - 0.3), p, 0.8)


## 巨剑碑（天剑宗）：剑身沿 y 竖直插地
static func giant_sword(m: BuildingMesh, cx: float, cz: float, h: float, p: Dictionary) -> void:
	var steel := Color(0.80, 0.84, 0.90)
	var edge := VoxelGrid.glow(Color(0.75, 0.9, 1.0), 0.35)
	var gold := col(p, "trim")
	m.box(Vector3(cx - 1.5, 0, cz - 1.5), Vector3(cx + 1.5, 1.0, cz + 1.5), col(p, "stone2"), true)
	m.box(Vector3(cx - 1.0, 1.0, cz - 1.0), Vector3(cx + 1.0, 1.5, cz + 1.0), col(p, "stone"), true)
	m.box(Vector3(cx - 0.5, 1.0, cz - 0.15), Vector3(cx + 0.5, h, cz + 0.15), steel, true)
	m.box(Vector3(cx - 0.1, 1.5, cz - 0.2), Vector3(cx + 0.1, h - 0.25, cz + 0.2), edge)
	m.box(Vector3(cx - 1.4, h, cz - 0.35), Vector3(cx + 1.4, h + 0.5, cz + 0.35), gold)
	m.box(Vector3(cx - 0.2, h + 0.5, cz - 0.2), Vector3(cx + 0.2, h + 2.5, cz + 0.2), Color(0.3, 0.12, 0.1))
	m.box(Vector3(cx - 0.35, h + 2.5, cz - 0.35), Vector3(cx + 0.35, h + 3.0, cz + 0.35), gold)


## 石灯柱（非可破坏装饰版）
static func stone_post(m: BuildingMesh, cx: float, cz: float, h: float, p: Dictionary, glow_c: Color = Color(1.0, 0.75, 0.4)) -> void:
	var s := col(p, "stone")
	m.box(Vector3(cx - 0.4, 0, cz - 0.4), Vector3(cx + 0.4, 0.4, cz + 0.4), s, true)
	m.box(Vector3(cx - 0.2, 0.4, cz - 0.2), Vector3(cx + 0.2, h, cz + 0.2), s)
	m.box(Vector3(cx - 0.35, h, cz - 0.35), Vector3(cx + 0.35, h + 0.6, cz + 0.35), VoxelGrid.glow(glow_c, 0.8))
	m.box(Vector3(cx - 0.5, h + 0.6, cz - 0.5), Vector3(cx + 0.5, h + 0.8, cz + 0.5), s)
	m.box(Vector3(cx - 0.2, h + 0.8, cz - 0.2), Vector3(cx + 0.2, h + 1.0, cz + 0.2), s)


## 铺装（石板）：矩形区域，棋盘略微变色
static func paving(m: BuildingMesh, x0: float, z0: float, x1: float, z1: float, y: float, p: Dictionary, tile: float = 2.0) -> void:
	var a := col(p, "stone")
	var b := col(p, "stone2")
	var nx := maxi(int(round((x1 - x0) / tile)), 1)
	var nz := maxi(int(round((z1 - z0) / tile)), 1)
	for j in nz:
		for i in nx:
			var c := a if (i + j) % 2 == 0 else a.lerp(b, 0.4)
			m.box(Vector3(x0 + i * (x1 - x0) / nx, y - 0.1, z0 + j * (z1 - z0) / nz), Vector3(x0 + (i + 1) * (x1 - x0) / nx, y + 0.05, z0 + (j + 1) * (z1 - z0) / nz), c, false, true)
