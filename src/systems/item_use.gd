class_name ItemUse
## 非战斗场景下使用物品（背包右键“使用”）：丹药、玉简、阵盘、灵种、炼化。
## 战斗中可用的效果（heal/qi/shield/buff/cast）在野外用 Q 键，由 CombatItems 处理。
## 返回 {ok: bool, text: String, consumed: int}


static func use(it: ItemInstance) -> Dictionary:
	var d := it.def()
	var p := GS.player
	var res := {"ok": false, "text": "", "consumed": 0}
	if d.has("teaches"):
		var t: Dictionary = d["teaches"]
		var learned := false
		if t.has("technique"):
			learned = GS.learn_technique(str(t["technique"]))
		elif t.has("spell"):
			learned = GS.learn_spell(str(t["spell"]))
		res["ok"] = learned
		res["consumed"] = 1 if learned else 0
		res["text"] = "参悟玉简，有所得。" if learned else "玉简中的内容你早已掌握。"
		return res
	if d.has("formation"):
		var f: Dictionary = d["formation"]
		if GS.location != "home":
			res["text"] = "阵盘需在洞府中布置。"
			return res
		GS.world["home"]["formation"] = {"mult": float(f.get("mult", 1.5)), "until_day": GS.day_index() + int(f.get("days", 30)), "item": it.id}
		res["ok"] = true
		res["consumed"] = 1
		res["text"] = "聚灵阵布下，洞府灵气浓郁了几分（%d 日）。" % int(f.get("days", 30))
		GS.recompute()
		return res
	if d.has("grow"):
		res["text"] = "灵种需种在洞府的灵田中。"
		return res
	var use_def: Dictionary = d.get("use", {})
	var eff := str(use_def.get("effect", ""))
	match eff:
		"exp", "heal_injury", "detox", "attribute":
			res["text"] = Cultivation.use_pill(p, GS.stats, it.id)
			res["ok"] = true
			res["consumed"] = 1
			GS.recompute()
			return res
		"breakthrough":
			res["text"] = "突破丹药需在修炼界面冲击瓶颈时服用。"
			return res
		"heal", "qi", "shield", "buff", "cast":
			res["text"] = "此物可在斗法时按 Q 使用（设为快捷丹药）。"
			return res
	if d.has("refine"):
		return refine(it)
	res["text"] = "此物无法直接使用。"
	return res


## 炼化灵物为修为
static func refine(it: ItemInstance) -> Dictionary:
	var v := Cultivation.refine_value(GS.player, it.id)
	if v <= 0.0:
		return {"ok": false, "text": "此物无法炼化。", "consumed": 0}
	Cultivation.add_exp(GS.player, v, "refine")
	GS.advance_time(2.0)
	GS.recompute()
	return {"ok": true, "text": "炼化%s，修为 +%d" % [it.display_name(), int(v)], "consumed": 1}
