class_name ItemInstance
extends RefCounted
## 一件（一堆）具体物品。定义数据来自 DB.items[id]，实例只保存可变部分。

static var _next_uid: int = 1

var uid: int = 0
var id: String = ""
var count: int = 1
## 实例品阶（-1 表示使用定义中的品阶）。随机掉落的法器会覆盖品阶。
var grade: int = -1
## 随机词条：[{ "k": "attack_pct", "v": 0.05 }, ...]
var affixes: Array = []
## 附加数据（如 灵植种子的成熟时间、法诀玉简的来源等）
var extra: Dictionary = {}


static func create(item_id: String, n: int = 1) -> ItemInstance:
	var it := ItemInstance.new()
	it.uid = _next_uid
	_next_uid += 1
	it.id = item_id
	it.count = maxi(n, 1)
	if DB.item(item_id).is_empty():
		push_warning("ItemInstance: 未知物品 id %s" % item_id)
	return it


func def() -> Dictionary:
	return DB.item(id)


func type() -> String:
	return str(def().get("type", "misc"))


func display_name() -> String:
	return str(def().get("name", id))


func get_grade() -> int:
	return grade if grade >= 0 else int(def().get("grade", 0))


func color() -> Color:
	return Grade.color_of(get_grade())


func element() -> String:
	return str(def().get("element", Elem.NONE))


func max_stack() -> int:
	return maxi(int(def().get("stack", 1)), 1)


func is_stackable() -> bool:
	return max_stack() > 1


## 占格尺寸（未旋转）
func size() -> Vector2i:
	var s: Array = def().get("size", [1, 1])
	return Vector2i(int(s[0]), int(s[1]))


## 单价（灵石）。高品阶随机法器按品阶放大。
func unit_value() -> int:
	var base := int(def().get("value", 1))
	var dg := int(def().get("grade", 0))
	if grade > dg:
		base = int(base * pow(2.2, grade - dg))
	return base


func total_value() -> int:
	return unit_value() * count


func can_stack_with(other: ItemInstance) -> bool:
	return other != null and other.id == id and is_stackable() and other.grade == grade and affixes.is_empty() and other.affixes.is_empty()


## 该装备提供的属性修正（含词条），非装备返回空
func equip_mods() -> Dictionary:
	var d := def()
	var mods := {}
	var scale := 1.0 + 0.35 * maxf(get_grade() - int(d.get("grade", 0)), 0)
	if d.has("weapon"):
		var w: Dictionary = d["weapon"]
		mods["attack"] = float(w.get("attack", 0)) * scale
		Stats.add_mods(mods, w.get("stats", {}), scale)
	if d.has("equip"):
		Stats.add_mods(mods, d["equip"].get("stats", {}), scale)
	for a in affixes:
		mods[a["k"]] = float(mods.get(a["k"], 0.0)) + float(a["v"])
	return mods


func split(n: int) -> ItemInstance:
	n = clampi(n, 1, count)
	var other := ItemInstance.create(id, n)
	other.grade = grade
	other.affixes = affixes.duplicate(true)
	other.extra = extra.duplicate(true)
	count -= n
	return other


func to_dict() -> Dictionary:
	var d := {"id": id, "n": count}
	if grade >= 0:
		d["g"] = grade
	if not affixes.is_empty():
		d["a"] = affixes
	if not extra.is_empty():
		d["x"] = extra
	return d


static func from_dict(d: Dictionary) -> ItemInstance:
	var it := ItemInstance.create(str(d.get("id", "")), int(d.get("n", 1)))
	it.grade = int(d.get("g", -1))
	it.affixes = d.get("a", [])
	it.extra = d.get("x", {})
	return it


## 物品描述（多行文本），供 tooltip 使用
func describe() -> String:
	var d := def()
	var lines: PackedStringArray = []
	lines.append("%s · %s" % [Grade.name_of(get_grade()), _type_name(type())])
	if element() != Elem.NONE and Elem.is_valid(element()):
		lines.append("五行：%s" % Elem.name_of(element()))
	if d.has("weapon"):
		lines.append("兵器：%s  攻击 %d" % [_weapon_name(str(d["weapon"].get("kind", ""))), int(equip_mods().get("attack", 0))])
	var mods := equip_mods()
	for k in mods:
		if k == "attack" and d.has("weapon"):
			continue
		lines.append(Stats.format_mod(k, mods[k]))
	if d.has("use"):
		lines.append("[使用] " + str(d["use"].get("text", "")))
	if d.has("refine"):
		lines.append("[可炼化] 修为 +%d" % int(d["refine"].get("exp", 0)))
	if d.has("desc"):
		lines.append(str(d["desc"]))
	lines.append("价值：%d 灵石" % unit_value())
	return "\n".join(lines)


static func _type_name(t: String) -> String:
	return {
		"weapon": "法器·兵刃", "armor": "法器·法衣", "accessory": "法器·佩饰", "pill": "丹药",
		"material": "材料", "currency": "灵石", "manual": "玉简", "talisman": "符箓",
		"treasure": "天材地宝", "bag": "储物袋", "formation": "阵盘", "seed": "灵种",
		"key": "信物", "misc": "杂物",
	}.get(t, t)


static func _weapon_name(k: String) -> String:
	return {"sword": "剑", "saber": "刀", "spear": "枪", "fist": "拳套"}.get(k, k)
