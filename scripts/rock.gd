class_name Rock
extends RigidBody3D
## Oyuncunun yuvarladığı kaya: taranmış gerçek kaya modeli, dışbükey örtü çarpışması.

const DENSITY := 2500.0
const MODEL := "rock_hero"

var radius := 2.0
var launched := false
var _roll: AudioStreamPlayer3D
var _prev_v := Vector3.ZERO
var _cooldown := 0.0
var _touching := false
var _thaw_timer := 0.0
var _query: PhysicsShapeQueryParameters3D


func setup(r: float) -> void:
	radius = r
	var visual := Models.instance(MODEL)
	add_child(visual)
	# Taranmış kaya yassı: eksenleri küreye doğru yaklaştır (doku bozulmadan, kısmi).
	# Çarpışma küre: rampada takılmadan, gerçek kaya gibi momentumla yuvarlanır.
	var b := Models.local_aabb(visual)
	var avg := (b.size.x + b.size.y + b.size.z) / 3.0
	var sc := Vector3.ZERO
	for ax in 3:
		sc[ax] = 2.0 * r * pow(b.size[ax] / avg, 0.35) / b.size[ax]
	visual.scale = sc
	visual.position = -b.get_center() * sc
	var shape := SphereShape3D.new()
	shape.radius = r * 0.93
	var cs := CollisionShape3D.new()
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
	max_contacts_reported = 2
	# Proje varsayılan sönümlemesini ezme: gerçekçi yuvarlanma için çok düşük
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.01
	angular_damp = 0.05
	can_sleep = false
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

	_roll = AudioStreamPlayer3D.new()
	_roll.stream = load("res://assets/sounds/roll_loop.ogg")
	_roll.bus = "SFX"
	_roll.unit_size = 18.0
	_roll.max_db = 6.0
	_roll.volume_db = -80.0
	add_child(_roll)


func launch(direction: Vector3, power: float) -> void:
	freeze = false
	launched = true
	# Durunca uyuyabilsin: uyumayan kaya, dokunduğu tüm moloz yığınını uyanık tutar (pahalı)
	can_sleep = true
	apply_central_impulse(direction.normalized() * mass * power)
	# Hafif ileri dönüş: yuvarlanmaya başlasın
	apply_torque_impulse(Vector3(1, 0, 0) * mass * radius * power * 0.4)
	_roll.play()


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func _physics_process(delta: float) -> void:
	if not launched:
		return
	_touching = get_contact_count() > 0
	# Yuvarlanma direnci: hızlıyken neredeyse yok, yavaşlayınca toprakta durur
	var spd := linear_velocity.length()
	var k := clampf(spd / 8.0, 0.0, 1.0)
	angular_damp = lerpf(1.2, 0.05, k) if _touching else 0.05
	linear_damp = lerpf(0.3, 0.01, k) if _touching else 0.01
	var spin := angular_velocity.length() * radius
	var target_db := -80.0
	if _touching and spin > 0.5:
		target_db = linear_to_db(clampf(spin / 20.0, 0.05, 1.0)) + 2.0
	_roll.volume_db = lerpf(_roll.volume_db, target_db, clampf(delta * 8.0, 0.0, 1.0))
	_roll.pitch_scale = clampf(0.7 + spin / 40.0, 0.7, 1.4) * Engine.time_scale

	# Önündeki donmuş molozu çöz: kaya geldiğinde yığınlar yine dağılabilsin
	_thaw_timer -= delta
	if _thaw_timer <= 0.0 and linear_velocity.length_squared() > 4.0:
		_thaw_timer = 0.15
		_thaw_nearby()

	# Darbe: tek adımdaki hız değişimi
	var v := linear_velocity
	var dv := (v - _prev_v).length()
	_prev_v = v
	_cooldown -= delta
	if dv > 1.2 and _cooldown <= 0.0:
		_cooldown = 0.12
		var p := global_position + (v.normalized() * radius if v.length() > 0.5 else Vector3.DOWN * radius)
		Sfx.impact("rock", p, dv * 3.0)
		Fx.dust(p, clampf(dv, 0.5, 2.5))
		Fx.shake(clampf(dv * radius * 0.12, 0.0, 1.0))


func _thaw_nearby() -> void:
	if _query == null:
		_query = PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = radius * 2.5
		_query.shape = sphere
		_query.collision_mask = 2
	_query.transform = Transform3D(Basis.IDENTITY, global_position + linear_velocity * 0.15)
	for hit in get_world_3d().direct_space_state.intersect_shape(_query, 32):
		var d := hit["collider"] as Destructible
		if d:
			d.thaw()
