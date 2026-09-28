class_name CreatorLogic
## 捏人规则（纯数据，可测试）：天赋点预算、灵根占比分配、随机生成、校验。
##
## 预算 12 点。花费 = 先天属性增减（基础 5，每 +1 花 1 点，每 -1 返 1 点，范围 1~10）
##                  + 天赋点数（缺陷为负，返还点数）+ 灵根类型点数（BuildCalc.ROOT_TYPES）。

const BUDGET := 12
const ATTR_BASE := 5
const ATTR_MIN := 1
const ATTR_MAX := 10
const ROOT_MIN := 5


# ================================================================ 点数

static func attr_cost(attributes: Dictionary) -> int:
	var c := 0
	for a in PlayerData.ATTRS:
		c += int(attributes.get(a, ATTR_BASE)) - ATTR_BASE
	return c


static func talent_cost(talents: Array) -> int:
	var c := 0
	for t in talents:
		c += int(DB.talent(str(t)).get("cost", 0))
	return c


static func root_count(roots: Dictionary) -> int:
	var n := 0
	for e in roots:
		if int(roots[e]) > 0:
			n += 1
	return n


static func root_type(roots: Dictionary) -> Dictionary:
	return BuildCalc.ROOT_TYPES.get(clampi(root_count(roots), 1, 5), BuildCalc.ROOT_TYPES[5])


static func root_cost(roots: Dictionary) -> int:
	if root_count(roots) == 0:
		return 0
	return int(root_type(roots)["cost"])


static func spent(attributes: Dictionary, talents: Array, roots: Dictionary) -> int:
	return attr_cost(attributes) + talent_cost(talents) + root_cost(roots)


static func remaining(attributes: Dictionary, talents: Array, roots: Dictionary) -> int:
	return BUDGET - spent(attributes, talents, roots)


static func can_raise(attributes: Dictionary, a: String, remain: int) -> bool:
	return int(attributes.get(a, ATTR_BASE)) < ATTR_MAX and remain >= 1


static func can_lower(attributes: Dictionary, a: String) -> bool:
	return int(attributes.get(a, ATTR_BASE)) > ATTR_MIN


## 选择/取消天赋是否可行（取消总是可行；缺陷返还点数总是可选）
static func can_toggle_talent(talents: Array, tid: String, remain: int) -> bool:
	if talents.has(tid):
		return true
	var cost := int(DB.talent(tid).get("cost", 0))
	return cost <= 0 or remain >= cost


# ================================================================ 灵根占比

## 把 total 按权重分给各键（每键至少 min_each），整数，最大余数法，保证总和精确等于 total
static func distribute(total: int, weights: Dictionary, min_each: int) -> Dictionary:
	var keys := weights.keys()
	var n := keys.size()
	var out := {}
	if n == 0:
		return out
	var free := total - min_each * n
	var wsum := 0.0
	for k in keys:
		wsum += maxf(float(weights[k]), 0.0)
	var fracs: Array = []
	var assigned := 0
	for k in keys:
		var share := float(free) * (maxf(float(weights[k]), 0.0) / wsum if wsum > 0.0 else 1.0 / n)
		var fl := int(floor(share))
		out[k] = min_each + fl
		assigned += fl
		fracs.append([share - fl, k])
	fracs.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var left := free - assigned
	var i := 0
	while left > 0 and not fracs.is_empty():
		var key: Variant = fracs[i % fracs.size()][1]
		out[key] = int(out[key]) + 1
		left -= 1
		i += 1
	return out


## 设置某灵根占比，其余灵根按原比例分配剩余（每系至少 5%）
static func set_root(roots: Dictionary, e: String, value: int) -> Dictionary:
	var others: Array[String] = []
	for k in Elem.LIST:
		if k != e and int(roots.get(k, 0)) > 0:
			others.append(k)
	if others.is_empty():
		return {e: 100}
	var v := clampi(value, ROOT_MIN, 100 - ROOT_MIN * others.size())
	var weights := {}
	for o in others:
		weights[o] = int(roots[o]) - ROOT_MIN
	var out := distribute(100 - v, weights, ROOT_MIN)
	out[e] = v
	return _ordered(out)


## 选中/取消某系灵根。至少保留一系；新加入的灵根取均分份额。
static func toggle_root(roots: Dictionary, e: String) -> Dictionary:
	var cur := {}
	for k in roots:
		if int(roots[k]) > 0:
			cur[k] = int(roots[k])
	if cur.has(e):
		if cur.size() <= 1:
			return _ordered(cur)
		cur.erase(e)
		var weights := {}
		for k in cur:
			weights[k] = int(cur[k]) - ROOT_MIN
		return _ordered(distribute(100, weights, ROOT_MIN))
	cur[e] = ROOT_MIN
	return set_root(cur, e, int(round(100.0 / cur.size())))


## 规范化：整数、合计 100、每系至少 5%
static func normalize(roots: Dictionary) -> Dictionary:
	var cur := {}
	for k in roots:
		if Elem.is_valid(str(k)) and int(roots[k]) > 0:
			cur[k] = int(roots[k])
	if cur.is_empty():
		return {"fire": 100}
	if cur.size() == 1:
		return {cur.keys()[0]: 100}
	var weights := {}
	for k in cur:
		weights[k] = maxi(int(cur[k]) - ROOT_MIN, 0)
	return _ordered(distribute(100, weights, ROOT_MIN))


static func roots_valid(roots: Dictionary) -> bool:
	var sum := 0
	var n := 0
	for k in roots:
		var v := int(roots[k])
		if v <= 0:
			continue
		if not Elem.is_valid(str(k)):
			return false
		n += 1
		sum += v
		if v < ROOT_MIN and root_count(roots) > 1:
			return false
	return n >= 1 and sum == 100


static func _ordered(d: Dictionary) -> Dictionary:
	var out := {}
	for e in Elem.LIST:
		if d.has(e) and int(d[e]) > 0:
			out[e] = int(d[e])
	return out


## 某系灵根被动的描述（按占比与天灵根纯度）
static func passive_text(roots: Dictionary, e: String) -> String:
	var pct := float(roots.get(e, 0)) / 100.0
	var purity := 1.25 if root_count(roots) == 1 else 1.0
	var parts: PackedStringArray = []
	var src: Dictionary = BuildCalc.ROOT_PASSIVES.get(e, {})
	for k in src:
		parts.append(Stats.format_mod(k, float(src[k]) * pct * purity))
	return "，".join(parts)


# ================================================================ 随机

static func random_name(gender: String, rng: RandomNumberGenerator) -> String:
	var sur: Array = DB.names.get("surnames", ["李"])
	var given: Array = DB.names.get("given_female" if gender == "female" else "given_male", ["无名"])
	return str(sur[rng.randi() % sur.size()]) + str(given[rng.randi() % given.size()])


static func random_roots(rng: RandomNumberGenerator) -> Dictionary:
	var r := rng.randf()
	var n := 1 if r < 0.14 else (2 if r < 0.5 else (3 if r < 0.8 else (4 if r < 0.92 else 5)))
	var pool: Array[String] = Elem.LIST.duplicate()
	var weights := {}
	for i in n:
		var e: String = pool[rng.randi() % pool.size()]
		pool.erase(e)
		weights[e] = rng.randf_range(0.3, 1.0)
	if n == 1:
		return {weights.keys()[0]: 100}
	return _ordered(distribute(100, weights, ROOT_MIN))


## 在预算内随机属性与天赋（给定灵根花费）
static func random_build(roots: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var attrs := {}
	for a in PlayerData.ATTRS:
		attrs[a] = ATTR_BASE
	var talents: Array = []
	var ids := DB.talents.keys()
	# 25% 概率带一项缺陷
	if rng.randf() < 0.25:
		var flaws: Array = ids.filter(func(t: Variant) -> bool: return int(DB.talent(str(t)).get("cost", 0)) < 0)
		if not flaws.is_empty():
			talents.append(flaws[rng.randi() % flaws.size()])
	var tries := 0
	while tries < 30 and talents.size() < 3:
		tries += 1
		var t := str(ids[rng.randi() % ids.size()])
		var cost := int(DB.talent(t).get("cost", 0))
		if talents.has(t) or cost <= 0:
			continue
		if remaining(attrs, talents, roots) - cost >= 2 or (talents.size() == 0 and remaining(attrs, talents, roots) >= cost):
			talents.append(t)
		if rng.randf() < 0.35:
			break
	# 余点加属性（偶尔降低一项换点）
	if rng.randf() < 0.3:
		var low: String = PlayerData.ATTRS[rng.randi() % PlayerData.ATTRS.size()]
		attrs[low] = ATTR_BASE - 1 - rng.randi() % 2
	var guard := 0
	while remaining(attrs, talents, roots) > 0 and guard < 100:
		guard += 1
		var a: String = PlayerData.ATTRS[rng.randi() % PlayerData.ATTRS.size()]
		if int(attrs[a]) < ATTR_MAX:
			attrs[a] = int(attrs[a]) + 1
	# 仍为负（灵根太贵）则降低属性
	guard = 0
	while remaining(attrs, talents, roots) < 0 and guard < 100:
		guard += 1
		var a2: String = PlayerData.ATTRS[rng.randi() % PlayerData.ATTRS.size()]
		if int(attrs[a2]) > ATTR_MIN:
			attrs[a2] = int(attrs[a2]) - 1
	return {"attributes": attrs, "talents": talents}


static func random_appearance(rng: RandomNumberGenerator, gender: String = "") -> Dictionary:
	var ap: Dictionary = DB.appearance
	var pick := func(key: String) -> Variant:
		var arr: Array = ap.get(key, [])
		return arr[rng.randi() % arr.size()] if not arr.is_empty() else null
	var g := gender if gender != "" else ("female" if rng.randf() < 0.55 else "male")
	var hair: Array = ap.get("hair_styles", [])
	var hair_id := str((pick.call("hair_styles") as Dictionary).get("id", "long")) if not hair.is_empty() else "long"
	var a := {
		"gender": g,
		"height": snappedf(rng.randf_range(0.93, 1.02) if g == "female" else rng.randf_range(0.98, 1.08), 0.01),
		"build": snappedf(rng.randf_range(0.2, 0.6) if g == "female" else rng.randf_range(0.4, 0.9), 0.01),
		"head_scale": snappedf(rng.randf_range(0.96, 1.1), 0.01),
		"chest": snappedf(rng.randf_range(0.3, 0.7), 0.01) if g == "female" else 0.0,
		"skin": str(pick.call("skin_colors")),
		"hair_style": hair_id,
		"hair_color": str(pick.call("hair_colors")),
		"eye_color": str(pick.call("eye_colors")),
		"eye_style": str((pick.call("eye_styles") as Dictionary).get("id", "almond")),
		"brow_style": rng.randi() % 3,
		"mark": "none" if rng.randf() < 0.6 else str((pick.call("marks") as Dictionary).get("id", "none")),
		"mark_color": ["#e02040", "#f0a020", "#3080f0", "#c040c0"][rng.randi() % 4],
		"ears": "human" if rng.randf() < 0.55 else str((pick.call("ears") as Dictionary).get("id", "human")),
		"tail": "none",
		"horns": "dragon" if rng.randf() < 0.1 else "none",
		"outfit": str((pick.call("outfits") as Dictionary).get("id", "robe")),
		"outfit_colors": (pick.call("outfit_palettes") as Array).duplicate(),
	}
	var hc := Color.html(a["hair_color"])
	a["hair_color2"] = "#" + hc.lightened(0.25).to_html(false)
	a["ear_color"] = a["hair_color"]
	if a["ears"] == "fox" and rng.randf() < 0.6:
		a["tail"] = "fox"
	return a


# ================================================================ 校验

## 返回错误文本；空字符串表示可以确认
static func validate(name_text: String, attributes: Dictionary, talents: Array, roots: Dictionary, background: String, sect: String) -> String:
	if name_text.strip_edges() == "":
		return "请为角色取名"
	if name_text.strip_edges().length() > 12:
		return "姓名过长（最多 12 字）"
	if not roots_valid(roots):
		return "灵根占比须合计 100%"
	var remain := remaining(attributes, talents, roots)
	if remain < 0:
		return "天赋点超支 %d 点" % -remain
	for a in PlayerData.ATTRS:
		var v := int(attributes.get(a, ATTR_BASE))
		if v < ATTR_MIN or v > ATTR_MAX:
			return "属性超出范围"
	if not DB.backgrounds.has(background):
		return "请选择出身"
	if bool(DB.backgrounds[background].get("sect_choice", false)) and not DB.sects.has(sect):
		return "请选择所在宗门"
	return ""
