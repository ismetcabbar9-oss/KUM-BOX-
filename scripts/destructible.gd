class_name Destructible
extends RigidBody3D
## Yıkılabilir parça. Uykuda başlar; uyanınca hız değişimine bakarak darbe sesi/tozu üretir.
## Temas izleme (contact_monitor) kullanılmaz: yüzlerce gövdede pahalı. Uyuyan gövdeler
## hiç script çalıştırmaz.

signal woke(body: Destructible)

## "concrete", "brick", "wood", "metal", "stone"
var material_kind := "concrete"
var start_pos := Vector3.ZERO
var _prev_v := Vector3.ZERO
var _cooldown := 0.0
var _rest_time := 0.0


func configure(kind: String, body_mass: float, friction := 0.8) -> void:
	material_kind = kind
	mass = maxf(body_mass, 5.0)
	var pm := PhysicsMaterial.new()
	pm.friction = friction
	pm.bounce = 0.05
	physics_material_override = pm
	# Katman 1: statik dünya, 2: parçalar, 3: kayalar
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	can_sleep = true
	add_to_group("destructible")
	sleeping_state_changed.connect(_on_sleeping_changed)


func add_box(size: Vector3, offset := Vector3.ZERO) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position = offset
	add_child(cs)


func _ready() -> void:
	# Godot, _physics_process tanımlıysa işlemeyi _ready'de otomatik açar: kapat
	set_physics_process(false)
	start_pos = global_position
	# Jolt, gövde dünyada ilk adımını atmadan verilen uyku komutunu yok sayar:
	# bir fizik karesi bekleyip sonra uyut (bu sürede gövde ~3 mm bile hareket etmez).
	await get_tree().physics_frame
	if is_inside_tree():
		sleeping = true


func is_displaced() -> bool:
	return global_position.distance_squared_to(start_pos) > 0.64


func _on_sleeping_changed() -> void:
	set_physics_process(not sleeping)
	if not sleeping:
		_prev_v = linear_velocity
		woke.emit(self)


func _physics_process(delta: float) -> void:
	var v := linear_velocity
	var slow := v.length_squared() < 1.0 and angular_velocity.length_squared() < 1.0
	if slow:
		_rest_time += delta
		# Uzun süre yerinde titreyen moloz: dondur (çarpışır ama fizik maliyeti yok).
		# Komşusu titreştikçe uyandırılan yığınlar normal uykuya giremez; bu onları keser.
		if _rest_time > 3.0:
			freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			freeze = true
			set_physics_process(false)
			return
	else:
		_rest_time = 0.0

	var dv := (v - _prev_v).length()
	_prev_v = v
	_cooldown -= delta
	if dv > 2.2 and _cooldown <= 0.0:
		_cooldown = 0.2
		var p := global_position
		Sfx.impact(material_kind, p, dv)
		if dv > 4.0:
			Fx.dust(p, clampf(dv / 10.0, 0.3, 1.5))
			if material_kind != "metal" and material_kind != "wood":
				Sfx.debris(p, dv)


## Donmuş molozu yeniden dinamik yap (yeni kaya yaklaşınca çağrılır).
func thaw() -> void:
	if freeze:
		freeze = false
		_rest_time = 0.0
		sleeping = false
