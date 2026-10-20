extends Node3D
## Ana sahne: düz test haritası, fırlatıcı istasyonları, mermi seçimi, engeller,
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
const MAPS := {"test": "TEST ALANI", "castle": "KALE"}

## Sahne yeniden yüklendiğinde de korunur
static var map_name := "test"

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


func _ready() -> void:
	randomize()
	Destructible.spawned = 0
	_build_environment()
	WorldBuilder.build_ground(self)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--ramp="):
			RampLauncher.type_index = int(a.get_slice("=", 1))
		if a.begins_with("--map="):
			map_name = a.get_slice("=", 1)
	_build_launchers()
	if map_name == "castle":
		_build_castle()
	else:
		_build_targets()
	_scatter_decor()
	_scatter_trees()

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
	hud.map_pressed.connect(func() -> void:
		var keys := MAPS.keys()
		map_name = keys[(keys.find(map_name) + 1) % keys.size()]
		Engine.time_scale = 1.0
		Sfx.set_slow_motion(false)
		get_tree().reload_current_scene())

	_destructibles = get_tree().get_nodes_in_group("destructible")
	var args := OS.get_cmdline_user_args()
	if "--lowgfx" in args:
		quality = 0
	elif not OS.has_feature("mobile"):
		quality = 2
	_apply_quality(quality)
	_select_launcher(0)
	if "--autotest" in args:
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
		1:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			sun.directional_shadow_max_distance = 140.0
			RenderingServer.directional_shadow_atlas_set_size(2048, true)
			vp.msaa_3d = Viewport.MSAA_2X
			vp.scaling_3d_scale = 0.85
			env.glow_enabled = true
			Destructible.max_spawned = 100
		2:
			sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			sun.directional_shadow_max_distance = 220.0
			RenderingServer.directional_shadow_atlas_set_size(4096, true)
			vp.msaa_3d = Viewport.MSAA_2X
			vp.scaling_3d_scale = 1.0
			env.glow_enabled = true
			Destructible.max_spawned = 160


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
	_add_launcher(Trebuchet.new(), Vector3(-42, 0, 120))
	_add_launcher(Slingshot.new(), Vector3(42, 0, 140))
	_add_launcher(AirCannon.new(), Vector3(-22, 0, 160))
	_add_launcher(RocketSled.new(), Vector3(22, 0, 120))
	if map_name != "castle":
		_add_launcher(WreckingCrane.new(), Vector3(30, 0, RAMP_FLAT + RAMP_SLOPE + RAMP_RUNOUT + 105.0))


func _add_launcher(l: Launcher, pos: Vector3) -> void:
	l.position = pos
	add_child(l)
	l.fired.connect(_on_fired)
	launchers.append(l)


## Her fırlatıcının önünde kendi düzenli hedef şeridi:
##   RAMPA (x=0)      : bariyer sırası -> tuğla duvar -> eski bina -> panel apartman
##   TOP (x=-22)      : sandık piramidi + variller -> taş yığını -> trafo binası
##   MANCINIK (x=-42) : dönen pervane -> konteyner yığını -> kule blok
##   SAPAN (x=42)     : sarkaç -> konteyner yığını -> fabrika
func _build_targets() -> void:
	var z0 := RAMP_FLAT + RAMP_SLOPE + RAMP_RUNOUT

	# RAMPA şeridi
	for i in 5:
		_prop("jersey", Vector3(-8.0 + i * 4.0, 0, z0 + 8.0), 0.0, "concrete", 1800.0)
	_brick_wall(Vector3(0, 0, z0 + 22.0), 18.2, 4, WorldBuilder.pbr("red_brick_03", 0.45))
	_vehicle("sedan", 4.6, 1150.0, Vector3(-3.2, 0, z0 + 36.0), 80.0)
	_vehicle("lada", 4.1, 1050.0, Vector3(3.0, 0, z0 + 38.0), -100.0)
	_building("oldbuilding", "brick", Vector3(0.0, 0, z0 + 50.0), 0.0)
	_structure(Structures.wood_tower(), Vector3(0.0, 0, z0 + 76.0), 0.0)
	_building("soviet", "concrete", Vector3(0.0, 0, z0 + 105.0), 90.0)

	# TOP şeridi
	var cx := -22.0
	for row in 4:
		for i in 4 - row:
			_prop("crate", Vector3(cx - 1.9 + (i + row * 0.5) * 1.25, row * 0.47, z0 + 18.0), 90.0, "wood", 45.0)
	for i in 12:
		_prop("barrel", Vector3(cx - 1.0 + (i % 4) * 0.64, (i / 8) * 0.9, z0 + 26.0 + ((i % 8) / 4) * 0.64), 0.0, "metal", 60.0)
	_stone_pile(Vector3(cx, 0, z0 + 37.0))
	_structure(Structures.greenhouse(), Vector3(cx, 0, z0 + 46.0), 0.0)
	_building("booth", "brick", Vector3(cx, 0, z0 + 60.0), 90.0)
	_prop("log_pile", Vector3(cx + 7.0, 0, z0 + 30.0), 20.0, "wood", 2600.0)

	# MANCINIK şeridi
	var tx := -42.0
	var mill := Windmill.new()
	mill.position = Vector3(tx, 0, z0 + 16.0)
	add_child(mill)
	_container_stack(Vector3(tx, 0, z0 + 40.0))
	_structure(Structures.water_tower(), Vector3(tx, 0, z0 + 60.0), 0.0)
	_building("tower", "concrete", Vector3(tx, 0, z0 + 82.0), 0.0)

	# SAPAN şeridi
	var sx := 42.0
	var pend := Pendulum.new()
	pend.position = Vector3(sx, 0, z0 + 12.0)
	add_child(pend)
	_girder_pile(Vector3(sx, 0, z0 + 28.0))
	_container_stack(Vector3(sx, 0, z0 + 42.0))
	_vehicle("van", 4.2, 1250.0, Vector3(sx - 3.0, 0, z0 + 56.0), 95.0)
	_vehicle("truck", 6.0, 6500.0, Vector3(sx + 3.5, 0, z0 + 58.0), -85.0)
	_building("factory", "brick", Vector3(sx, 0, z0 + 80.0), -90.0)

	# ROKET şeridi (x=22): elektrik hattı -> beton köprü -> konteyner yığını
	var rx := 22.0
	_power_line(Vector3(rx - 9.0, 0, z0 + 14.0), Vector3(rx + 9.0, 0, z0 + 14.0), 3)
	_structure(Structures.bridge(), Vector3(rx, 0, z0 + 34.0), 0.0)
	_container_stack(Vector3(rx, 0, z0 + 58.0))


## Dev kale haritası: yalnız kale (+ önünde birkaç bariyer)
func _build_castle() -> void:
	var z0 := RAMP_FLAT + RAMP_SLOPE + RAMP_RUNOUT
	var f := Fortress.new()
	f.setup_castle()
	f.position = Vector3(0, 0, z0 + 50.0)
	add_child(f)
	_buildings.append(f)


func _structure(st: BlockStructure, pos: Vector3, rot_y: float) -> void:
	st.position = pos
	st.rotation_degrees.y = rot_y
	add_child(st)
	_buildings.append(st)


## Araç: dışbükey örtü, gerçek kütle. Modelle gelen zemin/yol düzlemleri atılır.
func _vehicle(model_name: String, length: float, body_mass: float, pos: Vector3, rot_y: float) -> void:
	var d := Destructible.new()
	var visual := Models.instance(model_name)
	for mi: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		var b := mi.mesh.get_aabb()
		if b.size.y < 0.02 * maxf(b.size.x, b.size.z):
			mi.get_parent().remove_child(mi)
			mi.free()
	d.add_child(visual)
	Models.fit(visual, length, "length")
	var pts := PackedVector3Array()
	for mi: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		var hull := mi.mesh.create_convex_shape(true, true) as ConvexPolygonShape3D
		var xf := Models._relative_xform(d, mi)
		for p in hull.points:
			pts.append(xf * p)
	d.add_hull(pts)
	d.configure("metal", body_mass, 0.7)
	d.position = pos + Vector3.UP * 0.02
	d.rotation_degrees.y = rot_y
	add_child(d)


## Çelik I-kiriş yığını (4 + 3 + 2): ağır, kırılmaz, birbirinin üstünden kayar
## Elektrik hattı: n direk ve aralarında sarkık kablolar. Direklerden biri kırılınca
## ona bağlı kablolar kopar (gizlenir) ve kopma sesi çıkar.
func _power_line(a: Vector3, b: Vector3, n: int) -> void:
	var poles: Array[BlockStructure] = []
	for i in n:
		var p := Structures.power_pole()
		_structure(p, a.lerp(b, float(i) / (n - 1)), 0.0)
		poles.append(p)
	var cable_mat := StandardMaterial3D.new()
	cable_mat.albedo_color = Color(0.08, 0.08, 0.08)
	cable_mat.roughness = 0.6
	for i in n - 1:
		for side in [-1.0, 1.0]:
			var p0 := poles[i].position + Vector3(0, 8.75, side * 1.0)
			var p1 := poles[i + 1].position + Vector3(0, 8.75, side * 1.0)
			# Zincir eğrisi yaklaşığı: parabolik sarkma, kısa silindir parçaları
			var im := ImmediateMesh.new()
			im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, cable_mat)
			for k in 17:
				var t := k / 16.0
				im.surface_add_vertex(p0.lerp(p1, t) + Vector3.DOWN * 1.2 * 4.0 * t * (1.0 - t))
			im.surface_end()
			var mi := MeshInstance3D.new()
			mi.mesh = im
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			for pole in [poles[i], poles[i + 1]]:
				pole.broke.connect(func(_b) -> void:
					if mi.visible:
						mi.visible = false
						Sfx.play("chain", p0.lerp(p1, 0.5), 2.0))


func _girder_pile(base: Vector3) -> void:
	var mat := BlockStructure.material("steel")
	var size := Vector3(7.0, 0.5, 0.36)
	for row in 3:
		for i in 4 - row:
			var d := Destructible.new()
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = size - Vector3.ONE * 0.01
			bm.material = mat
			mi.mesh = bm
			d.add_child(mi)
			d.add_box(size)
			d.configure("metal", size.x * size.y * size.z * 7850.0 * 0.3, 0.45)
			d.position = base + Vector3(0, size.y * 0.5 + row * (size.y + 0.005), (i - (3 - row) * 0.5) * 0.4)
			add_child(d)


## Çevre ağaçları: statik, gövde çarpışmalı, uzakta görünmez
func _scatter_trees() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 41
	for i in 26:
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos := Vector3(side * rng.randf_range(62.0, 110.0), 0, rng.randf_range(-20.0, 340.0))
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


## 3 tabanlı konteyner piramidi (3 + 2 + 1)
func _container_stack(base: Vector3) -> void:
	for row in 3:
		for i in 3 - row:
			_container(base + Vector3((i - (2 - row) * 0.5) * 2.62, row * 2.6, 0), 0.0)


## Taş yığını: büyükler altta, küçükler üstte
func _stone_pile(center: Vector3) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for layer in 3:
		var n := 6 - layer * 2
		for i in n:
			var a := TAU * i / n + layer * 0.5
			var r := 1.8 - layer * 0.7
			_stone(center + Vector3(cos(a) * r, layer * 0.9, sin(a) * r), 1.3 - layer * 0.3, rng)


func _building(model_name: String, inner: String, pos: Vector3, rot_y: float) -> void:
	var b := Building.new()
	b.setup(model_name, inner)
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
		"log_pile":
			Models.fit(visual, 3.2, "length")
	var xf := visual.transform
	var pts := PackedVector3Array()
	for p in Models.hull_points(model_name, visual):
		pts.append(xf * p)
	d.add_hull(pts)
	d.configure(kind, body_mass, 0.5 if kind == "metal" else 0.8)
	d.position = pos + Vector3.UP * 0.01
	d.rotation_degrees.y = rot_y
	add_child(d)
	return d


func _container(pos: Vector3, rot_y: float) -> void:
	var d := Destructible.new()
	var visual := Models.instance("container")
	d.add_child(visual)
	Models.fit(visual, 6.06, "length")
	var b := Models.local_aabb(visual)
	var size := b.size * visual.scale.x
	# Konteyner uzun ekseni X olsun (atış yönüne dik duvar)
	if size.z > size.x:
		visual.rotation_degrees.y = 90.0
		visual.position = Vector3(visual.position.z, visual.position.y, -visual.position.x)
		size = Vector3(size.z, size.y, size.x)
	d.add_box(size, Vector3(0, size.y * 0.5, 0))
	d.configure("metal", 3800.0, 0.6)
	d.position = pos + Vector3.UP * 0.01
	d.rotation_degrees.y = rot_y
	add_child(d)


func _stone(pos: Vector3, size: float, rng: RandomNumberGenerator) -> void:
	var d := Destructible.new()
	var mesh: Mesh = load("res://assets/rocks/pebble_%d.res" % rng.randi_range(0, 3))
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.scale = Vector3.ONE * size
	d.add_child(mi)
	var hull := mesh.create_convex_shape(true, true) as ConvexPolygonShape3D
	var pts := PackedVector3Array()
	for p in hull.points:
		pts.append(p * size)
	d.add_hull(pts)
	var e := mesh.get_aabb().size * size
	d.configure("stone", e.x * e.y * e.z * 0.5 * 2600.0)
	d.position = pos + Vector3.UP * (e.y * 0.5 + 0.02)
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


## Statik dekor: büyük, kapalı tabanlı kayalar (uzakta gölgesiz, görünürlük mesafesi sınırlı).
func _scatter_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var meshes := ["granite", "basalt", "mossy", "sandstone", "river_1", "river_2"]
	for i in 18:
		var side := -1.0 if i % 2 == 0 else 1.0
		var size := rng.randf_range(2.0, 7.0)
		var pos := Vector3(side * rng.randf_range(60.0, 95.0), 0, rng.randf_range(-10.0, 330.0))
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


func _on_fire_pressed() -> void:
	if launcher.is_ready():
		launcher.fire()
	elif launcher.secondary():
		hud.set_ready(false, "", true)
	else:
		_reload()


func _on_fired(p: Projectile) -> void:
	current = p
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
	if "--shots" in args:
		await _shots()
		get_tree().quit()
		return
	for a in args:
		if a.begins_with("--siege-synth="):
			await _siege_synth(int(a.get_slice("=", 1)), 12.0e6)
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
	elif launcher is WreckingCrane:
		var wc := launcher as WreckingCrane
		var vs := get_viewport().get_visible_rect().size
		wc.press()
		for k in 20:
			wc.drag(Vector2(0, vs.y * 0.02), vs)
		print("Vinç: ", wc.info())
		wc.release(0.0)
		for a in args:
			if a.begins_with("--cut="):
				for f in int(float(a.get_slice("=", 1)) * 60.0):
					await get_tree().physics_frame
				print("Zincir kesildi, hız %.0f km/sa" % current.speed_kmh())
				_on_fire_pressed()
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
	print("TOPLAM işlem süresi (20 sn simülasyon): %.2f sn" % ((Time.get_ticks_usec() - t0) / 1e6))
	get_tree().quit()


## Yapay kuşatma: kalenin dış yüzündeki rastgele alçak bloklara E enerjili darbe
func _siege_synth(n: int, energy: float) -> void:
	var f: Building = _buildings[0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var center := f.global_position + Vector3.UP * 5.0
	for i in n:
		var cands := f.chunks.filter(func(c: Destructible) -> bool: return c.intact and c.layer <= 3)
		if cands.is_empty():
			break
		# Dışa yakın olanlardan seç (merkeze en uzak %40)
		cands.sort_custom(func(a: Destructible, b: Destructible) -> bool: return a.global_position.distance_squared_to(center) > b.global_position.distance_squared_to(center))
		var t: Destructible = cands[rng.randi() % maxi(1, int(cands.size() * 0.4))]
		var dir := (center - t.global_position)
		dir.y = 0
		Building.strike(get_world_3d(), t.global_position - dir.normalized() * 1.5, energy, dir.normalized())
		for k in 60 * 4:
			await get_tree().physics_frame
		print("darbe %2d  sağlam blok %%%d" % [i + 1, roundi(f.intact_ratio() * 100.0)])


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
		await get_tree().physics_frame
		launcher.fire()
		for f in 60 * 14:
			await get_tree().physics_frame
		var b: Building = _buildings[0]
		var awake := 0
		for c in b.chunks:
			if not c.intact and not c.freeze:
				awake += 1
		print("atış %2d  sağlam blok %%%d  hareketli blok=%d" % [i + 1, roundi(b.intact_ratio() * 100.0), awake])
	print("TOPLAM işlem: %.1f sn (%d atış × 14 sn)" % [(Time.get_ticks_usec() - t0) / 1e6, n])


func _shots() -> void:
	var z0 := RAMP_FLAT + RAMP_SLOPE + RAMP_RUNOUT
	if map_name == "castle":
		camera.target = null
		var cviews := [[Vector3(-60, 30, 150), Vector3(0, 8, z0 + 50)], [Vector3(0, 8, 175), Vector3(0, 10, z0 + 50)]]
		for k in cviews.size():
			camera.global_position = cviews[k][0]
			camera.look_at(cviews[k][1])
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("user://shot_castle%d.png" % k)
		for i in 8:
			var f: Building = _buildings[0]
			var cands := f.chunks.filter(func(c: Destructible) -> bool: return c.intact and c.layer <= 2 and c.global_position.z < f.global_position.z - 20.0)
			var t: Destructible = cands[(i * 7) % cands.size()]
			Building.strike(get_world_3d(), t.global_position + Vector3(0, 0, -1.5), 12.0e6, Vector3(0, 0, 1))
			for k in 3:
				await get_tree().physics_frame
		for k in 30:
			await get_tree().physics_frame
		camera.global_position = cviews[0][0]
		camera.look_at(cviews[0][1])
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://shot_castle2.png")
		return
	var views := [
		[Vector3(14, 8, z0 + 26), Vector3(0, 5, z0 + 62)],
		[Vector3(-27, 12, z0 + 38), Vector3(-42, 9, z0 + 62)],
		[Vector3(-11, 5, z0 + 35), Vector3(-22, 2, z0 + 47)],
		[Vector3(31, 6, z0 + 38), Vector3(42, 2, z0 + 56)],
		[Vector3(12, 9, 110), Vector3(22, 1, 150)],
		[Vector3(6, 8, z0 + 2), Vector3(22, 5, z0 + 30)],
		[Vector3(50, 16, z0 + 78), Vector3(14, 12, z0 + 105)],
	]
	camera.target = null
	for k in views.size():
		camera.global_position = views[k][0]
		camera.look_at(views[k][1])
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://shot_view%d.png" % k)
	# Yıkım: ahşap kule, su kulesi ayakları, sera, eski bina
	Building.strike(get_world_3d(), Vector3(0, 4, z0 + 74), 0.4e6, Vector3(0.3, 0, 1))
	Building.strike(get_world_3d(), Vector3(-42, 3, z0 + 57.5), 4.0e6, Vector3(0, 0, 1))
	Building.strike(get_world_3d(), Vector3(-22, 1.5, z0 + 43.5), 0.2e6, Vector3(0, 0, 1))
	Building.strike(get_world_3d(), Vector3(0, 3, z0 + 46), 8.0e6, Vector3(0, 0.1, 1))
	for f in 45:
		await get_tree().physics_frame
	for k in 3:
		camera.global_position = views[k][0]
		camera.look_at(views[k][1])
		await get_tree().process_frame
		await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("user://shot_break%d.png" % k)
