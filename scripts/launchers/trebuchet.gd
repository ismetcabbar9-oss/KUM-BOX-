class_name Trebuchet
extends Launcher
## Mancınık (karşı ağırlıklı): tamamen fiziksel.
##  - Kol: menteşeyle (HingeJoint3D) gövdeye bağlı RigidBody. Açı sınırı = durdurucu.
##  - Karşı ağırlık: kolun kısa ucuna menteşeyle asılı, serbest sallanır.
##  - Kaşık: kolun uzun ucunda taban + dudaklar. Kol sınıra çarpıp durunca mermi
##    kaşıktan ataletle (teğet yönde) kopar.
## Yana sürükle: yön. Dikey sürükle: karşı ağırlık (güç).

var pivot_h := 9.0
var l_long := 12.0
var l_short := 3.2
const COCK_DEG := 35.0
const SWING_DEG := 95.0
## Bırakma pimi açısı (kolun yataya göre açısı). Teğet yön = 90° - bu açı yükseliş.
var release_deg := 48.0

var counterweight_t := 90.0  # ton
var max_counterweight := 180.0
var yaw_deg := 0.0
var arm: RigidBody3D
var cw: RigidBody3D
var _arm_rest: Transform3D
var _cw_rest: Transform3D
var _pin: PinJoint3D
var _pivot: HingeJoint3D
var _wood: Material
var _iron: Material


func _init() -> void:
	super()
	title = "MANCINIK"
	base_radius = 0.6
	view_distance = 22.0


func _ready() -> void:
	_wood = WorldBuilder.pbr("rough_wood", 0.5, Color(0.9, 0.85, 0.8), false)
	_iron = WorldBuilder.pbr("rusty_metal_02", 0.5, Color.WHITE, false)
	var frame := Node3D.new()
	add_child(frame)
	# Yan çerçeveler (A şeklinde) + taban kirişleri
	for sx in [-1.4, 1.4]:
		for sz in [-1.0, 1.0]:
			var a := Vector3(sx, 0.0, sz * 4.5)
			var b := Vector3(sx, pivot_h, 0.0)
			var mid := (a + b) * 0.5
			var len := a.distance_to(b)
			var basis := Basis.looking_at((b - a).normalized(), Vector3.RIGHT).rotated(Vector3.UP, 0.0)
			beam(frame, Vector3(0.45, 0.45, len), Transform3D(basis, mid), _wood)
		beam(frame, Vector3(0.5, 0.5, 9.6), Transform3D(Basis.IDENTITY, Vector3(sx, 0.25, 0)), _wood)
	for sz in [-4.3, 4.3]:
		beam(frame, Vector3(3.3, 0.45, 0.45), Transform3D(Basis.IDENTITY, Vector3(0, 0.25, sz)), _wood)
	# Mil
	var axle := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.18
	cm.height = 3.4
	axle.mesh = cm
	axle.material_override = _iron
	axle.rotation_degrees = Vector3(0, 0, 90)
	axle.position = Vector3(0, pivot_h, 0)
	frame.add_child(axle)

	# Kol (yerel -Z uzun uç), kurulu açı
	arm = RigidBody3D.new()
	arm.name = "Arm"
	_arm_rest = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-COCK_DEG)), Vector3(0, pivot_h, 0))
	arm.transform = _arm_rest
	arm.mass = 3200.0
	_arm_box(Vector3(0.5, 0.6, l_long + l_short), Vector3(0, 0, (l_short - l_long) * 0.5), _wood)
	_arm_box(Vector3(1.8, 0.15, 1.8), Vector3(0, 0.375, -l_long + 0.9), _iron)  # kaşık tabanı
	# Alçak dudaklar: kurulu dururken mermiyi tutar, kol durunca mermi üstünden aşar
	_arm_box(Vector3(1.8, 0.4, 0.15), Vector3(0, 0.65, -l_long - 0.075), _iron)
	for sx in [-0.975, 0.975]:
		_arm_box(Vector3(0.15, 0.3, 1.8), Vector3(sx, 0.6, -l_long + 0.9), _iron)
	arm.collision_layer = 8
	arm.collision_mask = 4
	arm.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	arm.freeze = true
	arm.can_sleep = false
	add_child(arm)

	# Karşı ağırlık: kısa uca asılı demir kasa
	cw = RigidBody3D.new()
	cw.name = "Counterweight"
	var short_end := _arm_rest * Vector3(0, 0, l_short)
	_cw_rest = Transform3D(Basis.IDENTITY, short_end + Vector3(0, -1.6, 0))
	cw.transform = _cw_rest
	var cwm := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.8, 1.8, 1.8)
	cwm.mesh = bm
	cwm.material_override = _iron
	cw.add_child(cwm)
	var cws := CollisionShape3D.new()
	var cbs := BoxShape3D.new()
	cbs.size = bm.size
	cws.shape = cbs
	cw.add_child(cws)
	cw.mass = counterweight_t * 1000.0
	cw.collision_layer = 8
	cw.collision_mask = 1 | 2
	cw.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	cw.freeze = true
	cw.can_sleep = false
	add_child(cw)
	# Askı çubuğu (görsel)
	var rod := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.15, 1.6, 0.15)
	rod.mesh = rm
	rod.material_override = _iron
	rod.position = Vector3(0, 0.8 + 0.9, 0)
	cw.add_child(rod)

	# Menteşeler (eksen: eklemin yerel Z'si -> dünya X)
	_make_pivot()
	var hang := HingeJoint3D.new()
	hang.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), short_end)
	add_child(hang)
	hang.node_a = hang.get_path_to(arm)
	hang.node_b = hang.get_path_to(cw)
	view_target.position = Vector3(0, 4.0, -2.0)
	rotation_degrees.y = yaw_deg


## Kol menteşesi (dünyaya bağlı). Dünya uzayında kurulur: fırlatıcı döndürülünce yeniden kurulmalı.
func _make_pivot() -> void:
	if _pivot:
		_pivot.free()
	_pivot = HingeJoint3D.new()
	_pivot.transform = Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, pivot_h, 0))
	add_child(_pivot)
	_pivot.set_flag(HingeJoint3D.FLAG_USE_LIMIT, true)
	_pivot.set_param(HingeJoint3D.PARAM_LIMIT_LOWER, deg_to_rad(-SWING_DEG))
	_pivot.set_param(HingeJoint3D.PARAM_LIMIT_UPPER, deg_to_rad(2.0))
	_pivot.node_a = _pivot.get_path_to(arm)
	_pivot.node_b = NodePath("")


func _arm_box(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	arm.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	cs.position = pos
	arm.add_child(cs)


func _cup_point(r: float) -> Vector3:
	return arm.global_transform * Vector3(0, 0.45 + r, -l_long + r + 0.2)


func load_projectile(p: Projectile) -> void:
	# Kolu ve ağırlığı kurulu konuma geri al
	if _pin:
		_pin.queue_free()
		_pin = null
	arm.freeze = true
	cw.freeze = true
	arm.transform = _arm_rest
	cw.transform = _cw_rest
	arm.linear_velocity = Vector3.ZERO
	arm.angular_velocity = Vector3.ZERO
	cw.linear_velocity = Vector3.ZERO
	cw.angular_velocity = Vector3.ZERO
	arm.reset_physics_interpolation()
	cw.reset_physics_interpolation()
	loaded = p
	p.add_collision_exception_with(cw)
	p.global_transform = Transform3D(global_transform.basis, _cup_point(p.radius))
	p.reset_physics_interpolation()


func drag(relative: Vector2, _vs: Vector2) -> void:
	if not is_ready():
		return
	yaw_deg = clampf(yaw_deg - relative.x * 0.12, -35.0, 35.0)
	rotation_degrees.y = yaw_deg
	counterweight_t = clampf(counterweight_t - relative.y * 0.2 * max_counterweight / 180.0, 30.0, max_counterweight)
	cw.mass = counterweight_t * 1000.0
	loaded.global_transform = Transform3D(global_transform.basis, _cup_point(loaded.radius))


func release(swipe_up_speed: float) -> bool:
	return false


func fire(_power := -1.0) -> void:
	if not is_ready():
		return
	var p := loaded
	_make_pivot()  # güncel yön/konumla
	arm.freeze = false
	cw.freeze = false
	# Yüklemede kinematik ışınlanma gövdeye sahte hız bırakır: durgun başla
	for b: RigidBody3D in [arm, cw]:
		b.linear_velocity = Vector3.ZERO
		b.angular_velocity = Vector3.ZERO
	p.launch(Vector3.ZERO)
	# Bırakma pimi: mermi kaşığa fiziksel eklemle bağlı (kütlesi kolu yükler)
	_pin = PinJoint3D.new()
	add_child(_pin)
	_pin.global_position = p.global_position
	_pin.node_a = _pin.get_path_to(arm)
	_pin.node_b = _pin.get_path_to(p)
	Sfx.play("creak", global_position + Vector3.UP * pivot_h, 0.0)
	Sfx.play("catapult", global_position + Vector3.UP * pivot_h, 2.0)
	fired.emit(p)


func _physics_process(_delta: float) -> void:
	if _pin and arm.rotation_degrees.x >= release_deg:
		# Pim çözülür; kaşık mermiye artık dokunmaz (hâlâ hızlanan kol mermiye çarpmasın)
		if is_instance_valid(loaded):
			loaded.add_collision_exception_with(arm)
		_pin.queue_free()
		_pin = null


func info() -> String:
	return "Yön %+d°   Karşı ağırlık %d t" % [roundi(yaw_deg), roundi(counterweight_t)]


func hint() -> String:
	return "Yana sürükle: yön   •   Yukarı/aşağı: karşı ağırlık   •   FIRLAT"
