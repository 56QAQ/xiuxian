class_name PlayerData
extends RefCounted
## 玩家存档数据（纯数据 + 序列化）。计算逻辑见 BuildCalc / Cultivation。

const ATTRS: Array[String] = ["con", "int", "spi", "agi", "luk"]
const ATTR_NAMES := {"con": "根骨", "int": "悟性", "spi": "神识", "agi": "身法", "luk": "气运"}
const EQUIP_SLOTS: Array[String] = ["weapon", "armor", "accessory1", "accessory2", "bag"]
const PROFESSIONS: Array[String] = ["alchemy", "forging", "talisman", "formation", "herbalism"]
const PROFESSION_NAMES := {"alchemy": "炼丹", "forging": "炼器", "talisman": "制符", "formation": "阵法", "herbalism": "灵植"}

# ---- 身份
var name: String = "无名"
var gender: String = "female"
var appearance: Dictionary = {}
var background: String = "rogue"

# ---- 先天
var roots: Dictionary = {}          ## element -> 百分比(int)，合计 100
var attributes: Dictionary = {"con": 5, "int": 5, "spi": 5, "agi": 5, "luk": 5}
var talents: Array = []             ## talent ids

# ---- 修为
var realm: int = 0
var stage: int = 0
var cult_exp: float = 0.0
var age_days: float = 16.0 * 360.0
var pill_toxicity: float = 0.0      ## 0~100
var injury_days: float = 0.0        ## 受伤剩余天数
var breakthrough_fails: int = 0

# ---- 资源
var spirit_stones: int = 0
var bag: InventoryGrid = InventoryGrid.new(6, 5)
var secure: InventoryGrid = InventoryGrid.new(2, 2)     ## 本命空间
var stash: InventoryGrid = InventoryGrid.new(12, 16)    ## 洞府仓库
var equipment: Dictionary = {}      ## slot -> ItemInstance
var quick_item: String = ""         ## Q 键快捷使用的物品 id

# ---- 功法 / 法诀
var techniques: Dictionary = {}     ## id -> {"lv": int(0~3), "xp": float}
var main_technique: String = ""
var aux_techniques: Array = ["", ""]
var spells: Dictionary = {}         ## id -> {"lv": int(0~9), "xp": float}
var spell_slots: Array = ["", "", "", "", ""]

# ---- 生产
var professions: Dictionary = {}    ## id -> {"lv": int, "xp": float}
var known_recipes: Array = []

# ---- 门派与因果
var sect: String = ""
var sect_rank: int = 0
var contribution: Dictionary = {}   ## sect -> 贡献点
var reputation: Dictionary = {}     ## sect -> 声望（累计）
var karma: int = 0                  ## 业力（袭杀无辜等增加）
var flags: Dictionary = {}

# ---- 统计
var kills: int = 0
var realms_cleared: int = 0


func _init() -> void:
	for p in PROFESSIONS:
		professions[p] = {"lv": 0, "xp": 0.0}


func root_count() -> int:
	var n := 0
	for e in roots:
		if int(roots[e]) > 0:
			n += 1
	return n


## 主元素（占比最高的灵根）
func main_element() -> String:
	var best := Elem.NONE
	var bv := -1
	for e in Elem.LIST:
		var v := int(roots.get(e, 0))
		if v > bv:
			bv = v
			best = e
	return best


func root_pct(e: String) -> float:
	return float(roots.get(e, 0)) / 100.0


func has_talent(id: String) -> bool:
	return talents.has(id)


func age_years() -> int:
	return int(age_days / 360.0)


func equipped(slot: String) -> ItemInstance:
	return equipment.get(slot, null)


func weapon_kind() -> String:
	var w := equipped("weapon")
	if w == null:
		return "fist"
	return str(w.def().get("weapon", {}).get("kind", "fist"))


func technique_level(id: String) -> int:
	return int(techniques.get(id, {}).get("lv", 0))


func spell_level(id: String) -> int:
	return int(spells.get(id, {}).get("lv", 0))


func profession_level(p: String) -> int:
	return int(professions.get(p, {}).get("lv", 0))


# ---------------------------------------------------------------- 序列化

func to_dict() -> Dictionary:
	var eq := {}
	for s in equipment:
		if equipment[s] != null:
			eq[s] = equipment[s].to_dict()
	return {
		"name": name, "gender": gender, "appearance": appearance, "background": background,
		"roots": roots, "attributes": attributes, "talents": talents,
		"realm": realm, "stage": stage, "cult_exp": cult_exp, "age_days": age_days,
		"pill_toxicity": pill_toxicity, "injury_days": injury_days, "breakthrough_fails": breakthrough_fails,
		"spirit_stones": spirit_stones,
		"bag": bag.to_dict(), "secure": secure.to_dict(), "stash": stash.to_dict(),
		"equipment": eq, "quick_item": quick_item,
		"techniques": techniques, "main_technique": main_technique, "aux_techniques": aux_techniques,
		"spells": spells, "spell_slots": spell_slots,
		"professions": professions, "known_recipes": known_recipes,
		"sect": sect, "sect_rank": sect_rank, "contribution": contribution, "reputation": reputation,
		"karma": karma, "flags": flags, "kills": kills, "realms_cleared": realms_cleared,
	}


static func from_dict(d: Dictionary) -> PlayerData:
	var p := PlayerData.new()
	p.name = d.get("name", p.name)
	p.gender = d.get("gender", p.gender)
	p.appearance = d.get("appearance", {})
	p.background = d.get("background", p.background)
	p.roots = _int_dict(d.get("roots", {}))
	p.attributes = _int_dict(d.get("attributes", p.attributes))
	p.talents = d.get("talents", [])
	p.realm = int(d.get("realm", 0))
	p.stage = int(d.get("stage", 0))
	p.cult_exp = float(d.get("cult_exp", 0.0))
	p.age_days = float(d.get("age_days", p.age_days))
	p.pill_toxicity = float(d.get("pill_toxicity", 0.0))
	p.injury_days = float(d.get("injury_days", 0.0))
	p.breakthrough_fails = int(d.get("breakthrough_fails", 0))
	p.spirit_stones = int(d.get("spirit_stones", 0))
	if d.has("bag"):
		p.bag = InventoryGrid.from_dict(d["bag"])
	if d.has("secure"):
		p.secure = InventoryGrid.from_dict(d["secure"])
	if d.has("stash"):
		p.stash = InventoryGrid.from_dict(d["stash"])
	for s in d.get("equipment", {}):
		p.equipment[s] = ItemInstance.from_dict(d["equipment"][s])
	p.quick_item = d.get("quick_item", "")
	p.techniques = d.get("techniques", {})
	p.main_technique = d.get("main_technique", "")
	p.aux_techniques = d.get("aux_techniques", ["", ""])
	p.spells = d.get("spells", {})
	p.spell_slots = d.get("spell_slots", ["", "", "", "", ""])
	var profs: Dictionary = d.get("professions", {})
	for k in profs:
		p.professions[k] = profs[k]
	p.known_recipes = d.get("known_recipes", [])
	p.sect = d.get("sect", "")
	p.sect_rank = int(d.get("sect_rank", 0))
	p.contribution = d.get("contribution", {})
	p.reputation = d.get("reputation", {})
	p.karma = int(d.get("karma", 0))
	p.flags = d.get("flags", {})
	p.kills = int(d.get("kills", 0))
	p.realms_cleared = int(d.get("realms_cleared", 0))
	return p


static func _int_dict(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		out[k] = int(src[k])
	return out
