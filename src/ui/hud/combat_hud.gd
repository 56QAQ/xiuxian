class_name CombatHUD
extends CanvasLayer
## AC4 式战斗 HUD（国风）：屏幕中央“玉璧”——左侧朱砂笔触为生命、右侧青色灵液为灵力、外圈八卦为护体、
## 内圈细弧为韧性、下方印章为状态；整簇随角色运动反向漂移。
## 另含：八卦锁定环与悬牌、符纸法诀栏与葫芦丹药、罗盘雷达、笔触命中标记与“斩”印、受击方向墨痕、
## 卷轴目标、交互提示、搜索进度、打坐信息、低血量渗墨暗角。
##
## 结构：本层保存共享状态并逐帧更新；绘制分给 HUDCanvas（环下层：锁定、角落、雷达、法诀栏）、
## 玉璧着色器 ring、HUDCluster（环上层：八卦、数值、印章、准星、命中）。

const RING_R := 124.0          ## 玉璧环带中线半径（1080p 像素）
const BAND_W := 18.0           ## 环带宽

var actor: HumanoidActor
var cam: CameraRig

var canvas: HUDCanvas
var ring: ColorRect
var cluster: HUDCluster
var vignette: ColorRect

## 共享状态（各绘制节点读取）
var drift: Vector2 = Vector2.ZERO
var hit_t: float = 0.0
var hit_crit: bool = false
var kill_t: float = 0.0
var dmg_dirs: Array[Dictionary] = []   ## {angle, t}
var prompt: String = ""
var objective: String = ""
var search_p: float = -1.0
var shown_hp: float = 1.0        ## 生命（平滑）
var hp_lag: float = 1.0          ## 失血残痕（延迟回落）
var shown_shield: float = 1.0
var shield_flash: float = 0.0    ## 护体破碎闪光
var t: float = 0.0
var _prev_yaw: float = 0.0
var _prev_hp: float = -1.0
var _lag_hold: float = 0.0
var _prev_shield: float = 0.0
var _heartbeat: float = 0.0


func _ready() -> void:
	layer = 10
	vignette = ColorRect.new()
	vignette.name = "InkVignette"
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vm := ShaderMaterial.new()
	vm.shader = load("res://src/ui/hud/ink_vignette.gdshader")
	vm.set_shader_parameter("noise_tex", InkArt.tex("noise"))
	vignette.material = vm
	vignette.visible = false
	add_child(vignette)
	canvas = HUDCanvas.new()
	canvas.name = "Canvas"
	canvas.hud = self
	add_child(canvas)
	ring = ColorRect.new()
	ring.name = "JadeRing"
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rm := ShaderMaterial.new()
	rm.shader = load("res://src/ui/hud/jade_ring.gdshader")
	rm.set_shader_parameter("noise_tex", InkArt.tex("noise"))
	ring.material = rm
	ring.visible = false
	add_child(ring)
	cluster = HUDCluster.new()
	cluster.name = "Cluster"
	cluster.hud = self
	add_child(cluster)
	Events.hit_landed.connect(_on_hit)
	Events.interaction_prompt.connect(func(s: String) -> void: prompt = s)
	Events.search_progress.connect(func(p: float) -> void: search_p = p)
	Events.hud_objective.connect(func(s: String) -> void: objective = s)


func bind(a: HumanoidActor, c: CameraRig) -> void:
	actor = a
	cam = c
	if a != null and is_instance_valid(a):
		shown_hp = a.combatant.hp_ratio()
		hp_lag = shown_hp
		_prev_hp = a.combatant.hp


func has_actor() -> bool:
	return actor != null and is_instance_valid(actor)


## 界面缩放（以 1080p 为 1）
func ui_scale() -> float:
	return canvas.get_viewport_rect().size.y / 1080.0 if canvas != null else 1.0


## 中央簇的中心（含漂移）
func cluster_center() -> Vector2:
	var vs := canvas.get_viewport_rect().size
	return vs * 0.5 + drift * ui_scale()


func _on_hit(h: Dictionary) -> void:
	if not has_actor():
		return
	if h.get("source") == actor and str(h.get("kind", "")) != "dot":
		hit_t = 0.2
		hit_crit = h.get("crit", false)
		if h.get("killed", false):
			kill_t = 0.9
	if h.get("target") == actor and cam != null:
		var src: Node3D = h.get("source")
		if src != null and is_instance_valid(src):
			var to := src.global_position - actor.global_position
			var ang := atan2(to.x, to.z)
			var rel := wrapf(ang - cam.yaw + PI, -PI, PI)
			dmg_dirs.append({"angle": rel, "t": 1.0})
			if dmg_dirs.size() > 6:
				dmg_dirs.pop_front()


func _process(delta: float) -> void:
	t += delta
	hit_t = maxf(hit_t - delta, 0.0)
	kill_t = maxf(kill_t - delta, 0.0)
	shield_flash = maxf(shield_flash - delta * 2.5, 0.0)
	for d in dmg_dirs:
		d["t"] = float(d["t"]) - delta * 0.8
	dmg_dirs = dmg_dirs.filter(func(d: Dictionary) -> bool: return float(d["t"]) > 0.0)
	var alive := has_actor() and cam != null
	ring.visible = alive
	if not alive:
		vignette.visible = false
		canvas.queue_redraw()
		cluster.queue_redraw()
		return
	var s := ui_scale()
	var v := actor.velocity
	var cb := cam.camera.global_basis
	var sv := Vector2(v.dot(cb.x), -v.dot(cb.y))
	var yaw_rate := wrapf(cam.yaw - _prev_yaw, -PI, PI) / maxf(delta, 0.001)
	_prev_yaw = cam.yaw
	var k := 3.2 * Settings.hud_drift
	var want := (-sv * k + Vector2(yaw_rate * 18.0, 0.0) * Settings.hud_drift).limit_length(80.0)
	drift = drift.lerp(want, 1.0 - exp(-5.0 * delta))
	var c := actor.combatant
	var hr := c.hp_ratio()
	shown_hp = lerpf(shown_hp, hr, 1.0 - exp(-14.0 * delta))
	# 失血残痕：受击后停留片刻再回落；回复时立即跟上
	if _prev_hp >= 0.0 and c.hp < _prev_hp - 0.01:
		_lag_hold = 0.55
	_prev_hp = c.hp
	_lag_hold = maxf(_lag_hold - delta, 0.0)
	if hr >= hp_lag:
		hp_lag = hr
	elif _lag_hold <= 0.0:
		hp_lag = maxf(hr, hp_lag - delta * 0.45)
	var max_sh := maxf(c.stat("max_shield"), 1.0)
	shown_shield = lerpf(shown_shield, c.shield / max_sh, 1.0 - exp(-10.0 * delta))
	if _prev_shield > 0.5 and c.shield <= 0.5:
		shield_flash = 1.0
	_prev_shield = c.shield
	# 玉璧
	var ring_px := (RING_R + BAND_W + 6.0) * 2.0 * s
	var ctr := cluster_center()
	ring.size = Vector2(ring_px, ring_px)
	ring.position = ctr - ring.size * 0.5
	var qr := clampf(c.qi / maxf(c.stat("max_qi"), 1.0), 0.0, 1.0)
	var burn := c.has_status("qi_burnout")
	var low := clampf((0.35 - hr) / 0.35, 0.0, 1.0)
	var rm := ring.material as ShaderMaterial
	rm.set_shader_parameter("size_px", ring_px)
	rm.set_shader_parameter("ring_r", RING_R * s)
	rm.set_shader_parameter("band_w", BAND_W * s)
	rm.set_shader_parameter("hp", clampf(shown_hp, 0.0, 1.0))
	rm.set_shader_parameter("hp_lag", clampf(hp_lag, 0.0, 1.0))
	rm.set_shader_parameter("qi", qr)
	rm.set_shader_parameter("burn", 1.0 if burn else 0.0)
	rm.set_shader_parameter("low", low)
	# 渗墨暗角：低血量朱红（心跳）> 灵力枯竭青灰
	var vm := vignette.material as ShaderMaterial
	var vs := canvas.get_viewport_rect().size
	vm.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
	if low > 0.0:
		_heartbeat += delta * (1.2 + low * 1.4)
		var beat := pow(maxf(sin(_heartbeat * TAU), 0.0), 6.0)
		vignette.visible = true
		vm.set_shader_parameter("ink_color", Color(0.46, 0.02, 0.02, 1.0))
		vm.set_shader_parameter("amount", 0.3 + low * 0.6)
		vm.set_shader_parameter("pulse", beat)
	elif burn:
		vignette.visible = true
		vm.set_shader_parameter("ink_color", Color(0.16, 0.2, 0.28, 0.9))
		vm.set_shader_parameter("amount", 0.55)
		vm.set_shader_parameter("pulse", 0.0)
	else:
		vignette.visible = false
	canvas.queue_redraw()
	cluster.queue_redraw()
