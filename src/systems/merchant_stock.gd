class_name MerchantStock
## 坊市商人货架：按商铺类型从物品库中挑选，按玩家境界筛选品阶，每 7 日刷新。

const KINDS := {
	"pills": ["pill"],
	"gear": ["weapon", "armor", "accessory", "bag"],
	"misc": ["material", "seed", "formation", "key"],
	"talismans": ["talisman", "manual"],
}


static func stock(shop: String, npc_id: String) -> Array:
	var types: Array = KINDS.get(shop, ["material"])
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(npc_id) + int(GS.day_index() / 7) * 131
	var max_grade := 1 + GS.player.realm
	var cands: Array[String] = []
	for id in DB.items:
		var d: Dictionary = DB.items[id]
		if not types.has(str(d.get("type", ""))):
			continue
		if int(d.get("grade", 0)) > max_grade or int(d.get("value", 0)) <= 0:
			continue
		cands.append(id)
	var out := []
	var n := mini(10, cands.size())
	for i in n:
		var id: String = cands.pop_at(rng.randi() % cands.size())
		var price := int(ceil(float(DB.item(id).get("value", 1)) * rng.randf_range(1.1, 1.5)))
		out.append({"item": id, "price": price})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["price"]) < int(b["price"]))
	return out
