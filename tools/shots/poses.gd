extends RefCounted
## 动作定格：角色播放剪辑到出手帧附近（手动推进 rig._process），检查持械与动作在新骨架上的效果。
## 额外参数：--set=combat（默认）| move（移动/御风/打坐）


const COMBAT := [
	["sword_1", 0.14, "sword_green", {}],
	["saber_3", 0.44, "saber_iron", {"gender": "male", "hair_style": "bun", "outfit": "robe", "ears": "human", "hair_color": "#1a1a22", "hair_color2": "#50506a"}],
	["spear_1", 0.14, "flag_spear_fire", {}],
	["fist_4", 0.14, "fist_wraps", {"outfit": "martial", "hair_style": "ponytail", "ears": "cat", "hair_color": "#8a4a2a", "hair_color2": "#c07a4a", "outfit_colors": ["#5ab86a", "#2a4a30", "#e0d8a0"]}],
	["cast_forward", 0.16, "", {"hair_style": "flowing", "outfit": "robe", "ears": "elf", "hair_color": "#f0f0f4", "hair_color2": "#c8d4ff", "eye_color": "#3080f0", "mark": "lotus", "outfit_colors": ["#e8ecf4", "#4a5a78", "#d8b050"]}],
	["stagger", 0.1, "saber_iron", {"gender": "male", "outfit": "armor", "hair_style": "short", "ears": "human", "hair_color": "#1a1a22"}],
]
const MOVE := [
	["run", 1.6, "flag_spear_fire", {}],
	["boost", 1.2, "sword_green", {"hair_style": "long", "outfit": "robe", "ears": "human", "hair_color": "#1a1a22", "hair_color2": "#50506a"}],
	["fly", 1.4, "", {"hair_style": "flowing", "outfit": "robe", "ears": "elf", "hair_color": "#f0f0f4", "hair_color2": "#c8d4ff"}],
	["meditate", 1.0, "", {"gender": "male", "hair_style": "bun", "outfit": "robe", "ears": "human", "hair_color": "#1a1a22", "outfit_colors": ["#3a6ad0", "#1a2a50", "#c8e0ff"]}],
	["death", 1.4, "saber_iron", {"gender": "male", "outfit": "martial", "hair_style": "ponytail", "ears": "human", "hair_color": "#e8c060", "hair_color2": "#fff0a0", "outfit_colors": ["#2a2a30", "#101014", "#c02030"]}],
]


func _arg(k: String, def: String = "") -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + k + "="):
			return a.substr(k.length() + 3)
	return def


func frames() -> int:
	return 4


func build(root: Node) -> void:
	var list: Array = MOVE if _arg("set") == "move" else COMBAT
	var n := list.size()
	ArtStudio.setup(root, Vector3(0, 1.3, 3.2 + n * 0.8), Vector3(0, 0.85, 0), 36.0)
	var dt := 1.0 / 60.0
	for i in n:
		var e: Array = list[i]
		var eq := {}
		if str(e[2]) != "":
			eq["weapon"] = DB.item(str(e[2]))["weapon"]["visual"]
		var rig := CharacterBuilder.build(e[3], eq)
		rig.position = Vector3(-(n - 1) * 0.75 + i * 1.5, 0, 0)
		rig.rotation_degrees.y = 180.0 + 35.0
		root.add_child(rig)
		rig.set_process(false)
		var clip := str(e[0])
		# 先静止几帧让弹簧就位
		for k in 20:
			rig._process(dt)
		match clip:
			"run":
				rig.set_locomotion(Vector3(0, 0, -6.0), true, false, false)
			"boost":
				rig.set_locomotion(Vector3(0, 0, -12.0), true, true, false)
			"fly":
				rig.set_locomotion(Vector3(0, 0, -14.0), false, true, true)
			"meditate":
				rig.meditating = true
			_:
				rig.play(clip)
		var t := 0.0
		while t < float(e[1]):
			rig._process(dt)
			t += dt
