extends Node3D
## Geliştirici aracı: karakter pozlarını yandan/önden önizle
func _ready() -> void:
	var root := Node3D.new()
	add_child(root)
	var modes := ["strain", "strain", "cheer", "idle"]
	var men: Array = []
	for i in modes.size():
		var c := Caveman.new()
		c.setup("caveman_a" if i % 2 == 0 else "caveman_b")
		root.add_child(c)
		c.position = Vector3(-4.5 + i * 3.0, 0, 0)
		c.mode = modes[i]
		c.step_rate = 9.0 if i == 1 else 0.0
		men.append(c)
	var s := Soldier.new()
	s.setup()
	root.add_child(s)
	s.position = Vector3(7.5, 0, 0)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(40, 40)
	ground.mesh = pm
	root.add_child(ground)
	var cam := Camera3D.new()
	root.add_child(cam)
	var l := DirectionalLight3D.new()
	root.add_child(l)
	l.rotation_degrees = Vector3(-40, 60, 0)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.5, 0.6, 0.7)
	we.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root.add_child(we)
	for i in 8:
		await get_tree().process_frame
	# Yandan (karakterler +Z'ye bakıyor; kamera +X tarafında değil, -X... yandan: kamerayı +X'e koy)
	cam.position = Vector3(1.5, 1.3, 7.5)
	cam.look_at(Vector3(1.5, 0.9, 0))
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://pose_front.png")
	for i in men.size():
		men[i].rotation.y = PI * 0.5  # yandan görünsün (+X'e baksın)
	s.die(Vector3.ZERO)
	s.freeze = true
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://pose_side.png")
	get_tree().quit()
