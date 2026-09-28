class_name HitStop
## 顿帧：短暂降低全局时间流速，强化打击感。多个顿帧叠加时取最晚结束者。

static var _until_ms: int = 0
static var enabled: bool = true


static func trigger(duration: float = 0.06, scale: float = 0.06) -> void:
	if not enabled or duration <= 0.0:
		return
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.paused:
		return
	var now := Time.get_ticks_msec()
	var end := now + int(duration * 1000.0)
	if end <= _until_ms:
		return
	_until_ms = end
	Engine.time_scale = scale
	await tree.create_timer(duration, true, false, true).timeout
	if Time.get_ticks_msec() >= _until_ms - 2:
		Engine.time_scale = 1.0


static func reset() -> void:
	_until_ms = 0
	Engine.time_scale = 1.0
