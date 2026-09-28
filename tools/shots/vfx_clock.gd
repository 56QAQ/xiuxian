class_name VfxShotClock
## 截图用确定性时钟：每帧最多一个物理步长，软件渲染的慢帧会被引擎截断为恰好 1/60 秒，
## 因而“第 N 帧”严格对应 N/60 秒的模拟时间（特效补间、粒子、物理全部一致）。


static func fix() -> void:
	Engine.max_physics_steps_per_frame = 1
	Engine.physics_ticks_per_second = 60
	Engine.time_scale = 1.0
