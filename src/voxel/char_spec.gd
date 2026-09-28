class_name CharSpec
extends RefCounted
## 由外貌字典推导出的体型尺寸与配色（体素单位），供各绘制模块共用。
##
## 体素坐标约定（height = 1 时）：
##   hips 原点 (0,28,0)；骨盆 y -4..3；腿 leg_l/r 在 hips (∓leg_x, 0, 0)；大腿 14 高；shin 在 -14（膝）
##   spine 原点 hips+(0,4,0)；腰 y 0..6，胸 y 7..19
##   head  原点 spine+(0,20,0)；颈 y 0..1，头 16³（x -8..7，y 2..17，z -8..7），脸在 z=-8 面
##   arm_l/r 原点 spine+(∓arm_x,18,0)；上臂 -12..+1；forearm 在 -12（肘）；hand 在 forearm -11（腕）
##   hand 原点 = 拳心（武器握把穿过此处，沿 Z）

var a: Dictionary
var female: bool = true
var build: float = 0.4
var chest: float = 0.5
var outfit: String = "armor"
var hair_style: String = "twin_tails"

# ---- 尺寸（体素）
var leg_w: int = 7
var leg_d: int = 7
var leg_x: float = 3.5
var hip_w: int = 14
var waist_w: int = 12
var chest_w: int = 14
var torso_d: int = 7
var arm_w: int = 6
var arm_d: int = 6
var arm_x: float = 10.0
var hand_w: int = 5
var neck_w: int = 4

# ---- 颜色
var skin: Color
var skin_sh: Color     ## 皮肤暗部
var skin_hi: Color
var hair: Color
var hair2: Color
var eye: Color
var mark_color: Color
var ear_color: Color
var c1: Color          ## 主色
var c2: Color          ## 副色
var c3: Color          ## 饰边
var gem: Color
var gold: Color
var gold_hi: Color
var gold_sh: Color
var lash: Color


static func from(appearance: Dictionary) -> CharSpec:
	var s := CharSpec.new()
	s.a = appearance
	var ap := appearance
	s.female = str(ap.get("gender", "female")) != "male"
	s.build = clampf(float(ap.get("build", 0.4)), 0.0, 1.0)
	s.chest = clampf(float(ap.get("chest", 0.5)), 0.0, 1.0) if s.female else 0.0
	s.outfit = str(ap.get("outfit", "armor"))
	s.hair_style = str(ap.get("hair_style", "twin_tails"))
	if s.female:
		s.leg_w = 7 if s.build < 0.8 else 8
		s.leg_d = 7
		s.waist_w = 12 if s.build < 0.7 else 14
		s.chest_w = 14
		s.torso_d = 7
		s.arm_w = 6
		s.arm_d = 6
		s.hand_w = 5
		s.neck_w = 4
	else:
		s.leg_w = 8
		s.leg_d = 8
		s.waist_w = 14 if s.build < 0.65 else 16
		s.chest_w = 16 if s.build < 0.55 else 18
		s.torso_d = 8 if s.build < 0.75 else 9
		s.arm_w = 7 if s.build < 0.35 else 8
		s.arm_d = 7 if s.build < 0.35 else 8
		s.hand_w = 6
		s.neck_w = 6
	s.hip_w = s.leg_w * 2
	s.leg_x = s.leg_w / 2.0 + 0.5
	s.arm_x = s.chest_w / 2.0 + s.arm_w / 2.0
	# ---- 颜色
	var sk := CharacterBuilder.col(ap.get("skin", "#f3d2bd"), Color("f3d2bd"))
	# 动漫肤色：略提饱和度、偏粉，避免在亮光下发白
	s.skin = Color.from_hsv(sk.h, minf(sk.s * 1.35 + 0.02, 1.0), sk.v * 0.99)
	s.skin_sh = Color(s.skin.r * 0.88, s.skin.g * 0.72, s.skin.b * 0.7)
	s.skin_hi = VoxCanvas.tone(s.skin, 1.04)
	s.hair = CharacterBuilder.col(ap.get("hair_color", "#c8201e"), Color("c8201e"))
	s.hair2 = CharacterBuilder.col(ap.get("hair_color2", ""), s.hair.lightened(0.25))
	s.eye = CharacterBuilder.col(ap.get("eye_color", "#f0a020"), Color("f0a020"))
	s.mark_color = CharacterBuilder.col(ap.get("mark_color", "#e02040"), Color("e02040"))
	s.ear_color = CharacterBuilder.col(ap.get("ear_color", ""), s.hair)
	var cols: Array = ap.get("outfit_colors", ["#b3201c", "#3b2618", "#e2b23c"])
	while cols.size() < 3:
		cols = cols + ["#808080"]
	s.c1 = CharacterBuilder.col(cols[0], Color("b3201c"))
	s.c2 = CharacterBuilder.col(cols[1], Color("3b2618"))
	s.c3 = CharacterBuilder.col(cols[2], Color("e2b23c"))
	# 宝石：默认朱红；主色为蓝/绿/紫时换成同色系宝石
	s.gem = Color("e8283a")
	if s.c1.s > 0.4:
		if s.c1.h > 0.5 and s.c1.h < 0.72:
			s.gem = Color("38c0ff")
		elif s.c1.h > 0.22 and s.c1.h <= 0.5:
			s.gem = Color("38e088")
		elif s.c1.h >= 0.72 and s.c1.h < 0.9:
			s.gem = Color("c050ff")
	# 金属饰边：饰边色的高光/暗部
	s.gold = s.c3
	s.gold_hi = s.c3.lerp(Color(1, 0.98, 0.85), 0.55)
	s.gold_sh = Color(s.c3.r * 0.62, s.c3.g * 0.5, s.c3.b * 0.4)
	s.lash = Color(0.16, 0.08, 0.08).lerp(s.hair.darkened(0.6), 0.25)
	return s
