class_name ArtStudio
## 体素美术镜头公用影棚：接近参考图的暖灰背景、柔和主光 + 冷色补光、SSAO、辉光、阴影。


static func setup(root: Node, cam_pos: Vector3, look_at_pos: Vector3, fov: float = 36.0) -> Camera3D:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.56, 0.55, 0.52)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.78, 0.8, 0.86)
	e.ambient_light_energy = 0.42
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0
	e.ssao_enabled = true
	e.ssao_radius = 0.5
	e.ssao_intensity = 1.6
	e.glow_enabled = true
	e.glow_intensity = 0.7
	e.glow_bloom = 0.05
	env.environment = e
	root.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42, 28, 0)
	sun.light_energy = 1.05
	sun.light_color = Color(1.0, 0.97, 0.92)
	sun.shadow_enabled = true
	sun.shadow_blur = 1.5
	sun.directional_shadow_max_distance = 20.0
	root.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -150, 0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.8, 0.86, 1.0)
	root.add_child(fill)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(60, 60)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.56, 0.55, 0.52)
	gm.roughness = 0.95
	ground.material_override = gm
	root.add_child(ground)
	var cam := Camera3D.new()
	cam.fov = fov
	root.add_child(cam)
	cam.position = cam_pos
	cam.look_at(look_at_pos)
	return cam
