class_name UIManager
extends CanvasLayer
## 界面管理器（每个游戏场景放一个；加入组 "ui_manager"）。
##
## - 面板：Events.open_panel(name, args) 或快捷键（B/I 背包、C 角色、K 功法、M 地图、J 宗门、Esc 暂停）打开；
##   Esc 关闭最上层面板，没有面板时打开暂停菜单。
## - is_blocking()：有任何面板打开时为 true（玩法代码据此忽略输入）；此时显示鼠标，
##   全部关闭后若 capture_mouse_when_closed 为 true 则重新捕获鼠标。
## - 提示：Events.notify(text, kind) → 左侧提示流；kind == "realm" 显示居中大字横幅。
## - 扩展：UIManager.register_panel("sect", func(args: Dictionary) -> UIWindow: return SectPanel.new())

signal panel_opened(panel_name: String)
signal panel_closed(panel_name: String)
signal blocking_changed(blocking: bool)

## 面板全部关闭后是否重新捕获鼠标（大地图/秘境中设为 true）
@export var capture_mouse_when_closed: bool = false
## 是否响应面板快捷键（主菜单中关闭）
@export var hotkeys_enabled: bool = true
## 没有面板时 Esc 是否打开暂停菜单
@export var pause_menu_enabled: bool = true

## 快捷键动作 → 面板名
const HOTKEYS := {
	"ui_inventory": "inventory",
	"ui_character": "character",
	"ui_skills": "skills",
	"ui_map": "map",
	"ui_sect": "sect",
}

## 内置面板名
const BUILTIN: Array[String] = [
	"inventory", "character", "cultivation", "skills", "map", "pause", "dialogue", "shop", "craft", "settings", "saves",
]

## 外部注册的面板工厂：name -> Callable(args: Dictionary) -> UIWindow
static var _factories: Dictionary = {}

var _root: Control
var _backdrop: ColorRect
var _layer: Control
var _toasts: ToastFeed
var _stack: Array[UIWindow] = []
var _was_blocking: bool = false
var _paused_by_us: bool = false
var _dialog_seq: int = 0
var _backdrop_tween: Tween


# ================================================================ 注册

## 注册（或覆盖）一个面板。factory 接收 args，返回 UIWindow（或任意 Control，会被包进窗口）。
static func register_panel(panel_name: String, factory: Callable) -> void:
	_factories[panel_name] = factory


static func unregister_panel(panel_name: String) -> void:
	_factories.erase(panel_name)


static func has_panel(panel_name: String) -> bool:
	return _factories.has(panel_name) or BUILTIN.has(panel_name)


## 场景中的 UIManager（没有则返回 null）
static func find(tree: SceneTree) -> UIManager:
	if tree == null:
		return null
	return tree.get_first_node_in_group("ui_manager") as UIManager


# ================================================================ 生命周期

func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("ui_manager")
	_root = Control.new()
	_root.name = "UIRoot"
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.get_theme()
	add_child(_root)
	_backdrop = ColorRect.new()
	_backdrop.name = "Backdrop"
	_backdrop.color = Color(0.01, 0.012, 0.02, 0.0)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_backdrop.visible = false
	_root.add_child(_backdrop)
	_layer = Control.new()
	_layer.name = "Panels"
	_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_layer)
	_toasts = ToastFeed.new()
	_toasts.name = "Toasts"
	_root.add_child(_toasts)
	Events.open_panel.connect(_on_open_panel)
	Events.close_panels.connect(close_all)
	Events.notify.connect(notify)


func _exit_tree() -> void:
	if _paused_by_us and get_tree() != null:
		get_tree().paused = false
		_paused_by_us = false


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.is_echo():
		return
	var focus := get_viewport().gui_get_focus_owner()
	var typing := focus is LineEdit or focus is TextEdit
	if event.is_action_pressed("pause"):
		if typing:
			focus.release_focus()
			get_viewport().set_input_as_handled()
			return
		if _handle_escape():
			get_viewport().set_input_as_handled()
		return
	if typing or not hotkeys_enabled:
		return
	# 模态窗口打开时不响应面板快捷键
	var top := top_panel()
	if top != null and top.modal:
		return
	for action in HOTKEYS:
		if event.is_action_pressed(action):
			var pname: String = HOTKEYS[action]
			if has_panel(pname):
				toggle(pname)
				get_viewport().set_input_as_handled()
			return


func _handle_escape() -> bool:
	var top := top_panel()
	if top != null:
		if top.esc_closes:
			close_window(top)
		return true
	if pause_menu_enabled and hotkeys_enabled:
		open("pause")
		return true
	return false


# ================================================================ 面板

func _on_open_panel(panel_name: String, args: Dictionary) -> void:
	open(panel_name, args)


## 打开面板。已打开时：args 为空则置顶，否则以新参数重新打开。
func open(panel_name: String, args: Dictionary = {}) -> UIWindow:
	var existing := get_panel(panel_name)
	if existing != null:
		if args.is_empty():
			bring_to_front(existing)
			return existing
		_remove(existing, false)
	var w := _create(panel_name, args)
	if w == null:
		push_warning("UIManager: 未知面板 %s" % panel_name)
		return null
	w.panel_name = panel_name
	w.manager = self
	w.args = args
	_stack.append(w)
	_layer.add_child(w)
	_after_change()
	panel_opened.emit(panel_name)
	return w


func toggle(panel_name: String, args: Dictionary = {}) -> void:
	var w := get_panel(panel_name)
	if w != null:
		close_window(w)
	else:
		open(panel_name, args)


func close(panel_name: String) -> void:
	var w := get_panel(panel_name)
	if w != null:
		close_window(w)


func close_window(w: UIWindow) -> void:
	_remove(w, true)


func close_top() -> bool:
	var top := top_panel()
	if top == null:
		return false
	close_window(top)
	return true


func close_all() -> void:
	for w in _stack.duplicate():
		_remove(w, true)


func is_open(panel_name: String) -> bool:
	return get_panel(panel_name) != null


func get_panel(panel_name: String) -> UIWindow:
	for w in _stack:
		if w.panel_name == panel_name and is_instance_valid(w):
			return w
	return null


func top_panel() -> UIWindow:
	return _stack.back() if not _stack.is_empty() else null


func open_panels() -> Array[String]:
	var out: Array[String] = []
	for w in _stack:
		out.append(w.panel_name)
	return out


## 有面板打开：玩法层应忽略输入并显示鼠标
func is_blocking() -> bool:
	return not _stack.is_empty()


func bring_to_front(w: UIWindow) -> void:
	if not _stack.has(w) or _stack.back() == w:
		return
	# 模态窗口始终在非模态窗口之上
	var top := top_panel()
	if top != null and top.modal and not w.modal:
		return
	_stack.erase(w)
	_stack.append(w)
	_layer.move_child(w, -1)
	_update_backdrop()


func _remove(w: UIWindow, animate: bool) -> void:
	if not _stack.has(w):
		return
	_stack.erase(w)
	var pname := w.panel_name
	if animate and w.is_inside_tree():
		w.animate_out()
	else:
		w._closing = true
		w._on_closing()
		w.queue_free()
	_after_change()
	panel_closed.emit(pname)


func _create(panel_name: String, args: Dictionary) -> UIWindow:
	if _factories.has(panel_name):
		var f: Callable = _factories[panel_name]
		var made: Variant = f.call(args)
		if made is UIWindow:
			return made
		if made is Control:
			var wrap := UIWindow.new()
			wrap.window_title = str(args.get("title", ""))
			wrap.ready.connect(func() -> void: wrap.body.add_child(made))
			return wrap
		return null
	match panel_name:
		"inventory":
			return InventoryPanel.new()
		"character":
			return CharacterPanel.new()
		"cultivation":
			return CultivationPanel.new()
		"skills":
			return SkillsPanel.new()
		"map":
			return MapPanel.new()
		"pause":
			return PauseMenu.new()
		"dialogue":
			return DialoguePanel.new()
		"shop":
			return ShopPanel.new()
		"craft":
			return CraftPanel.new()
		"settings":
			return SettingsPanel.new()
		"saves":
			return SaveSlotsPanel.new()
	return null


func _after_change() -> void:
	_update_backdrop()
	_update_pause()
	var blocking := is_blocking()
	if blocking != _was_blocking:
		_was_blocking = blocking
		if blocking:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif capture_mouse_when_closed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		blocking_changed.emit(blocking)


func _update_pause() -> void:
	var want := false
	for w in _stack:
		if w.pauses_game:
			want = true
	if want and not _paused_by_us:
		_paused_by_us = true
		get_tree().paused = true
	elif not want and _paused_by_us:
		_paused_by_us = false
		get_tree().paused = false


func _update_backdrop() -> void:
	var modal_idx := -1
	for i in _stack.size():
		if _stack[i].modal:
			modal_idx = i
	var target := 0.0
	if modal_idx >= 0:
		target = 0.55
		# 遮罩放在最上层模态窗口之下
		_backdrop.reparent(_layer)
		_layer.move_child(_backdrop, _stack[modal_idx].get_index())
		_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		if _backdrop.get_parent() != _root:
			_backdrop.reparent(_root)
			_root.move_child(_backdrop, 0)
		_backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if not _stack.is_empty():
			target = 0.28
	if _backdrop_tween != null:
		_backdrop_tween.kill()
	_backdrop.visible = true
	_backdrop_tween = create_tween()
	_backdrop_tween.tween_property(_backdrop, "color:a", target, 0.18)
	if target <= 0.0:
		_backdrop_tween.tween_callback(func() -> void: _backdrop.visible = false)


# ================================================================ 提示与对话框

func notify(text: String, kind: String = "info") -> void:
	if _toasts != null:
		_toasts.push(text, kind)


## 确认框。on_yes / on_no 无参数。
func confirm(text: String, on_yes: Callable, title: String = "确认", yes_text: String = "确定", no_text: String = "取消", on_no: Callable = Callable()) -> ConfirmDialog:
	var d := ConfirmDialog.new()
	d.setup(title, text, on_yes, on_no, yes_text, no_text)
	_open_dialog(d)
	return d


## 数量选择框。on_ok(value: int)
func ask_number(title: String, min_value: int, max_value: int, default_value: int, on_ok: Callable, hint: String = "") -> NumberDialog:
	var d := NumberDialog.new()
	d.setup(title, min_value, max_value, default_value, on_ok, hint)
	_open_dialog(d)
	return d


## 以唯一名打开一个现成的窗口实例（对话框等）
func open_window(w: UIWindow, panel_name: String = "") -> UIWindow:
	_dialog_seq += 1
	w.panel_name = panel_name if panel_name != "" else "window#%d" % _dialog_seq
	w.manager = self
	_stack.append(w)
	_layer.add_child(w)
	_after_change()
	panel_opened.emit(w.panel_name)
	return w


func _open_dialog(d: UIWindow) -> void:
	open_window(d, "dialog#%d" % (_dialog_seq + 1))
