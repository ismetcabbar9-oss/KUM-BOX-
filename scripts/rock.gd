class_name Rock
extends RigidBody3D
## Oyuncunun yuvarladığı kaya: küre çarpışma, düzensiz görünüm, yuvarlanma sesi.

const DENSITY := 2400.0

var radius := 2.0
var launched := false
var _roll: AudioStreamPlayer3D
var _cooldown := 0.0
var _touching := false


func setup(r: float, seed_value: int) -> void:
	radius = r
	var mi := MeshInstance3D.new()
	mi.mesh = WorldBuilder.rock_mesh(r, seed_value)
	mi.material_override = WorldBuilder.pbr("rock_boulder_dry", 0.35 / r * 2.0, Color(0.95, 0.92, 0.88), false)
	add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = r * 0.97
	cs.shape = shape
	add_child(cs)
	mass = 4.0 / 3.0 * PI * pow(r, 3) * DENSITY
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.08
	physics_material_override = pm
	collision_layer = 4
	collision_mask = 1 | 2 | 4
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 4
	# Proje varsayılan sönümlemesini ezme: gerçekçi yuvarlanma için çok düşük
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.01
	angular_damp = 0.05
	can_sleep = false
	# Fırlatılana kadar yerinde dursun
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

	_roll = AudioStreamPlayer3D.new()
	_roll.stream = load("res://assets/sounds/roll_loop.wav")
	_roll.bus = "SFX"
	_roll.unit_size = 18.0
	_roll.max_db = 6.0
	_roll.volume_db = -80.0
	_roll.autoplay = true
	add_child(_roll)


func launch(direction: Vector3, power: float) -> void:
	freeze = false
	launched = true
	apply_central_impulse(direction.normalized() * mass * power)


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func _physics_process(delta: float) -> void:
	# Yuvarlanma sesi: zemine temas + açısal hıza bağlı
	var spin := angular_velocity.length() * radius
	var target_db := -80.0
	if _touching and spin > 0.5:
		target_db = linear_to_db(clampf(spin / 20.0, 0.05, 1.0)) + 2.0
	_roll.volume_db = lerpf(_roll.volume_db, target_db, clampf(delta * 8.0, 0.0, 1.0))
	_roll.pitch_scale = clampf(0.6 + spin / 35.0, 0.6, 1.5) * Engine.time_scale
	if not _roll.playing:
		_roll.play()


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	_touching = state.get_contact_count() > 0
	_cooldown -= state.step
	if _cooldown > 0.0:
		return
	var best := 0.0
	var best_pos := Vector3.ZERO
	for i in state.get_contact_count():
		var dv := state.get_contact_impulse(i).length() / mass
		if dv > best:
			best = dv
			best_pos = state.get_contact_local_position(i)
	if best > 0.8:
		_cooldown = 0.12
		Sfx.impact("rock", best_pos, best * 3.0)
		Fx.dust(best_pos, clampf(best, 0.5, 2.5))
		Fx.shake(clampf(best * radius * 0.15, 0.0, 1.0))
