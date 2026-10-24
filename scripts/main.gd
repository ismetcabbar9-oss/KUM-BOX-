extends Node3D
## Ana sahne: kale haritası, fırlatıcı istasyonları, mermi seçimi, engeller,
## dokunmatik girdi, grafik kalitesi ve otomatik test.

const RAMP_W := 14.0
const RAMP_H := 55.0
const RAMP_FLAT := 14.0
const RAMP_SLOPE := 150.0
const RAMP_RUNOUT := 25.0
const MAX_PROJECTILES := 5
const SIZES := [
	{"name": "ÇOK KÜÇÜK", "k": 0.5},
	{"name": "KÜÇÜK", "k": 0.75},
	{"name": "ORTA", "k": 1.0},
	{"name": "BÜYÜK", "k": 1.4},
	{"name": "DEV", "k": 2.2},
]
const QUALITY := ["DÜŞÜK", "ORTA", "YÜKSEK"]
const MAPS := {"castle": "KALE"}

## Sahne yeniden yüklendiğinde de korunur
static var map_name := "castle"

var camera: Camera3D
var hud: CanvasLayer
var sun: DirectionalLight3D
var env: Environment
var launchers: Array[Launcher] = []
var launcher: Launcher
var projectiles: Array = []
var current: Projectile
var ammo_index := 0
var size_index := 2
var quality := 1
var _touches := {}
var _stat_timer := 0.0
var _destructibles: Array[Node] = []
var _buildings: Array[Building] = []
var crew: Crew
var castle: Castle
var _soldiers: Array[Soldier] = []


func _ready() -> void:
	var t_start := Time.get_ticks_msec()
	randomize()
	Destructible.spawned = 0
	_build_environment()
	WorldBuilder.build_ground(self)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ramp="):
			RampLauncher.type_index = int(a.get_slice("=", 1))
	_build_launchers()
	_build_castle()
	_scatter_decor()
	_scatter_trees()
	crew = Crew.new()
	add_child(crew)

	camera = preload("res://scripts/game_camera.gd").new()
	add_child(camera)
	camera.current = true

	hud = preload("res://scripts/hud.gd").new()
	add_child(hud)
	hud.fire_pressed.connect(_on_fire_pressed)
	hud.launcher_pressed.connect(func() -> void: _select_launcher((launchers.find(launcher) + 1) % launchers.size()))
	hud.ammo_pressed.connect(func() -> void:
		ammo_index = (ammo_index + 1) % Projectile.ORDER.size()
		_reload_if_waiting())
	hud.size_pressed.connect(func() -> void:
		size_index = (size_index + 1) % SIZES.size()
		_reload_if_waiting())
	hud.reset_pressed.connect(func() -> void:
		Engine.time_scale = 1.0
		Sfx.set_slow_motion(false)
		get_tree().reload_current_scene())
	hud.slowmo_toggled.connect(func(on: bool) -> void:
		Engine.time_scale = 0.3 if on else 1.0
		Sfx.set_slow_motion(on))
	hud.option_pressed.connect(func() -> void:
		launcher.cycle_option()
		_reload_if_waiting())
	hud.quality_pressed.connect(func() -> void: _apply_quality((quality + 1) % QUALITY.size()))
	hud.set_map_name(MAPS[map_name])

	_destructibles = get_tree().get_nodes_in_group("destructible")
	var args := OS.get_cmdline_user_args()
	if "--lowgfx" in args:
		quality = 0
	elif not OS.has_feature("mobile"):
		quality = 2
	_apply_quality(quality)
	# Rampa tepesindeki mancınıkla başla
	_select_launcher(1)
	if "--autotest" in args:
		print("Sahne kurulumu: %d ms" % (Time.get_ticks_msec() - t_start))
		_autotest()



# --- Grafik kalitesi -------------------------------------------------------

func _apply_quality(q: int) -> void:
	quality = q
	hud.set_quality_name(QUALITY[q])
	var vp := get_viewport()
	match q:
		0:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			sun.directional_shadow_max_distance = 70.0
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			vp.msaa_3d = Viewport.MSAA_DISABLED
			vp.scaling_3d_scale = 0.7
			env.glow_enabled = false
			Destructible.max_spawned = 40
			BrickPool.limit = 400
			BrickPool.active_limit = 150
		1:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 140.0
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			vp.msaa_3d = Viewport.MSAA_2X
			vp.scaling_3d_scale = 0.85
			env.glow_enabled = true
			Destructible.max_spawned = 100
			BrickPool.limit = 700
			BrickPool.active_limit = 280
		2:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 220.0
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			vp.msaa_3d = Viewport.MSAA_2X
			vp.scaling_3d_scale = 1.0
			env.glow_enabled = true
			Destructible.max_spawned = 160
			BrickPool.limit = 1200
			BrickPool.active_limit = 450


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
	sun.shadow_enabled = true
	sun.shadow_blur = 1.2
	add_child(sun)


func _build_launchers() -> void:
	_add_launcher(RampLauncher.new(), Vector3.ZERO)
	# Güçlendirilmiş mancınık rampanın tepesinde, arkadaki beton platformda
	var deck_y := RAMP_H
	_build_deck(Vector3(0, 0, -24), deck_y)
	var tb := Trebuchet.new()
	tb.max_counterweight = 1200.0
	tb.counterweight_t = 295.0
	tb.yaw_deg = -2.5  # kapı değil, ön sur
	tb.base_radius = 1.0
	# Uzun kol: karşı ağırlık en fazla serbest düşüşle iner; menzili kol oranı belirler
	tb.pivot_h = 15.0
	tb.l_long = 23.0
	tb.release_deg = 55.0  # yatık yörünge: yüksek platformdan sur yüzüne doğrudan
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--cw="):
			tb.counterweight_t = float(a.get_slice("=", 1))
	_add_launcher(tb, Vector3(0, deck_y, -24))
	_add_launcher(Slingshot.new(), Vector3(42, 0, 140))
	_add_launcher(AirCannon.new(), Vector3(-22, 0, 160))
	_add_launcher(RocketSled.new(), Vector3(22, 0, 120))


## Rampa tepesinin arkasında mancınık platformu: beton tabliye + dört ayak
func _build_deck(center: Vector3, top: float) -> void:
	var mat := WorldBuilder.pbr("rough_concrete", 0.3, Color(0.8, 0.79, 0.76))
	var size := Vector3(18, 1.2, 22)
	Launcher.beam(self, size, Transform3D(Basis.IDENTITY, center + Vector3(0, top - size.y * 0.5, 0)), mat)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var h := top - size.y
			Launcher.beam(self, Vector3(1.6, h, 1.6), Transform3D(Basis.IDENTITY, center + Vector3(sx * 7.5, h * 0.5, sz * 9.0)), mat)


func _add_launcher(l: Launcher, pos: Vector3) -> void:
	l.position = pos
	add_child(l)
	l.fired.connect(_on_fired)
	launchers.append(l)


## İç içe dev kale + askerler
func _build_castle() -> void:
	var z0 := RAMP_FLAT + RAMP_SLOPE + RAMP_RUNOUT
	castle = Castle.new()
	castle.position = Vector3(0, 0, z0 + 100.0)
	add_child(castle)
	castle.build()
	for p in castle.parts:
		_buildings.append(p)
	Projectile.water_zones = castle.world_water()
	for spot in castle.soldier_spots:
		var s := Soldier.new()
		s.setup()
		s.role = spot[2]
		add_child(s)
		s.global_transform = Transform3D(Basis(Vector3.UP, spot[1]), castle.to_global(spot[0]))
		_soldiers.append(s)


## Çevre ağaçları: statik, gövde çarpışmalı, uzakta görünmez
func _scatter_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in 26:
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos := Vector3(side * rng.randf_range(125.0, 185.0), 0, rng.randf_range(-20.0, 420.0))
		var body := StaticBody3D.new()
		var visual := Models.instance("pine_b")
		body.add_child(visual)
		Models.fit(visual, rng.randf_range(9.0, 16.0), "height")
		Models.visibility(visual, 320.0)
		var trunk := CylinderShape3D.new()
		trunk.radius = 0.35
		trunk.height = 6.0
		var cs := CollisionShape3D.new()
		cs.shape = trunk
		cs.position.y = 3.0
		body.add_child(cs)
		body.position = pos
		body.rotation.y = rng.randf() * TAU
		add_child(body)


## Statik dekor: büyük, kapalı tabanlı kayalar (uzakta gölgesiz, görünürlük mesafesi sınırlı).
func _scatter_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var meshes := ["granite", "basalt", "mossy", "sandstone", "river_1", "river_2"]
	for i in 18:
		var side := -1.0 if i % 2 == 0 else 1.0
		var size := rng.randf_range(2.0, 7.0)
		var pos := Vector3(side * rng.randf_range(120.0, 170.0), 0, rng.randf_range(-10.0, 420.0))
		var body := StaticBody3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = load("res://assets/rocks/%s.res" % meshes[i % meshes.size()])
		mi.scale = Vector3.ONE * size
		mi.position.y = mi.mesh.get_aabb().size.y * size * 0.35
		mi.visibility_range_end = 280.0
		body.add_child(mi)
		var sh := SphereShape3D.new()
		sh.radius = size * 0.4
		var cs := CollisionShape3D.new()
		cs.shape = sh
		cs.position.y = size * 0.3
		body.add_child(cs)
		body.position = pos
		body.rotation.y = rng.randf() * TAU
		add_child(body)


# --- Fırlatıcı / mermi -------------------------------------------------------

func _select_launcher(i: int) -> void:
	if launcher and launcher.is_ready():
		_discard(launcher.loaded)
	launcher = launchers[i]
	hud.set_launcher_name(launcher.title)
	_reload()


func _reload_if_waiting() -> void:
	if launcher.is_ready():
		_discard(launcher.loaded)
	_reload()


## Uçuşta ayrılan mermiler (zincirli gülle, üçlü testere) listeye girer
func register_projectile(p: Projectile) -> void:
	projectiles.append(p)


func _discard(p: Projectile) -> void:
	projectiles.erase(p)
	if is_instance_valid(p):
		p.queue_free()
	launcher.loaded = null


func _reload() -> void:
	projectiles = projectiles.filter(func(p) -> bool: return is_instance_valid(p))
	while projectiles.size() >= MAX_PROJECTILES:
		var old = projectiles.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var ammo: String = Projectile.ORDER[ammo_index]
	if launcher.forced_ammo() != "":
		ammo = launcher.forced_ammo()
	var p := Projectile.new()
	p.setup(ammo, launcher.base_radius * SIZES[size_index]["k"], launcher.rolling())
	add_child(p)
	launcher.load_projectile(p)
	projectiles.append(p)
	current = p
	hud.set_ammo_name(p.display_name())
	hud.set_size_name(SIZES[size_index]["name"])
	hud.set_ready(true, launcher.hint(), launcher.uses_button())
	camera.follow(launcher.view_target, launcher.view_distance, launcher.heading())
	hud.set_option(launcher.option_label())
	camera.snap()
	crew.attach(launcher)


func _on_fire_pressed() -> void:
	if launcher.is_ready():
		launcher.fire()
	elif launcher.secondary():
		hud.set_ready(false, "", true)
	else:
		_reload()


func _on_fired(p: Projectile) -> void:
	current = p
	crew.on_fired()
	hud.set_ready(false, "", true)
	if launcher.flight_hint() != "":
		hud.set_flight(launcher.flight_hint())
	camera.follow(p, 14.0 + p.radius * 2.0)


# --- Döngü / girdi -------------------------------------------------------

func _count_displaced() -> int:
	var moved := 0
	for d in _destructibles:
		if not is_instance_valid(d) or (d as Destructible).is_displaced():
			moved += 1  # bölünen parça da yıkılmış sayılır
	return moved


func _process(delta: float) -> void:
	_stat_timer -= delta
	if _stat_timer <= 0.0:
		_stat_timer = 0.5
		var spd := current.speed_kmh() if is_instance_valid(current) else 0.0
		hud.set_stats(spd, _count_displaced(), _destructibles.size())
		var draws := int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
		hud.set_fps(int(Engine.get_frames_per_second()), "%d çizim" % draws)
	hud.set_info(launcher.info() if launcher.is_ready() else "")
	projectiles = projectiles.filter(func(p) -> bool: return is_instance_valid(p))
	for p in projectiles.duplicate():
		if p.global_position.y < -50.0:
			projectiles.erase(p)
			p.queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			if hud.is_over_ui(event.position):
				return
			_touches[event.index] = {"pos": event.position, "start": event.position, "t": Time.get_ticks_msec()}
			if _touches.size() == 1 and launcher.is_ready():
				launcher.press()
		elif _touches.has(event.index):
			var tch: Dictionary = _touches[event.index]
			_touches.erase(event.index)
			if _touches.is_empty() and launcher.is_ready():
				var dy: float = tch["start"].y - event.position.y
				var dt := maxf((Time.get_ticks_msec() - int(tch["t"])) / 1000.0, 0.05)
				var vh: float = get_viewport().get_visible_rect().size.y
				var swipe := 0.0
				if dy > vh * 0.08 and dt < 0.6:
					swipe = dy / vh / dt
				launcher.release(swipe)
	elif event is InputEventScreenDrag:
		if not _touches.has(event.index):
			return
		var prev: Vector2 = _touches[event.index]["pos"]
		_touches[event.index]["pos"] = event.position
		if _touches.size() == 1:
			if launcher.is_ready():
				launcher.drag(event.relative, get_viewport().get_visible_rect().size)
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


# --- Otomatik test -----------------------------------------------------------

## `godot --headless --path . --fixed-fps 60 -- --autotest [--launcher=N] [--ammo=ad] [--size=N]`
func _autotest() -> void:
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--ammo="):
			ammo_index = Projectile.ORDER.find(a.get_slice("=", 1))
		elif a.begins_with("--size="):
			size_index = int(a.get_slice("=", 1))
	var li := 0
	for a in args:
		if a.begins_with("--launcher="):
			li = int(a.get_slice("=", 1))
	_select_launcher(li)
	print("Hedef parça: %d   fırlatıcı: %s   mermi: %s (%.1f t, r=%.2f m)" % [
		_destructibles.size(), launcher.title, current.display_name(), current.mass / 1000.0, current.radius])
	for f in 90:
		await get_tree().physics_frame
	print("Fırlatmadan önce yerinden oynayan: ", _count_displaced())
	for part in castle.parts:
		print("  bölüm %s: %d blok" % [part.name, part.chunks.size()])
	for m in crew.men:
		print("  ekip: ", m.global_position, " görünür=", m.visible, " mod=", m.mode)
	for s in _soldiers:
		if not s.alive:
			print("  ölü asker: ", s.global_position)
	if "--drop-bridge" in args:
		castle.bridge.drop(Vector3.ZERO)
		for k in 8:
			for f in 30:
				await get_tree().physics_frame
			var bb := castle.bridge.body
			print("köprü açı=%.0f° uç=%s" % [rad_to_deg(castle.bridge._angle), bb.to_global(Vector3(0, 0, 8)).round()])
		get_tree().quit()
		return
	if "--shots2" in args:
		await _shots2()
		get_tree().quit()
		return
	if "--shots" in args:
		await _shots()
		get_tree().quit()
		return
	for a in args:
		if a.begins_with("--siege-synth="):
			await _siege_synth(int(a.get_slice("=", 1)), float(_arg("--energy=", "12e6")))
			get_tree().quit()
			return
		if a.begins_with("--siege="):
			await _siege(int(a.get_slice("=", 1)))
			get_tree().quit()
			return
	if launcher is Slingshot:
		# Gerçek dokunma akışı: bas -> geri çek (sürükle) -> bırak (kendiliğinden atar)
		var sl := launcher as Slingshot
		var vs := get_viewport().get_visible_rect().size
		sl.press()
		for k in 20:
			sl.drag(Vector2(0, 14), vs)
		print("Sapan gerilimi: ", sl.info())
		sl.release(0.0)
	else:
		launcher.fire()
	if "--trace" in args:
		for f in 150:
			await get_tree().physics_frame
			if f % 6 == 0:
				var extra := ""
				if launcher is Trebuchet:
					var t := launcher as Trebuchet
					extra = "kol açı=%.0f° kol ω=%.1f" % [rad_to_deg(t.arm.rotation.x), t.arm.angular_velocity.length()]
				print("  %.2fs  mermi=%s v=%s  %s" % [f / 60.0, current.global_position.snapped(Vector3.ONE * 0.1), current.linear_velocity.snapped(Vector3.ONE * 0.1), extra])
	var t0 := Time.get_ticks_usec()
	var sec_t := t0
	var max_speed := 0.0
	for i in 20:
		for f in Engine.physics_ticks_per_second:
			await get_tree().physics_frame
			if is_instance_valid(current):
				max_speed = maxf(max_speed, current.speed_kmh())
		var now := Time.get_ticks_usec()
		var broken := _buildings.filter(func(b: Building) -> bool: return b.broken).size()
		var released := 0
		for b in _buildings:
			for c in b.chunks:
				if not c.intact:
					released += 1
		var pos := current.global_position.round() if is_instance_valid(current) else Vector3.ZERO
		var spd := current.speed_kmh() if is_instance_valid(current) else 0.0
		print("t=%2d  mermi=%s  hız=%3.0f km/sa  yıkılan=%3d  kopan parça=%3d  hasarlı bina=%d  işlem=%4.0f ms/sn" % [
			i + 1, pos, spd, _count_displaced(), released, broken, (now - sec_t) / 1000.0])
		sec_t = now
	print("Azami hız: %.0f km/sa" % max_speed)
	print("Asma köprü: %s   sancak: %s" % ["DÜŞTÜ" if castle.bridge._down else "kalkık", "DÜŞTÜ" if castle.flag.down else "ayakta"])
	print("TOPLAM işlem süresi (20 sn simülasyon): %.2f sn" % ((Time.get_ticks_usec() - t0) / 1e6))
	get_tree().quit()


func _arg(prefix: String, default: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return default


## Yapay kuşatma: kalenin dış yüzündeki rastgele alçak bloklara E enerjili darbe
func _siege_synth(n: int, energy: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var center := castle.global_position + Vector3.UP * 5.0
	for i in n:
		var cands: Array = []
		for part in castle.parts:
			cands.append_array(part.chunks.filter(func(c: Destructible) -> bool: return c.intact and c.layer <= 3))
		if cands.is_empty():
			break
		# Dışa yakın olanlardan seç (merkeze en uzak %40)
		cands.sort_custom(func(a: Destructible, b: Destructible) -> bool: return a.global_position.distance_squared_to(center) > b.global_position.distance_squared_to(center))
		var t: Destructible = cands[rng.randi() % maxi(1, int(cands.size() * 0.4))]
		var dir := (center - t.global_position)
		dir.y = 0
		Building.strike(get_world_3d(), t.global_position - dir.normalized() * 1.5, energy, dir.normalized())
		var t0 := Time.get_ticks_usec()
		for k in 60 * 4:
			await get_tree().physics_frame
		var alive := _soldiers.filter(func(s: Soldier) -> bool: return s.alive).size()
		print("darbe %2d  sağlam blok %%%d  asker %d  işlem %d ms/4sn  %s" % [i + 1, roundi(castle.intact_ratio() * 100.0), alive, (Time.get_ticks_usec() - t0) / 1000, castle.pool.stats()])


## Kuşatma testi: N atış, her atıştan sonra kalenin sağlam blok oranı
func _siege(n: int) -> void:
	var t0 := Time.get_ticks_usec()
	var aims := [-4.5, 4.5, -2.5, 2.5, 0.0]
	for i in n:
		for p in projectiles.duplicate():
			if is_instance_valid(p) and p.launched:
				projectiles.erase(p)
				p.queue_free()
		if not launcher.is_ready():
			_reload()
		if launcher is RampLauncher:
			var r := launcher as RampLauncher
			r.aim = aims[i % aims.size()]
			r.drag(Vector2.ZERO, Vector2.ONE)
		elif launcher is Trebuchet:
			# Ön sur ve ön kuleler boyunca dağıt (kuleler ~±12°)
			var yaws := [-2.5, 6.0, -12.0, 12.0, -8.0, 9.0, -12.5, 12.5, -5.0, 3.0]
			var tb := launcher as Trebuchet
			tb.yaw_deg = yaws[i % yaws.size()]
			tb.drag(Vector2.ZERO, Vector2.ONE)
		await get_tree().physics_frame
		launcher.fire()
		for f in 60 * 14:
			await get_tree().physics_frame
			if "--trace" in OS.get_cmdline_user_args() and is_instance_valid(current) and (f % 60 == 0 or (f % 6 == 0 and current.global_position.z > 170.0 and f < 700)):
				print("   %ds mermi=%s v=%.0f km/sa" % [f / 60, current.global_position.round(), current.speed_kmh()])
		var awake := 0
		for part in castle.parts:
			for c in part.chunks:
				if not c.intact and not c.freeze:
					awake += 1
		var alive := _soldiers.filter(func(s: Soldier) -> bool: return s.alive).size()
		print("atış %2d  sağlam blok %%%d  hareketli blok=%d  asker %d" % [i + 1, roundi(castle.intact_ratio() * 100.0), awake, alive])
	print("TOPLAM işlem: %.1f sn (%d atış × 14 sn)" % [(Time.get_ticks_usec() - t0) / 1e6, n])


func _snap_views(views: Array, prefix: String) -> void:
	camera.target = null
	for k in views.size():
		camera.global_position = views[k][0]
		camera.look_at(views[k][1])
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://%s%d.png" % [prefix, k])


## Odaklı görüntüler: rampada itme (yandan) + kale ön surunda tuğla yıkımı
func _shots2() -> void:
	var z0 := RAMP_FLAT + RAMP_SLOPE + RAMP_RUNOUT
	_select_launcher(0)
	await get_tree().process_frame
	await _snap_views([[Vector3(9, 59.8, 5), Vector3(0, 56.0, 6)]], "s2_ramp_idle")
	launcher.fire()
	for k in 24:
		await get_tree().physics_frame
	await _snap_views([[Vector3(9, 59.8, 5.5), Vector3(0, 56.0, 6.5)]], "s2_ramp_push")
	var c := castle.global_position.z
	for k in 2:
		Building.strike(get_world_3d(), Vector3(-35, 5, c - 73.5), 7.0e6, Vector3(0, 0, 1))
		for f in 20:
			await get_tree().physics_frame
	await _snap_views([[Vector3(-30, 9, c - 95), Vector3(-35, 4, c - 72)]], "s2_bricks_fly")
	for f in 150:
		await get_tree().physics_frame
	await _snap_views([[Vector3(-30, 9, c - 95), Vector3(-35, 4, c - 72)]], "s2_bricks_rest")
	# Çatlaklar: kırmayan, yalnız hasar veren darbeler
	for k in 3:
		Building.strike(get_world_3d(), Vector3(35, 6, c - 74.0), 0.6e6, Vector3(0, 0, 1))
		for f in 10:
			await get_tree().physics_frame
	await _snap_views([[Vector3(38, 8, c - 86), Vector3(35, 6, c - 72)]], "s2_cracks")


func _shots() -> void:
	var c := castle.global_position.z
	var cviews := [
		[Vector3(-175, 85, c - 175), Vector3(0, 15, c)],
		[Vector3(0, 75, -48), Vector3(0, 30, c)],
		[Vector3(26, 12, c - 118), Vector3(0, 9, c - 78)],
		[Vector3(34, 74, c - 14), Vector3(0, 62, c + 20)],
		[Vector3(-28, 30, c - 82), Vector3(-56, 3, c - 42)],
		[Vector3(46, 44, c - 58), Vector3(0, 18, c - 4)],
	]
	await _snap_views(cviews, "shot_castle")
	_select_launcher(0)
	await get_tree().process_frame
	await _snap_views([[Vector3(9, 59.8, 5), Vector3(0, 56.0, 6)]], "shot_ramp_crew")
	castle.bridge.drop(Vector3.ZERO)
	for k in 150:
		await get_tree().physics_frame
	await _snap_views([cviews[2]], "shot_bridge_down")
	var front: Array = castle.parts[0].chunks.filter(func(ch: Destructible) -> bool: return ch.intact and ch.layer <= 2 and ch.global_position.z < c - 70.0)
	for i in 8:
		var t: Destructible = front[(i * 37) % front.size()]
		if not is_instance_valid(t):
			continue
		Building.strike(get_world_3d(), t.global_position + Vector3(0, 0, -1.5), 7.0e6, Vector3(0, 0, 1))
		for k in 20:
			await get_tree().physics_frame
	for k in 120:
		await get_tree().physics_frame
	await _snap_views([cviews[0], cviews[2]], "shot_castle_hit")
