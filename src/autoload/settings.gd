extends Node
## 用户设置与输入映射（autoload: Settings）。
## 输入动作在此以代码注册，方便改键与版本管理；项目设置中不另行定义。

const PATH := "user://settings.cfg"

var mouse_sensitivity := 0.0025
var invert_y := false
var fov := 72.0
var master_volume := 0.8
var sfx_volume := 0.9
var music_volume := 0.6
var camera_shake := 1.0
var show_damage_numbers := true
var hud_drift := 1.0  ## HUD 随运动漂移强度

## action -> Array of [type, code]；type: "key" | "mouse"
const BINDINGS := {
	"move_forward": [["key", KEY_W], ["key", KEY_UP]],
	"move_back": [["key", KEY_S], ["key", KEY_DOWN]],
	"move_left": [["key", KEY_A], ["key", KEY_LEFT]],
	"move_right": [["key", KEY_D], ["key", KEY_RIGHT]],
	"jump": [["key", KEY_SPACE]],
	"descend": [["key", KEY_CTRL]],
	"boost": [["key", KEY_SHIFT]],
	"quick_boost": [["key", KEY_E], ["mouse", MOUSE_BUTTON_XBUTTON1]],
	"melee": [["mouse", MOUSE_BUTTON_LEFT]],
	"bolt": [["mouse", MOUSE_BUTTON_RIGHT]],
	"lock_on": [["mouse", MOUSE_BUTTON_MIDDLE], ["key", KEY_TAB]],
	"spell_1": [["key", KEY_1]],
	"spell_2": [["key", KEY_2]],
	"spell_3": [["key", KEY_3]],
	"spell_4": [["key", KEY_4]],
	"spell_5": [["key", KEY_5]],
	"use_item": [["key", KEY_Q]],
	"interact": [["key", KEY_F]],
	"meditate": [["key", KEY_T]],
	"ui_inventory": [["key", KEY_B], ["key", KEY_I]],
	"ui_character": [["key", KEY_C]],
	"ui_skills": [["key", KEY_K]],
	"ui_sect": [["key", KEY_J]],
	"ui_map": [["key", KEY_M]],
	"pause": [["key", KEY_ESCAPE]],
	"rotate_item": [["key", KEY_R]],
	"toggle_mouse": [["key", KEY_ALT]],
}


func _ready() -> void:
	setup_input()
	load_settings()
	get_tree().root.theme = UITheme.get_theme()


func setup_input() -> void:
	for action in BINDINGS:
		if InputMap.has_action(action):
			InputMap.action_erase_events(action)
		else:
			InputMap.add_action(action, 0.2)
		for b in BINDINGS[action]:
			var ev: InputEvent
			if b[0] == "key":
				var k := InputEventKey.new()
				k.physical_keycode = b[1]
				ev = k
			else:
				var m := InputEventMouseButton.new()
				m.button_index = b[1]
				ev = m
			InputMap.action_add_event(action, ev)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		_apply_audio()
		return
	mouse_sensitivity = cfg.get_value("input", "mouse_sensitivity", mouse_sensitivity)
	invert_y = cfg.get_value("input", "invert_y", invert_y)
	fov = cfg.get_value("video", "fov", fov)
	camera_shake = cfg.get_value("video", "camera_shake", camera_shake)
	hud_drift = cfg.get_value("video", "hud_drift", hud_drift)
	show_damage_numbers = cfg.get_value("video", "show_damage_numbers", show_damage_numbers)
	master_volume = cfg.get_value("audio", "master", master_volume)
	sfx_volume = cfg.get_value("audio", "sfx", sfx_volume)
	music_volume = cfg.get_value("audio", "music", music_volume)
	_apply_audio()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("input", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("input", "invert_y", invert_y)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "camera_shake", camera_shake)
	cfg.set_value("video", "hud_drift", hud_drift)
	cfg.set_value("video", "show_damage_numbers", show_damage_numbers)
	cfg.set_value("audio", "master", master_volume)
	cfg.set_value("audio", "sfx", sfx_volume)
	cfg.set_value("audio", "music", music_volume)
	cfg.save(PATH)
	_apply_audio()


func _apply_audio() -> void:
	var idx := AudioServer.get_bus_index("Master")
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(master_volume, 0.0001)))
