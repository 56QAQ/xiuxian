class_name PauseMenu
extends UIWindow
## 暂停菜单：打开期间 get_tree().paused = true（由 UIManager 统一处理）。


func _init() -> void:
	super()
	window_title = "暂停"
	modal = true
	pauses_game = true
	auto_refresh = false


func _build() -> void:
	custom_minimum_size = Vector2(400, 0)
	if GS.active:
		var who := UITheme.vbox(2)
		var n := UITheme.label("%s · %s" % [GS.player.name, DB.realm_name(GS.player.realm, GS.player.stage)], 20, UITheme.GOLD_BRIGHT)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		who.add_child(n)
		var d := UITheme.label(GS.date_text(), 16, UITheme.TEXT_DIM)
		d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		who.add_child(d)
		add(who)
		add(UITheme.separator())
	var list := UITheme.vbox(10)
	list.add_child(_item("继续仙途", close, "JadeButton"))
	var save := _item("保存进度", func() -> void: ui().open("saves", {"mode": "save"}))
	if GS.in_realm or not GS.active:
		save.disabled = true
		save.tooltip_text = "秘境之中无法存档" if GS.in_realm else "尚未开始游戏"
	list.add_child(save)
	list.add_child(_item("读取存档", func() -> void: ui().open("saves", {"mode": "load"})))
	list.add_child(_item("设置", func() -> void: ui().open("settings")))
	list.add_child(_item("返回主菜单", _to_menu))
	list.add_child(_item("退出游戏", _quit))
	add(list)
	add(UITheme.spacer(4))
	var hint := UITheme.label("Esc 继续", 14, UITheme.TEXT_FAINT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add(hint)


func _item(text: String, cb: Callable, variation: String = "") -> Button:
	var b := UITheme.button(text, variation, cb)
	b.custom_minimum_size = Vector2(300, 46)
	b.add_theme_font_size_override("font_size", 21)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return b


func _to_menu() -> void:
	var text := "返回主菜单？未保存的进度将会丢失。"
	if GS.in_realm:
		text = "返回主菜单？秘境中的进度与收获将会丢失。"
	var go := func() -> void:
		ui().close_all()
		Scenes.goto_main_menu()
	ui().confirm(text, go, "返回主菜单")


func _quit() -> void:
	ui().confirm("确定退出游戏？未保存的进度将会丢失。", func() -> void: get_tree().quit(), "退出游戏", "退出")
