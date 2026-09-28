class_name Factions
## 阵营敌对关系。个体间的私仇由 Combatant.grudges 处理。
##
## 阵营：player（玩家及同伴）、beast（妖兽）、xuesha（魔道）、robber（劫修）、
##       neutral（散修/路人）、sect:<id>（宗门弟子）

const EVIL := ["xuesha", "robber"]


static func hostile(a: String, b: String) -> bool:
	if a == b:
		return false
	if a == "beast" or b == "beast":
		return true
	var a_evil := EVIL.has(a)
	var b_evil := EVIL.has(b)
	if a_evil and b_evil:
		return false
	# 魔道与玩家、宗门弟子互为敌对
	if (a_evil and (b == "player" or b.begins_with("sect:"))) or (b_evil and (a == "player" or a.begins_with("sect:"))):
		return true
	# 敌对宗门之间只是关系紧张，不会见面即战（冲突由私仇触发）
	return false


## 玩家的阵营标签（加入宗门后仍为 player，以便与同门友好）
static func player_faction() -> String:
	return "player"


static func sect_faction(sect_id: String) -> String:
	return "sect:" + sect_id
