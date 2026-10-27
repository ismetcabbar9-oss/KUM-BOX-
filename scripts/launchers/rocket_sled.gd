class_name RocketSled
extends Launcher
## Roket kızağı: U-kanal içinde kayan kızak, roket itkisiyle hızlanır. Kanalın sonundaki
## tampona çarpınca kızak durur, üstündeki mermi ataletle kalkış dudağından (8°) uçar.
## Dikey sürükle: itki gücü. FIRLAT: ateşle.

const TRACK := 64.0
const SLED := Vector3(2.4, 0.6, 4.0)
const GROOVE := 2.8  # kanal iç genişliği

var thrust_pct := 100.0
var sled: RigidBody3D
var _burning := false
var _burn_t := 0.0
var _flame: GPUParticles3D
var _smoke: GPUParticles3D
var _engine: AudioStreamPlayer3D
var _sled_rest: Transform3D
var _steel: Material


func _init() -> void:
	super()
	title = "ROKET KIZAĞI"
	id = "rocket"
	base_radius = 0.6
	view_distance = 14.0


func _ready() -> void:
	_steel = WorldBuilder.pbr("metal_plate", 0.6, Color(0.5, 0.52, 0.55), false)
	var conc := WorldBuilder.pbr("rough_concrete", 0.3, Color(0.8, 0.79, 0.76))
	# Kanal: taban + iki yan duvar, son 10 m kalkış dudağına doğru yükselir
	var segs := 16
	for i in segs:
		var z0 := TRACK * i / segs
		var z1 := TRACK * (i + 1) / segs
		var y0 := _rail_y(z0)
		var y1 := _rail_y(z1)
		var mid := Vector3(0, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
		var ang := atan2(y1 - y0, z1 - z0)
		var b := Basis(Vector3.RIGHT, -ang)
		var len := Vector2(z1 - z0, y1 - y0).length() + 0.02
		beam(self, Vector3(GROOVE + 1.2, 0.4, len), Transform3D(b, mid + b * Vector3(0, -0.2, 0)), conc)
		for sx in [-1.0, 1.0]:
			# Duvar kızak üstünden alçak: büyük mermi duvara sürtmez
			beam(self, Vector3(0.4, 0.5, len), Transform3D(b, mid + b * Vector3(sx * (GROOVE * 0.5 + 0.2), 0.25, 0)), _steel)
	# Tampon: yalnız kızak yüksekliğinde (mermi üstünden geçer)
	beam(self, Vector3(GROOVE, 0.55, 0.8), Transform3D(Basis.IDENTITY, Vector3(0, _rail_y(TRACK - 0.6) + 0.27, TRACK - 0.6)), _steel)

	sled = RigidBody3D.new()
	sled.name = "Sled"
	_sled_rest = Transform3D(Basis.IDENTITY, Vector3(0, _rail_y(3.0) + SLED.y * 0.5 + 0.01, 3.0))
	sled.transform = _sled_rest
	sled.mass = 1800.0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.04
	sled.physics_material_override = pm
	_sled_box(SLED, Vector3.ZERO)
	_sled_box(Vector3(SLED.x, 0.6, 0.25), Vector3(0, SLED.y * 0.5 + 0.3, -SLED.z * 0.5 + 0.12))  # arka dayanak
	for sx in [-1.0, 1.0]:
		_sled_box(Vector3(0.2, 0.3, SLED.z), Vector3(sx * (SLED.x * 0.5 - 0.1), SLED.y * 0.5 + 0.15, 0))
	# Roket motoru (görsel)
	var eng := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.35
	cm.bottom_radius = 0.5
	cm.height = 1.2
	eng.mesh = cm
	eng.material_override = _steel
	eng.rotation_degrees = Vector3(90, 0, 0)
	eng.position = Vector3(0, 0, -SLED.z * 0.5 - 0.5)
	sled.add_child(eng)
	sled.collision_layer = 8
	sled.collision_mask = 1 | 2 | 4
	sled.continuous_cd = true
	sled.can_sleep = false
	sled.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	sled.freeze = true
	add_child(sled)
	_flame = _particles(Color(1.0, 0.6, 0.2), 0.5, true)
	_smoke = _particles(Color(0.4, 0.4, 0.42, 0.6), 2.2, false)
	_engine = AudioStreamPlayer3D.new()
	_engine.stream = Sfx.stream("rocket_loop")
	_engine.bus = "SFX"
	_engine.unit_size = 25.0
	sled.add_child(_engine)
	view_target.position = Vector3(0, 3.0, 4.0)


func _rail_y(z: float) -> float:
	var k := clampf((z - (TRACK - 12.0)) / 12.0, 0.0, 1.0)
	return 0.4 + k * k * 12.0 * tan(deg_to_rad(8.0)) * 0.5


func _sled_box(size: Vector3, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _steel
	mi.position = pos
	sled.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	sled.add_child(cs)


func _particles(color: Color, life: float, additive: bool) -> GPUParticles3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if additive else BaseMaterial3D.BLEND_MODE_MIX
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var g := GradientTexture2D.new()
	g.fill = GradientTexture2D.FILL_RADIAL
	g.fill_from = Vector2(0.5, 0.5)
	g.fill_to = Vector2(1.0, 0.5)
	var gr := Gradient.new()
	gr.set_color(0, Color.WHITE)
	gr.set_color(1, Color(1, 1, 1, 0))
	g.gradient = gr
	mat.albedo_texture = g
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * (0.9 if additive else 2.2)
	quad.material = mat
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, -1)
	pm.spread = 12.0 if additive else 25.0
	pm.initial_velocity_min = 8.0 if additive else 2.0
	pm.initial_velocity_max = 14.0 if additive else 5.0
	pm.gravity = Vector3(0, 0.5, 0)
	pm.color = color
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var p := GPUParticles3D.new()
	p.amount = 40 if additive else 60
	p.lifetime = life
	p.local_coords = false
	p.process_material = pm
	p.draw_pass_1 = quad
	p.emitting = false
	p.position = Vector3(0, 0, -SLED.z * 0.5 - 1.1)
	p.visibility_aabb = AABB(Vector3(-20, -10, -60), Vector3(40, 30, 80))
	sled.add_child(p)
	return p


func _cradle_point(r: float) -> Vector3:
	return sled.global_transform * Vector3(0, SLED.y * 0.5 + r + 0.02, -SLED.z * 0.5 + 0.25 + r + 0.1)


func load_projectile(p: Projectile) -> void:
	_burning = false
	_flame.emitting = false
	_smoke.emitting = false
	_engine.stop()
	sled.freeze = true
	sled.transform = _sled_rest
	sled.linear_velocity = Vector3.ZERO
	sled.angular_velocity = Vector3.ZERO
	sled.reset_physics_interpolation()
	loaded = p
	p.global_transform = Transform3D(global_transform.basis, _cradle_point(p.radius))
	p.reset_physics_interpolation()


func drag(relative: Vector2, _vs: Vector2) -> void:
	if not is_ready():
		return
	thrust_pct = clampf(thrust_pct - relative.y * 0.25, 40.0, 160.0)


func fire(_power := -1.0) -> void:
	if not is_ready():
		return
	var p := loaded
	sled.freeze = false
	p.launch(Vector3.ZERO)
	_burning = true
	_burn_t = 0.0
	_flame.emitting = true
	_smoke.emitting = true
	_engine.play()
	Sfx.play("rocket_ignite", sled.global_position, 6.0)
	fired.emit(p)


func _physics_process(delta: float) -> void:
	if not _burning:
		return
	_burn_t += delta
	var local_z := (global_transform.affine_inverse() * sled.global_position).z
	if local_z > TRACK - 3.0 or _burn_t > 4.0:
		_burning = false
		_flame.emitting = false
		_engine.stop()
		return
	# İtki: ~13 m/s² (güç ayarıyla). Mermi kızağın beşiğinde: aynı ivmeyi alır (beşiğin
	# itişi), böylece ağır/büyük mermi de kızaktan kaymaz.
	var a := global_transform.basis.z * 13.0 * thrust_pct / 100.0 * power
	sled.apply_central_force(a * sled.mass)
	if is_instance_valid(loaded) and loaded.global_position.distance_to(sled.global_position) < loaded.radius + SLED.z:
		loaded.apply_central_force(a * loaded.mass)


func info() -> String:
	return "İtki %d%%" % roundi(thrust_pct)


func hint() -> String:
	return "Yukarı/aşağı sürükle: itki gücü   •   FIRLAT: ateşle"
