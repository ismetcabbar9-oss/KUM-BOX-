extends Node3D
## Ana sahne: seviyeyi kurar, dokunmatik girdiyi ve oyun durumunu yönetir.

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

var camera: Camera3D
var hud: CanvasLayer
var rocks: Array[Rock] = []
var current: Rock
var size_index := 1
var aim_x := 0.0
var _touches := {}
var _stat_timer := 0.0
var _destructibles: Array[Node] = []
var _rock_seed := 1


func _ready() -> void:
	randomize()
	_build_environment()
	WorldBuilder.build_terrain(self, 1000.0, 160, Rect2(-80, -40, 160, 480),
		{"height": RAMP_H, "flat": RAMP_FLAT, "slope": RAMP_SLOPE, "width": RAMP_W + 2.0})
	WorldBuilder.build_ramp(self, RAMP_W, RAMP_H, RAMP_FLAT, RAMP_SLOPE, RAMP_RUNOUT)
	_build_targets()
	_scatter_boulders()

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

	_destructibles = get_tree().get_nodes_in_group("destructible")
	_spawn_rock()
	camera.global_position = current.global_position + Vector3(0, 8, -18)
	camera.snap()
	if "--autotest" in OS.get_cmdline_user_args():
		_autotest()


## Geliştirici testi: `godot -- --autotest` kayayı fırlatır, durumu yazdırır, çıkar.
func _autotest() -> void:
	print("Hedef parça sayısı: ", _destructibles.size())
	await get_tree().create_timer(3.0).timeout
	if "--shots" in OS.get_cmdline_user_args():
		get_viewport().get_texture().get_image().save_png("user://shot_start.png")
		var z0 := RAMP_FLAT + RAMP_SLOPE + RAMP_RUNOUT
		var views := [
			[Vector3(28, 14, z0 - 10), Vector3(0, 4, z0 + 50)],
			[Vector3(-60, 40, 60), Vector3(0, 20, 110)],
		]
		camera.target = null
		for k in views.size():
			camera.global_position = views[k][0]
			camera.look_at(views[k][1])
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("user://shot_view%d.png" % k)
		get_tree().quit()
		return
	for d in _destructibles:
		if (d as Destructible).is_displaced():
			print("  erken hareket: ", (d as Destructible).material_kind, " ", d.start_pos.round(), " -> ", d.global_position.round())
	_launch(10.0)
	for i in 30:
		await get_tree().create_timer(1.0).timeout
		var moved := 0
		for d in _destructibles:
			if (d as Destructible).is_displaced():
				moved += 1
		if "--shots" in OS.get_cmdline_user_args() and i in [1, 5, 9, 10, 12]:
			get_viewport().get_texture().get_image().save_png("user://shot_%02d.png" % i)
		print("t=%2d  kaya=%s  hız=%.0f km/sa  yıkılan=%d  fps=%d" % [i + 1, current.global_position.round(), current.speed_kmh(), moved, Engine.get_frames_per_second()])
	get_tree().quit()


# --- Dünya ---------------------------------------------------------------

func _build_environment() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sky_mat := PanoramaSkyMaterial.new()
	sky_mat.panorama = load("res://assets/hdri/sky_2k.hdr")
	sky_mat.energy_multiplier = 1.0
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_256
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.8
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.05
	env.fog_enabled = true
	env.fog_light_color = Color(0.72, 0.78, 0.86)
	env.fog_density = 0.0005
	env.fog_aerial_perspective = 0.6
	env.fog_sky_affect = 0.15
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.05
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38, 145, 0)
	sun.light_energy = 1.6
	sun.light_color = Color(1.0, 0.96, 0.9)
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_max_distance = 220.0
	sun.shadow_blur = 1.2
	# Düşük grafik (zayıf cihaz / yazılım render testi): gölgeleri kapat
	if "--lowgfx" in OS.get_cmdline_user_args():
		sun.shadow_enabled = false
		get_viewport().msaa_3d = Viewport.MSAA_DISABLED
	add_child(sun)


func _build_targets() -> void:
	var z0 := RAMP_FLAT + RAMP_SLOPE + RAMP_RUNOUT
	var brick := WorldBuilder.pbr("red_brick_03", 0.45)
	var concrete := WorldBuilder.pbr("rough_concrete", 0.3, Color(0.92, 0.9, 0.86))
	var concrete_dark := WorldBuilder.pbr("rough_concrete", 0.3, Color(0.7, 0.68, 0.64))
	var wood := WorldBuilder.pbr("wood_planks", 0.7, Color.WHITE, false)

	# Tuğla duvar (şaşırtmalı örgü)
	_brick_wall(Vector3(0, 0, z0 + 8), 20.0, 6, brick)

	# Sütunlu kalıntı: iki sıra sütun + üst kirişler (domino etkisi)
	for side in [-1.0, 1.0]:
		var zs := [z0 + 26.0, z0 + 33.0, z0 + 40.0, z0 + 47.0]
		for z in zs:
			_add(Vector3(side * 6.0, 2.75, z), Vector3(0.9, 5.5, 0.9), concrete, "concrete", 2000.0, "cylinder")
		for k in 2:
			var zc: float = (zs[k * 2] + zs[k * 2 + 1]) * 0.5
			_add(Vector3(side * 6.0, 5.5 + 0.35, zc), Vector3(1.1, 0.7, 8.2), concrete_dark, "concrete", 1800.0)

	# Sandık piramidi
	var c := 1.2
	for row in 4:
		for i in 4 - row:
			var x := (i - (3 - row) * 0.5) * (c + 0.02)
			_add(Vector3(x, c * 0.5 + row * c + 0.01 * row, z0 + 36.0), Vector3.ONE * c, wood, "wood", 350.0)

	# Varil kümesi
	var barrel := StandardMaterial3D.new()
	barrel.albedo_color = Color(0.45, 0.12, 0.08)
	barrel.metallic = 0.6
	barrel.roughness = 0.45
	for i in 8:
		var p := Vector3(14.0 + (i % 3) * 1.0, 0.65, z0 + 18.0 + (i / 3) * 1.0)
		_add(p, Vector3(0.85, 1.3, 0.85), barrel, "metal", 220.0, "cylinder")

	# Binalar
	_building(Vector3(-9.0, 0, z0 + 58.0), 4, 4, 4, concrete, brick)
	_building(Vector3(9.5, 0, z0 + 64.0), 5, 3, 3, concrete_dark, concrete)
	_building(Vector3(0.0, 0, z0 + 88.0), 3, 3, 6, concrete, concrete_dark)


func _add(pos: Vector3, size: Vector3, mat: Material, kind: String, density: float, shape := "box") -> Destructible:
	var d := Destructible.new()
	d.setup(size, mat, kind, density, shape)
	d.position = pos
	add_child(d)
	return d


func _brick_wall(center: Vector3, length: float, rows: int, mat: Material) -> void:
	var bw := 2.0
	var bh := 0.8
	var bd := 0.7
	var count := int(length / bw)
	for r in rows:
		var offset := 0.5 * bw if r % 2 == 1 else 0.0
		var n := count - (1 if r % 2 == 1 else 0)
		for i in n:
			var x := -length * 0.5 + bw * 0.5 + i * bw + offset
			_add(center + Vector3(x, bh * 0.5 + r * (bh + 0.002), 0), Vector3(bw - 0.01, bh, bd), mat, "brick", 1900.0)


## Panellerden oluşan çok katlı bina: her kat 2 sıra duvar paneli + 4 döşeme parçası.
func _building(base: Vector3, cx: int, cz: int, floors: int, wall_mat: Material, accent_mat: Material) -> void:
	var p := 1.5
	var t := 0.35
	var slab := 0.3
	var w := cx * p
	var d := cz * p
	var floor_h := 2.0 * p + slab
	for f in floors:
		var y0 := f * floor_h + 0.002 * f
		for row in 2:
			var y := y0 + p * 0.5 + row * p
			var mat := accent_mat if row == 0 and f == 0 else wall_mat
			# Ön/arka duvarlar (köşeleri kapsar)
			for i in cx:
				var window := row == 1 and i % 2 == 1 and f > 0
				for s in [-1.0, 1.0]:
					if window and s > 0.0:
						continue
					_add(base + Vector3(-w * 0.5 + p * 0.5 + i * p, y, s * (d * 0.5 - t * 0.5)),
						Vector3(p - 0.01, p - 0.004, t), mat, "concrete", 1300.0)
			# Yan duvarlar (köşeler arası)
			var inner := d - 2.0 * t
			var wz := inner / cz
			for k in cz:
				var window_side := row == 1 and k % 2 == 1 and f > 0
				for s in [-1.0, 1.0]:
					if window_side:
						continue
					_add(base + Vector3(s * (w * 0.5 - t * 0.5), y, -inner * 0.5 + wz * 0.5 + k * wz),
						Vector3(t, p - 0.004, wz - 0.01), mat, "concrete", 1300.0)
		# Orta kolon: döşeme parçalarının iç köşelerini taşır
		_add(base + Vector3(0, y0 + p, 0), Vector3(0.7, 2.0 * p - 0.004, 0.7), accent_mat, "concrete", 1600.0)
		# Döşeme: 2x2 parça
		var sy := y0 + 2.0 * p + slab * 0.5 + 0.001
		for a in 2:
			for b in 2:
				_add(base + Vector3((a - 0.5) * w * 0.5, sy, (b - 0.5) * d * 0.5),
					Vector3(w * 0.5 - 0.01, slab, d * 0.5 - 0.01), wall_mat, "concrete", 1500.0)


func _scatter_boulders() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var mat := WorldBuilder.pbr("rock_boulder_dry", 0.25, Color(0.85, 0.82, 0.78), false)
	for i in 26:
		var side := -1.0 if i % 2 == 0 else 1.0
		var r := rng.randf_range(0.8, 3.5)
		var pos := Vector3(side * rng.randf_range(16.0, 75.0), r * 0.35, rng.randf_range(-20.0, 330.0))
		var body := StaticBody3D.new()
		body.position = pos
		body.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, 0)
		var mi := MeshInstance3D.new()
		mi.mesh = WorldBuilder.rock_mesh(r, 100 + i)
		mi.material_override = mat
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = r * 0.9
		cs.shape = sh
		body.add_child(cs)
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
	_rock_seed += 1
	rock.setup(r, _rock_seed)
	add_child(rock)
	aim_x = clampf(aim_x, -_aim_limit(), _aim_limit())
	rock.global_position = Vector3(aim_x, RAMP_H + r * 0.95, RAMP_FLAT * 0.5)
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

func _process(delta: float) -> void:
	_stat_timer -= delta
	if _stat_timer <= 0.0:
		_stat_timer = 0.4
		var moved := 0
		for d in _destructibles:
			if (d as Destructible).is_displaced():
				moved += 1
		var spd := current.speed_kmh() if current else 0.0
		hud.set_stats(spd, moved, _destructibles.size())
	# Haritadan düşen kayaları temizle
	for rock in rocks.duplicate():
		if is_instance_valid(rock) and rock.global_position.y < -50.0:
			rocks.erase(rock)
			rock.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
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
