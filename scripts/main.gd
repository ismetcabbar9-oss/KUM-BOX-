extends Node3D
## Ana sahne: seviyeyi kurar, dokunmatik girdiyi, grafik kalitesini ve oyun durumunu yönetir.

const RAMP_W := 14.0
const RAMP_H := 55.0
const RAMP_FLAT := 14.0
const RAMP_SLOPE := 150.0
const RAMP_RUNOUT := 25.0
const MAX_ROCKS := 4
const ROCK_SIZES := [
	{"name": "KÜÇÜK", "r": 1.2},
	{"name": "ORTA", "r": 2.0},
	{"name": "BÜYÜK", "r": 3.0},
]
const QUALITY := ["DÜŞÜK", "ORTA", "YÜKSEK"]

var camera: Camera3D
var hud: CanvasLayer
var sun: DirectionalLight3D
var env: Environment
var rocks: Array[Rock] = []
var current: Rock
var size_index := 1
var quality := 1
var aim_x := 0.0
var _touches := {}
var _stat_timer := 0.0
var _destructibles: Array[Node] = []
var _buildings: Array[Building] = []


func _ready() -> void:
	randomize()
	_build_environment()
	WorldBuilder.build_ground(self)
	WorldBuilder.build_ramp(self, RAMP_W, RAMP_H, RAMP_FLAT, RAMP_SLOPE, RAMP_RUNOUT)
	_build_targets()
	_scatter_decor()

	camera = preload("res://scripts/game_camera.gd").new()
	add_child(camera)
	camera.current = true

	hud = preload("res://scripts/hud.gd").new()
	add_child(hud)
	hud.push_pressed.connect(func() -> void: _launch(9.0))
	hud.new_rock_pressed.connect(_spawn_rock)
	hud.reset_pressed.connect(func() -> void:
		Engine.time_scale = 1.0
		Sfx.set_slow_motion(false)
		get_tree().reload_current_scene())
	hud.size_pressed.connect(_cycle_size)
	hud.slowmo_toggled.connect(func(on: bool) -> void:
		Engine.time_scale = 0.3 if on else 1.0
		Sfx.set_slow_motion(on))
	hud.quality_pressed.connect(func() -> void: _apply_quality((quality + 1) % QUALITY.size()))

	_destructibles = get_tree().get_nodes_in_group("destructible")
	var args := OS.get_cmdline_user_args()
	if "--lowgfx" in args:
		quality = 0
	elif not OS.has_feature("mobile"):
		quality = 2
	_apply_quality(quality)
	_spawn_rock()
	camera.global_position = current.global_position + Vector3(0, 8, -18)
	camera.snap()
	if "--autotest" in args:
		_autotest()


# --- Grafik kalitesi -------------------------------------------------------

func _apply_quality(q: int) -> void:
	quality = q
	hud.set_quality_name(QUALITY[q])
	var vp := get_viewport()
	match q:
		0:
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = 70.0
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.scaling_3d_scale = 0.7
			env.glow_enabled = false
		1:
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 140.0
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			vp.msaa_3d = Viewport.MSAA_2X
			vp.scaling_3d_scale = 0.85
			env.glow_enabled = true
		2:
			sun.shadow_enabled = true
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 220.0
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			vp.msaa_3d = Viewport.MSAA_2X
			vp.scaling_3d_scale = 1.0
			env.glow_enabled = true


# --- Dünya ---------------------------------------------------------------

func _build_environment() -> void:
	env = Environment.new()
	var sky := Sky.new()
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/hdri/sky_2k.hdr")
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.78, 0.86)
	env.fog_density = 0.0009
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.25
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 145, 0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_blur = 1.2
	add_child(sun)


func _build_targets() -> void:
	var z0 := RAMP_FLAT + RAMP_SLOPE + RAMP_RUNOUT

	# Beton bariyer sırası (aralıklı)
	for i in 5:
		_prop("jersey", Vector3(-8.0 + i * 4.0, 0, z0 + 8.0), 0.0, "concrete", 1800.0)

	# Tuğla duvar (şaşırtmalı örgü)
	_brick_wall(Vector3(0, 0, z0 + 20.0), 18.2, 4, WorldBuilder.pbr("red_brick_03", 0.45))

	# Sandık yığını ve variller
	for row in 3:
		for i in 3 - row:
			_prop("crate", Vector3(-7.5 + (i - (2 - row) * 0.5) * 1.25, row * 0.47, z0 + 30.0), 90.0, "wood", 45.0)
	for i in 9:
		_prop("barrel", Vector3(6.0 + (i % 3) * 0.62, 0, z0 + 28.0 + (i / 3) * 0.62), randf() * 360.0, "metal", 60.0)

	# Dağınık taşlar (dinamik)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 10:
		var p := Vector3(rng.randf_range(-12, 12), 0, z0 + rng.randf_range(34, 70))
		_stone(p, rng.randf_range(0.5, 1.3), rng)

	# Gerçek binalar
	_building("booth", Vector3(15.0, 0, z0 + 40.0), 90.0)
	_building("oldbuilding", Vector3(0.0, 0, z0 + 48.0), 0.0)
	_building("factory", Vector3(20.0, 0, z0 + 72.0), -90.0)
	_building("tower", Vector3(-4.0, 0, z0 + 78.0), 0.0)
	_building("soviet", Vector3(3.0, 0, z0 + 115.0), 90.0)


func _building(model_name: String, pos: Vector3, rot_y: float) -> void:
	var b := Building.new()
	b.setup(model_name)
	b.position = pos
	b.rotation_degrees.y = rot_y
	add_child(b)
	_buildings.append(b)


## Model tabanlı dinamik obje: dışbükey örtü çarpışması.
func _prop(model_name: String, pos: Vector3, rot_y: float, kind: String, body_mass: float) -> Destructible:
	var d := Destructible.new()
	var visual := Models.instance(model_name)
	d.add_child(visual)
	match model_name:
		"jersey":
			Models.fit(visual, 3.0, "length")
			visual.scale = Vector3(0.8, 0.75, 1.0) * visual.scale.x
			var b := Models.local_aabb(visual)
			visual.position.y = -b.position.y * visual.scale.y
		"crate":
			Models.fit(visual, 1.17, "length")
		"barrel":
			Models.fit(visual, 0.88, "height")
	var xf := visual.transform
	var pts := PackedVector3Array()
	for p in Models.hull_points(model_name, visual):
		pts.append(xf * p)
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	d.add_child(cs)
	d.configure(kind, body_mass, 0.5 if kind == "metal" else 0.8)
	d.position = pos + Vector3.UP * 0.01
	d.rotation_degrees.y = rot_y
	add_child(d)
	return d


func _stone(pos: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var d := Destructible.new()
	var visual := Models.instance("rocks4")
	# rocks4 dört ayrı kaya içerir; birini seç
	var meshes := visual.find_children("*", "MeshInstance3D", true, false)
	var keep: MeshInstance3D = meshes[rng.randi() % meshes.size()]
	var mi := MeshInstance3D.new()
	mi.mesh = keep.mesh
	visual.free()
	d.add_child(mi)
	var b := mi.mesh.get_aabb()
	var s := size / maxf(b.size.x, maxf(b.size.y, b.size.z))
	mi.scale = Vector3.ONE * s
	mi.position = -b.get_center() * s
	var hull := mi.mesh.create_convex_shape(true, true) as ConvexPolygonShape3D
	var pts := PackedVector3Array()
	for p in hull.points:
		pts.append(mi.transform * p)
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	var cs := CollisionShape3D.new()
	cs.shape = shape
	d.add_child(cs)
	var e := b.size * s
	d.configure("stone", e.x * e.y * e.z * 0.5 * 2600.0)
	d.position = pos + Vector3.UP * (b.size.y * s * 0.5 + 0.02)
	d.rotation = Vector3(0, rng.randf() * TAU, 0)
	add_child(d)


func _brick_wall(center: Vector3, length: float, rows: int, mat: Material) -> void:
	var bw := 2.6
	var bh := 1.0
	var bd := 0.8
	var count := int(length / bw)
	var box := BoxMesh.new()
	box.size = Vector3(bw - 0.01, bh, bd)
	var half := BoxMesh.new()
	half.size = Vector3(bw * 0.5 - 0.01, bh, bd)
	for r in rows:
		var odd := r % 2 == 1
		var x := -length * 0.5
		var pieces := count + (1 if odd else 0)
		for i in pieces:
			# Tek sıralar yarım tuğlayla başlayıp biter: kenarlar düz kalır
			var w := bw * 0.5 if odd and (i == 0 or i == pieces - 1) else bw
			var d := Destructible.new()
			var mi := MeshInstance3D.new()
			mi.mesh = half if w < bw else box
			mi.material_override = mat
			d.add_child(mi)
			d.add_box(Vector3(w - 0.01, bh, bd))
			d.configure("brick", w * bh * bd * 1900.0)
			d.position = center + Vector3(x + w * 0.5, bh * 0.5 + r * (bh + 0.002), 0)
			add_child(d)
			x += w


## Statik dekor: büyük kayalar (gölgesiz uzaklar, görünürlük mesafesi sınırlı).
func _scatter_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var models := ["rock_boulder2", "rock_medium", "rock_hero"]
	for i in 16:
		var side := -1.0 if i % 2 == 0 else 1.0
		var size := rng.randf_range(2.0, 7.0)
		var pos := Vector3(side * rng.randf_range(22.0, 70.0), 0, rng.randf_range(-10.0, 330.0))
		var body := StaticBody3D.new()
		var visual := Models.instance(models[i % models.size()])
		body.add_child(visual)
		Models.fit(visual, size, "max")
		visual.position.y -= size * 0.15  # biraz gömülü dursun
		var shape := SphereShape3D.new()
		shape.radius = size * 0.4
		var cs := CollisionShape3D.new()
		cs.shape = shape
		cs.position.y = size * 0.25
		body.add_child(cs)
		body.position = pos
		body.rotation.y = rng.randf() * TAU
		Models.visibility(visual, 260.0)
		add_child(body)


# --- Kaya ----------------------------------------------------------------

func _rock_radius() -> float:
	return ROCK_SIZES[size_index]["r"]


func _spawn_rock() -> void:
	if current and not current.launched:
		current.queue_free()
		rocks.erase(current)
	while rocks.size() >= MAX_ROCKS:
		var old: Rock = rocks.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var r := _rock_radius()
	var rock := Rock.new()
	rock.setup(r)
	add_child(rock)
	aim_x = clampf(aim_x, -_aim_limit(), _aim_limit())
	rock.global_position = Vector3(aim_x, RAMP_H + r * 1.05, RAMP_FLAT * 0.5)
	rock.reset_physics_interpolation()
	rocks.append(rock)
	current = rock
	camera.target = rock
	hud.set_aiming(true)


func _aim_limit() -> float:
	return RAMP_W * 0.5 - _rock_radius() - 0.2


func _launch(power: float) -> void:
	if current == null or current.launched:
		return
	current.launch(Vector3(0, 0, 1), power)
	hud.set_aiming(false)


func _cycle_size() -> void:
	size_index = (size_index + 1) % ROCK_SIZES.size()
	hud.set_size_name(ROCK_SIZES[size_index]["name"])
	if current and not current.launched:
		_spawn_rock()


# --- Döngü / girdi -------------------------------------------------------

func _count_displaced() -> int:
	var moved := 0
	for d in _destructibles:
		if (d as Destructible).is_displaced():
			moved += 1
	return moved


func _process(delta: float) -> void:
	_stat_timer -= delta
	if _stat_timer <= 0.0:
		_stat_timer = 0.5
		var spd := current.speed_kmh() if current else 0.0
		hud.set_stats(spd, _count_displaced(), _destructibles.size())
		var draws := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		hud.set_fps(int(Engine.get_frames_per_second()), "%d çizim" % draws)
	for rock in rocks.duplicate():
		if is_instance_valid(rock) and rock.global_position.y < -50.0:
			rocks.erase(rock)
			rock.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if hud.is_over_ui(event.position):
				return
			_touches[event.index] = {"pos": event.position, "start": event.position, "t": Time.get_ticks_msec()}
		elif _touches.has(event.index):
			var tch: Dictionary = _touches[event.index]
			_touches.erase(event.index)
			if _touches.is_empty() and current and not current.launched:
				var dy: float = tch["start"].y - event.position.y
				var dt := maxf((Time.get_ticks_msec() - int(tch["t"])) / 1000.0, 0.05)
				var vh: float = get_viewport().get_visible_rect().size.y
				if dy > vh * 0.08 and dt < 0.6:
					# Kaydırma hızına göre itiş gücü (m/s)
					var swipe_speed: float = dy / vh / dt
					_launch(clampf(4.0 + swipe_speed * 6.0, 4.0, 20.0))
	elif event is InputEventScreenDrag:
		if not _touches.has(event.index):
			return
		var prev: Vector2 = _touches[event.index]["pos"]
		_touches[event.index]["pos"] = event.position
		if _touches.size() == 1:
			if current and not current.launched:
				aim_x = clampf(aim_x - event.relative.x * 0.02, -_aim_limit(), _aim_limit())
				var p := current.global_position
				p.x = aim_x
				current.global_position = p
			else:
				camera.orbit(event.relative.x, event.relative.y)
		elif _touches.size() == 2:
			var other_pos: Vector2
			for k in _touches:
				if k != event.index:
					other_pos = _touches[k]["pos"]
			var before := prev.distance_to(other_pos)
			var after := (event.position as Vector2).distance_to(other_pos)
			if before > 10.0:
				camera.pinch(after / before)


## Geliştirici testi: `godot -- --autotest` kayayı fırlatır, durumu ve performansı yazdırır.
func _autotest() -> void:
	var args := OS.get_cmdline_user_args()
	print("Hedef parça sayısı: ", _destructibles.size())
	await get_tree().create_timer(2.0).timeout
	var early := _count_displaced()
	print("Fırlatmadan önce yerinden oynayan: ", early)
	if "--shots" in args:
		await _shots()
		get_tree().quit()
		return
	_launch(10.0)
	# Simülasyon saniyesi = 60 fizik karesi (gerçek zamandan bağımsız). `--fixed-fps 60`
	# ile çalıştırıldığında toplam süre, 30 sn simülasyonun gerçek işlem maliyetidir.
	var t0 := Time.get_ticks_usec()
	var sec_t := t0
	for i in 30:
		for f in Engine.physics_ticks_per_second:
			await get_tree().physics_frame
		var now := Time.get_ticks_usec()
		var awake := 0
		for d in _destructibles:
			if not (d as RigidBody3D).sleeping:
				awake += 1
		var broken := _buildings.filter(func(b: Building) -> bool: return b.broken).size()
		print("t=%2d  kaya=%s  hız=%3.0f km/sa  yıkılan=%3d  uyanık=%3d  kırık bina=%d  işlem=%4.0f ms/sn" % [
			i + 1, current.global_position.round(), current.speed_kmh(), _count_displaced(), awake, broken, (now - sec_t) / 1000.0])
		sec_t = now
	print("TOPLAM işlem süresi (30 sn simülasyon): %.2f sn" % ((Time.get_ticks_usec() - t0) / 1e6))
	get_tree().quit()


func _shots() -> void:
	var z0 := RAMP_FLAT + RAMP_SLOPE + RAMP_RUNOUT
	var views := [
		[current.global_position + Vector3(0, 8, -18), current.global_position + Vector3(0, 0, 20)],
		[Vector3(26, 12, z0 - 12), Vector3(0, 6, z0 + 50)],
		[Vector3(-45, 35, 70), Vector3(0, 15, 140)],
		[Vector3(-30, 8, z0 + 30), Vector3(0, 10, z0 + 90)],
	]
	camera.target = null
	for k in views.size():
		camera.global_position = views[k][0]
		camera.look_at(views[k][1])
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://shot_view%d.png" % k)
	# Yıkım görüntüsü: kulenin alt katlarına darbe ver, birkaç saniye simüle et
	var tower: Building = _buildings.filter(func(b: Building) -> bool: return b.name == "tower")[0]
	for c in tower.chunks:
		if c.global_position.y < 6.0:
			c.sleeping = false
			c.apply_central_impulse(Vector3(1, 0.2, 0.3) * c.mass * 9.0)
	for f in 25:
		await get_tree().physics_frame
	camera.global_position = Vector3(-30, 9, z0 + 62)
	camera.look_at(Vector3(-4, 6, z0 + 80))
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("user://shot_view%d.png" % views.size())
