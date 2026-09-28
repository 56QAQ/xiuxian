extends Node
## 游戏状态（autoload: GS）。持有玩家数据、世界数据、时间，并提供常用操作。

const HOURS_PER_DAY := 24.0
const DAYS_PER_MONTH := 30
const MONTHS_PER_YEAR := 12
const START_YEAR := 3721
const SHICHEN := ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]

var player: PlayerData = PlayerData.new()
var stats: Dictionary = Stats.DEFAULTS.duplicate()
## 世界状态（全部可序列化）：seed, hours, npcs, sects, missions, flags, home, encounters ...
var world: Dictionary = {}
var rng := RandomNumberGenerator.new()

## 当前修炼地点类型（见 Cultivation.LOCATION_MULT）
var location: String = "wild"
## 是否处于秘境中（秘境中不可存档）
var in_realm: bool = false
## 进入秘境时的参数 {realm_id, seed, entrance_pos}
var realm_request: Dictionary = {}
## 大地图上返回时的位置
var overworld_position: Vector3 = Vector3.INF
## 是否已有进行中的游戏
var active: bool = false


func _ready() -> void:
	rng.randomize()
	# 小境界/大境界变化时刷新属性（修炼、服丹、战斗感悟都可能触发）
	Events.realm_changed.connect(func(_r: int, _s: int) -> void:
		recompute()
		SectSystem.check_promotion())


# ================================================================ 新游戏

## creation: {name, gender, appearance, roots, attributes, talents, background, seed?}
func new_game(creation: Dictionary) -> void:
	player = PlayerData.new()
	player.name = str(creation.get("name", "无名"))
	player.gender = str(creation.get("gender", "female"))
	player.appearance = creation.get("appearance", {})
	player.roots = creation.get("roots", {"fire": 100})
	player.attributes = creation.get("attributes", player.attributes)
	player.talents = creation.get("talents", [])
	player.background = str(creation.get("background", "rogue"))
	var seed_value: int = int(creation.get("seed", randi()))
	rng.seed = seed_value
	world = {
		"seed": seed_value,
		"hours": 8.0,
		"npcs": {},
		"sects": {},
		"missions": [],
		"flags": {},
		"home": {"fields": [], "formation": ""},
		"encounters": {},
		"treasures": [],
	}
	_apply_background()
	WorldSetup.init_world(world, player, seed_value)
	overworld_position = Vector3.INF
	in_realm = false
	active = true
	recompute()


func _apply_background() -> void:
	var bg: Dictionary = DB.backgrounds.get(player.background, {})
	player.spirit_stones = int(bg.get("stones", 20))
	var bag_id: String = str(bg.get("bag", "bag_basic"))
	var bag_def := DB.item(bag_id)
	if not bag_def.is_empty():
		var b: Dictionary = bag_def.get("bag", {"w": 6, "h": 5})
		player.bag = InventoryGrid.new(int(b["w"]), int(b["h"]))
		player.equipment["bag"] = ItemInstance.create(bag_id)
	for entry in bg.get("items", []):
		give_item(str(entry[0]), int(entry[1]), false)
	for slot in bg.get("equip", {}):
		var it := ItemInstance.create(str(bg["equip"][slot]))
		player.equipment[slot] = it
	for tid in bg.get("techniques", []):
		learn_technique(tid, false)
	if player.main_technique == "" and not player.techniques.is_empty():
		player.main_technique = player.techniques.keys()[0]
	for sid in bg.get("spells", []):
		learn_spell(sid, false)
	var i := 0
	for sid in player.spells:
		if i < 4:
			player.spell_slots[i] = sid
			i += 1
	if bg.has("sect"):
		player.sect = str(bg["sect"])
	player.quick_item = str(bg.get("quick_item", "pill_heal_small"))


# ================================================================ 属性

func recompute() -> void:
	stats = BuildCalc.compute(player)
	Events.player_changed.emit()


# ================================================================ 时间

func hours() -> float:
	return float(world.get("hours", 0.0))


func day_index() -> int:
	return int(hours() / HOURS_PER_DAY)


func hour_of_day() -> float:
	return fmod(hours(), HOURS_PER_DAY)


func date_text() -> String:
	var d := day_index()
	var year := START_YEAR + d / (DAYS_PER_MONTH * MONTHS_PER_YEAR)
	var month := (d / DAYS_PER_MONTH) % MONTHS_PER_YEAR + 1
	var day := d % DAYS_PER_MONTH + 1
	var sc: String = SHICHEN[int(fmod(hour_of_day() + 1.0, 24.0) / 2.0) % 12]
	return "天元%d年%d月%d日 %s时" % [year, month, day, sc]


## 推进游戏时间（小时）。处理跨天事件。
func advance_time(h: float) -> void:
	if h <= 0.0:
		return
	var before := day_index()
	var injured_before := player.injury_days > 0.0
	var toxic_before := player.pill_toxicity > 50.0
	world["hours"] = hours() + h
	var after := day_index()
	Cultivation.pass_days(player, h / HOURS_PER_DAY)
	Events.time_advanced.emit(h)
	var changed := injured_before != (player.injury_days > 0.0) or toxic_before != (player.pill_toxicity > 50.0)
	if after > before:
		for d in range(before + 1, after + 1):
			Events.day_passed.emit(d)
		WorldSetup.simulate_days(world, player, after - before)
		changed = true
		if player.age_years() >= Cultivation.lifespan_years(player) - 1:
			Events.notify.emit("寿元将尽……", "bad")
	if changed:
		recompute()


# ================================================================ 物品

## 给予物品，优先放入储物袋，放不下则存入洞府仓库。返回实际放入储物袋的数量。
func give_item(id: String, n: int = 1, notify: bool = true, grade: int = -1) -> int:
	if DB.item(id).is_empty():
		push_warning("give_item: 未知物品 %s" % id)
		return 0
	if DB.item(id).get("type", "") == "currency":
		var per := int(DB.item(id).get("value", 1))
		add_stones(per * n, notify)
		return n
	var it := ItemInstance.create(id, n)
	it.grade = grade
	var left := player.bag.add(it)
	if left > 0:
		it.count = left
		player.stash.add(it)
		if notify:
			Events.notify.emit("储物袋已满，%s×%d 送回洞府" % [it.display_name(), left], "warn")
	if notify:
		Events.notify.emit("获得 %s ×%d" % [DB.item(id).get("name", id), n], "loot")
	Events.inventory_changed.emit()
	return n - left


func add_stones(n: int, notify: bool = true) -> void:
	player.spirit_stones += n
	if notify and n != 0:
		Events.notify.emit("灵石 %s%d" % ["+" if n > 0 else "", n], "loot")
	Events.inventory_changed.emit()


func spend_stones(n: int) -> bool:
	if player.spirit_stones < n:
		return false
	player.spirit_stones -= n
	Events.inventory_changed.emit()
	return true


## 从储物袋装备物品（entry 为 InventoryGrid 条目）
func equip_from(grid: InventoryGrid, entry: Dictionary) -> bool:
	var it: ItemInstance = entry["item"]
	var slot := slot_for(it)
	if slot == "":
		return false
	if slot == "accessory1" and player.equipped("accessory1") != null and player.equipped("accessory2") == null:
		slot = "accessory2"
	grid.remove_entry(entry)
	var old: ItemInstance = player.equipment.get(slot, null)
	player.equipment[slot] = it
	if slot == "bag":
		var b: Dictionary = it.def().get("bag", {"w": 6, "h": 5})
		for over in player.bag.resize(int(b["w"]), int(b["h"])):
			player.stash.add(over)
	if old != null:
		if grid.add(old) > 0:
			player.stash.add(old)
	recompute()
	Events.inventory_changed.emit()
	return true


func unequip(slot: String) -> bool:
	var it: ItemInstance = player.equipment.get(slot, null)
	if it == null or slot == "bag":
		return false
	if player.bag.add(it) > 0:
		Events.notify.emit("储物袋空间不足", "warn")
		return false
	player.equipment.erase(slot)
	recompute()
	Events.inventory_changed.emit()
	return true


static func slot_for(it: ItemInstance) -> String:
	match it.type():
		"weapon":
			return "weapon"
		"armor":
			return "armor"
		"accessory":
			return "accessory1"
		"bag":
			return "bag"
	return ""


# ================================================================ 功法 / 法诀

func learn_technique(id: String, notify: bool = true) -> bool:
	if DB.technique(id).is_empty() or player.techniques.has(id):
		return false
	player.techniques[id] = {"lv": 0, "xp": 0.0}
	if notify:
		Events.notify.emit("习得功法《%s》" % DB.technique(id).get("name", id), "good")
	recompute()
	return true


func learn_spell(id: String, notify: bool = true) -> bool:
	if DB.spell(id).is_empty() or player.spells.has(id):
		return false
	player.spells[id] = {"lv": 0, "xp": 0.0}
	if notify:
		Events.notify.emit("习得法诀【%s】" % DB.spell(id).get("name", id), "good")
	Events.player_changed.emit()
	return true


func set_spell_slot(i: int, id: String) -> void:
	if i < 0 or i >= BuildCalc.spell_slot_count(player):
		return
	for j in player.spell_slots.size():
		if player.spell_slots[j] == id and id != "":
			player.spell_slots[j] = ""
	player.spell_slots[i] = id
	recompute()


func set_main_technique(id: String) -> void:
	if id != "" and not player.techniques.has(id):
		return
	if player.aux_techniques.has(id):
		player.aux_techniques[player.aux_techniques.find(id)] = ""
	player.main_technique = id
	recompute()


func set_aux_technique(i: int, id: String) -> void:
	if id != "" and (not player.techniques.has(id) or player.main_technique == id):
		return
	for j in player.aux_techniques.size():
		if player.aux_techniques[j] == id and id != "":
			player.aux_techniques[j] = ""
	player.aux_techniques[i] = id
	recompute()


## 法诀熟练度增长（施放时调用）
func add_spell_xp(id: String, amount: float) -> void:
	if not player.spells.has(id):
		return
	var s: Dictionary = player.spells[id]
	s["xp"] = float(s.get("xp", 0.0)) + amount * float(stats.get("insight_gain", 1.0))
	var need := 20.0 * pow(1.8, int(s["lv"]))
	if int(s["lv"]) < 9 and float(s["xp"]) >= need:
		s["xp"] = float(s["xp"]) - need
		s["lv"] = int(s["lv"]) + 1
		Events.notify.emit("【%s】熟练度提升至 %d 重" % [DB.spell(id).get("name", id), int(s["lv"]) + 1], "good")


## 功法熟练度增长（修炼时调用）
func add_technique_xp(id: String, amount: float) -> void:
	if not player.techniques.has(id):
		return
	var t: Dictionary = player.techniques[id]
	t["xp"] = float(t.get("xp", 0.0)) + amount
	var need := 200.0 * pow(3.0, int(t["lv"]))
	if int(t["lv"]) < 3 and float(t["xp"]) >= need:
		t["xp"] = float(t["xp"]) - need
		t["lv"] = int(t["lv"]) + 1
		const LV := ["入门", "小成", "大成", "圆满"]
		Events.notify.emit("《%s》修炼至%s" % [DB.technique(id).get("name", id), LV[int(t["lv"])]], "good")
		recompute()


# ================================================================ 存档

func to_dict() -> Dictionary:
	return {
		"version": 1,
		"player": player.to_dict(),
		"world": world,
		"overworld_position": [overworld_position.x, overworld_position.y, overworld_position.z] if overworld_position != Vector3.INF else [],
	}


func from_dict(d: Dictionary) -> void:
	player = PlayerData.from_dict(d.get("player", {}))
	world = d.get("world", {})
	var op: Array = d.get("overworld_position", [])
	overworld_position = Vector3(op[0], op[1], op[2]) if op.size() == 3 else Vector3.INF
	rng.seed = int(world.get("seed", 0)) + int(hours())
	in_realm = false
	active = true
	recompute()
