class_name Trebuchet
extends Launcher

## Bırakma pimi çözüldü: mermi kaşıktan ayrıldı
signal released(p: Projectile)
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
## Ağır mermi: kol ve karşı ağırlık mermiyle aynı oranda büyür (tüm kütleler aynı oranda
## ölçeklenince hareket değişmez: dev kaya, MASS_REF'lik taşla aynı yörüngede uçar).
## Gerçekte imkânsız oranlar oyunda "güçlendirilmiş mancınık" olarak ele alınır.
const MASS_REF := 6000.0
const ARM_MASS := 3200.0
var _scale := 1.0
var yaw_deg := 0.0
var arm: RigidBody3D
var cw: RigidBody3D
var _arm_rest: Transform3D
var _cw_rest: Transform3D
var _pin: PinJoint3D
var _pivot: HingeJoint3D
## Nişan yardımı: kalibrasyon tablosu (karşı ağırlık × mermi kütlesi -> bırakma konumu/hızı)
var _table := {}
var _aim_dots: MultiMeshInstance3D
var _aim_ring: MeshInstance3D
var _last_mark: MeshInstance3D
var _aim_key := ""
var _aim_range := -1.0
var _flying: Projectile
var _wood: Material
var _iron: Material


func _init() -> void:
	super()
	title = "MANCINIK"
	id = "trebuchet"
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
	arm.mass = ARM_MASS
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


## Nişan yardımını etkinleştir (tablo tools/dev/calibrate_trebuchet ile üretilir)
func use_aim_table(path: String) -> void:
	var txt := FileAccess.get_file_as_string(path)
	if txt != "":
		_table = JSON.parse_string(txt)
	released.connect(func(p: Projectile) -> void: _flying = p)


static func _bracket(arr: Array, x: float, log_scale: bool) -> Array:
	var v := log(x) if log_scale else x
	for i in arr.size() - 1:
		var a: float = log(arr[i]) if log_scale else arr[i]
		var b: float = log(arr[i + 1]) if log_scale else arr[i + 1]
		if v <= b or i == arr.size() - 2:
			return [i, clampf((v - a) / (b - a), 0.0, 1.0)]
	return [0, 0.0]


## Bırakma anı tahmini: [dünya konumu, dünya hızı]; mermi atılamıyorsa boş
func predict_release() -> Array:
	if _table.is_empty() or loaded == null:
		return []
	var ci := _bracket(_table["cw"], counterweight_t, false)
	var mi := _bracket(_table["mass"], loaded.mass / _scale, true)
	var data: Array = _table["data"]
	var acc := PackedFloat64Array([0, 0, 0, 0, 0, 0])
	for dc in 2:
		for dm in 2:
			var cell: Array = data[ci[0] + dc][mi[0] + dm]
			var w: float = (ci[1] if dc == 1 else 1.0 - ci[1]) * (mi[1] if dm == 1 else 1.0 - mi[1])
			if cell.is_empty():
				if w > 0.01:
					return []
				continue
			for k in 6:
				acc[k] += cell[k] * w
	var pos := to_global(Vector3(acc[0], acc[1], acc[2]))
	var vel := global_transform.basis * Vector3(acc[3], acc[4], acc[5])
	return [pos, vel]


func _aim_nodes() -> void:
	if _aim_dots:
		return
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.82, 0.25)
	var dot := SphereMesh.new()
	dot.radius = 0.35
	dot.height = 0.7
	dot.radial_segments = 8
	dot.rings = 4
	dot.material = m
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = dot
	mm.instance_count = 48
	_aim_dots = MultiMeshInstance3D.new()
	_aim_dots.multimesh = mm
	_aim_dots.top_level = true
	_aim_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_aim_dots)
	_aim_ring = _ring(Color(1.0, 0.82, 0.25), 4.0)
	var mark := _ring(Color(0.95, 0.2, 0.15), 2.2)
	_last_mark = mark
	_last_mark.visible = false


func _ring(c: Color, r: float) -> MeshInstance3D:
	var tm := TorusMesh.new()
	tm.inner_radius = r - 0.5
	tm.outer_radius = r
	tm.rings = 32
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	m.no_depth_test = true
	m.render_priority = 1
	tm.material = m
	var mi := MeshInstance3D.new()
	mi.mesh = tm
	mi.top_level = true
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## Tahmini yörünge: noktalar + düşüş halkası (yalnız ayar değişince yeniden hesaplanır)
func _update_aim() -> void:
	if _table.is_empty():
		return
	_aim_nodes()
	var ready := is_ready()
	_aim_dots.visible = ready
	_aim_ring.visible = ready
	if not ready:
		return
	var key := "%.1f|%.2f|%.0f" % [counterweight_t, yaw_deg, loaded.mass]
	if key == _aim_key:
		return
	_aim_key = key
	var mm := _aim_dots.multimesh
	var hide := Transform3D(Basis.from_scale(Vector3.ZERO), Vector3(0, -500, 0))
	var rel := predict_release()
	if rel.is_empty():
		for i in mm.instance_count:
			mm.set_instance_transform(i, hide)
		_aim_ring.visible = false
		_aim_range = -1.0
		return
	var p: Vector3 = rel[0]
	var v: Vector3 = rel[1]
	var dt := 1.0 / 30.0
	var space := get_world_3d().direct_space_state
	var dot_i := 0
	var hit := {}
	for step in 600:
		v += Vector3(0, -9.81, 0) * dt
		v *= 1.0 - 0.01 * dt
		var np := p + v * dt
		var q := PhysicsRayQueryParameters3D.create(p, np, 1 | 2)
		q.exclude = [loaded.get_rid()]
		hit = space.intersect_ray(q)
		if hit:
			break
		p = np
		if step % 8 == 0 and dot_i < mm.instance_count:
			mm.set_instance_transform(dot_i, Transform3D(Basis.IDENTITY, p))
			dot_i += 1
	for i in range(dot_i, mm.instance_count):
		mm.set_instance_transform(i, hide)
	if hit:
		var n: Vector3 = hit["normal"]
		var b := Basis.looking_at(n.cross(Vector3.RIGHT).normalized() if absf(n.dot(Vector3.RIGHT)) < 0.9 else n.cross(Vector3.FORWARD).normalized(), n)
		_aim_ring.global_transform = Transform3D(b, hit["position"] + n * 0.2)
		_aim_range = Vector2(hit["position"].x - global_position.x, hit["position"].z - global_position.z).length()
	else:
		_aim_ring.visible = false
		_aim_range = -1.0


func _process(_delta: float) -> void:
	_update_aim()
	# Son atışın ilk çarptığı yer: kırmızı halka
	if _flying and is_instance_valid(_flying):
		if _flying.get_contact_count() > 0:
			_last_mark.visible = true
			_last_mark.global_transform = Transform3D(Basis.IDENTITY, _flying.global_position + Vector3.DOWN * (_flying.radius - 0.2))
			_flying = null


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
	_scale = maxf(1.0, p.mass / MASS_REF)
	arm.mass = ARM_MASS * _scale
	cw.mass = counterweight_t * 1000.0 * _scale
	p.add_collision_exception_with(cw)
	p.global_transform = Transform3D(global_transform.basis, _cup_point(p.radius))
	p.reset_physics_interpolation()


func drag(relative: Vector2, _vs: Vector2) -> void:
	if not is_ready():
		return
	yaw_deg = clampf(yaw_deg - relative.x * 0.12, -35.0, 35.0)
	rotation_degrees.y = yaw_deg
	counterweight_t = clampf(counterweight_t - relative.y * 0.2 * max_counterweight / 180.0, 30.0, max_counterweight)
	cw.mass = counterweight_t * 1000.0 * _scale
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
		released.emit(loaded)


func info() -> String:
	var t := "Yön %+d°   Karşı ağırlık %d t" % [roundi(yaw_deg), roundi(counterweight_t * _scale)]
	if not _table.is_empty():
		t += ("   Menzil ~%d m" % roundi(_aim_range)) if _aim_range > 0.0 else "   Karşı ağırlık yetersiz"
	return t


func hint() -> String:
	return "Yana sürükle: yön   •   Yukarı/aşağı: karşı ağırlık   •   FIRLAT"
