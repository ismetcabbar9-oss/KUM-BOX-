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
	"multisaw": {"name": "ÜÇLÜ TESTERE", "density": 7850.0},
	"sticky": {"name": "YAPIŞKAN BOMBA", "density": 1400.0},
	"fire": {"name": "ATEŞ GÜLLESİ", "density": 900.0},
}
const ORDER := ["granite", "basalt", "mossy", "sandstone", "river", "saw", "steel", "bomb", "multisaw", "sticky", "fire"]
const STICKY_FUSE := 1.8

static var _hull_cache := {}
## Sığ su bölgeleri (hendek): içinden geçen mermi yavaşlar, su sıçrar
static var water_zones: Array[AABB] = []

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
## Serbest uçuş algılama (ayrılan mermiler için): yalnız yerçekimiyle hızlanan kare sayısı
var _free_frames := 0
var _deployed := false
var _stuck := false
var _fuse := 0.0
var _beep_t := 0.0
var _glow: StandardMaterial3D
var _in_water := false
var _fire_fx: GPUParticles3D
var _ignite_cd := 0.0
var _fire_spots := 0
var _fire_light: OmniLight3D


## r: yarıçap (m). rolling: rampada yuvarlanacaksa küre çarpışma kullanılır.
func setup(ammo_id: String, r: float, rolling: bool) -> void:
	ammo = ammo_id
	radius = r
	var def: Dictionary = AMMO[ammo]
	var density: float = def["density"]
	collision_layer = 4
	collision_mask = 1 | 2 | 4 | 8 | 16
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
			"multisaw":
				radius = r * 0.65
				_build_saw(radius, density)
				pm.friction = 1.0
				energy_cost = 0.35
			"sticky":
				radius = r * 0.6
				_build_sticky(radius, density)
				pm.friction = 1.0
				pm.bounce = 0.0
			"fire":
				_build_fire(r, density)
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


## Yapışkan bomba: kırmızı küre + yanıp sönen ışık
func _build_sticky(r: float, density: float) -> void:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = 2.0 * r
	_glow = StandardMaterial3D.new()
	_glow.albedo_color = Color(0.55, 0.06, 0.04)
	_glow.roughness = 0.35
	_glow.emission_enabled = true
	_glow.emission = Color(1.0, 0.15, 0.05)
	_glow.emission_energy_multiplier = 0.0
	sm.material = _glow
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	add_child(mi)
	var sphere := SphereShape3D.new()
	sphere.radius = r
	var cs := CollisionShape3D.new()
	cs.shape = sphere
	add_child(cs)
	mass = 4.0 / 3.0 * PI * pow(r, 3) * density


## Ateş güllesi: ziftli bez sarılı top, yanarak uçar
func _build_fire(r: float, density: float) -> void:
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = 2.0 * r
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.12, 0.08, 0.05)
	mat.roughness = 0.9
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.04)
	mat.emission_energy_multiplier = 0.7
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


## Uçarken alev + duman izi ve turuncu ışık (yangın sisteminin görünümünü kullanır)
func _start_fire_trail() -> void:
	if FireSystem.inst == null or _fire_fx:
		return
	var src: GPUParticles3D = FireSystem.inst._fx[0]
	_fire_fx = GPUParticles3D.new()
	_fire_fx.process_material = src.process_material
	_fire_fx.draw_pass_1 = src.draw_pass_1
	_fire_fx.amount = 70
	_fire_fx.lifetime = 1.0
	_fire_fx.local_coords = false
	_fire_fx.visibility_aabb = AABB(Vector3(-40, -40, -40), Vector3(80, 80, 80))
	_fire_fx.scale = Vector3.ONE * maxf(radius * 1.3, 0.8)
	add_child(_fire_fx)
	_fire_fx.emitting = true
	var smoke_src: GPUParticles3D = FireSystem.inst._smoke[0]
	var smoke := GPUParticles3D.new()
	smoke.process_material = smoke_src.process_material
	smoke.draw_pass_1 = smoke_src.draw_pass_1
	smoke.amount = 30
	smoke.lifetime = 2.5
	smoke.local_coords = false
	smoke.visibility_aabb = AABB(Vector3(-80, -80, -80), Vector3(160, 160, 160))
	smoke.scale = Vector3.ONE * maxf(radius, 0.6)
	add_child(smoke)
	smoke.emitting = true
	_fire_light = OmniLight3D.new()
	_fire_light.light_color = Color(1.0, 0.55, 0.2)
	_fire_light.light_energy = 3.0
	_fire_light.omni_range = 10.0 + radius * 4.0
	add_child(_fire_light)


func display_name() -> String:
	return AMMO[ammo]["name"]


## Fırlat: v başlangıç hızı (m/s vektörü). spin: açısal hız.
func launch(velocity: Vector3, spin := Vector3.ZERO) -> void:
	freeze = false
	launched = true
	linear_velocity = velocity
	if ammo == "fire":
		_start_fire_trail()
	if ammo == "saw" or ammo == "multisaw":
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
	if ammo == "saw" or ammo == "multisaw":
		# Dönme enerjisi (ince disk, I = m r² / 2) de kesmeye gider
		e += 0.25 * mass * radius * radius * angular_velocity.length_squared()
	return e


func _physics_process(delta: float) -> void:
	if not launched or exploded:
		return
	_age += delta
	_ignite_cd -= delta
	_touching = get_contact_count() > 0
	if ammo == "fire" and _touching and _age > 0.3:
		_fire_impact()
	if _fire_light:
		_fire_light.light_energy = 2.5 + randf() * 1.5
	var v := linear_velocity
	var spd := v.length()
	if ammo == "sticky":
		_sticky_update(delta)
		if exploded:
			return
	elif not _deployed and ammo == "multisaw":
		# Serbest uçuşa geçince (yalnız yerçekimi) ayrıl
		var acc := (v - _prev_v) / maxf(delta, 0.001)
		_free_frames = _free_frames + 1 if not _touching and _age > 0.1 and spd > 6.0 and (acc - get_gravity()).length() < 3.0 else 0
		if _free_frames >= 4:
			_deploy()
	if ammo != "saw" and ammo != "multisaw":
		# Yuvarlanma direnci: hızlıyken neredeyse yok, yavaşlayınca durur
		var k := clampf(spd / 8.0, 0.0, 1.0)
		angular_damp = lerpf(1.2, 0.05, k) if _touching else 0.05
		linear_damp = lerpf(0.3, 0.01, k) if _touching else 0.01
	if spd < 0.3 and _age > 3.0:
		can_sleep = true
	_water(v)
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
		if ammo == "fire":
			_fire_impact()
		var kind := "metal" if ammo in ["saw", "steel", "multisaw", "sticky"] else "rock"
		Sfx.impact(kind, p, dv * 3.0)
		Fx.dust(p, clampf(dv * radius * 0.5, 0.5, 2.5))
		Fx.shake(clampf(dv * radius * 0.12 * sqrt(mass / 20000.0), 0.0, 1.0))


func _water(v: Vector3) -> void:
	var wet := false
	for z in water_zones:
		if z.has_point(global_position - Vector3.UP * radius * 0.5):
			wet = true
			break
	if wet and not _in_water and v.length() > 2.0:
		Fx.dust(global_position, clampf(radius * 1.5, 0.8, 3.0))
		Sfx.impact("debris", global_position, 8.0)
	_in_water = wet
	if wet:
		# Suyun direnci: hızla artan sürükleme
		linear_damp = maxf(linear_damp, 0.12)
		angular_damp = maxf(angular_damp, 0.25)


func _update_loop(delta: float) -> void:
	var target_db := -80.0
	if ammo == "saw" or ammo == "multisaw":
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
	if ammo == "sticky":
		return  # yapışkan bomba binayı kırmaz, yapışır
	if ammo == "fire":
		_fire_impact()
	_strike_cooldown = 0.06
	var e := kinetic_energy()
	if ammo == "fire":
		e *= 0.5  # ziftli bez topu: yapıya zayıf darbe, asıl etkisi yangın
	var used := Building.strike(get_world_3d(), ahead + v.normalized() * radius * 0.6, e, v, self)
	if used > 0.0:
		# Kırmaya giden enerji mermiden düşülür
		var remain := clampf(1.0 - used * energy_cost / maxf(e, 1.0), 0.05, 1.0)
		linear_velocity = v * sqrt(remain)
		if ammo == "saw" or ammo == "multisaw":
			angular_velocity *= sqrt(remain)
			Sfx.impact("metal", global_position, 20.0)
		Fx.shake(clampf(used / 2.0e6, 0.2, 1.0))


## Ateş güllesi çarptı: çevresindeki ahşabı tutuşturur, düştüğü yerde yer yangını çıkar.
## İlk sert düşüşte alevli zift etrafa sıçrar (ileriye doğru birkaç küçük yangın daha).
## Yuvarlanırken aralıklarla arkasında yanan iz bırakır. Fırlatıcıya değmesi sayılmaz.
func _fire_impact() -> void:
	if _ignite_cd > 0.0 or FireSystem.inst == null or _age > 20.0:
		return
	var on_launcher := false
	for b in get_colliding_bodies():
		if _is_launcher_part(b):
			on_launcher = true
	if on_launcher:
		return
	_ignite_cd = 0.5
	var fs := FireSystem.inst
	fs.ignite_area(global_position, 6.0 + radius * 2.0)
	if _fire_spots >= 8:
		return
	_fire_spots += 1
	fs.ground_fire(global_position, 16.0)
	if _fire_spots == 1:
		var v := linear_velocity
		var fwd := Vector3(v.x, 0, v.z).normalized() if Vector2(v.x, v.z).length() > 1.0 else Vector3.FORWARD
		for k in 3:
			var off := fwd.rotated(Vector3.UP, randf_range(-0.9, 0.9)) * randf_range(3.0, 7.0)
			fs.ground_fire(global_position + off, 12.0)
		Fx.dust(global_position, clampf(radius * 1.5, 0.8, 2.5))
		Sfx.play("ignite", global_position, 8.0)


func _thaw_nearby() -> void:
	for hit in _shape_query(radius * 2.5, global_position + linear_velocity * 0.15, 2):
		var c: Object = hit["collider"]
		if c is Destructible:
			(c as Destructible).thaw()
		elif c and c.has_meta("pool"):
			c.get_meta("pool").thaw(c)


## Patlama: çevredeki yapıya enerji, serbest gövdelere itki, ses/ışık/duman.
func explode() -> void:
	if exploded:
		return
	exploded = true
	var p := global_position
	# Yapışkan bomba küçük ama yoğun patlayıcı (C4 benzeri)
	var k := radius / (0.36 if ammo == "sticky" else 0.6)
	var energy := 6.0e6 * pow(k, 3.0)
	var blast_r := 9.0 * k
	if Crowd.inst:
		Crowd.inst.alarm(p, energy)
	Building.strike(get_world_3d(), p, energy, Vector3.UP * 0.3, self)
	for hit in _shape_query(blast_r, p, 2 | 4 | 8 | 16):
		var b := hit["collider"] as RigidBody3D
		if b == null or b == self:
			continue
		if b is Soldier:
			var to_s := b.global_position - p
			(b as Soldier).die((to_s.normalized() + Vector3.UP).normalized() * clampf(40.0 / maxf(to_s.length(), 1.0), 2.0, 14.0))
			continue
		if b.has_meta("pool"):
			b.get_meta("pool").thaw(b)
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
	Fx.explosion(p, k)
	Sfx.explosion(p)
	Fx.shake(1.0)
	queue_free()


# --- Ayrılan / özel mermiler --------------------------------------------------

## Üçlü testere: iki kopya ±8° açıyla ayrılır.
func _deploy() -> void:
	_deployed = true
	var v := linear_velocity
	var side := Vector3.UP.cross(v).normalized()
	if side.length() < 0.5:
		side = Vector3.RIGHT
	for sgn in [-1.0, 1.0]:
		var c := _spawn_copy("multisaw", global_position + side * sgn * radius * 2.6)
		c._deployed = true
		c.launch(v.rotated(Vector3.UP, deg_to_rad(8.0) * sgn))
	Sfx.impact("metal", global_position, 10.0)


func _spawn_copy(id: String, at: Vector3) -> Projectile:
	var c := Projectile.new()
	# setup yarıçapı ölçekler; aynı boyut için geri böl
	c.setup(id, radius / 0.65, false)
	get_parent().add_child(c)
	c.global_transform = Transform3D(global_transform.basis, at)
	c.reset_physics_interpolation()
	if get_parent().has_method("register_projectile"):
		get_parent().register_projectile(c)
	return c


## Yapışkan bomba: ilk temasta yapışır (fırlatıcının kendisi hariç), bip sesleri hızlanır,
## STICKY_FUSE saniye sonra patlar.
func _sticky_update(delta: float) -> void:
	if not _stuck:
		if _age > 0.1 and _touching:
			for b in get_colliding_bodies():
				if _is_launcher_part(b):
					continue
				_stick_to(b)
				break
		if _age > 8.0:
			explode()
		return
	_fuse += delta
	_beep_t -= delta
	var k := _fuse / STICKY_FUSE
	if _beep_t <= 0.0:
		_beep_t = lerpf(0.45, 0.08, k)
		Sfx.play("beep", global_position, 0.0, 1.0 + k * 0.5)
		_glow.emission_energy_multiplier = 6.0
	else:
		_glow.emission_energy_multiplier = maxf(_glow.emission_energy_multiplier - delta * 40.0, 0.0)
	if _fuse >= STICKY_FUSE:
		explode()


func _is_launcher_part(n: Node) -> bool:
	while n:
		if n is Launcher:
			return true
		n = n.get_parent()
	return false


func _stick_to(b: Node) -> void:
	_stuck = true
	_beep_t = 0.0
	var rb := b as RigidBody3D
	if rb and not rb.freeze:
		# Hareketli gövdeye iğnele: onunla birlikte gider
		var j := PinJoint3D.new()
		add_child(j)
		j.global_position = global_position
		j.node_a = j.get_path_to(self)
		j.node_b = j.get_path_to(rb)
	else:
		# Sabit yüzey / sağlam bina parçası: olduğu yerde kalır
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		freeze = true
	Sfx.impact("metal", global_position, 6.0)
