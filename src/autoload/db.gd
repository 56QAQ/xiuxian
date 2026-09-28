extends Node
## 静态数据库（autoload: DB）。启动时从 res://data/*.json 读取全部设计数据。
##
## 约定：列表型文件为 JSON 数组，每个元素必须带 "id"，加载后按 id 建字典；
## realms.json 保持数组（按境界序号访问）。字段说明见 docs/DATA.md。

const DATA_DIR := "res://data/"

var items: Dictionary = {}
var spells: Dictionary = {}
var techniques: Dictionary = {}
var talents: Dictionary = {}
var backgrounds: Dictionary = {}
var sects: Dictionary = {}
var enemies: Dictionary = {}
var recipes: Dictionary = {}
var secret_realms: Dictionary = {}
var missions: Dictionary = {}
var encounters: Dictionary = {}
var loot_tables: Dictionary = {}
var statuses: Dictionary = {}
var movesets: Dictionary = {}
var realms: Array = []
var names: Dictionary = {}
var dialogue: Dictionary = {}
var appearance: Dictionary = {}

var _errors: PackedStringArray = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	_errors.clear()
	items = _load_by_id("items.json")
	spells = _load_by_id("spells.json")
	techniques = _load_by_id("techniques.json")
	talents = _load_by_id("talents.json")
	backgrounds = _load_by_id("backgrounds.json")
	sects = _load_by_id("sects.json")
	enemies = _load_by_id("enemies.json")
	recipes = _load_by_id("recipes.json")
	secret_realms = _load_by_id("secret_realms.json")
	missions = _load_by_id("missions.json")
	encounters = _load_by_id("encounters.json")
	loot_tables = _load_by_id("loot_tables.json")
	statuses = _load_by_id("statuses.json")
	movesets = _load_by_id("movesets.json")
	var r = _load_json("realms.json")
	realms = r if r is Array else []
	var n = _load_json("names.json")
	names = n if n is Dictionary else {}
	var d = _load_json("dialogue.json")
	dialogue = d if d is Dictionary else {}
	var a = _load_json("appearance.json")
	appearance = a if a is Dictionary else {}
	for e in _errors:
		push_error(e)


func errors() -> PackedStringArray:
	return _errors


func _load_json(file: String) -> Variant:
	var path := DATA_DIR + file
	if not FileAccess.file_exists(path):
		_errors.append("DB: 缺少数据文件 %s" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var err := json.parse(text)
	if err != OK:
		_errors.append("DB: %s 第 %d 行解析失败: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


func _load_by_id(file: String) -> Dictionary:
	var out := {}
	var data = _load_json(file)
	if data == null:
		return out
	if not data is Array:
		_errors.append("DB: %s 顶层应为数组" % file)
		return out
	for entry in data:
		if not entry is Dictionary or not entry.has("id"):
			_errors.append("DB: %s 中存在缺少 id 的条目" % file)
			continue
		if out.has(entry["id"]):
			_errors.append("DB: %s 中 id 重复: %s" % [file, entry["id"]])
		out[entry["id"]] = entry
	return out


# ---------------------------------------------------------------- 访问器

func item(id: String) -> Dictionary:
	return items.get(id, {})


func spell(id: String) -> Dictionary:
	return spells.get(id, {})


func technique(id: String) -> Dictionary:
	return techniques.get(id, {})


func talent(id: String) -> Dictionary:
	return talents.get(id, {})


func sect(id: String) -> Dictionary:
	return sects.get(id, {})


func enemy(id: String) -> Dictionary:
	return enemies.get(id, {})


func status(id: String) -> Dictionary:
	return statuses.get(id, {})


func moveset(id: String) -> Dictionary:
	return movesets.get(id, {})


func realm(idx: int) -> Dictionary:
	if idx < 0 or idx >= realms.size():
		return {}
	return realms[idx]


func realm_count() -> int:
	return realms.size()


## 境界全名，如 “炼气三层”“筑基中期”
func realm_name(idx: int, stage: int) -> String:
	var r := realm(idx)
	if r.is_empty():
		return "凡人"
	var stages: Array = r.get("stages", [])
	var s := "" if stages.is_empty() else str(stages[clampi(stage, 0, stages.size() - 1)])
	return str(r.get("name", "")) + s


## 所有带某标签的物品 id
func items_with_tag(tag: String) -> Array[String]:
	var out: Array[String] = []
	for id in items:
		if (items[id].get("tags", []) as Array).has(tag):
			out.append(id)
	return out
