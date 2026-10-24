extends Node3D
## Geliştirici aracı: pişirilmiş animasyonları yan yana önizle
const SET := [["soldier", "walk"], ["soldier", "run"], ["archer", "shoot"], ["peasant", "idle"], ["peasant", "walk"], ["peasant", "swing"], ["peasant", "run"], ["peasant", "death"]]
const T := 0.45


func _ready() -> void:
	var i := 0
	for s in SET:
		var m: Node3D = load("res://assets/models/%s/scene.gltf" % s[0]).instantiate()
		add_child(m)
		Models.fit(m, 1.8, "height")
		m.position.x += -7.0 + i * 2.0
		var ap: AnimationPlayer = m.find_children("*", "AnimationPlayer", true, false)[0]
		ap.add_animation_library("k", load("res://assets/anims/%s.res" % s[0]))
		ap.play("k/" + s[1])
		ap.seek(T if s[1] != "death" else 2.0, true)
		ap.pause()
		i += 1
	var cam := Camera3D.new()
	add_child(cam)
	var l := DirectionalLight3D.new()
	add_child(l)
	l.rotation_degrees = Vector3(-40, 60, 0)
	var we := WorldEnvironment.new()
	we.environment = Environment.new()
	we.environment.background_mode = Environment.BG_COLOR
	we.environment.background_color = Color(0.5, 0.6, 0.7)
	we.environment.ambient_light_color = Color(0.7, 0.7, 0.7)
	we.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	add_child(we)
	cam.position = Vector3(0, 1.2, 9.0)
	for k in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://anims_front.png")
	cam.position = Vector3(12, 1.2, 0.5)
	cam.look_at(Vector3(0, 0.9, 0))
	for k in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://anims_side.png")
	get_tree().quit()
