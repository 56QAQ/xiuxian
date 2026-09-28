class_name Grade
## 品阶：0 凡 1 灵 2 玄 3 地 4 天 5 仙

const MAX := 5

const NAMES: Array[String] = ["凡品", "灵品", "玄品", "地品", "天品", "仙品"]
const SHORT: Array[String] = ["凡", "灵", "玄", "地", "天", "仙"]

const COLORS: Array[Color] = [
	Color(0.78, 0.78, 0.76),
	Color(0.40, 0.85, 0.45),
	Color(0.35, 0.62, 1.0),
	Color(0.72, 0.42, 1.0),
	Color(1.0, 0.62, 0.18),
	Color(1.0, 0.25, 0.30),
]

## 功法/法诀阶位用“黄玄地天”称呼
const ART_NAMES: Array[String] = ["黄阶下品", "黄阶上品", "玄阶", "地阶", "天阶", "仙阶"]


static func name_of(g: int) -> String:
	return NAMES[clampi(g, 0, MAX)]


static func color_of(g: int) -> Color:
	return COLORS[clampi(g, 0, MAX)]


static func art_name(g: int) -> String:
	return ART_NAMES[clampi(g, 0, MAX)]
