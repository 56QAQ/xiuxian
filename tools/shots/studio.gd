class_name ShotStudio
## 镜头脚本公用：影棚环境（灰色背景、日光、阴影、SSAO、辉光）


static func setup(root: Node, cam_pos: Vector3, look_at_pos: Vector3, fov: float = 40.0) -> Camera3D:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.62, 0.61, 0.58)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.85)
	e.ambient_light_energy = 0.55
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.ssao_enabled = true
	e.ssao_radius = 0.6
	e.ssao_intensity = 2.0
	e.glow_enabled = true
	e.glow_intensity = 0.6
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 30.0
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, -140, 0)
	fill.light_energy = 0.35
	root.add_child(fill)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.62, 0.61, 0.58)
	ground.material_override = gm
	root.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = fov
	root.add_child(cam)
	cam.position = cam_pos
	cam.look_at(look_at_pos)
	return cam
