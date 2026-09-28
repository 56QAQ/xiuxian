extends CanvasLayer
## 场景切换（autoload: Scenes），带淡入淡出。

const MAIN_MENU := "res://scenes/main_menu.tscn"
const CREATOR := "res://scenes/character_creator.tscn"
const OVERWORLD := "res://scenes/overworld.tscn"
const SECRET_REALM := "res://scenes/secret_realm.tscn"

var _fade: ColorRect
var _busy := false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 0)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_fade)


func change_to(path: String, fade_time: float = 0.35) -> void:
	if _busy:
		return
	_busy = true
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, fade_time)
	await tw.finished
	get_tree().paused = false
	Engine.time_scale = 1.0
	# 等后台体素网格任务（异步构建、远景 LOD）收尾，避免旧场景释放时仍有线程在跑
	VoxMesh.finish_pending()
	var err := get_tree().change_scene_to_file(path)
	if err != OK:
		push_error("切换场景失败 %s: %s" % [path, error_string(err)])
	await get_tree().process_frame
	await get_tree().process_frame
	var tw2 := create_tween()
	tw2.tween_property(_fade, "color:a", 0.0, fade_time)
	await tw2.finished
	_busy = false


func _exit_tree() -> void:
	VoxMesh.finish_pending()


func goto_main_menu() -> void:
	GS.in_realm = false
	change_to(MAIN_MENU)


func goto_creator() -> void:
	change_to(CREATOR)


func goto_overworld() -> void:
	GS.in_realm = false
	change_to(OVERWORLD)


## request: {"realm_id": String, "seed": int}
func goto_realm(request: Dictionary) -> void:
	GS.realm_request = request
	GS.in_realm = true
	change_to(SECRET_REALM)
