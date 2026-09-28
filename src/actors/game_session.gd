class_name GameSession
extends Node
## 游戏会话：在任意 3D 场景中生成玩家、镜头、HUD、伤害跳字与 UI 管理器，并处理鼠标捕获与玩家死亡。
## 大地图、秘境、试炼场共用。

signal player_died

var world: Node3D
var player: HumanoidActor
var camera: CameraRig
var controller: PlayerController
var hud: CombatHUD
var ui: UIManager
var numbers: DamageNumbers
## 场景基础音乐；遭遇敌人时切换为战斗音乐
var base_music: String = ""
var _battle_t: float = 0.0
var _in_battle: bool = false
var _music_check: float = 0.0


func start(world_root: Node3D, pos: Vector3) -> void:
	world = world_root
	var r := ActorFactory.spawn_player(world_root, pos)
	player = r["actor"]
	camera = r["camera"]
	controller = r["controller"]
	player.died.connect(_on_player_died)
	numbers = DamageNumbers.new()
	numbers.name = "DamageNumbers"
	world_root.add_child(numbers)
	hud = CombatHUD.new()
	hud.name = "HUD"
	add_child(hud)
	hud.bind(player, camera)
	var mgr := UIManager.new()
	mgr.name = "UIManager"
	mgr.capture_mouse_when_closed = DisplayServer.get_name() != "headless"
	ui = mgr
	add_child(mgr)
	if not UIManager.has_panel("sect"):
		UIManager.register_panel("sect", SectPanel.create)
	capture_mouse()


func _exit_tree() -> void:
	# 静态注册表中不保留本会话的回调，避免退出时访问已释放的脚本
	UIManager.unregister_panel("sect")
	UIManager.register_args_provider("map", Callable())


func set_music(track: String) -> void:
	base_music = track
	if not _in_battle:
		Audio.play_music(track, 1.5)


func _process(delta: float) -> void:
	_music_check -= delta
	if _music_check > 0.0 or player == null or not is_instance_valid(player):
		return
	_music_check = 0.5
	var threat := false
	if player.combatant.alive:
		var h := CombatUtil.nearest_hostile(player, 32.0)
		threat = h != null or player.combatant.since_damage < 4.0
	if threat:
		_battle_t = 8.0
		if not _in_battle:
			_in_battle = true
			Audio.play_music("music_battle", 0.8)
	elif _in_battle:
		_battle_t -= 0.5
		if _battle_t <= 0.0:
			_in_battle = false
			if base_music != "":
				Audio.play_music(base_music, 2.5)


func capture_mouse() -> void:
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func ui_blocking() -> bool:
	return ui != null and ui.has_method("is_blocking") and bool(ui.call("is_blocking"))


func _unhandled_input(event: InputEvent) -> void:
	if ui != null:
		return
	# 没有 UI 管理器时的最小鼠标处理
	if event.is_action_pressed("pause") or event.is_action_pressed("toggle_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		capture_mouse()


func _on_player_died(_a: HumanoidActor, _killer: Node3D) -> void:
	HitStop.reset()
	Events.player_died.emit()
	player_died.emit()
