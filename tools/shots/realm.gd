extends RefCounted
## 秘境截图：生成指定主题秘境，从玩家出生点向内眺望。用 --realm=<id> 选择秘境。

var realm: Node


func frames() -> int:
	return 40


func build(root: Node) -> void:
	GS.active = false
	var rid := "herb_valley"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--realm="):
			rid = a.substr(8)
	GS.realm_request = {"realm_id": rid, "seed": 20260928}
	realm = load("res://scenes/secret_realm.tscn").instantiate()
	realm.test_mode = true
	root.add_child(realm)


func step(_root: Node, i: int) -> void:
	var cam: CameraRig = realm.session.camera
	cam.yaw = PI
	cam.pitch = -16.0
	if i == 2:
		var p: HumanoidActor = realm.session.player
		p.rotation.y = PI
