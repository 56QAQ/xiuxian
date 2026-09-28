extends RefCounted
## 地形弹坑：坊市郊外炸出的三个弹坑（焦土、碎块），验证 carve_crater 的网格/碰撞重建


var _ow: Node3D
var _pts: Array[Vector3] = []


func frames() -> int:
	return 16


func build(root: Node) -> void:
	_ow = WorldShot.make_overworld(root, 11.0)
	var t: TerrainGen = _ow.get("terrain")
	# 选在道路上（道路两侧无树），坊市与离火殿之间
	var road: PackedVector2Array = t.roads[3]
	var c := road[int(road.size() * 0.35)]
	for off in [Vector2(0, 0), Vector2(11, 7), Vector2(-8, 9)]:
		var p: Vector2 = c + off
		_pts.append(Vector3(p.x, t.get_ground_y(p.x, p.y), p.y))
	var cam_pos := _pts[0] + Vector3(-6, 24, -20)
	WorldShot.place_camera(_ow, cam_pos, _pts[0] + Vector3(2, 0, 5), 58.0)
	WorldShot.prime(_ow, 5)


func step(_root: Node, frame: int) -> void:
	if frame == 2:
		var t: TerrainGen = _ow.get("terrain")
		var radii := [6.0, 4.0, 3.0]
		for i in _pts.size():
			t.carve_crater(_pts[i], radii[i])
