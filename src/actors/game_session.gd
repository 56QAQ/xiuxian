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
var ui: Node
var numbers: DamageNumbers


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
	if ResourceLoader.exists("res://src/ui/ui_manager.gd"):
		var ui_script: Script = load("res://src/ui/ui_manager.gd")
		ui = ui_script.new()
		ui.name = "UIManager"
		add_child(ui)
	capture_mouse()


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
