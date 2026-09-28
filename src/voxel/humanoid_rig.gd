class_name HumanoidRig
extends CharacterRig
## 人形体素角色（CharacterBuilder 生成）：在 CharacterRig 基础上增加
## - 布料跟随：cloth_ 弹簧骨骼的 meta "follow"（front/back/side）+ "follow_legs"（l/r/both）+ "follow_weight"，
##   每帧根据腿的摆角修改其静止方向，使裙甲/下摆随步伐张合而不被腿穿透。
## - 弹簧重力：meta "spring_gravity"（0~1）让发束/袖囊的静止方向部分朝向世界下方（前倾、抬臂时自然下垂）。
## - 眨眼：头部 "Blink" 网格（闭眼贴片）定时显示。
## 接口与 CharacterRig 完全一致。

var _drivers: Array[Dictionary] = []
var _blink: Node3D
var _blink_timer: float = 2.5
var _blink_hold: float = 0.0
var _rng_seed: int = 0


func setup() -> void:
	super.setup()
	_drivers.clear()
	for bn in bones:
		var node: Node3D = bones[bn]
		if not _is_spring_name(bn):
			continue
		var follow := str(node.get_meta("follow", ""))
		var grav := float(node.get_meta("spring_gravity", 0.0))
		if follow == "" and grav <= 0.0:
			continue
		_drivers.append({
			"name": bn, "node": node, "base": rest[bn],
			"follow": follow, "legs": str(node.get_meta("follow_legs", "both")),
			"w": float(node.get_meta("follow_weight", 1.0)), "grav": grav,
		})
	var h := bone("head")
	if h != null:
		_blink = h.get_node_or_null("Blink") as Node3D
	_rng_seed = int(get_instance_id() % 997)
	_blink_timer = 1.5 + float(_rng_seed % 30) / 10.0


func _process(delta: float) -> void:
	super._process(delta)
	if _blink != null:
		if _blink_hold > 0.0:
			_blink_hold -= delta
			if _blink_hold <= 0.0:
				_blink.visible = false
		else:
			_blink_timer -= delta
			if _blink_timer <= 0.0:
				_blink.visible = true
				_blink_hold = 0.11
				_rng_seed = (_rng_seed * 1103515245 + 12345) & 0x7fffffff
				_blink_timer = 2.2 + float(_rng_seed % 35) / 10.0


## 在弹簧更新之前调整被驱动骨骼的静止方向；之后按 meta "spring_damping" 追加阻尼（抑制起步/急停时的过度甩动）
func _update_springs(delta: float) -> void:
	if not _drivers.is_empty():
		_drive(delta)
	super._update_springs(delta)
	for s in _springs:
		var node: Node3D = s["bone"]
		if not is_instance_valid(node):
			continue
		var d := float(node.get_meta("spring_damping", 0.12))
		if d > 0.0:
			s["prev"] = (s["prev"] as Vector3).lerp(s["tip"], d)


## 腿的前摆角（弧度，前为正）与外展角（外为正）
func _leg_angles(side: String) -> Vector2:
	var leg := bone("leg_" + side)
	if leg == null:
		return Vector2.ZERO
	var d := leg.transform.basis * Vector3.DOWN
	var fwd := atan2(-d.z, -d.y)
	var out := atan2(d.x if side == "r" else -d.x, -d.y)
	return Vector2(fwd, out)


func _drive(_delta: float) -> void:
	var al := _leg_angles("l")
	var ar := _leg_angles("r")
	for dr in _drivers:
		var base: Transform3D = dr["base"]
		var b := base.basis
		var follow: String = dr["follow"]
		if follow != "":
			var legs: String = dr["legs"]
			var w: float = dr["w"]
			var fa := 0.0
			var sa := 0.0
			match legs:
				"l":
					fa = al.x
					sa = al.y
				"r":
					fa = ar.x
					sa = ar.y
				_:
					fa = maxf(al.x, ar.x) if follow == "front" else minf(al.x, ar.x)
					sa = maxf(al.y, ar.y)
			match follow:
				"front":
					var ang := maxf(fa, 0.0) * w
					b = Basis(Vector3.RIGHT, ang) * b
				"back":
					var ang2 := minf(fa, 0.0) * w
					b = Basis(Vector3.RIGHT, ang2) * b
				"side":
					var ang3 := maxf(sa, 0.0) * w
					var sgn := -1.0 if legs == "l" else 1.0
					b = Basis(Vector3.FORWARD, -sgn * ang3) * b
					b = Basis(Vector3.RIGHT, fa * 0.5 * w) * b
		var node: Node3D = dr["node"]
		var g: float = dr["grav"]
		if g > 0.0:
			var parent := node.get_parent() as Node3D
			if parent != null:
				var pb := parent.global_basis.orthonormalized()
				var dir: Vector3 = node.get_meta("spring_dir", Vector3.DOWN)
				var wd := (pb * b * dir).normalized()
				var target := wd.slerp(Vector3.DOWN, g) if wd.dot(Vector3.DOWN) > -0.99 else wd
				if wd.dot(target) < 0.99999:
					var rot := Basis(Quaternion(wd, target.normalized()))
					b = pb.inverse() * rot * pb * b
		rest[dr["name"]] = Transform3D(b, base.origin)
