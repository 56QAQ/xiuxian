class_name SettingsPanel
extends UIWindow
## 设置面板（主菜单与暂停菜单共用）：修改即时生效，关闭或点“保存”时写入 Settings.save_settings()。

const DEFAULTS := {
	"mouse_sensitivity": 0.0025, "invert_y": false, "fov": 72.0, "camera_shake": 1.0, "hud_drift": 1.0,
	"show_damage_numbers": true, "master_volume": 0.8, "sfx_volume": 0.9, "music_volume": 0.6,
}

var _rows: Dictionary = {}
var _dirty: bool = false


func _init() -> void:
	super()
	window_title = "设置"
	modal = true
	auto_refresh = false


func _build() -> void:
	custom_minimum_size = Vector2(620, 0)
	add(UITheme.header("操作"))
	_slider_row("mouse_sensitivity", "鼠标灵敏度", 0.0005, 0.0075, 0.00025, func(v: float) -> String: return "%.1f×" % (v / 0.0025))
	_toggle_row("invert_y", "反转视角上下")
	add(UITheme.header("画面"))
	_slider_row("fov", "视野范围", 55.0, 100.0, 1.0, func(v: float) -> String: return "%d°" % int(v))
	_slider_row("camera_shake", "镜头震动", 0.0, 1.5, 0.05, _pct)
	_slider_row("hud_drift", "界面漂移", 0.0, 1.5, 0.05, _pct)
	_toggle_row("show_damage_numbers", "显示伤害数字")
	add(UITheme.header("声音"))
	_slider_row("master_volume", "总音量", 0.0, 1.0, 0.01, _pct)
	_slider_row("sfx_volume", "音效", 0.0, 1.0, 0.01, _pct)
	_slider_row("music_volume", "音乐", 0.0, 1.0, 0.01, _pct)
	add(UITheme.separator())
	var btns := UITheme.hbox(20)
	btns.alignment = BoxContainer.ALIGNMENT_CENTER
	btns.add_child(UITheme.button("恢复默认", "", _reset))
	var ok := UITheme.button("保存并返回", "JadeButton", close)
	btns.add_child(ok)
	add(btns)


static func _pct(v: float) -> String:
	return "%d%%" % int(roundf(v * 100.0))


func _slider_row(key: String, text: String, lo: float, hi: float, step: float, fmt: Callable) -> void:
	var row := UITheme.hbox(14)
	var l := UITheme.label(text, 18)
	l.custom_minimum_size.x = 150
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = float(Settings.get(key))
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(s)
	var v := UITheme.label(fmt.call(s.value), 17, UITheme.GOLD_BRIGHT)
	v.custom_minimum_size.x = 64
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	s.value_changed.connect(func(nv: float) -> void:
		Settings.set(key, nv)
		v.text = fmt.call(nv)
		_dirty = true
		if key.ends_with("volume"):
			Settings._apply_audio())
	_rows[key] = s
	add(row)


func _toggle_row(key: String, text: String) -> void:
	var row := UITheme.hbox(14)
	var l := UITheme.label(text, 18)
	l.custom_minimum_size.x = 150
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(l)
	var c := CheckButton.new()
	c.button_pressed = bool(Settings.get(key))
	c.focus_mode = Control.FOCUS_NONE
	c.toggled.connect(func(on: bool) -> void:
		Settings.set(key, on)
		_dirty = true
		Audio.play("ui_click"))
	row.add_child(c)
	_rows[key] = c
	add(row)


func _reset() -> void:
	for k in DEFAULTS:
		var ctl: Control = _rows.get(k)
		if ctl is HSlider:
			(ctl as HSlider).value = float(DEFAULTS[k])
		elif ctl is CheckButton:
			(ctl as CheckButton).button_pressed = bool(DEFAULTS[k])
		Settings.set(k, DEFAULTS[k])
	_dirty = true


func _on_closing() -> void:
	Settings.save_settings()
