extends SceneTree
## Geliştirici aracı: karakter modellerini önizle (iskelet, boyut, ekran görüntüsü)
func _init() -> void:
	var root := Node3D.new()
	get_root().add_child(root)
	var x := -2.0
	for n in ["caveman_a", "caveman_b", "soldier"]:
		var m: Node3D = load("res://assets/models/%s/scene.gltf" % n).instantiate()
		root.add_child(m)
		m.position.x = x
		x += 2.0
		for sk: Skeleton3D in m.find_children("*", "Skeleton3D", true, false):
			print(n, " skeleton bones=", sk.get_bone_count(), " path=", m.get_path_to(sk))
		for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
			print("  mesh ", mi.name, " aabb=", mi.get_aabb(), " surf=", mi.mesh.get_surface_count(), " mat0=", mi.get_active_material(0).resource_name if mi.get_active_material(0) else "")
		var ap := m.find_children("*", "AnimationPlayer", true, false)
		if ap.size() > 0:
			print("  anims ", (ap[0] as AnimationPlayer).get_animation_list())
			(ap[0] as AnimationPlayer).play((ap[0] as AnimationPlayer).get_animation_list()[0])
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 1.0, 5.5)
	var l := DirectionalLight3D.new()
	root.add_child(l)
	l.rotation_degrees = Vector3(-40, 30, 0)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.5, 0.6, 0.7)
	we.environment.ambient_light_color = Color(0.6, 0.6, 0.6)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	root.add_child(we)
	for i in 10:
		await process_frame
	for m in root.get_children():
		if m is Node3D and m.get_child_count() > 0 and not (m is Camera3D):
			print(m.name, " world aabb ", Models.local_aabb(m))
	get_root().get_texture().get_image().save_png("user://chars.png")
	quit()
