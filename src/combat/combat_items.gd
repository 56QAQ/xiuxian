class_name CombatItems
## 战斗中可用的消耗品（丹药、符箓）。返回是否成功使用（调用方负责扣除物品）。


static func use(actor: Node3D, item_id: String) -> bool:
	var def := DB.item(item_id)
	var use_def: Dictionary = def.get("use", {})
	var c := CombatUtil.combatant_of(actor)
	if c == null or not c.alive or use_def.is_empty():
		return false
	var name := str(def.get("name", item_id))
	match str(use_def.get("effect", "")):
		"heal":
			c.heal(c.stat("max_hp") * float(use_def.get("amount", 0.3)))
			VfxSpells.heal(actor, Color(0.5, 1.0, 0.55))
			Audio.play_at("heal", actor.global_position)
		"qi":
			c.restore_qi(c.stat("max_qi") * float(use_def.get("amount", 0.5)))
			c.remove_status("qi_burnout")
			VfxSpells.buff_cast(actor, Color(0.45, 0.7, 1.0))
			Audio.play_at("buff", actor.global_position)
		"shield":
			c.add_shield(c.stat("max_shield") * float(use_def.get("amount", 0.5)))
			VfxSpells.shield_cast(actor, Color(1, 0.88, 0.55), 2.5)
			Audio.play_at("buff", actor.global_position)
		"buff":
			var sid := str(use_def.get("status", "fury"))
			c.apply_status(sid, float(use_def.get("stacks", 1)), c)
			if c.statuses.has(sid) and use_def.has("duration"):
				c.statuses[sid]["time"] = float(use_def["duration"])
			VfxSpells.buff_cast(actor, Color.html(str(DB.status(sid).get("color", "#ffd080"))))
			Audio.play_at("buff", actor.global_position)
		"cleanse":
			c.clear_debuffs()
			VfxSpells.buff_cast(actor, Color(0.9, 0.97, 1.0))
			Audio.play_at("heal", actor.global_position)
		"cast":
			if actor.has_method("cast_spell"):
				if not bool(actor.call("cast_spell", str(use_def.get("spell", "")), true)):
					return false
				if str(def.get("type", "")) == "talisman":
					FX.talisman(actor, str(def.get("element", Elem.NONE)))
		_:
			Events.notify.emit("%s 需在修炼界面中使用" % name, "info")
			return false
	if CombatUtil.is_player(actor):
		Events.notify.emit("使用 %s" % name, "info")
	return true
