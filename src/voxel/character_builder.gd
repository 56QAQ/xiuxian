class_name CharacterBuilder
## 根据外貌参数生成体素角色（CharacterRig）。
##
## 骨骼与尺寸约定（单位：体素，VOXEL = 0.025m；以下为 height=1 时）：
##   hips      原点 (0, 28, 0)          髋部网格 y 24..32
##   leg_l/r   原点 hips + (∓4, 0, 0)    大腿 14 高；shin_l/r 在其下 14 处（膝）；脚向前伸出
##   spine     原点 hips + (0, 4, 0)     躯干 y 32..52（腰 8 + 胸 12）
##   head      原点 spine + (0, 20, 0)   颈 2 + 头 16×16×16
##   arm_l/r   原点 spine + (∓11, 18, 0) 上臂 12；forearm 在其下 12 处；hand 在 forearm 下 11 处
## 外貌字典字段见 docs/DATA.md「appearance」。

const VOXEL := 0.025

const DEFAULT_APPEARANCE := {
	"gender": "female",
	"height": 1.0,
	"build": 0.4,
	"head_scale": 1.0,
	"chest": 0.5,
	"skin": "#f3d2bd",
	"hair_style": "twin_tails",
	"hair_color": "#c8201e",
	"hair_color2": "#ff5a40",
	"eye_color": "#f0a020",
	"eye_style": "almond",
	"brow_style": 0,
	"mark": "none",
	"mark_color": "#e02040",
	"ears": "fox",
	"ear_color": "#7a4424",
	"tail": "none",
	"horns": "none",
	"outfit": "armor",
	"outfit_colors": ["#b3201c", "#3b2618", "#e2b23c"],
}


static func appearance_with_defaults(a: Dictionary) -> Dictionary:
	var out := DEFAULT_APPEARANCE.duplicate(true)
	for k in a:
		out[k] = a[k]
	return out


static func col(v: Variant, fallback: Color = Color.MAGENTA) -> Color:
	if v is Color:
		return v
	if v is String and (v as String).length() >= 6:
		return Color.html(v)
	return fallback


## 生成角色。equip_visual 可包含 {"weapon": 武器 visual 字典, "outfit": 覆盖服饰}
static func build(appearance: Dictionary, equip_visual: Dictionary = {}) -> CharacterRig:
	var a := appearance_with_defaults(appearance)
	if equip_visual.has("outfit"):
		for k in equip_visual["outfit"]:
			a[k] = equip_visual["outfit"][k]
	var rig := CharacterRig.new()
	rig.name = "CharacterRig"
	rig.voxel_size = VOXEL
	var build_f := clampf(float(a["build"]), 0.0, 1.0)
	var widen := 1 if build_f > 0.66 else 0
	var skin := col(a["skin"])
	var cols: Array = a["outfit_colors"]
	var c1 := col(cols[0])
	var c2 := col(cols[1])
	var c3 := col(cols[2])

	var hips := _bone(rig, "hips", Vector3(0, 28, 0))
	var spine := _bone(hips, "spine", Vector3(0, 4, 0))
	var head := _bone(spine, "head", Vector3(0, 20, 0))
	var arm_l := _bone(spine, "arm_l", Vector3(-11 - widen, 18, 0))
	var arm_r := _bone(spine, "arm_r", Vector3(11 + widen, 18, 0))
	var fore_l := _bone(arm_l, "forearm_l", Vector3(0, -12, 0))
	var fore_r := _bone(arm_r, "forearm_r", Vector3(0, -12, 0))
	var hand_l := _bone(fore_l, "hand_l", Vector3(0, -11, 0))
	var hand_r := _bone(fore_r, "hand_r", Vector3(0, -11, 0))
	var leg_l := _bone(hips, "leg_l", Vector3(-4, 0, 0))
	var leg_r := _bone(hips, "leg_r", Vector3(4, 0, 0))
	var shin_l := _bone(leg_l, "shin_l", Vector3(0, -14, 0))
	var shin_r := _bone(leg_r, "shin_r", Vector3(0, -14, 0))

	# 髋部：16×8×8，原点在 y=4（相对网格底部）
	var g := VoxelGrid.new(16 + widen * 2, 8, 8)
	g.fill_box(Vector3i(0, 0, 0), Vector3i(g.sx - 1, 7, 7), c1)
	g.fill_box(Vector3i(0, 6, 0), Vector3i(g.sx - 1, 7, 7), c2)
	g.fill_box(Vector3i(0, 6, 0), Vector3i(g.sx - 1, 6, 0), c3)
	_attach(hips, g, Vector3(-g.sx / 2.0, -4, -4))

	# 躯干：腰 14 宽 8 高，胸 16 宽 12 高
	g = VoxelGrid.new(16 + widen * 2, 20, 8)
	var o := widen
	g.fill_box(Vector3i(1 + o, 0, 0), Vector3i(14 + o, 7, 7), skin)
	g.fill_box(Vector3i(0, 8, 0), Vector3i(15 + o * 2, 19, 7), skin)
	g.fill_box(Vector3i(0, 10, 0), Vector3i(15 + o * 2, 16, 7), c2)
	g.fill_box(Vector3i(0, 16, 0), Vector3i(15 + o * 2, 16, 7), c3)
	g.fill_box(Vector3i(1 + o, 0, 0), Vector3i(14 + o, 1, 7), c3)
	_attach(spine, g, Vector3(-g.sx / 2.0, 0, -4))

	# 头：颈 + 16³
	g = VoxelGrid.new(16, 18, 16)
	g.fill_box(Vector3i(5, 0, 5), Vector3i(10, 1, 10), skin)
	g.fill_box(Vector3i(0, 2, 0), Vector3i(15, 17, 15), skin)
	_paint_face(g, a)
	_attach(head, g, Vector3(-8, 0, -8))
	head.scale = Vector3.ONE * clampf(float(a["head_scale"]), 0.85, 1.2)
	_build_hair(head, a)

	# 手臂
	for side in [["l", arm_l, fore_l], ["r", arm_r, fore_r]]:
		g = VoxelGrid.new(6, 12, 6)
		g.fill_box(Vector3i(0, 0, 0), Vector3i(5, 11, 5), skin)
		g.fill_box(Vector3i(0, 6, 0), Vector3i(5, 11, 5), c1)
		g.fill_box(Vector3i(0, 6, 0), Vector3i(5, 6, 5), c3)
		_attach(side[1], g, Vector3(-3, -12, -3))
		g = VoxelGrid.new(6, 14, 6)
		g.fill_box(Vector3i(0, 0, 0), Vector3i(5, 13, 5), skin)
		g.fill_box(Vector3i(0, 4, 0), Vector3i(5, 11, 5), c2)
		g.fill_box(Vector3i(0, 4, 0), Vector3i(5, 4, 5), c3)
		_attach(side[2], g, Vector3(-3, -14, -3))

	# 腿
	for side in [leg_l, leg_r]:
		g = VoxelGrid.new(8, 14, 8)
		g.fill_box(Vector3i(0, 0, 0), Vector3i(7, 13, 7), skin)
		g.fill_box(Vector3i(0, 8, 0), Vector3i(7, 13, 7), c1)
		_attach(side, g, Vector3(-4, -14, -4))
	for side in [shin_l, shin_r]:
		g = VoxelGrid.new(8, 14, 11)
		g.fill_box(Vector3i(0, 0, 3), Vector3i(7, 13, 10), c2)
		g.fill_box(Vector3i(0, 0, 0), Vector3i(7, 3, 10), c2)
		g.fill_box(Vector3i(0, 0, 0), Vector3i(7, 0, 10), c3.darkened(0.3))
		g.fill_box(Vector3i(0, 12, 3), Vector3i(7, 13, 10), c3)
		_attach(side, g, Vector3(-4, -14, -7))

	rig.body_scale = clampf(float(a["height"]), 0.85, 1.15)
	rig.scale = Vector3.ONE * rig.body_scale
	rig.setup()
	if equip_visual.has("weapon") and not (equip_visual["weapon"] as Dictionary).is_empty():
		var w := WeaponBuilder.build(equip_visual["weapon"])
		rig.attach_to_hand(w, "r")
		rig.stance = str(equip_visual["weapon"].get("kind", "fist"))
	return rig


static func _bone(parent: Node3D, bone_name: String, pos_vox: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = bone_name
	n.position = pos_vox * VOXEL
	parent.add_child(n)
	return n


## origin_vox：体素 (0,0,0) 相对骨骼原点的位置（体素单位）
static func _attach(bone_node: Node3D, g: VoxelGrid, origin_vox: Vector3) -> MeshInstance3D:
	var mi := VoxelMesher.build_instance(g, VOXEL, origin_vox * VOXEL)
	mi.name = "Mesh"
	bone_node.add_child(mi)
	return mi


static func _paint_face(g: VoxelGrid, a: Dictionary) -> void:
	# 头网格前面为 z=0（面朝 -Z）；头部体素 y 2..17
	var eye := col(a["eye_color"])
	var white := Color(0.97, 0.96, 0.95)
	var dark := Color(0.12, 0.08, 0.08)
	for side: int in [-1, 1]:
		var cx: int = 8 + side * 3 - (1 if side < 0 else 0)
		var x0: int = cx - 1
		g.fill_box(Vector3i(x0, 7, 0), Vector3i(x0 + 2, 9, 0), white)
		g.fill_box(Vector3i(x0 + (1 if side < 0 else 0), 7, 0), Vector3i(x0 + (2 if side < 0 else 1), 9, 0), eye)
		g.set_color(x0 + (1 if side < 0 else 1), 9, 0, eye.lightened(0.5))
		g.fill_box(Vector3i(x0, 10, 0), Vector3i(x0 + 2, 10, 0), dark)
	g.fill_box(Vector3i(7, 5, 0), Vector3i(8, 5, 0), Color(0.75, 0.4, 0.4))


static func _build_hair(head: Node3D, a: Dictionary) -> void:
	var hc := col(a["hair_color"])
	var hc2 := col(a["hair_color2"], hc.lightened(0.2))
	var g := VoxelGrid.new(18, 12, 18)
	# 发帽：覆盖头顶与后脑
	g.fill_box(Vector3i(0, 4, 1), Vector3i(17, 11, 17), hc)
	g.fill_box(Vector3i(0, 0, 9), Vector3i(17, 4, 17), hc)
	g.clear_box(Vector3i(1, 0, 1), Vector3i(16, 9, 16))
	g.fill_box(Vector3i(1, 10, 1), Vector3i(16, 11, 16), hc)
	# 刘海
	for x in range(1, 17):
		var len_b := 3 + (x * 7) % 3
		g.fill_box(Vector3i(x, 10 - len_b, 0), Vector3i(x, 10, 0), hc if x % 3 else hc2)
	var mi := VoxelMesher.build_instance(g, VOXEL, Vector3(-9, 8, -9) * VOXEL)
	mi.name = "HairMesh"
	head.add_child(mi)
	if str(a["hair_style"]) == "twin_tails":
		for side: int in [-1, 1]:
			var pivot := Node3D.new()
			pivot.name = "hair_tail_" + ("l" if side < 0 else "r")
			pivot.position = Vector3(side * 9.5, 16, 4) * VOXEL
			pivot.set_meta("spring_length", 0.6)
			head.add_child(pivot)
			var tg := VoxelGrid.new(6, 26, 6)
			for y in 26:
				var r := 2.6 - absf(y - 6.0) * 0.08
				tg.fill_ellipsoid(Vector3(3, y + 0.5, 3), Vector3(r, 0.6, r), hc if y % 4 else hc2)
			var tmi := VoxelMesher.build_instance(tg, VOXEL, Vector3(-3, -26, -3) * VOXEL)
			pivot.add_child(tmi)
