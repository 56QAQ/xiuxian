extends RefCounted
## LOD 检查：同一角色/妖兽并排——左边近景 LOD0，右边强制显示远景 LOD1（把 LOD1 拉到近处对比细节损失）。
## 额外参数：--app='{...}'  --beast=wolf


func _arg(k: String, def: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.substr(k.length() + 3)
	return def


func frames() -> int:
	return 60


func _force_lod1(n: Node) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.visibility_range_begin > 0.0:
			mi.visibility_range_begin = 0.0
			mi.visibility_range_begin_margin = 0.0
		elif mi.visibility_range_end > 0.0:
			mi.visible = false
	for c in n.get_children():
		_force_lod1(c)


func build(root: Node) -> void:
	var app := {}
	var js := _arg("app")
	if js != "":
		var d: Variant = JSON.parse_string(js)
		if d is Dictionary:
			app = d
	var beast := _arg("beast")
	ArtStudio.setup(root, Vector3(0, 1.1, 4.6), Vector3(0, 0.85, 0), 34.0)
	for i in 2:
		var rig: CharacterRig
		if beast != "":
			rig = BeastBuilder.build(beast, [], 1.0)
			rig.rotation_degrees.y = 120.0
		else:
			rig = CharacterBuilder.build(app, {"weapon": DB.item("flag_spear_fire")["weapon"]["visual"]})
			rig.rotation_degrees.y = 180.0 + 20.0
		rig.position = Vector3(-0.8 + i * 1.6, 0, 0)
		root.add_child(rig)
		VoxMesh.finish_pending()
		if i == 1:
			_force_lod1(rig)
