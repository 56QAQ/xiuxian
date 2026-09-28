class_name CharacterBuilder
## 根据外貌参数生成体素角色（返回 HumanoidRig，它继承 CharacterRig，接口相同）。
##
## 骨骼与尺寸约定（单位：体素，VOXEL = 0.0125m，每米 80 体素；以下为 height=1 时，详见 CharSpec）：
##   hips      原点 (0, 60, 0)             骨盆网格 y -8..7（相对 hips）
##   leg_l/r   原点 hips + (∓leg_x, 0, 0)   大腿 30 高；shin_l/r 在其下 30 处（膝）；小腿+靴 30 高，脚向前伸出
##   spine     原点 hips + (0, 6, 0)       躯干 y 0..35（腰 12 + 胸 24）
##   head      原点 spine + (0, 36, 0)     颈 + 头 32×32×32（脸朝 -Z，在 z=-16 面）；头顶约 1.72m
##   arm_l/r   原点 spine + (∓arm_x, 32, 0) 上臂 24；forearm 在其下 24 处（肘）；hand 在 forearm 下 22 处
##   hand_l/r  原点 = 拳心；武器握把在此、沿本地 Z 穿过拳头（刃朝 -Z）
## 米制尺寸与骨骼位置和旧版（0.025m 体素）完全相同，动画剪辑、碰撞、武器握点不受影响。
## 弹簧骨骼（CharacterRig 自动二次运动）：hair_*（发束链）、ear_l/r（兽耳）、tail_0..3（狐尾链）、
## cloth_*（裙甲/下摆，随腿摆动，见 HumanoidRig）。
## 外貌字典字段见 docs/DATA.md「外貌字典」。
##
## 生成流程：先搭骨架并为每个部件请求 VoxMesh.part()（按参数键缓存），缺失部件在 WorkerThreadPool 中
## 并行绘制 + 网格化（两级 LOD：近处全精度、约 22m 外半精度，visibility range 切换）。
##   build(appearance, equip_visual, opts)        同步：返回时网格已就绪（界面预览、测试）
##   build_async(appearance, equip_visual, opts)  异步：立即返回骨架（隐藏），网格在后台生成完后
##                                                 自动显示并发出 rig.meshes_ready（游戏内刷 NPC 用）
##   opts: {"lod": false} 不挂远景 LOD（界面预览）

const VOXEL := 0.0125
## 骨架布局（体素）
const HIP_Y := 60
const SPINE_DY := 6
const HEAD_DY := 36
const ARM_DY := 32
const THIGH := 30
const SHIN := 30
const ELBOW := 24
const WRIST := 22

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
	"brow_style": 2,
	"mark": "none",
	"mark_color": "#e02040",
	"ears": "fox",
	"ear_color": "#7a4424",
	"tail": "none",
	"horns": "none",
	"outfit": "armor",
	"outfit_colors": ["#b3201c", "#3b2618", "#e2b23c"],
}

const HAIR_STYLES: Array[String] = ["twin_tails", "ponytail", "long", "short", "bun", "flowing", "double_bun", "braid"]
const EYE_STYLES: Array[String] = ["almond", "round", "sharp", "droopy"]
const OUTFITS: Array[String] = ["robe", "martial", "armor"]
const EARS: Array[String] = ["human", "fox", "cat", "elf"]
const MARKS: Array[String] = ["none", "lotus", "flame", "dot", "crescent", "tear"]

## 当前构建是否挂远景 LOD（构建期间有效）
static var _lod: bool = true


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


## 生成角色（同步）。equip_visual 可包含 {"weapon": 武器 visual 字典, "outfit": 覆盖服饰（outfit / outfit_colors）}
static func build(appearance: Dictionary, equip_visual: Dictionary = {}, opts: Dictionary = {}) -> CharacterRig:
	return _assemble(appearance, equip_visual, opts, false)


## 生成角色（异步）：立即返回（隐藏的）骨架，网格在工作线程生成，完成后自动显示并发出 meshes_ready。
## 接口与 build() 相同，可直接替换（动画、挂武器、闪白等都可立即使用）。
static func build_async(appearance: Dictionary, equip_visual: Dictionary = {}, opts: Dictionary = {}) -> CharacterRig:
	return _assemble(appearance, equip_visual, opts, true)


static func _assemble(appearance: Dictionary, equip_visual: Dictionary, opts: Dictionary, async: bool) -> CharacterRig:
	var a := appearance_with_defaults(appearance)
	if equip_visual.has("outfit") and equip_visual["outfit"] is Dictionary:
		for k in equip_visual["outfit"]:
			a[k] = equip_visual["outfit"][k]
	var s := CharSpec.from(a)
	var prev_lod := _lod
	_lod = bool(opts.get("lod", true))
	var rig := HumanoidRig.new()
	rig.name = "CharacterRig"
	rig.voxel_size = VOXEL
	VoxMesh.begin_batch(async)

	var hips := _bone(rig, "hips", Vector3(0, HIP_Y, 0))
	var spine := _bone(hips, "spine", Vector3(0, SPINE_DY, 0))
	var head := _bone(spine, "head", Vector3(0, HEAD_DY, 0))
	var arm_l := _bone(spine, "arm_l", Vector3(-s.arm_x, ARM_DY, 0))
	var arm_r := _bone(spine, "arm_r", Vector3(s.arm_x, ARM_DY, 0))
	var fore_l := _bone(arm_l, "forearm_l", Vector3(0, -ELBOW, 0))
	var fore_r := _bone(arm_r, "forearm_r", Vector3(0, -ELBOW, 0))
	var hand_l := _bone(fore_l, "hand_l", Vector3(0, -WRIST, 0))
	var hand_r := _bone(fore_r, "hand_r", Vector3(0, -WRIST, 0))
	var leg_l := _bone(hips, "leg_l", Vector3(-s.leg_x, 0, 0))
	var leg_r := _bone(hips, "leg_r", Vector3(s.leg_x, 0, 0))
	var shin_l := _bone(leg_l, "shin_l", Vector3(0, -THIGH, 0))
	var shin_r := _bone(leg_r, "shin_r", Vector3(0, -THIGH, 0))

	var kb := body_key(s)
	var kh := head_key(s)
	mesh(hips, part("pelvis|" + kb, func() -> Variant: return OutfitBuilder.pelvis(s)))
	mesh(spine, part("torso|" + kb, func() -> Variant: return OutfitBuilder.torso(s)))
	# 左右对称部件：只生成右侧网格，左侧用镜像实例
	var m_uarm := part("uarm|" + kb, func() -> Variant: return OutfitBuilder.upper_arm(s, 1))
	var m_farm := part("farm|" + kb, func() -> Variant: return OutfitBuilder.forearm(s, 1))
	var m_hand := part("hand|" + kb, func() -> Variant: return OutfitBuilder.hand(s, 1))
	var m_thigh := part("thigh|" + kb, func() -> Variant: return OutfitBuilder.thigh(s, 1))
	var m_shin := part("shin|" + kb, func() -> Variant: return OutfitBuilder.shin(s, 1))
	mesh(arm_r, m_uarm)
	mesh(arm_l, m_uarm, true)
	mesh(fore_r, m_farm)
	mesh(fore_l, m_farm, true)
	mesh(hand_r, m_hand)
	mesh(hand_l, m_hand, true)
	mesh(leg_r, m_thigh)
	mesh(leg_l, m_thigh, true)
	mesh(shin_r, m_shin)
	mesh(shin_l, m_shin, true)
	mesh(head, part("head|" + kh, func() -> Variant: return head_canvas(s)))
	# 闭眼贴片（贴在脸前，极薄；只有近景需要）
	var blink := MeshInstance3D.new()
	blink.name = "Blink"
	blink.mesh = part("blink|" + kh, func() -> Variant:
		var bc := VoxCanvas.new(Vector3i(-16, 8, 0), Vector3i(15, 26, 0))
		FacePainter.paint_blink(bc, s)
		return bc)[0]
	blink.position = Vector3(0, 0, -16.0 * VOXEL - 0.0012)
	blink.scale = Vector3(1, 1, 0.04)
	blink.visible = false
	if _lod:
		blink.visibility_range_end = VoxMesh.lod_distance
	head.add_child(blink)
	head.scale = Vector3.ONE * clampf(float(a["head_scale"]), 0.85, 1.2)

	HairStyles.build_springs(head, s, kh)
	HairStyles.build_ears(head, s, str(a["ears"]), kh)
	HairStyles.build_tail(hips, s, str(a["tail"]), "%s|%s" % [kb, str(a["ear_color"])])
	OutfitBuilder.build_cloth(hips, s, kb)

	rig.body_scale = clampf(float(a["height"]), 0.85, 1.15)
	rig.scale = Vector3.ONE * rig.body_scale
	rig.setup()
	if equip_visual.has("weapon") and equip_visual["weapon"] is Dictionary and not (equip_visual["weapon"] as Dictionary).is_empty():
		WeaponBuilder.attach_to_rig(rig, equip_visual["weapon"], true)
	var recs: Variant = VoxMesh.end_batch()
	_lod = prev_lod
	if async and recs is Array and not (recs as Array).is_empty():
		rig.set_pending_meshes(recs)
	return rig


## 头部画布：颈 + 头颅 + 五官 + 耳 + 发帽 + 发饰 + 龙角 + 颈饰
static func head_canvas(s: CharSpec) -> VoxCanvas:
	var ears := s.ears
	var horns := str(s.a.get("horns", "none"))
	var lo := Vector3i(-25, -4, -22)
	var hi := Vector3i(24, 44, 24)
	if ears == "elf":
		lo.x = -30
		hi.x = 29
	if s.hair_style == "bun" or s.hair_style == "double_bun":
		hi.y = 56
	if horns == "dragon":
		hi.y = 64
		hi.z = 28
		lo.x = mini(lo.x, -28)
		hi.x = maxi(hi.x, 27)
	var cv := VoxCanvas.new(lo, hi)
	FacePainter.paint_head(cv, s)
	if ears == "human" or ears == "elf":
		FacePainter.paint_ears(cv, s, ears)
	HairStyles.paint_cap(cv, s)
	if ears == "elf":
		FacePainter.paint_ears(cv, s, ears)
	HairStyles.paint_extras(cv, s)
	if horns == "dragon":
		HairStyles.paint_horns(cv, s)
	OutfitBuilder.paint_neck(cv, s)
	return cv


static func body_key(s: CharSpec) -> String:
	var a := s.a
	return "%s|%d%d%d%d%d%d|%d|%s|%s|%s" % [
		"f" if s.female else "m", s.leg_w, s.waist_w, s.chest_w, s.torso_d, s.arm_w, s.arm_d,
		int(s.chest * 4.0), str(a.get("skin", "")), s.outfit, str(a.get("outfit_colors", [])),
	]


static func head_key(s: CharSpec) -> String:
	var a := s.a
	var parts: Array[String] = ["f" if s.female else "m"]
	for k in ["skin", "hair_style", "hair_color", "hair_color2", "eye_color", "eye_style", "brow_style", "mark", "mark_color", "ears", "ear_color", "horns", "outfit"]:
		parts.append(str(a.get(k, "")))
	parts.append(str(a.get("outfit_colors", [])))
	return "|".join(parts)


static func _bone(parent: Node3D, bone_name: String, pos_vox: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = bone_name
	n.position = pos_vox * VOXEL
	parent.add_child(n)
	return n


## 请求角色部件网格对（[LOD0, LOD1]），maker 返回 VoxCanvas（或数组）
static func part(key: String, maker: Callable) -> Array:
	return VoxMesh.part(key, maker, VOXEL)


## 挂部件网格（LOD0 + 可选 LOD1）
static func mesh(bone_node: Node3D, pair: Array, mirror: bool = false, mesh_name: String = "Mesh") -> MeshInstance3D:
	return VoxMesh.attach(bone_node, pair, mesh_name, mirror, _lod)


# ================================================================ 随机外貌（NPC）

static var _palette: Dictionary = {}


static func _load_palette() -> Dictionary:
	if not _palette.is_empty():
		return _palette
	var f := FileAccess.open("res://data/appearance.json", FileAccess.READ)
	if f != null:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			_palette = d
	if _palette.is_empty():
		_palette = {
			"hair_colors": ["#1a1a22", "#8a4a2a", "#c8201e"], "eye_colors": ["#1a1a1a", "#f0a020"],
			"skin_colors": ["#f3d2bd"], "outfit_palettes": [["#b3201c", "#3b2618", "#e2b23c"]],
		}
	return _palette


static func _pick(rng: RandomNumberGenerator, arr: Array) -> Variant:
	return arr[rng.randi_range(0, arr.size() - 1)]


## 按权重挑选：pairs = [[值, 权重], ...]
static func _wpick(rng: RandomNumberGenerator, pairs: Array) -> Variant:
	var total := 0.0
	for p in pairs:
		total += float(p[1])
	var r := rng.randf() * total
	for p in pairs:
		r -= float(p[1])
		if r <= 0.0:
			return p[0]
	return pairs[pairs.size() - 1][0]


## 随机生成好看的 NPC 外貌（调色板取自 data/appearance.json）。gender 为空时随机。
static func random_appearance(rng: RandomNumberGenerator, gender: String = "") -> Dictionary:
	var pal := _load_palette()
	var female := gender == "female" if gender != "" else rng.randf() < 0.5
	var a := {}
	a["gender"] = "female" if female else "male"
	a["height"] = snappedf(rng.randf_range(0.93, 1.0) if female else rng.randf_range(0.98, 1.07), 0.01)
	a["build"] = snappedf(rng.randf_range(0.15, 0.6) if female else rng.randf_range(0.3, 0.9), 0.01)
	a["head_scale"] = snappedf(rng.randf_range(0.97, 1.08) if female else rng.randf_range(0.94, 1.02), 0.01)
	a["chest"] = snappedf(rng.randf_range(0.25, 0.7), 0.01) if female else 0.0
	a["skin"] = _pick(rng, pal.get("skin_colors", ["#f3d2bd"]))
	# 发色：自然色（黑/棕/白/金）更常见
	var hair_pool: Array = pal.get("hair_colors", ["#1a1a22"])
	var natural: Array = []
	for hcol in hair_pool:
		var c := col(hcol)
		if c.s < 0.45 or c.v < 0.25 or (c.h > 0.04 and c.h < 0.16):
			natural.append(hcol)
	var hair: String = str(_pick(rng, natural if (rng.randf() < 0.7 and not natural.is_empty()) else hair_pool))
	a["hair_color"] = hair
	a["hair_color2"] = _highlight_of(col(hair), rng)
	if female:
		a["hair_style"] = _wpick(rng, [["twin_tails", 2], ["ponytail", 3], ["long", 3], ["short", 1], ["bun", 2], ["flowing", 3], ["double_bun", 1.5], ["braid", 2]])
	else:
		a["hair_style"] = _wpick(rng, [["short", 3], ["bun", 4], ["ponytail", 3], ["long", 2], ["flowing", 1], ["braid", 0.5]])
	a["eye_color"] = _pick(rng, pal.get("eye_colors", ["#1a1a1a"]))
	a["eye_style"] = _wpick(rng, [["almond", 3], ["round", 2], ["sharp", 2], ["droopy", 1.5]]) if female else _wpick(rng, [["almond", 2], ["sharp", 3], ["round", 1], ["droopy", 1]])
	a["brow_style"] = rng.randi_range(0, 2)
	a["mark"] = _wpick(rng, [["none", 6], ["lotus", 2], ["flame", 1], ["dot", 2], ["crescent", 1], ["tear", 1]]) if female else _wpick(rng, [["none", 12], ["dot", 1], ["flame", 1], ["crescent", 0.5]])
	a["mark_color"] = _pick(rng, ["#e02040", "#d02030", "#f05060", "#e0a020", "#40a0e0"])
	var ears: String
	if female:
		ears = _wpick(rng, [["human", 12], ["fox", 3], ["cat", 2], ["elf", 3]])
	else:
		ears = _wpick(rng, [["human", 18], ["fox", 1], ["elf", 1], ["cat", 0.5]])
	a["ears"] = ears
	var hc := col(hair)
	a["ear_color"] = ("#" + hc.darkened(0.1).to_html(false)) if rng.randf() < 0.6 else _pick(rng, ["#7a4424", "#e8e0d8", "#2a2228", "#c87a3a"])
	a["tail"] = "fox" if ears == "fox" and rng.randf() < 0.5 else "none"
	a["horns"] = "dragon" if rng.randf() < 0.05 else "none"
	a["outfit"] = _wpick(rng, [["robe", 5], ["martial", 3], ["armor", 2]])
	a["outfit_colors"] = (_pick(rng, pal.get("outfit_palettes", [["#b3201c", "#3b2618", "#e2b23c"]])) as Array).duplicate()
	return a


## 挑染色：同色相更亮（深色头发用冷灰高光）
static func _highlight_of(c: Color, rng: RandomNumberGenerator) -> String:
	var h: Color
	if c.v < 0.2:
		h = Color(0.32, 0.33, 0.42)
	elif c.s < 0.15:
		h = c.lerp(Color(1, 1, 1), 0.5) if c.v < 0.8 else Color(0.82, 0.86, 0.98)
	else:
		h = Color.from_hsv(c.h + rng.randf_range(-0.03, 0.03), c.s * 0.8, minf(c.v * 1.3 + 0.08, 1.0))
	return "#" + h.to_html(false)
