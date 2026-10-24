extends Node
## Görsel efektler: toz bulutu havuzu ve kamera sarsıntısı sinyali.

signal shake_requested(amount: float)

const POOL_SIZE := 10
const RUBBLE_POOL := 8
const BRICK_POOL := 12
const MARK_POOL := 48
const BIG_DUST_POOL := 4

var _pool: Array[GPUParticles3D] = []
var _next := 0
var _cooldown := 0.0
var _rubble: Array[GPUParticles3D] = []
var _rubble_next := 0
var _soft_tex: GradientTexture2D
var _glass_mat: StandardMaterial3D
var _glass_pm: ParticleProcessMaterial
var _bricks: Array[GPUParticles3D] = []
var _bricks_next := 0
var _marks: Array[Decal] = []
var _marks_next := 0
var _big: Array[GPUParticles3D] = []
var _big_next := 0


func _ready() -> void:
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g
	_soft_tex = tex

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.62, 0.57, 0.5, 0.55)

	var quad := QuadMesh.new()
	quad.size = Vector2(2.5, 2.5)
	quad.material = mat

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, -0.6, 0)
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.scale_min = 0.6
	pm.scale_max = 1.8
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.8

	for i in POOL_SIZE:
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.amount = 14
		p.lifetime = 2.2
		p.explosiveness = 0.9
		p.process_material = pm
		p.draw_pass_1 = quad
		p.visibility_aabb = AABB(Vector3(-10, -5, -10), Vector3(20, 15, 20))
		add_child(p)
		_pool.append(p)
	_setup_rubble()
	_setup_bricks()
	_setup_marks()
	_setup_big_dust()


## Görsel moloz: fizik gövdesi olmayan küçük taş parçaları (GPU parçacık, zemine çarpar).
func _setup_rubble() -> void:
	var col := GPUParticlesCollisionBox3D.new()
	col.size = Vector3(3000, 2, 3000)
	col.position = Vector3(0, -1, 0)
	add_child(col)
	var mesh: Mesh = load("res://assets/rocks/pebble_1.res")
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 9.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.12
	pm.scale_max = 0.4
	pm.angular_velocity_min = -360.0
	pm.angular_velocity_max = 360.0
	pm.particle_flag_rotate_y = true
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_friction = 0.7
	pm.collision_bounce = 0.15
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.0
	for i in RUBBLE_POOL:
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.amount = 18
		p.lifetime = 4.0
		p.explosiveness = 0.95
		p.process_material = pm
		p.draw_pass_1 = mesh
		p.visibility_aabb = AABB(Vector3(-20, -10, -20), Vector3(40, 30, 40))
		add_child(p)
		_rubble.append(p)


## Görsel tuğla kırıntıları: fizik gövdesi olmayan küçük taş kesekleri (20–40 cm),
## savrulup zemine çarpar, sekip durur, ömür sonunda küçülerek kaybolur.
func _setup_bricks() -> void:
	var bm := BoxMesh.new()
	bm.size = Vector3(0.36, 0.2, 0.24)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/textures/rock_boulder_dry_diff_1k.jpg")
	mat.albedo_color = Color(0.8, 0.77, 0.72)
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3.ONE * 0.6
	mat.roughness = 0.95
	bm.material = mat
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 60.0
	pm.initial_velocity_min = 3.0
	pm.initial_velocity_max = 11.0
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.5
	pm.scale_max = 1.6
	var sc := Curve.new()
	sc.add_point(Vector2(0, 1))
	sc.add_point(Vector2(0.85, 1))
	sc.add_point(Vector2(1, 0))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	pm.angular_velocity_min = -540.0
	pm.angular_velocity_max = 540.0
	pm.particle_flag_rotate_y = true
	pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
	pm.collision_friction = 0.8
	pm.collision_bounce = 0.2
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 1.2
	for i in BRICK_POOL:
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.amount = 70
		p.lifetime = 7.0
		p.explosiveness = 0.95
		p.process_material = pm.duplicate()
		p.draw_pass_1 = bm
		p.visibility_aabb = AABB(Vector3(-30, -10, -30), Vector3(60, 40, 60))
		add_child(p)
		_bricks.append(p)


## Tuğla kırıntısı püskürt: dir yönüne (yukarı açılarak), amount 0..1
func bricks(pos: Vector3, dir: Vector3, amount: float) -> void:
	var p := _bricks[_bricks_next]
	_bricks_next = (_bricks_next + 1) % BRICK_POOL
	p.global_position = pos
	p.amount_ratio = clampf(amount, 0.1, 1.0)
	var m := p.process_material as ParticleProcessMaterial
	m.direction = (dir.normalized() + Vector3.UP * 0.6).normalized()
	p.restart()


## Moloz izi: zeminde kalıcı toz/kırıntı lekesi (çıkartma), en eski yenisine yer açar
func _setup_marks() -> void:
	var img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.08
	noise.fractal_octaves = 4
	var grit := FastNoiseLite.new()
	grit.frequency = 0.5
	for y in 128:
		for x in 128:
			var d := Vector2(x - 63.5, y - 63.5).length() / 64.0
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((1.0 - d) * 1.6 - 0.3 + (n - 0.5) * 0.9, 0.0, 1.0)
			var g := grit.get_noise_2d(x, y) * 0.5 + 0.5
			var c := lerpf(0.42, 0.72, g) * lerpf(0.85, 1.05, n)
			img.set_pixel(x, y, Color(c, c * 0.96, c * 0.9, a * 0.85))
	var tex := ImageTexture.create_from_image(img)
	for i in MARK_POOL:
		var d := Decal.new()
		d.texture_albedo = tex
		d.size = Vector3(6, 2, 6)
		d.visible = false
		d.cull_mask = 1
		d.distance_fade_enabled = true
		d.distance_fade_begin = 220.0
		d.distance_fade_length = 60.0
		add_child(d)
		_marks.append(d)


func debris_mark(pos: Vector3, size: float) -> void:
	var d := _marks[_marks_next]
	_marks_next = (_marks_next + 1) % MARK_POOL
	var s := clampf(size * randf_range(0.9, 1.4), 3.0, 14.0)
	d.size = Vector3(s, 3.0, s)
	d.global_position = pos
	d.rotation.y = randf() * TAU
	d.visible = true


## Büyük toz bulutu (kule çöküşü): iri, yavaş yayılan, uzun ömürlü
func _setup_big_dust() -> void:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_tex
	mat.albedo_color = Color(0.64, 0.6, 0.53, 0.5)
	var quad := QuadMesh.new()
	quad.size = Vector2(9, 9)
	quad.material = mat
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 90.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 7.0
	pm.gravity = Vector3(0, -0.3, 0)
	pm.damping_min = 0.8
	pm.damping_max = 1.6
	pm.scale_min = 0.8
	pm.scale_max = 2.2
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.5))
	curve.add_point(Vector2(1, 2.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.8))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(8, 6, 8)
	for i in BIG_DUST_POOL:
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.amount = 40
		p.lifetime = 7.0
		p.explosiveness = 0.6
		p.process_material = pm
		p.draw_pass_1 = quad
		p.visibility_aabb = AABB(Vector3(-50, -10, -50), Vector3(100, 80, 100))
		add_child(p)
		_big.append(p)


func big_dust(pos: Vector3) -> void:
	var p := _big[_big_next]
	_big_next = (_big_next + 1) % BIG_DUST_POOL
	p.global_position = pos
	p.restart()


## Cam kırıkları: parlak küçük üçgenimsi parçalar, zemine çarpıp seker
func glass_shards(pos: Vector3, size: Vector3) -> void:
	if _glass_mat == null:
		_glass_mat = StandardMaterial3D.new()
		_glass_mat.albedo_color = Color(0.8, 0.92, 0.95, 0.55)
		_glass_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_glass_mat.metallic = 0.3
		_glass_mat.roughness = 0.05
		_glass_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.direction = Vector3.UP
		pm.spread = 120.0
		pm.initial_velocity_min = 1.0
		pm.initial_velocity_max = 5.0
		pm.gravity = Vector3(0, -9.8, 0)
		pm.angular_velocity_min = -720.0
		pm.angular_velocity_max = 720.0
		pm.scale_min = 0.5
		pm.scale_max = 1.5
		pm.collision_mode = ParticleProcessMaterial.COLLISION_RIGID
		pm.collision_bounce = 0.3
		pm.collision_friction = 0.5
		_glass_pm = pm
	var p := GPUParticles3D.new()
	var pm2 := _glass_pm.duplicate() as ParticleProcessMaterial
	pm2.emission_box_extents = size * 0.5
	p.process_material = pm2
	var q := QuadMesh.new()
	q.size = Vector2(0.18, 0.12)
	q.material = _glass_mat
	p.draw_pass_1 = q
	p.amount = clampi(int((size.x + size.y + size.z) * 10.0), 12, 48)
	p.lifetime = 3.0
	p.one_shot = true
	p.explosiveness = 1.0
	p.visibility_aabb = AABB(Vector3(-8, -6, -8), Vector3(16, 14, 16))
	add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(3.5, true, false, true).timeout.connect(p.queue_free)


func rubble(pos: Vector3, direction: Vector3, amount: float) -> void:
	var p := _rubble[_rubble_next]
	_rubble_next = (_rubble_next + 1) % RUBBLE_POOL
	p.global_position = pos
	p.amount_ratio = clampf(amount, 0.2, 1.0)
	var m := p.process_material as ParticleProcessMaterial
	m.direction = (direction.normalized() + Vector3.UP).normalized()
	p.restart()


## Patlama: ışık parlaması + ateş topu + duman + toz.
func explosion(pos: Vector3, scale_k: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_position = pos
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 14.0
	light.omni_range = 30.0 * scale_k
	root.add_child(light)
	var tw := create_tween()
	tw.tween_property(light, "light_energy", 0.0, 0.5)
	root.add_child(_burst(Color(1.0, 0.55, 0.15, 1.0), 26, 0.9, 6.0 * scale_k, 3.5 * scale_k, true))
	root.add_child(_burst(Color(0.18, 0.16, 0.15, 0.8), 30, 3.5, 4.0 * scale_k, 6.0 * scale_k, false))
	dust(pos, 2.5)
	rubble(pos, Vector3.UP, 1.0)
	get_tree().create_timer(4.5, true, false, true).timeout.connect(root.queue_free)


func _burst(color: Color, count: int, life: float, speed: float, size: float, additive: bool) -> GPUParticles3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_tex
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size
	quad.material = mat
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = speed * 0.4
	pm.initial_velocity_max = speed
	pm.gravity = Vector3(0, 1.5 if not additive else 0.5, 0)
	pm.damping_min = 2.0
	pm.damping_max = 4.0
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	pm.color = color
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 1))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.amount = count
	p.lifetime = life
	p.explosiveness = 0.95
	p.process_material = pm
	p.draw_pass_1 = quad
	p.visibility_aabb = AABB(Vector3(-25, -10, -25), Vector3(50, 40, 50))
	p.emitting = true
	return p


func _process(delta: float) -> void:
	_cooldown -= delta


func dust(pos: Vector3, amount: float) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = 0.04
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.global_position = pos
	p.scale = Vector3.ONE * clampf(amount, 0.3, 2.5)
	p.restart()


func shake(amount: float) -> void:
	if amount > 0.02:
		shake_requested.emit(amount)
