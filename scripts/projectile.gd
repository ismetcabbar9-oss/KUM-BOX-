class_name Projectile
extends RigidBody3D
## Fırlatılan her şey: kaya türleri, dönen testere, çelik gülle, patlayıcı varil.
##
## Binaya çarpma "öngörülü" işlenir: mermi bir sonraki adımda sağlam bir parçaya değecekse
## kinetik enerjisi önceden Building.strike() ile uygulanır; kırılan parçalar o adımda
## dinamikleşir ve çarpışma fiziksel olarak sürer. Kırmaya harcanan enerji merminin
## hızından düşülür.

const AMMO := {
	"granite": {"name": "GRANİT", "rock": "granite", "density": 2700.0},
	"basalt": {"name": "BAZALT", "rock": "basalt", "density": 3000.0},
	"mossy": {"name": "YOSUNLU KAYA", "rock": "mossy", "density": 2500.0},
	"sandstone": {"name": "KUMTAŞI", "rock": "sandstone", "density": 2200.0},
	"river": {"name": "DERE TAŞI", "rock": "river_0", "density": 2650.0},
	"saw": {"name": "DÖNEN TESTERE", "density": 7850.0},
	"steel": {"name": "ÇELİK GÜLLE", "density": 7850.0},
	"bomb": {"name": "PATLAYICI VARİL", "density": 900.0},
}
const ORDER := ["granite", "basalt", "mossy", "sandstone", "river", "saw", "steel", "bomb"]

static var _hull_cache := {}

var ammo := "granite"
var radius := 1.0
var launched := false
var exploded := false
## Kırmaya harcanan enerjinin ne kadarı mermiden düşülür (testere keser: az kaybeder)
var energy_cost := 1.0
var _loop: AudioStreamPlayer3D
var _prev_v := Vector3.ZERO
var _cooldown := 0.0
var _strike_cooldown := 0.0
var _thaw_timer := 0.0
var _touching := false
var _query: PhysicsShapeQueryParameters3D
var _age := 0.0


## r: yarıçap (m). rolling: rampada yuvarlanacaksa küre çarpışma kullanılır.
func setup(ammo_id: String, r: float, rolling: bool) -> void:
	ammo = ammo_id
	radius = r
	var def: Dictionary = AMMO[ammo]
	var density: float = def["density"]
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.01
	angular_damp = 0.05
	can_sleep = false
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.08
	if def.has("rock"):
		_build_rock(def["rock"], r, density, rolling)
	else:
		match ammo:
			"saw":
				_build_saw(r, density)
				pm.friction = 1.0
				energy_cost = 0.35
			"steel":
				_build_steel(r, density)
				pm.bounce = 0.15
			"bomb":
				_build_bomb(r, density)
	physics_material_override = pm
	if _loop == null:
		_loop = AudioStreamPlayer3D.new()
		_loop.stream = Sfx.stream("roll_loop")
		_loop.bus = "SFX"
		_loop.unit_size = 18.0
		_loop.max_db = 6.0
		_loop.volume_db = -80.0
		add_child(_loop)


func _build_rock(mesh_name: String, r: float, density: float, rolling: bool) -> void:
	var mesh: Mesh = load("res://assets/rocks/%s.res" % mesh_name)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)
	var b := mesh.get_aabb()  # en büyük boyut = 1, orijin merkezli
	var cs := CollisionShape3D.new()
	if rolling:
		# Rampa: küre çarpışma, görsel küreye doğru hafifçe toplanır (takılmadan yuvarlanır)
		var avg := (b.size.x + b.size.y + b.size.z) / 3.0
		var sc := Vector3.ZERO
		for ax in 3:
			sc[ax] = 2.0 * r * pow(b.size[ax] / avg, 0.35) / b.size[ax]
		mi.scale = sc
		mi.position = -b.get_center() * sc
		var sphere := SphereShape3D.new()
		sphere.radius = r * 0.93
		cs.shape = sphere
		mass = 4.0 / 3.0 * PI * pow(r, 3) * density
	else:
		# Uçan kaya: gerçek şekil (dışbükey örtü), takla atarak gider
		var s := 2.0 * r
		mi.scale = Vector3.ONE * s
		if not _hull_cache.has(mesh_name):
			_hull_cache[mesh_name] = (mesh.create_convex_shape(true, true) as ConvexPolygonShape3D).points
		var pts := PackedVector3Array()
		for p in _hull_cache[mesh_name]:
			pts.append(p * s)
		var hull := ConvexPolygonShape3D.new()
		hull.points = pts
		cs.shape = hull
		var e := b.size * s * 0.5
		mass = 4.0 / 3.0 * PI * e.x * e.y * e.z * density * 0.8
	add_child(cs)


func _build_saw(r: float, density: float) -> void:
	var visual := Models.instance("saw")
	add_child(visual)
	var bb := Models.local_aabb(visual)
	# Diskin ince ekseni yerel X olsun (Z yönünde yuvarlanır)
	var thin_axis := 0
	for ax in 3:
		if bb.size[ax] < bb.size[thin_axis]:
			thin_axis = ax
	var s := 2.0 * r / maxf(bb.size[(thin_axis + 1) % 3], bb.size[(thin_axis + 2) % 3])
	var holder := Node3D.new()
	remove_child(visual)
	holder.add_child(visual)
	visual.scale = Vector3.ONE * s
	visual.position = -bb.get_center() * s
	if thin_axis == 1:
		holder.rotation_degrees = Vector3(0, 0, 90)
	elif thin_axis == 2:
		holder.rotation_degrees = Vector3(0, 90, 0)
	add_child(holder)
	var thick := maxf(bb.size[thin_axis] * s, 0.08)
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = thick
	var cs := CollisionShape3D.new()
	cs.shape = cyl
	cs.rotation_degrees = Vector3(0, 0, 90)  # silindir ekseni X
	add_child(cs)
	mass = PI * r * r * thick * density
	angular_damp = 0.02


func _build_steel(r: float, density: float) -> void:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = 2.0 * r
	sm.radial_segments = 40
	sm.rings = 20
	var mat := WorldBuilder.pbr("metal_plate", 0.6 / r, Color(0.55, 0.56, 0.58), false)
	mat = mat.duplicate()
	mat.metallic = 1.0
	mat.metallic_specular = 0.6
	sm.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	add_child(mi)
	var sphere := SphereShape3D.new()
	sphere.radius = r
	var cs := CollisionShape3D.new()
	cs.shape = sphere
	add_child(cs)
	mass = 4.0 / 3.0 * PI * pow(r, 3) * density


func _build_bomb(r: float, density: float) -> void:
	var visual := Models.instance("barrel")
	add_child(visual)
	Models.fit(visual, 2.0 * r, "height", true)
	for mi: MeshInstance3D in visual.find_children("*", "MeshInstance3D", true, false):
		var m := mi.get_active_material(0)
		if m is BaseMaterial3D:
			m = m.duplicate()
			m.albedo_color = Color(1.0, 0.35, 0.2)
			mi.material_override = m
	var b := Models.local_aabb(visual)
	var cyl := CylinderShape3D.new()
	cyl.radius = maxf(b.size.x, b.size.z) * visual.scale.x * 0.5
	cyl.height = 2.0 * r
	var cs := CollisionShape3D.new()
	cs.shape = cyl
	add_child(cs)
	mass = PI * cyl.radius * cyl.radius * cyl.height * density


func display_name() -> String:
	return AMMO[ammo]["name"]


## Fırlat: v başlangıç hızı (m/s vektörü). spin: açısal hız.
func launch(velocity: Vector3, spin := Vector3.ZERO) -> void:
	freeze = false
	launched = true
	linear_velocity = velocity
	if ammo == "saw":
		# Testere: kendi ekseninde (yerel X) yüksek devir; yere değince ileri sürer
		var axis := global_transform.basis.x.normalized()
		angular_velocity = axis * 70.0
		_loop.stream = Sfx.stream("saw_loop")
	else:
		angular_velocity = spin
	_loop.play()


func speed_kmh() -> float:
	return linear_velocity.length() * 3.6


func kinetic_energy() -> float:
	var e := 0.5 * mass * linear_velocity.length_squared()
	if ammo == "saw":
		# Dönme enerjisi (ince disk, I = m r² / 2) de kesmeye gider
		e += 0.25 * mass * radius * radius * angular_velocity.length_squared()
	return e


func _physics_process(delta: float) -> void:
	if not launched or exploded:
		return
	_age += delta
	_touching = get_contact_count() > 0
	var v := linear_velocity
	var spd := v.length()
	if ammo != "saw":
		# Yuvarlanma direnci: hızlıyken neredeyse yok, yavaşlayınca durur
		var k := clampf(spd / 8.0, 0.0, 1.0)
		angular_damp = lerpf(1.2, 0.05, k) if _touching else 0.05
		linear_damp = lerpf(0.3, 0.01, k) if _touching else 0.01
	if spd < 0.3 and _age > 3.0:
		can_sleep = true
	_update_loop(delta)

	# Öngörülü bina darbesi
	_strike_cooldown -= delta
	if spd > 3.5 and _strike_cooldown <= 0.0:
		_predictive_strike(delta)

	# Donmuş molozu çöz
	_thaw_timer -= delta
	if _thaw_timer <= 0.0 and spd > 2.0:
		_thaw_timer = 0.15
		_thaw_nearby()

	# Darbe: tek adımdaki hız değişimi
	var dv := (v - _prev_v).length()
	_prev_v = v
	_cooldown -= delta
	if dv > 1.5 and _cooldown <= 0.0:
		_cooldown = 0.12
		var p := global_position + (v.normalized() * radius if spd > 0.5 else Vector3.DOWN * radius)
		if ammo == "bomb" and _age > 0.2:
			explode()
			return
		var kind := "metal" if ammo == "saw" or ammo == "steel" else "rock"
		Sfx.impact(kind, p, dv * 3.0)
		Fx.dust(p, clampf(dv * radius * 0.5, 0.5, 2.5))
		Fx.shake(clampf(dv * radius * 0.12 * sqrt(mass / 20000.0), 0.0, 1.0))


func _update_loop(delta: float) -> void:
	var target_db := -80.0
	if ammo == "saw":
		var w := angular_velocity.length()
		target_db = linear_to_db(clampf(w / 70.0, 0.05, 1.0)) - 2.0
		_loop.pitch_scale = clampf(0.5 + w / 90.0, 0.5, 1.4) * Engine.time_scale
	else:
		var spin := angular_velocity.length() * radius
		if _touching and spin > 0.5:
			target_db = linear_to_db(clampf(spin / 20.0, 0.05, 1.0)) + 2.0
		_loop.pitch_scale = clampf(0.7 + spin / 40.0, 0.7, 1.4) * Engine.time_scale
	_loop.volume_db = lerpf(_loop.volume_db, target_db, clampf(delta * 8.0, 0.0, 1.0))


func _shape_query(r: float, at: Vector3, mask: int) -> Array[Dictionary]:
	if _query == null:
		_query = PhysicsShapeQueryParameters3D.new()
		_query.shape = SphereShape3D.new()
	(_query.shape as SphereShape3D).radius = r
	_query.transform = Transform3D(Basis.IDENTITY, at)
	_query.collision_mask = mask
	return get_world_3d().direct_space_state.intersect_shape(_query, 32)


func _predictive_strike(delta: float) -> void:
	var v := linear_velocity
	var ahead := global_position + v * delta * 2.0
	var hit_intact := false
	for hit in _shape_query(radius * 1.05, ahead, 2):
		var d := hit["collider"] as Destructible
		if d and d.intact:
			hit_intact = true
			break
	if not hit_intact:
		return
	if ammo == "bomb":
		explode()
		return
	_strike_cooldown = 0.06
	var e := kinetic_energy()
	var used := Building.strike(get_world_3d(), ahead + v.normalized() * radius * 0.6, e, v, self)
	if used > 0.0:
		# Kırmaya giden enerji mermiden düşülür
		var remain := clampf(1.0 - used * energy_cost / maxf(e, 1.0), 0.05, 1.0)
		linear_velocity = v * sqrt(remain)
		if ammo == "saw":
			angular_velocity *= sqrt(remain)
			Sfx.impact("metal", global_position, 20.0)
		Fx.shake(clampf(used / 2.0e6, 0.2, 1.0))


func _thaw_nearby() -> void:
	for hit in _shape_query(radius * 2.5, global_position + linear_velocity * 0.15, 2):
		var d := hit["collider"] as Destructible
		if d:
			d.thaw()


## Patlama: çevredeki yapıya enerji, serbest gövdelere itki, ses/ışık/duman.
func explode() -> void:
	if exploded:
		return
	exploded = true
	var p := global_position
	var energy := 6.0e6 * pow(radius / 0.6, 3.0)
	var blast_r := 9.0 * radius / 0.6
	Building.strike(get_world_3d(), p, energy, Vector3.UP * 0.3, self)
	for hit in _shape_query(blast_r, p, 2 | 4 | 8):
		var b := hit["collider"] as RigidBody3D
		if b == null or b == self:
			continue
		if b is Destructible:
			var d := b as Destructible
			if d.intact:
				continue
			d.thaw()
		elif b.freeze:
			continue
		var to := b.global_position - p
		var dist := maxf(to.length(), 0.5)
		var push := minf(energy * 0.004 / (dist * dist), 30.0 * b.mass)
		b.sleeping = false
		b.apply_impulse((to.normalized() + Vector3.UP * 0.6).normalized() * push, (p - b.global_position) * 0.2)
	Fx.explosion(p, radius / 0.6)
	Sfx.explosion(p)
	Fx.shake(1.0)
	queue_free()
