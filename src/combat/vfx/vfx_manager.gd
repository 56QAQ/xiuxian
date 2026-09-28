class_name VfxManager
extends Node
## 特效管理器：随当前场景创建（场景切换时一并释放），负责：
## 粒子对象池、闪光点光源池、贴花/残影数量上限、镜头位置缓存、粒子预算，以及受击涟漪/暴击等全局命中表现。
## 所有一次性特效节点都挂在本节点下（本节点是 Node，子节点的局部坐标即世界坐标）。

const POOL_MAX := 6          ## 每种预设 × 数量档位的池上限
const LIGHT_MAX := 8         ## 同时存在的闪光点光源上限
const DECAL_MAX := 28        ## 地面贴花上限
const GHOST_MAX := 6         ## 残影上限（每个残影约 20~25 个网格实例）
const BUDGET := 2400.0       ## 每秒粒子预算（超出后按比例削减）

static var _inst: VfxManager

var clock: float = 0.0
var cam_pos: Vector3 = Vector3.ZERO
var cam_fwd: Vector3 = Vector3.FORWARD
var has_cam: bool = false
var _pools: Dictionary = {}           ## key -> Array[CPUParticles3D]
var _started: Dictionary = {}         ## 粒子节点 instance_id -> 开始时刻
var _lights: Array[OmniLight3D] = []
var _decals: Array = []
var _ghosts: Array = []
var _rate: float = 0.0                ## 最近粒子发射速率（指数衰减）
## 统计（性能报告用）
var stat_bursts: int = 0
var stat_particles: int = 0


static func get_mgr() -> VfxManager:
	if _inst != null and is_instance_valid(_inst) and not _inst.is_queued_for_deletion():
		return _inst
	var r := FX.root()
	if r == null:
		return null
	_inst = VfxManager.new()
	_inst.name = "VfxManager"
	if r.is_node_ready() or r == r.get_tree().root:
		r.add_child(_inst)
	else:
		r.add_child.call_deferred(_inst)
	return _inst


static func has_mgr() -> bool:
	return _inst != null and is_instance_valid(_inst)


func _ready() -> void:
	process_priority = 100
	_update_cam()
	if not Events.hit_landed.is_connected(_on_hit_landed):
		Events.hit_landed.connect(_on_hit_landed)


func _exit_tree() -> void:
	if Events.hit_landed.is_connected(_on_hit_landed):
		Events.hit_landed.disconnect(_on_hit_landed)
	if _inst == self:
		_inst = null


var _sweep_t: float = 0.0


func _process(delta: float) -> void:
	clock += delta
	_rate = maxf(_rate - _rate * minf(delta * 3.0, 1.0), 0.0)
	_update_cam()
	_sweep_t -= delta
	if _sweep_t <= 0.0:
		_sweep_t = 0.5
		_sweep_pools()


func _update_cam() -> void:
	var vp := get_viewport()
	var cam := vp.get_camera_3d() if vp != null else null
	has_cam = cam != null and cam.is_inside_tree()
	if has_cam:
		cam_pos = cam.global_position
		cam_fwd = -cam.global_basis.z


## 是否值得在 pos 处生成特效（远处的小特效直接跳过）
func visible_at(pos: Vector3, max_dist: float) -> bool:
	if not has_cam:
		return true
	return cam_pos.distance_squared_to(pos) <= max_dist * max_dist


## 粒子预算：短时间内发射过多时按比例削减数量
func budget(amount: int) -> int:
	var scale := 1.0
	if _rate > BUDGET:
		scale = clampf(BUDGET / _rate, 0.25, 1.0)
	var n := int(ceil(amount * scale))
	_rate += n * 3.0
	stat_particles += n
	stat_bursts += 1
	return n


## 加入节点（一次性特效），返回该节点
func add(n: Node) -> Node:
	add_child(n)
	return n


# ================================================================ 粒子池

func acquire_particles(preset: String, amount: int) -> CPUParticles3D:
	var b := VfxParticles.bucket(amount)
	var key := "%s:%d" % [preset, b]
	var arr: Array = _pools.get(key, [])
	if arr.is_empty():
		_pools[key] = arr
	var oldest: CPUParticles3D = null
	var oldest_t := INF
	for p in arr:
		var pp := p as CPUParticles3D
		if not is_instance_valid(pp):
			continue
		var st := float(_started.get(pp.get_instance_id(), -INF))
		if not pp.emitting and clock - st > pp.lifetime * 1.6:
			return pp
		if clock - st > pp.lifetime * 2.0 + 0.2:
			return pp
		if st < oldest_t:
			oldest_t = st
			oldest = pp
	if arr.size() < POOL_MAX:
		var n := CPUParticles3D.new()
		VfxParticles.configure(n, preset)
		n.one_shot = true
		n.emitting = false
		n.amount = b
		n.visible = false
		add_child(n)
		# 结束后隐藏：空闲的池中节点不产生绘制调用
		n.finished.connect(n.hide)
		arr.append(n)
		return n
	return oldest


func started(p: CPUParticles3D) -> void:
	_started[p.get_instance_id()] = clock
	p.visible = true


## 兜底：隐藏已结束的池中粒子（防止 finished 信号遗漏）
func _sweep_pools() -> void:
	for key in _pools:
		for p in _pools[key]:
			var pp := p as CPUParticles3D
			if is_instance_valid(pp) and pp.visible and clock - float(_started.get(pp.get_instance_id(), -INF)) > pp.lifetime * 2.0 + 0.3:
				pp.visible = false


## 池中粒子统计：total 池节点数，active 正在显示的系统数，particles 其粒子容量之和
func pool_stats() -> Dictionary:
	var total := 0
	var active := 0
	var particles := 0
	for key in _pools:
		for p in _pools[key]:
			var pp := p as CPUParticles3D
			if not is_instance_valid(pp):
				continue
			total += 1
			if pp.visible:
				active += 1
				particles += pp.amount
	return {"total": total, "active": active, "particles": particles}


# ================================================================ 闪光灯池

func flash_light(pos: Vector3, color: Color, energy: float, light_range: float, time: float) -> void:
	if not visible_at(pos, 70.0):
		return
	var l: OmniLight3D = null
	var best_left := INF
	for c in _lights:
		if not is_instance_valid(c):
			continue
		var left := float(c.get_meta("until", 0.0)) - clock
		if left <= 0.0:
			l = c
			break
		if left < best_left:
			best_left = left
			l = c
	if (l == null or float(l.get_meta("until", 0.0)) > clock) and _lights.size() < LIGHT_MAX:
		l = OmniLight3D.new()
		l.shadow_enabled = false
		l.omni_attenuation = 1.6
		add_child(l)
		_lights.append(l)
	if l == null:
		return
	if l.has_meta("tw"):
		var old: Tween = l.get_meta("tw")
		if old != null and old.is_valid():
			old.kill()
	l.visible = true
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = light_range
	l.set_meta("until", clock + time)
	var tw := l.create_tween()
	tw.tween_property(l, "light_energy", 0.0, time).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)
	tw.tween_callback(l.hide)
	l.set_meta("tw", tw)


# ================================================================ 上限管理

func register_decal(n: Node3D) -> void:
	_decals = _alive(_decals)
	_decals.append(n)
	while _decals.size() > DECAL_MAX:
		var o = _decals.pop_front()
		if is_instance_valid(o):
			(o as Node).queue_free()


func register_ghost(n: Node3D) -> void:
	_ghosts = _alive(_ghosts)
	_ghosts.append(n)
	while _ghosts.size() > GHOST_MAX:
		var o = _ghosts.pop_front()
		if is_instance_valid(o):
			(o as Node).queue_free()


static func _alive(arr: Array) -> Array:
	var out := []
	for x in arr:
		if is_instance_valid(x) and not (x as Node).is_queued_for_deletion():
			out.append(x)
	return out


func decal_count() -> int:
	return _alive(_decals).size()


func ghost_count() -> int:
	return _alive(_ghosts).size()


# ================================================================ 全局命中表现

func _on_hit_landed(h: Dictionary) -> void:
	var target: Node = h.get("target", null)
	if target == null or not is_instance_valid(target):
		return
	var pos: Vector3 = h.get("pos", Vector3.ZERO)
	var kind := str(h.get("kind", ""))
	if kind == "dot":
		return
	# 护体灵光吸收：护盾涟漪
	if bool(h.get("shield", false)):
		var av: ActorVfx = target.get_meta("vfx", null) if target.has_meta("vfx") else null
		if av != null and is_instance_valid(av):
			av.shield_hit(pos)
	# 暴击：灵气迸发
	if bool(h.get("crit", false)):
		FX.crit_burst(pos, str(h.get("element", Elem.NONE)))
