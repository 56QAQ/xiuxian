extends RefCounted
## 妖兽展示：八种模型（enemies.json 配色 + 默认配色），侧前方视角。
## 额外参数：--anim=walk|trot|gallop|clip名（全部同时播放，截取中段）


var _rigs: Array = []
var _anim := ""


func _arg(k: String, def: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.substr(k.length() + 3)
	return def


func frames() -> int:
	return 50


func build(root: Node) -> void:
	_anim = _arg("anim")
	var only := _arg("only")
	if only != "":
		# 单只特写：三个角度
		ArtStudio.setup(root, Vector3(0, 1.4, 6.4), Vector3(0, 0.55, 0), 36.0)
		var cols: Array = []
		var sz := 1.0
		for eid in DB.enemies:
			if str(DB.enemies[eid].get("model", "")) == only:
				cols = DB.enemies[eid].get("colors", [])
				sz = float(DB.enemies[eid].get("size", 1.0))
		sz = float(_arg("scale", str(sz)))
		var yaws := [90.0, 145.0, 200.0]
		for i in 3:
			var r := BeastBuilder.build(only, cols, sz)
			r.position = Vector3(-2.0 + i * 2.0, 0, 0)
			r.rotation_degrees.y = yaws[i]
			root.add_child(r)
			_rigs.append(r)
		return
	ArtStudio.setup(root, Vector3(0.5, 2.6, 8.8), Vector3(0.3, 0.7, 0), 34.0)
	var list := [
		["wolf", DB.enemies.get("wolf_grey", {}).get("colors", []), 1.0],
		["fox", DB.enemies.get("fox_flame", {}).get("colors", []), 0.9],
		["boar", DB.enemies.get("boar_iron", {}).get("colors", []), 1.3],
		["golem", DB.enemies.get("golem_stone", {}).get("colors", []), 1.6],
		["bear", [], 1.0],
		["snake", [], 1.0],
		["crane", [], 1.0],
		["spider", [], 1.0],
	]
	var pos := [Vector3(-3.4, 0, 0.6), Vector3(-1.6, 0, 1.2), Vector3(0.2, 0, 0.6), Vector3(2.4, 0, -0.4), Vector3(-2.8, 0, -2.2), Vector3(-0.4, 0, -1.6), Vector3(1.4, 0, -2.4), Vector3(4.0, 0, 1.0)]
	for i in list.size():
		var rig := BeastBuilder.build(str(list[i][0]), list[i][1], float(list[i][2]))
		rig.position = pos[i]
		rig.rotation_degrees.y = 150.0 if str(list[i][0]) != "golem" else 195.0
		root.add_child(rig)
		_rigs.append(rig)


func step(_root: Node, frame: int) -> void:
	if _anim == "":
		return
	for r in _rigs:
		var rig := r as CharacterRig
		match _anim:
			"walk":
				rig.set_locomotion(Vector3(0, 0, -1.5), true, false, false)
			"trot":
				rig.set_locomotion(Vector3(0, 0, -4.0), true, false, false)
			"gallop":
				rig.set_locomotion(Vector3(0, 0, -9.0), true, false, false)
			_:
				if frame == 5:
					rig.play(_anim)
