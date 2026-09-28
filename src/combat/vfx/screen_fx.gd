class_name ScreenFx
extends CanvasLayer
## 屏幕特效层（位于 HUD 之下）：高速疾行的径向速度线；重击时短暂的径向模糊 + 色散。
## 强度随 Settings.camera_shake 缩放；若 Settings 提供 screen_effects=false 则完全关闭。
## 两项均为 0 时隐藏全屏矩形，不产生额外的屏幕拷贝开销。

const LAYER := 4

var _rect: ColorRect
var _mat: ShaderMaterial
var speed: float = 0.0          ## 目标速度线强度 0~1
var _speed_v: float = 0.0
var _kick: float = 0.0


func _ready() -> void:
	layer = LAYER
	_rect = ColorRect.new()
	_rect.name = "ScreenFxRect"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = VfxLib.shader("screen")
	_mat.set_shader_parameter("noise_tex", VfxLib.tex("noise"))
	_rect.material = _mat
	_rect.visible = false
	add_child(_rect)


static func enabled() -> bool:
	var v = Settings.get("screen_effects")
	if v is bool and not v:
		return false
	return Settings.camera_shake > 0.001


## 重击冲击（0~1）
func kick(amount: float) -> void:
	if not enabled():
		return
	_kick = clampf(maxf(_kick, amount * clampf(Settings.camera_shake, 0.0, 1.5)), 0.0, 1.0)


func _process(delta: float) -> void:
	var on := enabled()
	var real_dt := delta / maxf(Engine.time_scale, 0.05)
	_speed_v = move_toward(_speed_v, speed if on else 0.0, real_dt * 2.5)
	_kick = maxf(_kick - real_dt * 4.0, 0.0)
	var vis := on and (_speed_v > 0.01 or _kick > 0.01)
	_rect.visible = vis
	if not vis:
		return
	var vp := get_viewport()
	var sz := vp.get_visible_rect().size if vp != null else Vector2(16, 9)
	_mat.set_shader_parameter("aspect", sz.x / maxf(sz.y, 1.0))
	_mat.set_shader_parameter("speed", _speed_v)
	_mat.set_shader_parameter("kick", _kick)
