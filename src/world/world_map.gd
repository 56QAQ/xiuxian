class_name WorldMap
## POI 注册表（静态）：由种子确定性生成，区块加载前即可使用（地图 UI、NPC 放置）。
## pois() 每项：{id, name, type: "sect"/"town"/"home"/"portal"/"landmark", pos: Vector3（平台/地面高度）,
##   facing: Vector3（正面朝向）, yaw, region, sect_id?, realm_id?, markers: {标记名: Transform3D（世界）}}


## 全部 POI（副本）。seed_v = -1 时使用 GS.world.seed（未开局则默认种子）。
static func pois(seed_v: int = -1) -> Array[Dictionary]:
	var t := TerrainGen.shared(seed_v)
	var out: Array[Dictionary] = []
	for p in t.pois:
		out.append(_export(p, t))
	return out


static func _export(p: Dictionary, t: TerrainGen) -> Dictionary:
	var pos: Vector3 = p["pos"]
	var y := float(p["height"]) if p.has("height") else t.get_ground_y(pos.x, pos.z)
	var d := {
		"id": p["id"], "name": p["name"], "type": p["type"],
		"pos": Vector3(pos.x, y, pos.z), "facing": p["facing"], "yaw": p["yaw"],
		"region": p.get("region", t.get_biome(pos.x, pos.z)),
	}
	if p.has("sect_id"):
		d["sect_id"] = p["sect_id"]
	if p.has("realm_id"):
		d["realm_id"] = p["realm_id"]
	d["markers"] = BuildingLayouts.marker_transforms(p)
	return d


## 按 id 查找（找不到返回空字典）
static func find(id: String, seed_v: int = -1) -> Dictionary:
	var t := TerrainGen.shared(seed_v)
	var p := t.find_poi(id)
	return {} if p.is_empty() else _export(p, t)


## 宗门 POI
static func sect(sect_id: String, seed_v: int = -1) -> Dictionary:
	return find("sect_" + sect_id, seed_v)


## 某 POI 的标记点世界变换（不存在返回 Transform3D() 且 ok=false 由调用者用 has_marker 判断）
static func marker(poi_id: String, marker_name: String, seed_v: int = -1) -> Transform3D:
	var p := find(poi_id, seed_v)
	if p.is_empty():
		return Transform3D()
	return (p["markers"] as Dictionary).get(marker_name, Transform3D())


static func has_marker(poi_id: String, marker_name: String, seed_v: int = -1) -> bool:
	var p := find(poi_id, seed_v)
	return not p.is_empty() and (p["markers"] as Dictionary).has(marker_name)


## 某类 POI
static func of_type(ptype: String, seed_v: int = -1) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in pois(seed_v):
		if p["type"] == ptype:
			out.append(p)
	return out


## 最近的 POI（可按类型过滤）
static func nearest(pos: Vector3, ptype: String = "", seed_v: int = -1) -> Dictionary:
	var best := {}
	var bd := INF
	for p in pois(seed_v):
		if ptype != "" and p["type"] != ptype:
			continue
		var d := Vector2(pos.x, pos.z).distance_to(Vector2(p["pos"].x, p["pos"].z))
		if d < bd:
			bd = d
			best = p
	return best


## 区域中文名（地图 UI 显示）
static func region_name(pos: Vector3, seed_v: int = -1) -> String:
	var t := TerrainGen.shared(seed_v)
	var b := t.get_biome(pos.x, pos.z)
	var i := TerrainGen.BIOME_NAMES.find(b)
	return TerrainGen.BIOME_CN[i] if i >= 0 else b
