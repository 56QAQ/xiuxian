extends Node
## 战斗特效测试：API 冒烟（无头模式下全部接口可调用、无脚本错误）、对象池与上限、角色状态特效、弹道表现、刀光月牙、资源完整性。

var runner: Node


func _ok(c: bool, m: String) -> void:
	runner.check(c, m)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _actor(pos: Vector3, weapon: String = "sword_iron") -> HumanoidActor:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pd := ActorFactory.make_cultivator_pd(DB.enemy("xuesha_disciple"), rng, {"realm": 1, "stage": 1, "weapon": weapon, "spells": ["fireball"]})
	var a := ActorFactory.spawn_cultivator(self, pd, pos, "xuesha", "balanced", true)
	var ai := a.get_node_or_null("AI")
	if ai != null:
		ai.queue_free()
	a.controller = null
	return a


func test_vfx_resources() -> void:
	for t in ["glow", "flare", "spark", "mote", "smoke", "flame", "noise", "ribbon", "circle", "glyphs", "crack", "scorch", "frost", "leaf", "shard", "talisman", "hex"]:
		_ok(VfxLib.tex(t) != null, "特效贴图 %s" % t)
	for s in ["particle", "particle_emit", "ribbon", "slash", "ring", "circle", "beam", "energy", "ice", "shield", "decal", "field", "ghost", "screen", "distort"]:
		_ok(VfxLib.shader(s) != null, "特效着色器 %s" % s)
	for m in VfxLib.PARTICLE_MATS:
		_ok(VfxLib.particle_mat(m) is ShaderMaterial, "粒子材质 %s" % m)
		_ok(VfxLib.emitter_mat(m) is ShaderMaterial, "发射器材质 %s" % m)
	for p in VfxParticles.PRESETS:
		var n := CPUParticles3D.new()
		VfxParticles.configure(n, p)
		_ok(n.mesh != null and n.material_override != null, "粒子预设 %s" % p)
		# 发射器不使用带实例参数的精灵着色器（Compatibility 渲染器实例参数槽位有限）
		var sm := n.material_override as ShaderMaterial
		_ok(sm == null or sm.shader != VfxLib.shader("particle"), "粒子预设 %s 使用发射器着色器" % p)
		n.free()


func test_fx_api_smoke() -> void:
	var a := _actor(Vector3(0, 0, 0))
	var p := Vector3(2, 1, 0)
	FX.burst(p, Color.RED, 12)
	FX.burst(p, Color.GRAY, 12, 6.0, 0.2, 0.8, false, 18.0)
	FX.dust(p, 10)
	FX.ring(p, 3.0, Color.CYAN)
	FX.shock_sphere(p, 2.0, Color.YELLOW)
	FX.flash_light(p, Color.WHITE)
	FX.pillar(p, 1.0, 6.0, Color.BLUE)
	FX.telegraph(p, 3.0, Color.ORANGE, 0.5)
	FX.beam(p, p + Vector3(5, 0, 0), Color.WHITE)
	FX.beam(p + Vector3.UP * 20.0, p, Color.VIOLET, 0.3, 0.2, true)
	FX.meteor(p + Vector3.UP * 20.0, p, Color.ORANGE_RED, 0.3)
	FX.sparkle(p, Color.WHITE, 6)
	for e in ["metal", "wood", "water", "fire", "earth", "none", "thunder"]:
		FX.hit(p, Vector3.RIGHT, e, 2.0, true)
		FX.impact(p, Vector3.UP, e, 0.4)
		FX.explosion(p, 2.5, e, {"molten": e == "earth"})
		FX.crit_burst(p, e)
		VfxSpells.strike_telegraph(p, 2.0, e, 0.4, "pillar", VfxLib.main_color(e))
		VfxSpells.strike_land(p, 2.0, e, "pillar", VfxLib.main_color(e))
		VfxSpells.strike_land(p, 2.0, e, "meteor", VfxLib.main_color(e))
		VfxSpells.strike_fall(p, 2.0, e, 0.3)
	for v in ["ring", "blade", "frost", "flame", "quake"]:
		VfxSpells.nova(p, 4.0, "metal", v)
	VfxSpells.strike_land(p, 2.0, "thunder", "lightning", Color.VIOLET)
	FX.heavy_ground(p, "earth")
	FX.magic_circle(p, 2.0, "fire", 0.5, {"ground": true, "fill": 0.4})
	FX.magic_circle(p, 1.0, "water", 0.5, {"follow": a, "normal": Vector3.FORWARD})
	FX.ground_decal(Vector3(3, 0, 0), 2.0, "crack", 1.0)
	FX.cast_begin(a, DB.spell("fireball"))
	FX.cast_release(p, Vector3.FORWARD, DB.spell("ice_arrow"))
	FX.talisman(a, "fire")
	FX.quick_boost(a, Vector3.LEFT, Color.CYAN)
	FX.dash_start(a, Vector3.LEFT, Color.GOLD)
	FX.lunge_start(a, Vector3.LEFT, Color.GOLD)
	FX.land(Vector3.ZERO, 1.0)
	FX.jump(Vector3.ZERO)
	FX.afterimage(a.rig, Color.CYAN)
	FX.shield_break(p, Color.GOLD)
	FX.level_up(a)
	FX.breakthrough(a)
	VfxSpells.shield_cast(a, Color.GOLD, 1.0)
	VfxSpells.buff_cast(a, Color.RED)
	VfxSpells.heal(a, Color.GREEN)
	var m := VfxManager.get_mgr()
	_ok(m != null and is_instance_valid(m), "特效管理器已创建")
	await _frames(3)
	_ok(m.get_child_count() > 0, "一次性特效挂在管理器下")
	# 死亡与溶解
	a.combatant.kill()
	FX.dissolve(a, 0.2)
	await _frames(2)
	a.queue_free()
	await _frames(2)


func test_vfx_caps() -> void:
	var m := VfxManager.get_mgr()
	for i in VfxManager.DECAL_MAX + 12:
		FX.ground_decal(Vector3(i, 0, 0), 1.0, "scorch", 5.0)
	_ok(m.decal_count() <= VfxManager.DECAL_MAX, "地面贴花数量受上限约束（%d）" % m.decal_count())
	var a := _actor(Vector3(0, 0, 5))
	for i in VfxManager.GHOST_MAX + 6:
		FX.afterimage(a.rig, Color.CYAN)
	_ok(m.ghost_count() <= VfxManager.GHOST_MAX, "残影数量受上限约束（%d）" % m.ghost_count())
	for i in 20:
		FX.flash_light(Vector3(i, 1, 0), Color.WHITE, 3.0, 5.0, 0.3)
	var lights := 0
	for c in m.get_children():
		if c is OmniLight3D:
			lights += 1
	_ok(lights <= VfxManager.LIGHT_MAX, "闪光灯数量受上限约束（%d）" % lights)
	# 同一预设的对象池不会无限增长
	for i in 60:
		VfxParticles.burst("spark", Vector3(0, 1, 0), Color.WHITE, 10)
	var pooled := 0
	for c in m.get_children():
		if c is CPUParticles3D:
			pooled += 1
	_ok(pooled <= VfxManager.POOL_MAX * VfxParticles.BUCKETS.size() * 4, "粒子池有上限（%d）" % pooled)
	a.queue_free()
	await _frames(2)


func test_status_visuals() -> void:
	var a := _actor(Vector3(0, 0, -5))
	var av := FX.vfx_of(a)
	_ok(av != null, "角色挂载了持续特效组件")
	var c := a.combatant
	for sid in ["bleed", "poison", "burn", "shock", "stone_skin", "fury", "qi_burnout", "regen"]:
		c.apply_status(sid, 3.0, null)
	c.apply_status("bind", 40.0, null)
	av._process(0.2)
	var keys: Array = av._fx.keys()
	for k in ["bleed", "poison", "burn", "shock", "stone_skin", "aura", "qi_burnout", "regen", "bind"]:
		_ok(keys.has(k), "状态特效：%s" % k)
	c.apply_status("bind", 80.0, null)
	av._process(0.2)
	_ok(av._fx.has("rooted") and not av._fx.has("bind"), "束缚满值 → 冰枷")
	c.statuses.clear()
	av._process(0.2)
	_ok(av._fx.is_empty(), "状态结束后特效移除")
	# 护盾：显示与受击涟漪
	av.show_shield(Color.GOLD, 0.5)
	av.shield_hit(a.global_position + Vector3(0, 1, 1))
	av._process(0.1)
	_ok(av._shield != null, "护体灵光显示")
	av.break_shield(Color.GOLD)
	_ok(av._shield == null, "护盾破碎后移除")
	# 硬直星环
	a.action = "stagger"
	av._process(0.1)
	_ok(av._stun != null, "硬直星环")
	a.action = ""
	av._process(0.1)
	_ok(av._stun == null, "硬直结束")
	a.queue_free()
	await _frames(2)


func test_projectile_visuals() -> void:
	var shapes := [["orb", "fire", 0.6, 3.5], ["spike", "water", 0.35, 0.0], ["blade", "metal", 0.3, 0.0], ["spike", "wood", 0.25, 0.0],
		["orb", "earth", 0.6, 0.0], ["orb", "none", 0.14, 0.0], ["leaf", "wood", 0.22, 0.0], ["rock", "earth", 0.9, 4.5]]
	var ps: Array[Projectile] = []
	for s in shapes:
		var p := Projectile.spawn({"pos": Vector3(0, 30, 0), "dir": Vector3.RIGHT, "speed": 30.0, "size": s[2], "range": 3.0,
			"shape": s[0], "element": s[1], "explode": s[3], "info": {"kind": "spell"}})
		ps.append(p)
		_ok(p.get_child_count() > 0, "弹道表现 %s/%s" % [s[0], s[1]])
	# 飞行 → 到达射程后命中消散
	for i in 30:
		await get_tree().physics_frame
	for p in ps:
		_ok(not is_instance_valid(p) or p._dead, "弹道到达射程后结束")
	await _frames(40)


func test_weapon_trail_arc() -> void:
	var a := _actor(Vector3(4, 0, 4), "sword_green")
	await _frames(1)
	var m := VfxManager.get_mgr()
	var before := m.get_child_count()
	a.trail.start(Color.GOLD, "metal")
	a.rig.play("sword_2")
	for i in 8:
		a.trail._process(1.0 / 60.0)
		a.rig._process(1.0 / 60.0)
	a.trail.release_arc(false)
	for i in 8:
		a.rig._process(1.0 / 60.0)
		a.trail._process(1.0 / 60.0)
	_ok(a.trail._tips.size() >= 2, "刀光记录了轨迹")
	_ok(a.trail._arc.is_empty(), "月牙已生成")
	_ok(m.get_child_count() >= before, "剑气月牙挂在管理器下")
	a.queue_free()
	await _frames(2)
