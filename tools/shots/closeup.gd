extends RefCounted
## 角色特写：默认 4 个角度（正面 / 3/4 / 侧面 / 背面）。
## 额外参数：
##   --app='{"hair_style":"long"}'      JSON，覆盖默认外貌（所有角色）
##   --apps='[{...},{...}]'             JSON 数组，每个角色一套外貌（与 --angles 配合）
##   --angles=0,35,90,180               每个角色的朝向（度，0 = 正面朝镜头）
##   --weapon=物品id（全部）/ --weapons=id1,id2,...（逐个，- 表示空手）  --zoom=head|body  --pose=剪辑名  --stance=sword|saber|spear|fist


var _rigs: Array = []
var _pose := ""


func _arg(k: String, def: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.substr(k.length() + 3)
	return def


func frames() -> int:
	return 40


func build(root: Node) -> void:
	var app := {}
	var js := _arg("app")
	if js != "":
		var d: Variant = JSON.parse_string(js)
		if d is Dictionary:
			app = d
	var apps: Array = []
	var jss := _arg("apps")
	if jss != "":
		var d2: Variant = JSON.parse_string(jss)
		if d2 is Array:
			apps = d2
	var angles: Array = [0.0, 35.0, 90.0, 180.0]
	var an := _arg("angles")
	if an != "":
		angles = []
		for p in an.split(","):
			angles.append(float(p))
	var wlist: Array = []
	if _arg("weapons") != "":
		wlist = Array(_arg("weapons").split(","))
	var n := maxi(maxi(angles.size(), apps.size()), wlist.size())
	var zoom := _arg("zoom", "body")
	_pose = _arg("pose")
	var spacing := 1.1 if zoom == "head" else 1.45
	var width := spacing * (n - 1)
	if zoom == "head":
		ArtStudio.setup(root, Vector3(0, 1.55, 3.2 + maxf(0.0, (n - 4) * 0.6)), Vector3(0, 1.45, 0), 34.0)
	else:
		ArtStudio.setup(root, Vector3(0, 1.05, 5.4 + maxf(0.0, (n - 3) * 1.3)), Vector3(0, 0.92, 0), 32.0)
	var eq := {}
	var wid := _arg("weapon")
	if wid != "":
		eq["weapon"] = DB.item(wid)["weapon"]["visual"]
	for i in n:
		var a2: Dictionary = app.duplicate()
		if i < apps.size():
			for k in apps[i]:
				a2[k] = apps[i][k]
		var eq2 := eq
		if i < wlist.size() and str(wlist[i]) != "-":
			eq2 = {"weapon": DB.item(str(wlist[i]))["weapon"]["visual"]}
		var rig := CharacterBuilder.build(a2, eq2)
		rig.position = Vector3(-width * 0.5 + i * spacing, 0, 0)
		rig.rotation_degrees.y = 180.0 + float(angles[i % angles.size()])
		var st := _arg("stance")
		if st != "":
			rig.stance = st
		root.add_child(rig)
		_rigs.append(rig)


func step(_root: Node, frame: int) -> void:
	if frame == 1 and _pose != "":
		for r in _rigs:
			(r as CharacterRig).play(_pose)
