class_name CombatRewards
## 击杀结算：战斗感悟、任务进度、修士遗骸（储物袋）掉落、袭杀因果。
## 大地图与秘境在 Events.actor_died 时调用 on_actor_died。


static func on_actor_died(actor: Node, killer: Node) -> void:
	if actor == null or not is_instance_valid(actor) or CombatUtil.is_player(actor):
		return
	var c := CombatUtil.combatant_of(actor)
	var by_player := CombatUtil.is_player(killer)
	if by_player and c != null:
		var gain := Cultivation.combat_insight(GS.player, GS.stats, c.realm, c.stage)
		Cultivation.add_exp(GS.player, gain, "combat")
		GS.player.kills += 1
		Events.notify.emit("战斗感悟：修为 +%d" % int(gain), "info")
		var eid := str(actor.get("enemy_id")) if actor.get("enemy_id") != null else str(actor.get_meta("template_id", ""))
		if eid != "":
			SectSystem.on_enemy_killed(eid)
		if c.faction in ["xuesha", "robber"]:
			GS.player.karma = maxi(GS.player.karma - 2, -100)
		GS.recompute()
	if actor is HumanoidActor:
		drop_humanoid_loot(actor as HumanoidActor)
		if c != null and c.npc_id != "" and by_player:
			NpcSystem.on_killed_by_player(c.npc_id, witnesses_of(actor as Node3D, c.npc_id))
		elif c != null and c.npc_id != "":
			var rec := NpcSystem.get_npc(c.npc_id)
			if not rec.is_empty():
				rec["alive"] = false


## 修士死后留下遗骸：储物袋 + 兵器法衣 + 灵石
static func drop_humanoid_loot(a: HumanoidActor) -> void:
	var pd := a.pd
	if pd == null:
		return
	var items: Array[ItemInstance] = []
	for it in pd.bag.items():
		items.append(ItemInstance.from_dict(it.to_dict()))
	for slot in ["weapon", "armor", "accessory1", "accessory2"]:
		var e: ItemInstance = pd.equipped(slot)
		if e != null and randf() < 0.6:
			items.append(ItemInstance.from_dict(e.to_dict()))
	if pd.spirit_stones > 0:
		items.append(ItemInstance.create("spirit_stone", pd.spirit_stones))
	if items.is_empty():
		return
	var parent := a.get_parent()
	var pos := a.global_position
	var nm := a.combatant.display_name
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	a.get_tree().create_timer(1.2).timeout.connect(func() -> void:
		if is_instance_valid(parent):
			var cont := LootContainer.create(parent, pos, "corpse", "", 1.5, rng, items)
			cont.title = "%s的储物袋" % nm)


static func witnesses_of(victim: Node3D, victim_id: String) -> Array[String]:
	var out: Array[String] = []
	for b in CombatUtil.bodies():
		var h := b as HumanoidActor
		if h == null or h == victim or h.is_player or not h.combatant.alive:
			continue
		if h.combatant.npc_id != "" and h.combatant.npc_id != victim_id and h.global_position.distance_to(victim.global_position) < 40.0:
			out.append(h.combatant.npc_id)
	return out
