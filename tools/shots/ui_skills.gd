extends RefCounted
## 界面截图：功法与法诀

var ui: UIManager


func frames() -> int:
	return 30


func build(root: Node) -> void:
	UIShotCommon.new_game()
	var p := GS.player
	for t in ["lihuo_jue", "changchun_gong", "duanti_shu", "qingshen_shu"]:
		GS.learn_technique(t, false)
	for s in ["fireball", "flame_rain", "vine_bind", "spring_heal", "earth_shield"]:
		GS.learn_spell(s, false)
	GS.set_main_technique("lihuo_jue")
	GS.set_aux_technique(0, "duanti_shu")
	p.techniques["lihuo_jue"]["lv"] = 1
	p.techniques["lihuo_jue"]["xp"] = 320.0
	p.spells["fireball"]["lv"] = 3
	p.spells["fireball"]["xp"] = 70.0
	GS.set_spell_slot(0, "fireball")
	GS.set_spell_slot(1, "vine_bind")
	GS.set_spell_slot(2, "earth_shield")
	GS.set_spell_slot(3, "qi_palm")
	GS.recompute()
	UIShotCommon.backdrop(root)
	ui = UIShotCommon.manager(root)


func step(_root: Node, frame: int) -> void:
	if frame == 1:
		ui.open("skills")
