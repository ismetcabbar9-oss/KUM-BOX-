class_name Destructible
extends RigidBody3D
## Yıkılabilir gövde. İki kullanım:
##  - Serbest obje (bariyer, varil, taş...): uykuda başlar, çarpılınca uyanır.
##  - Bina parçası: "intact" iken statik dondurulmuştur (fizik maliyeti sıfır); yalnız
##    Building.strike() ile yeterli enerji gelince ya da desteği kalmayınca serbest kalır.
## Temas izleme (contact_monitor) kullanılmaz; darbeler hız değişiminden algılanır.

signal woke(body: Destructible)
signal released(body: Destructible)

## "concrete", "brick", "wood", "metal", "stone"
var material_kind := "concrete"
var start_pos := Vector3.ZERO
var building: Node = null  # Building (döngüsel class_name bağımlılığından kaçınmak için Node)
var intact := false
var layer := 0
var neighbors := PackedStringArray()
var hp := 0.0
var _prev_v := Vector3.ZERO
var _cooldown := 0.0
var _rest_time := 0.0
var _pending_impulse := Vector3.ZERO
var _pending_offset := Vector3.ZERO


func configure(kind: String, body_mass: float, friction := 0.8) -> void:
	material_kind = kind
	mass = maxf(body_mass, 5.0)
	var pm := PhysicsMaterial.new()
	pm.friction = friction
	pm.bounce = 0.05
	physics_material_override = pm
	# Katman 1: statik dünya, 2: parçalar, 3: mermiler, 4: engeller
	collision_layer = 2
	collision_mask = 1 | 2 | 4 | 8
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


func add_hull(points: PackedVector3Array) -> void:
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)


## Yapının parçası olarak statik dondur (bina ayaktayken).
func make_intact() -> void:
	intact = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true


func _ready() -> void:
	# Godot, _physics_process tanımlıysa işlemeyi _ready'de otomatik açar: kapat
	set_physics_process(false)
	start_pos = global_position
	if intact:
		return
	# Jolt, gövde dünyada ilk adımını atmadan verilen uyku komutunu yok sayar:
	# bir fizik karesi bekleyip sonra uyut.
	await get_tree().physics_frame
	if is_inside_tree() and not freeze:
		sleeping = true


func is_displaced() -> bool:
	return global_position.distance_squared_to(start_pos) > 0.64


## Yapıdan kopar: dinamik ol, isteğe bağlı darbe uygula.
func release(impulse := Vector3.ZERO, at := Vector3.ZERO) -> void:
	if not intact:
		return
	intact = false
	freeze = false
	sleeping = false
	_prev_v = Vector3.ZERO
	_rest_time = 0.0
	set_physics_process(true)
	# Statikten dinamiğe geçiş fizik sunucusunda bir sonraki adımda olur: itkiyi o zaman uygula
	_pending_impulse = impulse
	_pending_offset = at - global_position
	released.emit(self)


func _on_sleeping_changed() -> void:
	if intact:
		return
	set_physics_process(not sleeping)
	if not sleeping:
		_prev_v = linear_velocity
		woke.emit(self)


func _physics_process(delta: float) -> void:
	if _pending_impulse != Vector3.ZERO:
		# Doğrudan hız ver: statikten yeni çözülen gövdede itki güvenilir uygulanmıyor
		linear_velocity += _pending_impulse / mass
		angular_velocity += (_pending_offset.cross(_pending_impulse) / mass) * 0.15
		_pending_impulse = Vector3.ZERO
		return
	var v := linear_velocity
	var slow := v.length_squared() < 1.0 and angular_velocity.length_squared() < 1.0
	if slow:
		_rest_time += delta
		# Uzun süre yerinde titreyen moloz: dondur (çarpışır ama fizik maliyeti yok).
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
			# Düşen ağır parça alttaki sağlam yapıyı ezer (katlar üst üste çöker)
			var energy := 0.5 * mass * dv * dv
			if energy > 60000.0:
				Building.strike(get_world_3d(), p, energy * 0.6, Vector3.DOWN, self)


## Donmuş molozu yeniden dinamik yap (yeni mermi yaklaşınca çağrılır).
func thaw() -> void:
	if freeze and not intact:
		freeze = false
		_rest_time = 0.0
		sleeping = false
		set_physics_process(true)
