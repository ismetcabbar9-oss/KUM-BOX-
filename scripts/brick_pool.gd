class_name BrickPool
extends Node3D
## Örgü yapılar (kale) için tuğla havuzu. Kopan blok, harç ızgarasıyla aynı boyutta
## tuğlalara ayrılır. Mobil için:
##  - Tüm tuğlalar tek MultiMesh ile çizilir (tuğla başına draw call yok); yalnız uyanık
##    tuğlaların dönüşümü her karede güncellenir.
##  - Tuğlaların script'i yok: darbe sesi/tozu ve dinlenme dondurması buradan yürür.
##  - Kare başına tuğla üretim bütçesi; toplam canlı tuğla tavanı (grafik kalitesine
##    bağlı). Tavan dolunca en eski duran tuğlalar fizikten çıkarılıp sabit moloz
##    olarak çizilmeye devam eder.

const SPAWN_PER_FRAME := 110
const REST_FREEZE := 1.2

const CAP := 1500
## Aynı anda fizikte tutulan tuğla tavanı (grafik kalitesine göre, ≤ CAP)
static var limit := 1500
## Aynı anda hareket eden tuğla tavanı: büyük çöküşte aşılırsa bloklar bütün kalır
static var active_limit := 450

var brick := Vector3(1.5, 1.0, 1.0)
var material: Material
var kind := "stone"
var density := 2300.0

var _mm: MultiMesh
var _rubble: MultiMesh
var _rubble_next := 0
var _bodies: Array = []  # indeks -> RigidBody3D / null
var _sizes := PackedVector3Array()
var _prev_v := PackedVector3Array()
var _rest := PackedFloat32Array()
var _free: Array[int] = []
var _active := {}
var _order: Array[int] = []  # üretim sırası (geri dönüşüm için)
var _queue: Array[Destructible] = []
var _shapes := {}
var _pm: PhysicsMaterial
var _fx_budget := 0
var _alive := 0


func setup(mat: Material, brick_size: Vector3, kind_name: String, dens: float) -> void:
	material = mat
	brick = brick_size
	kind = kind_name
	density = dens


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	box.material = material
	_mm = _make_mm(box, CAP)
	_rubble = _make_mm(box, CAP)
	_bodies.resize(CAP)
	_sizes.resize(CAP)
	_prev_v.resize(CAP)
	_rest.resize(CAP)
	for i in range(CAP - 1, -1, -1):
		_free.append(i)
	_pm = PhysicsMaterial.new()
	_pm.friction = 0.85
	_pm.bounce = 0.04


func _make_mm(mesh: Mesh, n: int) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = n
	var hidden := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -1000, 0))
	for i in n:
		mm.set_instance_transform(i, hidden)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	# Dönüşümler _process'te elle ara değerlendirilir (gövdelerin interpolasyonlu konumu)
	mmi.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	# Görünürlük kutusu: tüm alan (parçalar her yere savrulabilir)
	mmi.custom_aabb = AABB(Vector3(-400, -50, -400), Vector3(800, 300, 800))
	add_child(mmi)
	return mm


## Bloğu tuğlalara ayırma isteği (kuyruğa alınır, bütçeyle işlenir)
func stats() -> String:
	var r := "tuğla %d (hareketli %d) script %d ms (üretim %d)" % [_alive, _active.size(), prof_us / 1000, shatter_us / 1000]
	prof_us = 0
	shatter_us = 0
	return r


func request(d: Destructible) -> void:
	if not _queue.has(d):
		_queue.append(d)


var prof_us := 0
var shatter_us := 0


func _physics_process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_fx_budget = 3
	var made := 0
	while not _queue.is_empty() and made < SPAWN_PER_FRAME:
		if _active.size() >= active_limit:
			_queue.clear()  # blok bütün kalır; sonraki sert darbede yeniden istenir
			break
		var d = _queue.pop_front()
		if is_instance_valid(d) and d.is_inside_tree():
			var ts := Time.get_ticks_usec()
			made += _shatter(d)
			shatter_us += Time.get_ticks_usec() - ts
	for i: int in _active.keys():
		var b: RigidBody3D = _bodies[i]
		if b == null:
			_active.erase(i)
			continue
		var v := b.linear_velocity
		var dv := (v - _prev_v[i]).length()
		_prev_v[i] = v
		if dv > 4.0 and _fx_budget > 0:
			_fx_budget -= 1
			var p := b.global_position
			Sfx.impact(kind, p, dv)
			if dv > 7.0:
				Fx.dust(p, clampf(dv / 12.0, 0.3, 1.2))
			var e := 0.5 * b.mass * dv * dv
			if e > 150000.0:
				# Yüksekten düşen tuğla kümesi alttaki sağlam örgüyü ezer
				Building.strike(get_world_3d(), p, e * 0.5, Vector3.DOWN, b)
		if v.length_squared() < 0.8 and b.angular_velocity.length_squared() < 1.0:
			_rest[i] += delta
			if _rest[i] > REST_FREEZE:
				_freeze(i)
		else:
			_rest[i] = 0.0
	prof_us += Time.get_ticks_usec() - t0


func _process(_delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	for i: int in _active:
		var b: RigidBody3D = _bodies[i]
		if b:
			_draw(i, b.get_global_transform_interpolated())
	prof_us += Time.get_ticks_usec() - t0


func _draw(i: int, t: Transform3D) -> void:
	_mm.set_instance_transform(i, Transform3D(t.basis * Basis.from_scale(_sizes[i]), t.origin))


func _freeze(i: int) -> void:
	var b: RigidBody3D = _bodies[i]
	_active.erase(i)
	b.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	b.freeze = true
	_draw(i, b.global_transform)


## Donmuş tuğlayı yeniden dinamik yap (mermi yaklaşınca / patlamada)
func thaw(b: RigidBody3D) -> void:
	var i: int = b.get_meta("brick", -1)
	if i < 0 or _bodies[i] != b:
		return
	if b.freeze:
		b.freeze = false
	b.sleeping = false
	_rest[i] = 0.0
	_active[i] = true


func _on_sleep(i: int) -> void:
	var b: RigidBody3D = _bodies[i]
	if b == null:
		return
	if b.sleeping:
		_draw(i, b.global_transform)
		_active.erase(i)
	else:
		_active[i] = true


func _shape(size: Vector3) -> BoxShape3D:
	var k := size.snapped(Vector3.ONE * 0.01)
	if not _shapes.has(k):
		var s := BoxShape3D.new()
		s.size = k - Vector3.ONE * 0.06  # komşu tuğlalar sıkışmasın
		_shapes[k] = s
	return _shapes[k]


func _alloc() -> int:
	if not _free.is_empty() and _alive < limit:
		_alive += 1
		return _free.pop_back()
	# Tavan dolu: en eski tuğlayı sabit moloza çevir
	while not _order.is_empty():
		var i: int = _order.pop_front()
		var b: RigidBody3D = _bodies[i]
		if b == null:
			continue
		var t := b.global_transform
		_rubble.set_instance_transform(_rubble_next, Transform3D(t.basis * Basis.from_scale(_sizes[i]), t.origin))
		_rubble.set_instance_custom_data(_rubble_next, Color(_sizes[i].x, _sizes[i].y, _sizes[i].z, 1.0))
		_rubble_next = (_rubble_next + 1) % _rubble.instance_count
		b.queue_free()
		_bodies[i] = null
		_active.erase(i)
		return i
	return -1


## Bloğu tuğla ızgarasına böl. Döner: üretilen tuğla sayısı.
func _shatter(d: Destructible) -> int:
	var size: Vector3 = d.get_meta("block_size")
	var n := Vector3i(maxi(1, roundi(size.x / brick.x)), maxi(1, roundi(size.y / brick.y)), maxi(1, roundi(size.z / brick.z)))
	var cell := Vector3(size.x / n.x, size.y / n.y, size.z / n.z)
	var xf := d.global_transform
	var v := d.linear_velocity
	var w := d.angular_velocity
	var shape := _shape(cell)
	# Darbeyle kopan blok: tuğlalar en az ~4 m/s ile darbe yönünde savrulur
	if d.hit_point != Vector3.INF and v.length() < 4.0:
		v = v.normalized() * 4.0 if v.length() > 0.1 else (xf.origin - d.hit_point).normalized() * 4.0
	var m := cell.x * cell.y * cell.z * density
	var made := 0
	for x in n.x:
		for y in n.y:
			for z in n.z:
				var i := _alloc()
				if i < 0:
					break
				var local := Vector3((x + 0.5) * cell.x, (y + 0.5) * cell.y, (z + 0.5) * cell.z) - size * 0.5
				var p := xf * local
				var b := RigidBody3D.new()
				var cs := CollisionShape3D.new()
				cs.shape = shape
				b.add_child(cs)
				b.mass = m
				b.physics_material_override = _pm
				b.collision_layer = 2
				b.collision_mask = 1 | 2 | 4 | 8 | 16
				b.set_meta("brick", i)
				b.set_meta("pool", self)
				add_child(b)
				b.global_transform = Transform3D(xf.basis, p)
				# Dağılma: bloğun hızı + dönüşü + hafif dışa açılma
				var r := p - xf.origin
				# Darbe yönündeki hız tuğlalara geçer; ön yüzdekiler daha hızlı (enerji önce onlara)
				var near := 1.0
				if d.hit_point != Vector3.INF:
					near += 3.0 * exp(-p.distance_to(d.hit_point) / 1.8)
				var push := v * near * randf_range(0.8, 1.3)
				b.linear_velocity = push + w.cross(r) + r.normalized() * randf_range(0.5, 1.5)
				b.angular_velocity = w + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))
				b.sleeping_state_changed.connect(_on_sleep.bind(i))
				_bodies[i] = b
				_sizes[i] = cell
				_prev_v[i] = b.linear_velocity
				_rest[i] = 0.0
				_mm.set_instance_custom_data(i, Color(cell.x, cell.y, cell.z, 1.0))
				_draw(i, b.global_transform)
				_active[i] = true
				_order.append(i)
				made += 1
	Fx.dust(xf.origin, clampf(size.length() / 4.0, 0.6, 1.8))
	Fx.rubble(xf.origin, Vector3.UP, 0.8)
	Sfx.debris(xf.origin, 12.0)
	if d.building and d.building.has_method("forget"):
		d.building.forget(d)
	d.queue_free()
	return made
