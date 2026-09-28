class_name Elem
## 五行常量与相生相克关系。所有数据与代码中五行均以字符串 id 表示。

const METAL := "metal"
const WOOD := "wood"
const WATER := "water"
const FIRE := "fire"
const EARTH := "earth"
const NONE := "none"

const LIST: Array[String] = ["metal", "wood", "water", "fire", "earth"]

const NAMES := {
	"metal": "金", "wood": "木", "water": "水", "fire": "火", "earth": "土", "none": "无",
}

const COLORS := {
	"metal": Color(0.98, 0.86, 0.42),
	"wood": Color(0.36, 0.86, 0.42),
	"water": Color(0.30, 0.66, 1.0),
	"fire": Color(1.0, 0.36, 0.14),
	"earth": Color(0.80, 0.60, 0.30),
	"none": Color(0.80, 0.90, 1.0),
}

## 相生：key 生 value（金生水、水生木、木生火、火生土、土生金）
const GENERATES := {
	"metal": "water", "water": "wood", "wood": "fire", "fire": "earth", "earth": "metal",
}

## 相克：key 克 value（金克木、木克土、土克水、水克火、火克金）
const OVERCOMES := {
	"metal": "wood", "wood": "earth", "earth": "water", "water": "fire", "fire": "metal",
}

## 每个元素的招牌状态
const STATUS := {
	"metal": "bleed", "wood": "poison", "water": "bind", "fire": "burn", "earth": "stagger",
}


static func name_of(e: String) -> String:
	return NAMES.get(e, "无")


static func color_of(e: String) -> Color:
	return COLORS.get(e, COLORS["none"])


static func is_valid(e: String) -> bool:
	return LIST.has(e)


## 攻击方元素对防御方主元素的克制倍率
static func counter_mult(attacker: String, defender: String) -> float:
	if OVERCOMES.get(attacker, "") == defender:
		return 1.2
	if OVERCOMES.get(defender, "") == attacker:
		return 0.9
	return 1.0


## 两元素是否相生（任一方向）
static func generates_pair(a: String, b: String) -> bool:
	return GENERATES.get(a, "") == b or GENERATES.get(b, "") == a
