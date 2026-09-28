class_name ConfirmDialog
extends UIWindow
## 通用确认框。通过 UIManager.confirm(text, on_yes) 打开，或 setup() 后自行 add_child。

var text: String = ""
var yes_text: String = "确定"
var no_text: String = "取消"
var on_yes: Callable
var on_no: Callable
## 危险操作：确认按钮使用朱砂色
var danger: bool = false:
	set(v):
		danger = v
		if _yes != null:
			_yes.theme_type_variation = "PrimaryButton" if v else "JadeButton"

var _yes: Button


func _init() -> void:
	super()
	modal = true
	auto_refresh = false


func setup(p_title: String, p_text: String, p_on_yes: Callable, p_on_no: Callable = Callable(), p_yes: String = "确定", p_no: String = "取消") -> ConfirmDialog:
	window_title = p_title
	text = p_text
	on_yes = p_on_yes
	on_no = p_on_no
	yes_text = p_yes
	no_text = p_no
	return self


func _build() -> void:
	custom_minimum_size = Vector2(460, 0)
	var msg := UITheme.wrap_label(text, 19)
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	msg.custom_minimum_size = Vector2(400, 60)
	msg.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add(msg)
	add(UITheme.separator())
	var row := UITheme.hbox(24)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if no_text != "":
		var no := UITheme.button(no_text, "", _on_no)
		no.custom_minimum_size.x = 130
		row.add_child(no)
	_yes = UITheme.button(yes_text, "PrimaryButton" if danger else "JadeButton", _on_yes)
	_yes.custom_minimum_size.x = 130
	row.add_child(_yes)
	add(row)
	_yes.grab_focus.call_deferred()


func _on_yes() -> void:
	close()
	if on_yes.is_valid():
		on_yes.call()


func _on_no() -> void:
	close()
	if on_no.is_valid():
		on_no.call()


func _unhandled_key_input(event: InputEvent) -> void:
	if is_closing():
		return
	if event.pressed and (event as InputEventKey).keycode in [KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_on_yes()
