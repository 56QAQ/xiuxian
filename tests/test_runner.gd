extends Node
## 无头测试入口：godot --headless --path . res://tests/test_runner.tscn
## 自动发现 tests/test_*.gd 中所有以 test_ 开头的方法并执行。
## 失败时以非零退出码结束，便于 CI。可用 -- --filter=关键字 只运行部分测试。

var _failures: Array[String] = []
var _current: String = ""
var _checks: int = 0


func _ready() -> void:
	await get_tree().process_frame
	var filter := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--filter="):
			filter = a.substr(9)
	var files: Array[String] = []
	var dir := DirAccess.open("res://tests")
	for f in dir.get_files():
		if f.begins_with("test_") and f.ends_with(".gd") and f != "test_runner.gd":
			files.append("res://tests/" + f)
	files.sort()
	var ran := 0
	var t0 := Time.get_ticks_msec()
	for path in files:
		var script: GDScript = load(path)
		if script == null:
			_failures.append("%s: 无法加载" % path)
			continue
		var suite: Node = script.new()
		suite.set("runner", self)
		add_child(suite)
		for m in suite.get_method_list():
			var mname: String = m["name"]
			if not mname.begins_with("test_"):
				continue
			if filter != "" and not (path + ":" + mname).contains(filter):
				continue
			_current = "%s:%s" % [path.get_file(), mname]
			var before := _failures.size()
			var r = suite.call(mname)
			if r is Signal or (r != null and r is Object and r.get_class() == "GDScriptFunctionState"):
				await r
			ran += 1
			print("  %s %s" % ["✓" if _failures.size() == before else "✗", _current])
		suite.queue_free()
		await get_tree().process_frame
	print("\n%d 个测试，%d 项断言，用时 %d ms" % [ran, _checks, Time.get_ticks_msec() - t0])
	if _failures.is_empty():
		print("全部通过")
		get_tree().quit(0)
	else:
		print("失败 %d 项：" % _failures.size())
		for f in _failures:
			print("  - " + f)
		get_tree().quit(1)


func check(cond: bool, msg: String = "") -> bool:
	_checks += 1
	if not cond:
		_failures.append("%s: %s" % [_current, msg])
		push_error("断言失败 %s: %s" % [_current, msg])
	return cond


func check_eq(a: Variant, b: Variant, msg: String = "") -> bool:
	return check(a == b, "%s（期望 %s，实际 %s）" % [msg, str(b), str(a)])
