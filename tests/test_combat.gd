extends Node
## 战斗测试：伤害公式、状态、护盾、以及试炼场冒烟（AI 真实交战若干秒）。

var runner: Node


func _ok(c: bool, m: String) -> void:
	runner.check(c, m)


func _mk(realm: int, stage: int, faction: String) -> Combatant:
	var c := Combatant.new()
	add_child(c)
	c.faction = faction
	var st := Stats.resolve(BuildCalc.realm_base(realm, stage), {})
	c.setup(st, realm, stage, Elem.NONE)
	return c


func test_damage_and_shield() -> void:
	var a := _mk(0, 3, "xuesha")
	var b := _mk(0, 3, "player")
	_ok(a.is_hostile_to(b), "魔道与玩家敌对")
	var shield0 := b.shield
	var r := b.take_damage({"source": a, "kind": "melee", "mult": 1.0})
	_ok(r["damage"] > 0.0, "造成伤害")
	_ok(b.shield < shield0, "护体先承伤")
	_ok(is_equal_approx(b.hp, b.stat("max_hp")) or r["hp_damage"] > 0.0, "护体吸收")
	# 境界压制
	var hi := _mk(1, 0, "xuesha")
	var lo := _mk(0, 0, "player")
	var d_hi := 0.0
	var d_lo := 0.0
	for i in 20:
		d_hi += DamageCalc.compute(hi, lo, {"kind": "melee", "mult": 1.0})["damage"]
		d_lo += DamageCalc.compute(lo, hi, {"kind": "melee", "mult": 1.0})["damage"]
	_ok(d_hi > d_lo * 3.5, "筑基压制炼气（%.0f vs %.0f）" % [d_hi, d_lo])
	for n in [a, b, hi, lo]:
		n.queue_free()


func test_statuses() -> void:
	var a := _mk(0, 5, "xuesha")
	var b := _mk(0, 5, "player")
	b.apply_status("poison", 5, a)
	_ok(b.stat("attack") < b.base_stats["attack"], "中毒降低攻击")
	b.apply_status("bind", 60, a)
	_ok(b.stat("move_speed") < b.base_stats["move_speed"], "束缚减速")
	b.apply_status("bind", 60, a)
	_ok(b.is_rooted(), "束缚满值定身")
	var hp0 := b.hp
	b.apply_status("bleed", 5, a)
	for i in 120:
		b._physics_process(1.0 / 60.0)
	_ok(b.hp < hp0, "流血持续伤害")
	b.apply_status("stagger", 500, a)
	_ok(b.poise >= b.stat("poise") - 1.0, "震慑破韧后重置韧性")
	a.queue_free()
	b.queue_free()


func test_qi_burnout() -> void:
	var c := _mk(0, 0, "player")
	_ok(not c.drain_qi(c.qi + 10.0), "灵力不足时失败")
	_ok(c.has_status("qi_burnout"), "进入灵力枯竭")
	c.queue_free()


func test_arena_smoke() -> void:
	GS.active = false
	var scene: PackedScene = load("res://scenes/dev_arena.tscn")
	var arena := scene.instantiate()
	get_tree().root.add_child(arena)
	var player: HumanoidActor = arena.session.player
	_ok(player != null and player.combatant.alive, "玩家生成")
	_ok(arena.enemies.size() == 3, "敌人生成")
	var took := [false]
	var dealt := [false]
	player.combatant.damaged.connect(func(_i: Dictionary, _r: Dictionary) -> void: took[0] = true)
	var on_hit := func(h: Dictionary) -> void:
		if h.get("source") == player and str(h.get("kind", "")) != "dot":
			dealt[0] = true
	Events.hit_landed.connect(on_hit)
	# 玩家自动出招：锁定最近的敌人，靠近并连段（保持存活以覆盖完整流程）
	for i in 900:
		player.combatant.hp = maxf(player.combatant.hp, player.combatant.stat("max_hp") * 0.5)
		if player.combatant.alive:
			var tgt := CombatUtil.nearest_hostile(player, 80.0)
			player.lock_target = tgt
			if tgt != null:
				var to := tgt.global_position - player.global_position
				to.y = 0
				player.in_move = to.normalized() if to.length() > 2.5 else Vector3.ZERO
				player.in_boost = to.length() > 10.0
				if i % 9 == 0:
					player.in_melee = true
				if i % 120 == 30:
					player.in_spell = 1
				if i % 150 == 60:
					player.in_spell = 0
		await get_tree().physics_frame
		if took[0] and dealt[0] and i > 300:
			break
	Events.hit_landed.disconnect(on_hit)
	_ok(took[0], "敌人对玩家发起了攻击")
	_ok(dealt[0], "玩家对敌人造成了伤害")
	arena.queue_free()
	HitStop.reset()
	await get_tree().process_frame
