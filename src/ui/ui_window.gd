class_name UIWindow
extends PanelContainer
## 界面窗口基类：标题栏（标题 + 关闭按钮，可拖动）+ 内容区 body。
## 由 UIManager.open(name, args) 创建；子类覆盖 _build()（构建一次）与 refresh()（数据变化时刷新）。
## 也可脱离 UIManager 直接 add_child 使用（关闭时自行淡出并释放）。

signal close_requested
signal closed

## UIManager 中登记的面板名
var panel_name: String = ""
var manager: UIManager = null
var args: Dictionary = {}

var window_title: String = ""
var closable: bool = true
var draggable: bool = true
## 模态：显示深色遮罩并阻挡下层窗口
var modal: bool = false
## 打开期间暂停游戏（暂停菜单）
var pauses_game: bool = false
## Esc 是否可关闭
var esc_closes: bool = true
## 玩家数据变化时自动刷新
var auto_refresh: bool = true

var title_label: Label
var title_bar: Control
var body: VBoxContainer
var close_button: Button

var _dragging: bool = false
var _drag_offset: Vector2 = Vector2.ZERO
var _refresh_queued: bool = false
var _closing: bool = false
var _moved: bool = false


func _init() -> void:
	theme_type_variation = "WindowPanel"
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	# 标题栏
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	bar.mouse_filter = Control.MOUSE_FILTER_STOP
	bar.gui_input.connect(_on_bar_input)
	title_bar = bar
	root.add_child(bar)
	var sl := GoldSeparator.new()
	sl.ornament = false
	sl.fade_right = false
	bar.add_child(sl)
	title_label = UITheme.title(window_title, 26)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(title_label)
	var sr := GoldSeparator.new()
	sr.ornament = false
	sr.fade_left = false
	bar.add_child(sr)
	close_button = UITheme.icon_button("close", "关闭（Esc）", close)
	close_button.visible = closable
	bar.add_child(close_button)
	if window_title == "":
		bar.visible = false
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)
	_build()
	refresh()
	if auto_refresh:
		Events.player_changed.connect(queue_refresh)
		Events.inventory_changed.connect(queue_refresh)
	modulate.a = 0.0
	resized.connect(_recenter)
	minimum_size_changed.connect(_queue_fit)
	_open_anim.call_deferred()


## 子类覆盖：构建界面（只调用一次，body 已就绪）
func _build() -> void:
	pass


## 子类覆盖：根据 GS 数据刷新显示
func refresh() -> void:
	pass


func set_title(t: String) -> void:
	window_title = t
	if title_label != null:
		title_label.text = t
		title_bar.visible = t != ""


## 合并同一帧内的多次刷新请求
func queue_refresh() -> void:
	if _refresh_queued or _closing:
		return
	_refresh_queued = true
	_do_refresh.call_deferred()


func _do_refresh() -> void:
	_refresh_queued = false
	if is_inside_tree() and not _closing:
		refresh()


func close() -> void:
	if _closing:
		return
	if manager != null and is_instance_valid(manager):
		close_requested.emit()
		manager.close_window(self)
	else:
		close_requested.emit()
		animate_out()


## 由 UIManager 调用：播放关闭动画后释放
func animate_out() -> void:
	if _closing:
		return
	_closing = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_on_closing()
	Audio.play("ui_close", -4.0)
	pivot_offset = size * 0.5
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 0.0, 0.12)
	tw.tween_property(self, "scale", Vector2(0.97, 0.97), 0.12)
	tw.chain().tween_callback(func() -> void:
		closed.emit()
		queue_free())


## 子类覆盖：关闭时的清理（如取消暂停、断开信号）
func _on_closing() -> void:
	pass


func is_closing() -> bool:
	return _closing


var _fit_queued: bool = false


## 窗口不在容器中，最小尺寸变小时需主动收缩
func _queue_fit() -> void:
	if _fit_queued:
		return
	_fit_queued = true
	_fit.call_deferred()


func _fit() -> void:
	_fit_queued = false
	if not is_inside_tree():
		return
	var ms := get_combined_minimum_size()
	if not size.is_equal_approx(ms):
		size = ms
	_recenter()


## 未被拖动过时保持居中（窗口尺寸随内容变化）
func _recenter() -> void:
	if not is_inside_tree():
		return
	pivot_offset = size * 0.5
	var parent_size := get_parent_area_size()
	if _moved:
		# 保证标题栏始终可见
		position.y = clampf(position.y, 0.0, maxf(parent_size.y - 60.0, 0.0))
		return
	var off: Vector2 = args.get("offset", Vector2.ZERO)
	position = ((parent_size - size) * 0.5 + off).floor()
	position.y = maxf(position.y, 0.0)


func _open_anim() -> void:
	if not is_inside_tree():
		return
	_fit()
	Audio.play("ui_open", -4.0)
	pivot_offset = size * 0.5
	scale = Vector2(0.965, 0.965)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "modulate:a", 1.0, 0.16).set_ease(Tween.EASE_OUT)
	tw.tween_property(self, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _on_bar_input(event: InputEvent) -> void:
	if not draggable:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if _dragging:
			_drag_offset = get_global_mouse_position() - global_position
			if manager != null:
				manager.bring_to_front(self)
	elif event is InputEventMouseMotion and _dragging:
		var vp := get_viewport_rect().size
		var target := get_global_mouse_position() - _drag_offset
		target.x = clampf(target.x, -size.x + 80.0, vp.x - 80.0)
		target.y = clampf(target.y, 0.0, vp.y - 40.0)
		global_position = target
		_moved = true


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and manager != null:
		manager.bring_to_front(self)


## 便捷：在 body 中添加子节点
func add(c: Control) -> Control:
	body.add_child(c)
	return c


## 最近的 UIManager（面板打开确认框等）
func ui() -> UIManager:
	if manager != null and is_instance_valid(manager):
		return manager
	return UIManager.find(get_tree())


static func clear_children(n: Node) -> void:
	for c in n.get_children():
		n.remove_child(c)
		c.queue_free()
