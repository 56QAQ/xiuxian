extends RefCounted
## 实机截图：开新游戏进入大地图。--at=<POI id>（如 home、town、sect_tianjian、portal_0）传送；--yaw=度 --pitch=度 --hour=时

var ow: Node3D
var at := "home"
var yaw := -999.0
var pitch := -14.0
var hour := 10.0


func frames() -> int:
	return 150


func build(root: Node) -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--at="):
			at = a.substr(5)
		elif a.begins_with("--yaw="):
			yaw = float(a.substr(6))
		elif a.begins_with("--pitch="):
			pitch = float(a.substr(8))
		elif a.begins_with("--hour="):
			hour = float(a.substr(7))
	GS.new_game({"name": "赵灵儿", "roots": {"fire": 60, "metal": 40}, "background": "clan", "seed": 20250917,
		"talents": ["fox_blood"], "appearance": {}})
	GS.world["hours"] = hour
	if at != "home":
		var p := WorldMap.find(at)
		if not p.is_empty():
			var f: Vector3 = p["facing"]
			GS.overworld_position = (p["pos"] as Vector3) + f * 14.0 + Vector3.UP * 2.0
	ow = load("res://scenes/overworld.tscn").instantiate()
	root.add_child(ow)


func step(_root: Node, i: int) -> void:
	var gp: OverworldGameplay = ow.get_node_or_null("Gameplay")
	if gp == null or gp.player == null:
		return
	var cam: CameraRig = gp.session.camera
	if i == 5:
		var p := WorldMap.find(at)
		if not p.is_empty():
			var to: Vector3 = (p["pos"] as Vector3) - gp.player.global_position
			gp.player.rotation.y = atan2(-to.x, -to.z)
			cam.yaw = gp.player.rotation.y if yaw < -900.0 else deg_to_rad(yaw)
	cam.pitch = pitch
	if i == 20:
		ow.prime_props()
