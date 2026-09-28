extends Node
## 截图工具：渲染一个“镜头脚本”并保存 PNG，用于在无显示器环境检查画面。
## 用法（需要 X 服务器，例如 xvfb-run）：
##   godot --path . res://tools/shots/shot_runner.tscn -- --shot=characters --out=/tmp/a.png [--frames=30] [--size=1600x900]
## 镜头脚本位于 res://tools/shots/<shot>.gd，需实现 func build(root: Node) -> void，
## 可选实现 func frames() -> int 与 func step(root: Node, frame: int) -> void（逐帧驱动）。

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv := a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
	var shot := str(args.get("shot", "characters"))
	var out := str(args.get("out", "user://shot.png"))
	if args.has("size"):
		var wh: PackedStringArray = str(args["size"]).split("x")
		get_window().size = Vector2i(int(wh[0]), int(wh[1]))
		get_tree().root.content_scale_size = Vector2i(int(wh[0]), int(wh[1]))
	var script: GDScript = load("res://tools/shots/%s.gd" % shot)
	if script == null:
		push_error("找不到镜头脚本 %s" % shot)
		get_tree().quit(1)
		return
	var director: Object = script.new()
	var root := Node.new()
	root.name = "ShotRoot"
	add_child(root)
	director.call("build", root)
	var n := int(args.get("frames", director.call("frames") if director.has_method("frames") else 20))
	for i in n:
		if director.has_method("step"):
			director.call("step", root, i)
		await get_tree().process_frame
	# 异步体素网格（角色/妖兽/远景 LOD）收尾后再多走两帧，让模型显示出来
	VoxMesh.finish_pending()
	await get_tree().process_frame
	await get_tree().process_frame
	if DisplayServer.get_name() == "headless":
		print("无头模式：跳过截图")
		get_tree().quit(0)
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("截图已保存: ", out, " ", img.get_size())
	get_tree().quit(0)
