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
## İkincil kırılma (kutu parçalar): sert darbede uzun ekseni boyunca ikiye bölünür
var split_size := Vector3.ZERO
var split_material: Material
var split_energy_density := 0.0  # J/m³
var _splitting := false
var split_halves := []
var split_gen := 0
## Örgü yapı bloğu: sert darbede / hızla koptuğunda BrickPool tuğlalara ayırır
var shatter_pool: Node = null
## Son kopmada darbe noktası (dünya): tuğlalar bu noktaya yakınsa daha hızlı fırlar
var hit_point := Vector3.INF
## Bölünme bütçesi (performans): kare başına en fazla 2 bölünme, toplamda max_spawned yeni parça
const MAX_SPLITS_PER_FRAME := 2
static var max_spawned := 160  # grafik kalitesine göre ayarlanır
const MAX_GEN := 2
static var _budget_frame := -1
static var _budget_used := 0
static var spawned := 0


func configure(kind: String, body_mass: float, friction := 0.8) -> void:
	material_kind = kind
	mass = maxf(body_mass, 5.0)
	var pm := PhysicsMaterial.new()
	pm.friction = friction
	pm.bounce = 0.05
	physics_material_override = pm
	# Katman 1: statik dünya, 2: parçalar, 3: mermiler, 4: engeller
	collision_layer = 2
	collision_mask = 1 | 2 | 4 | 8 | 16
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


func add_cylinder(radius: float, height: float) -> void:
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)


func add_hull(points: PackedVector3Array) -> void:
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var cs := CollisionShape3D.new()
	cs.shape = shape
	add_child(cs)


## Kutu parçayı bölünebilir yap. energy_density: bölünme için gereken J/m³.
func make_splittable(size: Vector3, mat: Material, energy_density: float) -> void:
	split_size = size
	split_material = mat
	split_energy_density = energy_density


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
	if impulse.length_squared() > 0.0:
		hit_point = at
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
		# Darbeyle kopan örgü bloğu dağılır (desteği giden blok ise önce düşer, yere çarpınca)
		if shatter_pool and linear_velocity.length() > 1.2:
			shatter_pool.request(self)
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
			_try_split(energy)
			if energy > 60000.0:
				Building.strike(get_world_3d(), p, energy * 0.6, Vector3.DOWN, self)


## Donmuş molozu yeniden dinamik yap (yeni mermi yaklaşınca çağrılır).
func thaw() -> void:
	if freeze and not intact:
		freeze = false
		_rest_time = 0.0
		sleeping = false
		set_physics_process(true)


## Önceden hesaplanmış iki yarı (bina parçaları): {mesh, hull, volume, offset}
func make_splittable_halves(halves: Array, energy_density: float) -> void:
	split_halves = halves
	split_energy_density = energy_density


func _try_split(energy: float) -> void:
	if shatter_pool:
		if hit_point == Vector3.INF:
			# Düşerek çarpan blok: çarpma noktası hareket yönündeki yüz (çoğunlukla alt yüz)
			var dir := linear_velocity.normalized() if linear_velocity.length() > 0.5 else Vector3.DOWN
			hit_point = global_position + dir * 1.4
		shatter_pool.request(self)
		return
	if _splitting or intact or split_gen >= MAX_GEN or spawned >= max_spawned:
		return
	var f := Engine.get_physics_frames()
	if f != _budget_frame:
		_budget_frame = f
		_budget_used = 0
	if _budget_used >= MAX_SPLITS_PER_FRAME:
		return
	if not split_halves.is_empty():
		var v: float = split_halves[0]["volume"] + split_halves[1]["volume"]
		if energy >= v * split_energy_density:
			_splitting = true
			_budget_used += 1
			spawned += 2
			_split_halves.call_deferred()
		return
	if split_size == Vector3.ZERO:
		return
	var vol := split_size.x * split_size.y * split_size.z
	var axis := 0
	for a in 3:
		if split_size[a] > split_size[axis]:
			axis = a
	if split_size[axis] < 1.0 or energy < vol * split_energy_density:
		return
	_splitting = true
	_budget_used += 1
	spawned += 2
	_split.call_deferred(axis)


func _split_halves() -> void:
	if not is_inside_tree():
		return
	var total: float = split_halves[0]["volume"] + split_halves[1]["volume"]
	for h in split_halves:
		var d := Destructible.new()
		var mi := MeshInstance3D.new()
		mi.mesh = h["mesh"]
		d.add_child(mi)
		d.add_hull(h["hull"])
		d.configure(material_kind, mass * float(h["volume"]) / total)
		d.split_gen = MAX_GEN
		get_parent().add_child(d)
		var off: Vector3 = h["offset"]
		d.global_transform = global_transform * Transform3D(Basis.IDENTITY, off)
		var sep := (global_transform.basis * off).normalized()
		d.linear_velocity = linear_velocity + sep * 1.2
		d.angular_velocity = angular_velocity
		d.sleeping = false
		d.set_physics_process(true)
	Sfx.debris(global_position, 10.0)
	Fx.dust(global_position, 1.2)
	Fx.rubble(global_position, Vector3.UP, 0.7)
	if building and building.has_method("forget"):
		building.forget(self)
	queue_free()


## İki parçaya böl: hız ve dönüş korunur, parçalar kesik yönünde hafifçe ayrılır.
func _split(axis: int) -> void:
	if not is_inside_tree():
		return
	var ratio := randf_range(0.38, 0.62)
	var lens := [split_size[axis] * ratio, split_size[axis] * (1.0 - ratio)]
	var dir := global_transform.basis[axis].normalized()
	var start := -split_size[axis] * 0.5
	for i in 2:
		var size := split_size
		size[axis] = lens[i]
		var center_off: float = start + lens[i] * 0.5 + (lens[0] if i == 1 else 0.0)
		var d := Destructible.new()
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size - Vector3.ONE * 0.02
		bm.material = split_material
		mi.mesh = bm
		d.add_child(mi)
		d.add_box(size - Vector3.ONE * 0.01)
		d.configure(material_kind, mass * lens[i] / split_size[axis])
		d.make_splittable(size, split_material, split_energy_density)
		d.split_gen = split_gen + 1
		d.building = null
		get_parent().add_child(d)
		d.global_transform = Transform3D(global_transform.basis, global_position + dir * center_off)
		d.linear_velocity = linear_velocity + dir * (1.5 if i == 1 else -1.5)
		d.angular_velocity = angular_velocity
		d.sleeping = false
		d.set_physics_process(true)
	Sfx.impact("wood" if material_kind == "wood" else material_kind, global_position, 8.0)
	Fx.dust(global_position, 1.0)
	if material_kind != "wood" and material_kind != "metal":
		Fx.rubble(global_position, Vector3.UP, 0.6)
	if building and building.has_method("forget"):
		building.forget(self)
	queue_free()
