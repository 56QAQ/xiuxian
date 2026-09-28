extends RefCounted
## 特效性能采样：试炼场 1 名玩家（自动出招、放法诀、瞬步）对 3 名修士 + 6 头妖兽。
## 每 10 帧统计一次特效节点、粒子、灯光、贴花、残影与渲染调用，结束时打印平均/峰值。
## 模拟步长固定约 1/60 秒（同 vfx_gallery）。用法：tools/shot.sh <godot> vfx_perf out.png --size=1600x900

var arena: Node
var total: int = 330
var _samples: Array[Dictionary] = []
var _proc_ms: Array[float] = []


func frames() -> int:
	return total


func build(root: Node) -> void:
	GS.active = false
	arena = load("res://scenes/dev_arena.tscn").instantiate()
	root.add_child(arena)
	# 让玩家拥有 4 个不同类型的法诀
	for id in ["gengjin_jianqi", "fireball", "flame_rain", "frost_nova"]:
		GS.learn_spell(id, false)
	GS.set_spell_slot(0, "gengjin_jianqi")
	GS.set_spell_slot(1, "fireball")
	GS.set_spell_slot(2, "flame_rain")
	GS.set_spell_slot(3, "frost_nova")
	var ids := ["wolf_grey", "fox_flame", "boar_iron", "snake_water", "spider_jade", "crane_white"]
	for i in ids.size():
		var a := TAU * i / ids.size()
		ActorFactory.spawn_beast(arena, ids[i], Vector3(cos(a) * 9.0, 0.5, sin(a) * 9.0 - 4.0))
	VfxShotClock.fix()


func step(_root: Node, i: int) -> void:
	var player: HumanoidActor = arena.session.player
	if player == null or not is_instance_valid(player):
		return
	player.combatant.invuln = 1.0
	player.combatant.qi = player.combatant.stat("max_qi")
	var tgt := CombatUtil.nearest_hostile(player, 80.0)
	player.lock_target = tgt
	if tgt != null:
		var to := tgt.global_position - player.global_position
		to.y = 0
		player.in_move = to.normalized() if to.length() > 2.5 else Vector3.ZERO
		player.in_boost = to.length() > 8.0
		if i % 9 == 0:
			player.in_melee = true
		if i % 45 == 20:
			player.in_spell = (i / 45) % 4
		if i % 70 == 35:
			player.in_move = to.normalized().rotated(Vector3.UP, PI / 2.0)
			player.in_qb = true
		var cam: CameraRig = arena.session.camera
		cam.yaw = lerp_angle(cam.yaw, atan2(-to.x, -to.z) + 0.4, 0.1)
	_proc_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	if i % 10 == 5 and i > 30:
		_samples.append(_sample())
	if i == total - 1:
		_report()


func _sample() -> Dictionary:
	var tree := Engine.get_main_loop() as SceneTree
	var emitters := 0
	var particles := 0
	for n in tree.root.find_children("*", "CPUParticles3D", true, false):
		var p := n as CPUParticles3D
		if p.is_visible_in_tree():
			emitters += 1
			particles += p.amount
	# 可见的特效几何体（≈ 特效带来的绘制调用）
	var vfx_geo := 0
	var roots: Array[Node] = []
	var mgr := VfxManager.get_mgr()
	if mgr != null:
		roots.append(mgr)
	roots.append_array(tree.get_nodes_in_group("projectiles"))
	for c in tree.get_nodes_in_group("combatants"):
		var v = (c as Node).get_meta("vfx", null) if (c as Node).has_meta("vfx") else null
		if v != null and is_instance_valid(v):
			roots.append(v)
		var tr = (c as Node).get("trail")
		if tr != null and is_instance_valid(tr):
			roots.append(tr)
	for r in roots:
		if r is GeometryInstance3D and (r as GeometryInstance3D).is_visible_in_tree():
			vfx_geo += 1
		for g in r.find_children("*", "GeometryInstance3D", true, false):
			if (g as GeometryInstance3D).is_visible_in_tree():
				vfx_geo += 1
	var ribbons := tree.root.find_children("*", "VfxRibbon", true, false).size()
	var lights := 0
	for n in tree.root.find_children("*", "OmniLight3D", true, false):
		if (n as OmniLight3D).is_visible_in_tree() and (n as OmniLight3D).light_energy > 0.01:
			lights += 1
	var m := VfxManager.get_mgr()
	return {
		"vfx_nodes": m.get_child_count() if m != null else 0,
		"vfx_geo": vfx_geo, "emitters": emitters, "particles": particles, "ribbons": ribbons, "lights": lights,
		"pool_total": mgr.pool_stats()["total"] if mgr != null else 0,
		"decals": m.decal_count() if m != null else 0, "ghosts": m.ghost_count() if m != null else 0,
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"objects": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"combatants": tree.get_nodes_in_group("combatants").size(),
	}


func _report() -> void:
	if _samples.is_empty():
		return
	var keys: Array = _samples[0].keys()
	print("==== 特效性能（%d 个采样）====" % _samples.size())
	for k in keys:
		var sum := 0.0
		var peak := 0.0
		for s in _samples:
			sum += float(s[k])
			peak = maxf(peak, float(s[k]))
		print("  %-11s 平均 %8.1f  峰值 %8.0f" % [k, sum / _samples.size(), peak])
	var ps := 0.0
	for v in _proc_ms:
		ps += v
	print("  process_ms  平均 %8.2f（软件渲染下仅供参考）" % (ps / maxf(_proc_ms.size(), 1.0)))
	var m := VfxManager.get_mgr()
	if m != null:
		print("  累计迸发 %d 次，累计粒子 %d" % [m.stat_bursts, m.stat_particles])
