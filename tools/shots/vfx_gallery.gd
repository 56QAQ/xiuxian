extends RefCounted
## 特效图鉴（v0.15 战斗特效语言）：tools/shot.sh <godot> vfx_gallery out.png --size=1600x900 --panel=<名字> [--dusk]
## 面板：proj 弹道 / impact 爆炸 / nova 爆发 / strike 天降 / field 领域 / beam 光束 / melee 近战 /
##       status 状态 / move 身法 / cast 施法 / summon 召唤 / misc 破盾·死亡·突破·天材地宝
## 在固定机位下按帧触发特效；每帧模拟时间固定为 1/60 秒（动态调整 time_scale 补偿软件渲染的慢帧），定格到选定时刻。

var panel: String = "proj"
var dusk: bool = false
var stage: Node3D
var cam: Camera3D
var total: int = 40
var _events: Dictionary = {}
var _every: Array[Callable] = []
var _last_us: int = 0
var _ema: float = 0.0
var _actors: Array[HumanoidActor] = []


func frames() -> int:
	return total


func build(root: Node) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--panel="):
			panel = a.substr(8)
		if a == "--dusk":
			dusk = true
	GS.active = false
	if GS.player == null:
		GS.new_game({"name": "观者", "roots": {"fire": 50, "water": 50}, "background": "clan", "seed": 3})
	stage = Node3D.new()
	stage.name = "Stage"
	root.add_child(stage)
	var arena_script: GDScript = load("res://src/combat/dev_arena.gd")
	arena_script.call("build_arena", stage)
	if dusk:
		for c in stage.get_children():
			if c is WorldEnvironment:
				var e := (c as WorldEnvironment).environment
				var sky := e.sky.sky_material as ProceduralSkyMaterial
				sky.sky_top_color = Color(0.08, 0.1, 0.2)
				sky.sky_horizon_color = Color(0.3, 0.22, 0.25)
				sky.ground_horizon_color = Color(0.15, 0.13, 0.14)
				e.ambient_light_energy = 0.25
			if c is DirectionalLight3D:
				(c as DirectionalLight3D).light_energy = 0.25
				(c as DirectionalLight3D).light_color = Color(1.0, 0.7, 0.55)
	cam = Camera3D.new()
	cam.fov = 50.0
	stage.add_child(cam)
	Engine.time_scale = 0.05
	call("_panel_" + panel)


func step(_root: Node, i: int) -> void:
	# 固定模拟步长约 1/60 秒：用真实帧时间的平滑值（剔除着色器编译等卡顿）换算 time_scale
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		var dt := float(now - _last_us) / 1000000.0
		if _ema <= 0.0:
			_ema = dt
		else:
			_ema = lerpf(_ema, minf(dt, _ema * 2.0), 0.3)
		# 引擎把单帧真实时间限制在 max_physics_steps_per_frame 个物理步长以内
		var cap := float(Engine.max_physics_steps_per_frame) / float(Engine.physics_ticks_per_second)
		Engine.time_scale = clampf((1.0 / 60.0) / clampf(_ema, 0.001, cap), 0.0005, 1.0)
	_last_us = now
	for c in _every:
		c.call(i)
	for c in _events.get(i, []):
		(c as Callable).call()
	if i == total - 1:
		Engine.time_scale = 1.0


func at(frame: int, c: Callable) -> void:
	if not _events.has(frame):
		_events[frame] = []
	_events[frame].append(c)


func _look(pos: Vector3, target: Vector3, fov: float = 50.0) -> void:
	cam.position = pos
	cam.look_at(target)
	cam.fov = fov
	cam.current = true


func _label(text: String, pos: Vector3) -> void:
	var l := Label3D.new()
	l.text = text
	l.font = load("res://assets/fonts/XianKai-Regular.ttf")
	l.font_size = 42
	l.pixel_size = 0.005
	l.outline_size = 8
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = pos
	stage.add_child(l)


## 静止的修士（移除 AI）。weapon：物品 id
func _actor(pos: Vector3, weapon: String, yaw_deg: float = 0.0, faction: String = "xuesha", seed_v: int = 1) -> HumanoidActor:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var tpl := DB.enemy("xuesha_disciple")
	var pd := ActorFactory.make_cultivator_pd(tpl, rng, {"realm": 1, "stage": 2, "weapon": weapon, "spells": ["fireball"]})
	var a := ActorFactory.spawn_cultivator(stage, pd, pos, faction, "balanced", true)
	var ai := a.get_node_or_null("AI")
	if ai != null:
		ai.queue_free()
	a.controller = null
	a.rotation.y = deg_to_rad(yaw_deg)
	a.set("_yaw", deg_to_rad(yaw_deg))
	a.combatant.invuln = 999.0
	if a.nameplate != null:
		a.nameplate.queue_free()
		a.nameplate = null
	_actors.append(a)
	return a


# ================================================================ 面板

func _panel_proj() -> void:
	total = 34
	_look(Vector3(0.0, 2.6, 12.5), Vector3(0.0, 1.8, 0), 50.0)
	var specs := [
		["fireball", "火球术"], ["ice_arrow", "玄冰箭"], ["gengjin_jianqi", "庚金剑气"], ["wood_thorn", "棘刺术"],
		["stone_bullet", "飞石术"], ["qi_palm", "灵元掌"], ["lava_bomb", "熔岩弹"], ["blood_blade", "血神刀芒"],
	]
	for i in specs.size():
		var def := DB.spell(specs[i][0])
		var p: Dictionary = def["params"]
		var x := -6.6 + i * 1.95
		var y := 1.1 + (i % 2) * 1.6
		_label(specs[i][1], Vector3(x + 1.2, y - 0.7, 0))
		at(total - 22, func() -> void:
			Projectile.spawn({"pos": Vector3(x - 2.0, y, 0), "dir": Vector3.RIGHT, "speed": 9.0, "size": float(p.get("size", 0.3)),
				"range": 99.0, "shape": str(p.get("shape", "orb")), "element": str(def.get("element", "none")), "explode": float(p.get("explode", 0.0)),
				"info": {"kind": "spell", "status": def.get("status", {})}, "color": VfxLib.spell_color(def), "vfx_elem": VfxLib.spell_elem(def)}))


func _panel_impact() -> void:
	total = 30
	_look(Vector3(0, 5.5, 14), Vector3(0, 1.0, 0), 50.0)
	var elems := ["fire", "earth", "water", "wood", "metal", "none"]
	var names := ["火·爆炎", "土·熔岩", "水·冰溅", "木·飞叶", "金·火花", "灵光"]
	for i in elems.size():
		var x := -10.0 + i * 4.0
		_label(names[i], Vector3(x, 3.6, 0))
		at(total - 9, func() -> void:
			FX.explosion(Vector3(x, 0.8, 0), 2.4, elems[i], {"molten": elems[i] == "earth"}))
	# 命中火花（近战）与暴击
	for i in 3:
		at(total - 4, func() -> void:
			FX.hit(Vector3(-6.0 + i * 6.0, 1.2, 4.0), Vector3(1, 0, 0), ["metal", "fire", "water"][i], 2.0))


func _panel_nova() -> void:
	total = 30
	_look(Vector3(0, 9, 17), Vector3(0, 0.5, 0), 50.0)
	var vis := [["ring", "none", "灵爆术"], ["blade", "metal", "剑气纵横"], ["frost", "water", "冰魄寒潮"], ["flame", "fire", "炎爆术"], ["quake", "earth", "地裂术"]]
	for i in vis.size():
		var x := -12.0 + i * 6.0
		_label(vis[i][2], Vector3(x, 3.4, 0))
		at(total - (12 if vis[i][0] != "frost" else 16), func() -> void:
			VfxSpells.nova(Vector3(x, 0.5, 0), 3.2, vis[i][1], vis[i][0]))


func _panel_strike() -> void:
	total = 64
	_look(Vector3(0, 11, 19), Vector3(0, 1.5, -1), 52.0)
	# 预警法阵（火 / 水 / 雷），填充到约 60%
	var tele := [["fire", "pillar", -11.0], ["water", "pillar", -4.0], ["thunder", "lightning", 3.0]]
	for t in tele:
		at(total - 38, func() -> void:
			VfxSpells.strike_telegraph(Vector3(t[2], 0, 3), 3.0, t[0], 1.0, t[1], VfxLib.main_color(t[0])))
	_label("预警法阵", Vector3(-4, 2.2, 3))
	# 流火陨星（下落中）与万剑归宗飞剑
	at(total - 26, func() -> void:
		VfxSpells.meteor(Vector3(-14, 22, -8), Vector3(-10, 0, -6), "fire", 0.8, 1.2)
		VfxSpells.meteor(Vector3(-8.5, 20, -6), Vector3(-7, 0, -6), "metal", 0.6, 1.0))
	# 雷击、水牢、地刺、大日坠天落地
	at(total - 3, func() -> void:
		VfxSpells.strike_land(Vector3(10, 0, 3), 2.5, "thunder", "lightning", VfxLib.main_color("thunder")))
	at(total - 16, func() -> void:
		VfxSpells.strike_land(Vector3(-1, 0, -6), 3.2, "water", "pillar", VfxLib.main_color("water")))
	at(total - 12, func() -> void:
		VfxSpells.strike_land(Vector3(6, 0, -6), 2.4, "earth", "pillar", VfxLib.main_color("earth")))
	at(total - 7, func() -> void:
		VfxSpells.strike_land(Vector3(13, 0, -7), 4.0, "fire", "meteor", VfxLib.main_color("fire")))


func _panel_field() -> void:
	total = 70
	_look(Vector3(0, 10, 16), Vector3(0, 0, -1), 52.0)
	var f := [["vine_bind", -10.5, "青藤缠"], ["frozen_field", -3.5, "玄冥冰域"], ["quicksand", 3.5, "流沙陷"], ["qi_burst", 10.5, "火海"]]
	for s in f:
		_label(s[2], Vector3(s[1], 2.6, 0))
	at(2, func() -> void:
		for s in f:
			var def := DB.spell(s[0]).duplicate(true)
			if s[0] == "qi_burst":
				def = {"id": "fire_field", "element": "fire", "params": {"radius": 3.2, "duration": 9.0, "tick": 9.0}}
			else:
				def["params"]["radius"] = 3.2
				def["params"]["duration"] = 9.0
			SpellField.spawn(null, Vector3(s[1], 0, 0), def, 0))


func _panel_beam() -> void:
	total = 40
	_look(Vector3(0, 3.6, 15), Vector3(0, 3.2, 0), 50.0)
	var beams := [["samadhi_fire", "三昧真火"], ["water_dragon", "水龙吟"], ["taibai_beam", "太白庚金光"], ["yimu_thunder", "乙木神雷"]]
	for i in beams.size():
		var def := DB.spell(beams[i][0])
		var holder := Node3D.new()
		stage.add_child(holder)
		var y := 0.9 + i * 1.75
		var from := Vector3(-8, y + 0.3, 0)
		var to := Vector3(8, y - 0.6, -1.0)
		var vis := VfxSpells.beam_visual(holder, VfxLib.spell_elem(def), VfxLib.spell_color(def), float(def["params"]["width"]))
		_label(beams[i][1], from + Vector3(-1.0, 0.0, 0))
		_every.append(func(fr: int) -> void:
			VfxSpells.beam_update(vis, from, to, true, fr / 60.0))


func _panel_melee() -> void:
	total = 46
	_look(Vector3(0, 2.6, 8.5), Vector3(0, 1.1, 0), 55.0)
	var specs := [["sword_green", -6.0, 3, "剑·终结（重）"], ["saber_blood", -2.0, 0, "刀·赤焰"], ["spear_serpent", 2.0, 1, "枪·玄水"], ["sword_peach", 6.0, 1, "剑·青木"]]
	for s in specs:
		var a := _actor(Vector3(s[1] - 0.8, 0, 0), s[0], -90.0, "xuesha", 11)
		var d := _actor(Vector3(s[1] + 1.4, 0, 0), "fist_wraps", 90.0, "player", 12)
		a.lock_target = d
		_label(s[3], Vector3(s[1], 2.6, 0))
		at(total - 13, func() -> void:
			a.call("_begin_step", s[2], false))


func _panel_status() -> void:
	total = 50
	_look(Vector3(0, 2.8, 11.5), Vector3(0, 1.0, 0), 56.0)
	var specs := [["bleed", 5.0, "流血"], ["poison", 6.0, "中毒"], ["bind", 60.0, "束缚"], ["rooted", 1.0, "定身冰枷"], ["burn", 4.0, "灼烧"],
		["shock", 3.0, "感电"], ["stone_skin", 1.0, "石肤"], ["fury", 1.0, "狂火光环"], ["qi_burnout", 1.0, "灵力枯竭"], ["shield", 1.0, "护体涟漪"], ["stagger", 1.0, "硬直"]]
	for i in specs.size():
		var x := -10.0 + i * 2.0
		var a := _actor(Vector3(x, 0, 0), "sword_iron", 0.0, "xuesha", 20 + i)
		_label(specs[i][2], Vector3(x, 2.35, 0))
		var sid: String = specs[i][0]
		var stacks: float = specs[i][1]
		at(2, _apply_status.bind(a, sid, stacks))
		if sid == "burn" or sid == "poison":
			at(total - 2, func() -> void:
				var av := FX.vfx_of(a)
				print(sid, " fx=", av._fx.keys(), " st=", a.combatant.statuses.keys(), " near=", av._near)
				for k in av._fx:
					for n in av._fx[k]:
						if n is CPUParticles3D:
							print("  ", k, " pos=", (n as CPUParticles3D).global_position, " aabb=", (n as CPUParticles3D).capture_aabb(), " emit=", (n as CPUParticles3D).emitting))
		if sid == "shield":
			for k in 3:
				at(total - 26 + k * 8, func() -> void:
					var av2 := FX.vfx_of(a)
					if av2 != null:
						av2.shield_hit(a.global_position + Vector3(randf_range(-0.6, 0.6), 1.0 + randf_range(-0.3, 0.5), 1.0)))


func _apply_status(a: HumanoidActor, sid: String, stacks: float) -> void:
	if sid == "shield":
		var av := FX.vfx_of(a)
		if av != null:
			av.show_shield(Color(1.0, 0.85, 0.45), 3.0)
	elif sid == "stagger":
		a.set("stagger_t", 99.0)
		a.action = "stagger"
		a.rig.play("stagger", 0.3)
	else:
		a.combatant.apply_status(sid, stacks, null)
		if a.combatant.statuses.has(sid):
			a.combatant.statuses[sid]["time"] = 99.0


func _panel_move() -> void:
	total = 60
	_look(Vector3(0, 3.2, 12), Vector3(0, 1.4, 0), 56.0)
	# 疾行：从左向右
	var runner := _actor(Vector3(-11, 0, -1), "flag_spear_fire", -90.0, "xuesha", 31)
	runner.bolt_element = "fire"
	_label("疾行尾流", Vector3(-3, 2.8, -1))
	_every.append(func(_fr: int) -> void:
		runner.in_move = Vector3.RIGHT
		runner.in_boost = true
		runner.combatant.qi = runner.combatant.stat("max_qi"))
	# 瞬步残影
	var qb := _actor(Vector3(7.5, 0, 1), "sword_azure", 0.0, "xuesha", 32)
	qb.bolt_element = "water"
	_label("瞬步残影", Vector3(4, 2.8, 1))
	at(total - 12, func() -> void:
		qb.in_move = Vector3.LEFT
		qb.quick_boost())
	# 御空（悬停）与升空
	var hover := _actor(Vector3(-5, 2.5, 2), "sword_green", 20.0, "xuesha", 33)
	hover.bolt_element = "metal"
	_label("御空", Vector3(-5, 4.9, 2))
	var asc := _actor(Vector3(9, 1.5, 0), "spear_bamboo", -20.0, "xuesha", 34)
	asc.bolt_element = "wood"
	_label("升空", Vector3(9, 4.6, 0))
	_every.append(func(_fr: int) -> void:
		hover.hovering = true
		hover.combatant.qi = hover.combatant.stat("max_qi")
		asc.in_jump_held = true
		asc.combatant.qi = asc.combatant.stat("max_qi"))
	# 蓄力灵气弹
	var ch := _actor(Vector3(0.5, 0, 3), "fist_wraps", 200.0, "xuesha", 35)
	ch.bolt_element = "thunder"
	_label("蓄力", Vector3(0.5, 2.4, 3))
	_every.append(func(fr: int) -> void:
		ch.in_bolt_held = fr > 4
		ch.combatant.qi = ch.combatant.stat("max_qi")
		)


func _panel_cast() -> void:
	total = 40
	_look(Vector3(0, 2.8, 10.5), Vector3(0, 1.1, 0), 55.0)
	var specs := [["fireball", -7.0, "火球术·起手"], ["earth_shield", -3.5, "厚土盾"], ["fire_fury", 0.0, "离火燃元"], ["withered_spring", 3.5, "枯木逢春"], ["talisman", 7.0, "符箓·掌心雷"]]
	for s in specs:
		var a := _actor(Vector3(s[1], 0, 0), "sword_iron", 0.0, "xuesha", 40)
		_label(s[2], Vector3(s[1], 2.5, 0))
		if s[0] == "talisman":
			at(total - 12, func() -> void:
				FX.talisman(a, "wood"))
			at(total - 4, func() -> void:
				a.cast_spell("lightning_strike", true))
		else:
			at(total - (6 if s[0] == "fireball" else 14), func() -> void:
				a.cast_spell(s[0], true))


func _panel_summon() -> void:
	total = 60
	_look(Vector3(0, 3.0, 11), Vector3(0, 1.4, 0), 55.0)
	var specs := [["flying_swords", -7.5, "御剑术"], ["leaf_swarm", -2.5, "飞叶摘花"], ["fire_crows", 2.5, "火鸦术"], ["boulder_orbit", 7.5, "磐石环"]]
	for s in specs:
		var a := _actor(Vector3(s[1], 0, 0), "sword_iron", 0.0, "xuesha", 50)
		_label(s[2], Vector3(s[1], 3.2, 0))
		at(4, func() -> void:
			var def := DB.spell(s[0])
			var n := int(def["params"].get("count", 3))
			for k in n:
				SummonedBlade.spawn(a, def, 0, k, n))


func _panel_misc() -> void:
	total = 70
	_look(Vector3(0, 4.5, 15), Vector3(0, 2.0, 0), 58.0)
	# 护盾破碎
	var sb := _actor(Vector3(-9, 0, 0), "sword_iron", 0.0, "xuesha", 60)
	_label("护盾破碎", Vector3(-9, 2.6, 0))
	at(total - 5, func() -> void:
		var av := FX.vfx_of(sb)
		if av != null:
			av.break_shield(Color(1.0, 0.88, 0.55)))
	# 死亡灵气消散
	var dd := _actor(Vector3(-4.5, 0, 0), "sword_iron", 0.0, "xuesha", 61)
	_label("灵气消散", Vector3(-4.5, 2.6, 0))
	at(total - 30, func() -> void:
		dd.combatant.invuln = 0.0
		dd.combatant.kill())
	# 突破（天降光柱 + 天劫）
	var bt := _actor(Vector3(1.5, 0, -2), "sword_iron", 0.0, "xuesha", 62)
	_label("突破", Vector3(1.5, 3.2, -2))
	at(total - 46, func() -> void:
		FX.breakthrough(bt))
	# 小境界提升
	var lv := _actor(Vector3(7, 0, 0), "sword_iron", 0.0, "xuesha", 63)
	_label("境界精进", Vector3(7, 2.6, 0))
	at(total - 30, func() -> void:
		FX.level_up(lv))
	# 天材地宝与撤离阵
	at(1, func() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		TreasureSite.create(stage, Vector3(12, 0, -8), rng)
		var ep := ExtractionPoint.new()
		stage.add_child(ep)
		ep.position = Vector3(-13, 0.2, -8))


func _panel_dbg() -> void:
	total = 40
	_look(Vector3(0, 1.6, 5.5), Vector3(0, 1.0, 0), 50.0)
	var holder := Node3D.new()
	stage.add_child(holder)
	holder.position = Vector3(-1.5, 0, 0)
	var p1 := VfxParticles.make("flame", 16, holder, Color.WHITE)
	p1.position = Vector3(0, 0.8, 0)
	VfxParticles.set_shape(p1, "tube", 0.38, 1.0)
	var p3 := VfxParticles.make("flame", 16, holder, Color.WHITE)
	p3.position = Vector3(1.0, 0.8, 0)
	var a := _actor(Vector3(1.2, 0, 0), "sword_iron", 0.0, "xuesha", 20)
	at(2, _apply_status.bind(a, "burn", 3.0))
	at(total - 2, func() -> void:
		print("plain tube aabb=", p1.capture_aabb(), " emitting=", p1.emitting)
		print("plain point aabb=", p3.capture_aabb())
		var av := FX.vfx_of(a)
		print("statuses=", a.combatant.statuses.keys(), " apos=", a.global_transform, " vfx=", av.global_transform)
		for k in av._fx:
			for n in av._fx[k]:
				if n is CPUParticles3D:
					var p := n as CPUParticles3D
					print(k, " xf=", p.global_transform, " aabb=", p.capture_aabb(), " local=", p.local_coords))
