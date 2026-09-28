class_name Crafting
## 生产技艺（炼丹/炼器/制符/阵法/灵植）：配方筛选、材料检查、成功率、制作（扣材料 → 推进时间 → 判定 → 产出 → 熟练度）。
## 成功率 = 配方 success + 0.05 ×（技艺等级 − 配方等级）+ 属性[技艺] × 0.03，限制在 5%~98%。
## 配方等级要求按“有效等级”= 技艺等级 + 属性[技艺]（天赋如“丹道天成”+2）判断。

const MAX_LEVEL := 9

const FAIL_TEXT := {
	"alchemy": "丹炉轰然一震，药力散尽，炼制失败……",
	"forging": "火候失准，胚料崩裂，炼器失败……",
	"talisman": "笔锋一滞，灵纹溃散，制符失败……",
	"formation": "阵纹错位，灵光熄灭，布阵失败……",
	"herbalism": "灵气不济，灵植枯萎，培育失败……",
}
const VERB := {"alchemy": "炼成", "forging": "炼成", "talisman": "制成", "formation": "布成", "herbalism": "收获"}


static func recipes_for(profession: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for rid in DB.recipes:
		var r: Dictionary = DB.recipes[rid]
		if str(r.get("profession", "")) == profession:
			out.append(r)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a.get("level", 0)) != int(b.get("level", 0)):
			return int(a.get("level", 0)) < int(b.get("level", 0))
		return str(a["id"]) < str(b["id"]))
	return out


## 持有数量（储物袋 + 本命空间；灵石为货币）
static func have_count(p: PlayerData, item_id: String) -> int:
	if DB.item(item_id).get("type", "") == "currency":
		return p.spirit_stones / maxi(int(DB.item(item_id).get("value", 1)), 1)
	return p.bag.count_of(item_id) + p.secure.count_of(item_id)


## 缺少的材料：[[id, need, have], ...]
static func missing_inputs(p: PlayerData, recipe: Dictionary, times: int = 1) -> Array:
	var out: Array = []
	for inp in recipe.get("inputs", []):
		var id := str(inp[0])
		var need := int(inp[1]) * times
		var have := have_count(p, id)
		if have < need:
			out.append([id, need, have])
	return out


static func effective_level(p: PlayerData, stats: Dictionary, profession: String) -> int:
	return p.profession_level(profession) + int(stats.get(profession, 0.0))


static func success_chance(p: PlayerData, stats: Dictionary, recipe: Dictionary) -> float:
	var prof := str(recipe.get("profession", ""))
	var c := float(recipe.get("success", 0.5)) + 0.05 * (p.profession_level(prof) - int(recipe.get("level", 0))) + float(stats.get(prof, 0.0)) * 0.03
	return clampf(c, 0.05, 0.98)


## {ok: bool, reason: String}
static func can_craft(p: PlayerData, stats: Dictionary, recipe: Dictionary) -> Dictionary:
	var prof := str(recipe.get("profession", ""))
	if effective_level(p, stats, prof) < int(recipe.get("level", 0)):
		return {"ok": false, "reason": "%s等级不足（需 %d 级）" % [PlayerData.PROFESSION_NAMES.get(prof, prof), int(recipe.get("level", 0))]}
	var miss := missing_inputs(p, recipe)
	if not miss.is_empty():
		var names: PackedStringArray = []
		for m in miss:
			names.append("%s %d/%d" % [DB.item(str(m[0])).get("name", m[0]), int(m[2]), int(m[1])])
		return {"ok": false, "reason": "材料不足：" + "、".join(names)}
	return {"ok": true, "reason": ""}


static func xp_needed(lv: int) -> float:
	return 60.0 * pow(float(lv + 1), 1.6)


## 增加熟练度，返回提升的等级数
static func add_xp(p: PlayerData, profession: String, amount: float) -> int:
	if not p.professions.has(profession):
		p.professions[profession] = {"lv": 0, "xp": 0.0}
	var pr: Dictionary = p.professions[profession]
	pr["xp"] = float(pr.get("xp", 0.0)) + amount
	var ups := 0
	while int(pr["lv"]) < MAX_LEVEL and float(pr["xp"]) >= xp_needed(int(pr["lv"])):
		pr["xp"] = float(pr["xp"]) - xp_needed(int(pr["lv"]))
		pr["lv"] = int(pr["lv"]) + 1
		ups += 1
	return ups


static func _take(p: PlayerData, item_id: String, n: int) -> void:
	if DB.item(item_id).get("type", "") == "currency":
		p.spirit_stones -= n * maxi(int(DB.item(item_id).get("value", 1)), 1)
		return
	var from_bag := mini(p.bag.count_of(item_id), n)
	if from_bag > 0:
		p.bag.take(item_id, from_bag)
	if n - from_bag > 0:
		p.secure.take(item_id, n - from_bag)


## 制作一次。返回 {ok, success, text, kind, output, n, xp, level_up}
## ok=false 表示未能开工（等级或材料不足），此时不消耗任何东西。
static func craft(recipe_id: String) -> Dictionary:
	var recipe: Dictionary = DB.recipes.get(recipe_id, {})
	if recipe.is_empty():
		return {"ok": false, "success": false, "text": "未知配方", "kind": "bad"}
	var p := GS.player
	var chk := can_craft(p, GS.stats, recipe)
	if not chk["ok"]:
		return {"ok": false, "success": false, "text": chk["reason"], "kind": "warn"}
	var prof := str(recipe.get("profession", ""))
	var chance := success_chance(p, GS.stats, recipe)
	for inp in recipe.get("inputs", []):
		_take(p, str(inp[0]), int(inp[1]))
	GS.advance_time(float(recipe.get("time", 1)))
	var success := GS.rng.randf() < chance
	var out: Array = recipe.get("output", ["", 0])
	var out_id := str(out[0])
	var n := int(out[1])
	var xp := 10.0 + 6.0 * int(recipe.get("level", 0))
	var text := ""
	if success:
		GS.give_item(out_id, n, false)
		text = "%s %s ×%d" % [VERB.get(prof, "制成"), DB.item(out_id).get("name", out_id), n]
	else:
		xp *= 0.4
		text = str(FAIL_TEXT.get(prof, "制作失败……"))
	var ups := add_xp(p, prof, xp)
	if ups > 0:
		text += "\n%s精进至 %d 级！" % [PlayerData.PROFESSION_NAMES.get(prof, prof), p.profession_level(prof)]
	GS.recompute()
	Events.inventory_changed.emit()
	return {"ok": true, "success": success, "text": text, "kind": "good" if success else "bad", "output": out_id, "n": n if success else 0, "xp": xp, "level_up": ups}
