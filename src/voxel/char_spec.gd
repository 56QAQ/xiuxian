class_name CharSpec
extends RefCounted
## 由外貌字典推导出的体型尺寸与配色（体素单位，VOXEL = 0.0125m），供各绘制模块共用。
## 全部字段在主线程一次算好，绘制（可能在工作线程中）只读，不得写入。
##
## 体素坐标约定（height = 1 时；骨骼位置见 CharacterBuilder，米制与旧版 0.025m 体素完全一致）：
##   hips 原点 (0,60,0)；骨盆 y -8..7；腿 leg_l/r 在 hips (∓leg_x, 0, 0)；大腿 30 高；shin 在 -30（膝）
##   spine 原点 hips+(0,6,0)；腰 y 0..11，胸 y 12..35（顶面即肩线）
##   head  原点 spine+(0,36,0)；颈 y -2..5，头 32³（x -16..15，y 4..35，z -16..15），脸在 z=-16 面
##   arm_l/r 原点 spine+(∓arm_x,32,0)；上臂 -24..+3；forearm 在 -24（肘）；hand 在 forearm -22（腕）
##   hand 原点 = 拳心（武器握把穿过此处，沿 Z）

var a: Dictionary
var female: bool = true
var build: float = 0.4
var chest: float = 0.5
var outfit: String = "armor"
var hair_style: String = "twin_tails"
var eye_style: String = "almond"
var ears: String = "human"

# ---- 尺寸（体素）
var leg_w: int = 14
var leg_d: int = 14
var leg_x: float = 8.0
var hip_w: int = 28
var waist_w: int = 24
var chest_w: int = 28
var torso_d: int = 14
var arm_w: int = 12
var arm_d: int = 12
var arm_x: float = 20.0
var hand_w: int = 10
var neck_w: int = 8

# ---- 颜色
var skin: Color
var skin_sh: Color     ## 皮肤暗部
var skin_dk: Color     ## 深暗部（指缝、耳内）
var skin_hi: Color
var blush: Color
var lip: Color
var hair: Color
var hair2: Color
var hair_dk: Color
var hair_hi: Color
var hair_line: Color   ## 发丝缝（最深）
var eye: Color
var mark_color: Color
var ear_color: Color
var c1: Color          ## 主色
var c2: Color          ## 副色
var c3: Color          ## 饰边
var c1_sh: Color
var c1_hi: Color
var c2_sh: Color
var c2_hi: Color
var gem: Color
var gem_hi: Color
var gem_sh: Color
var gold: Color
var gold_hi: Color
var gold_sh: Color
var gold_dk: Color
var lash: Color
var brow: Color
## 发丝颜色表（64 种：明暗、挑染、冷暖微差），按发丝编号取
var strand: Array[Color] = []


static func from(appearance: Dictionary) -> CharSpec:
	var s := CharSpec.new()
	s.a = appearance
	var ap := appearance
	s.female = str(ap.get("gender", "female")) != "male"
	s.build = clampf(float(ap.get("build", 0.4)), 0.0, 1.0)
	s.chest = clampf(float(ap.get("chest", 0.5)), 0.0, 1.0) if s.female else 0.0
	s.outfit = str(ap.get("outfit", "armor"))
	s.hair_style = str(ap.get("hair_style", "twin_tails"))
	s.eye_style = str(ap.get("eye_style", "almond"))
	s.ears = str(ap.get("ears", "human"))
	if s.female:
		s.leg_w = 14 if s.build < 0.8 else 16
		s.leg_d = 14
		s.waist_w = 22 + int(round(s.build * 4.0))
		s.chest_w = 28
		s.torso_d = 14
		s.arm_w = 12
		s.arm_d = 12
		s.hand_w = 10
		s.neck_w = 8
	else:
		s.leg_w = 16
		s.leg_d = 16
		s.waist_w = 26 + int(round(s.build * 6.0))
		s.chest_w = 32 if s.build < 0.55 else 36
		s.torso_d = 16 if s.build < 0.75 else 18
		s.arm_w = 14 if s.build < 0.35 else 16
		s.arm_d = 14 if s.build < 0.35 else 16
		s.hand_w = 12
		s.neck_w = 12
	s.hip_w = s.leg_w * 2
	s.leg_x = s.leg_w / 2.0 + 1.0
	s.arm_x = s.chest_w / 2.0 + s.arm_w / 2.0
	# ---- 颜色
	var sk := CharacterBuilder.col(ap.get("skin", "#f3d2bd"), Color("f3d2bd"))
	# 动漫肤色：略提饱和度、偏粉，避免在亮光下发白
	var boost := 1.35 if sk.v > 0.9 else (1.15 if sk.v > 0.8 else 1.0)
	s.skin = Color.from_hsv(sk.h, minf(sk.s * boost + (0.02 if sk.v > 0.9 else 0.0), 1.0), sk.v * 0.99)
	s.skin_sh = Color(s.skin.r * 0.9, s.skin.g * 0.74, s.skin.b * 0.72)
	s.skin_dk = Color(s.skin.r * 0.72, s.skin.g * 0.52, s.skin.b * 0.52)
	s.skin_hi = VoxCanvas.tone(s.skin, 1.05)
	s.blush = s.skin.lerp(Color(1.0, 0.42, 0.48), 0.3)
	s.lip = s.skin.lerp(Color(0.86, 0.36, 0.4), 0.55)
	s.hair = CharacterBuilder.col(ap.get("hair_color", "#c8201e"), Color("c8201e"))
	s.hair2 = CharacterBuilder.col(ap.get("hair_color2", ""), s.hair.lightened(0.25))
	s.hair_dk = Color(s.hair.r * 0.6, s.hair.g * 0.55, s.hair.b * 0.62)
	s.hair_line = Color(s.hair.r * 0.42, s.hair.g * 0.38, s.hair.b * 0.46)
	s.hair_hi = s.hair.lerp(s.hair2.lightened(0.2), 0.55)
	s.eye = CharacterBuilder.col(ap.get("eye_color", "#f0a020"), Color("f0a020"))
	s.mark_color = CharacterBuilder.col(ap.get("mark_color", "#e02040"), Color("e02040"))
	s.ear_color = CharacterBuilder.col(ap.get("ear_color", ""), s.hair)
	var cols: Array = ap.get("outfit_colors", ["#b3201c", "#3b2618", "#e2b23c"])
	while cols.size() < 3:
		cols = cols + ["#808080"]
	s.c1 = CharacterBuilder.col(cols[0], Color("b3201c"))
	s.c2 = CharacterBuilder.col(cols[1], Color("3b2618"))
	s.c3 = CharacterBuilder.col(cols[2], Color("e2b23c"))
	s.c1_sh = VoxCanvas.shade(s.c1, 0.74, -0.3)
	s.c1_hi = s.c1.lerp(Color(1, 0.98, 0.92), 0.16)
	s.c2_sh = VoxCanvas.shade(s.c2, 0.7, -0.3)
	s.c2_hi = s.c2.lerp(Color(1, 0.96, 0.9), 0.14)
	# 宝石：默认朱红；主色为蓝/绿/紫时换成同色系宝石
	s.gem = Color("e8283a")
	if s.c1.s > 0.4:
		if s.c1.h > 0.5 and s.c1.h < 0.72:
			s.gem = Color("38c0ff")
		elif s.c1.h > 0.22 and s.c1.h <= 0.5:
			s.gem = Color("38e088")
		elif s.c1.h >= 0.72 and s.c1.h < 0.9:
			s.gem = Color("c050ff")
	s.gem_hi = s.gem.lerp(Color(1, 1, 1), 0.55)
	s.gem_sh = Color(s.gem.r * 0.5, s.gem.g * 0.45, s.gem.b * 0.55)
	# 金属饰边：饰边色的高光/暗部
	s.gold = s.c3
	s.gold_hi = s.c3.lerp(Color(1, 0.98, 0.85), 0.55)
	s.gold_sh = Color(s.c3.r * 0.66, s.c3.g * 0.54, s.c3.b * 0.42)
	s.gold_dk = Color(s.c3.r * 0.42, s.c3.g * 0.32, s.c3.b * 0.24)
	s.lash = Color(0.16, 0.08, 0.08).lerp(s.hair.darkened(0.6), 0.25)
	s.brow = s.hair.darkened(0.35).lerp(s.lash, 0.3)
	# 发丝颜色表（单根发丝只做细微明暗，发绺层次由 lock_tone 决定）
	for i in 64:
		var h := VoxCanvas.h1(i * 7 + 3)
		var k: float = [0.93, 0.96, 0.98, 1.0, 1.0, 1.02, 1.05, 0.97][h & 7]
		var c := VoxCanvas.tone(s.hair, k)
		var hs := (h >> 4) % 17
		if hs == 0:
			c = c.lerp(s.hair2, 0.6)
		elif hs < 3:
			c = c.lerp(s.hair2, 0.22)
		s.strand.append(c)
	return s


static var _LOCK_K: PackedFloat32Array = PackedFloat32Array([0.86, 0.93, 1.0, 0.9, 1.05, 0.96, 1.08, 0.89])


## 发绺整体明暗（按发绺编号）
static func lock_tone(lock_id: int) -> float:
	return _LOCK_K[VoxCanvas.h1(lock_id * 5 + 2) & 7]


## 发丝颜色（sid 为发丝编号）
func strand_c(sid: int) -> Color:
	return strand[VoxCanvas.h1(sid) & 63]
