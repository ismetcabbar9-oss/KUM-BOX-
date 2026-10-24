class_name FireSystem
extends Node
## Yangın: ahşap bloklar (çatı kalasları, ahır, asma köprü) tutuşur, komşu ahşaba sıçrar,
## yanıp kömürleşince kopup düşer. Taş yanmaz.
## Yer yangını: ateş güllesinin düştüğü yerde (çimen, taş, moloz) bir süre yanan alev
## öbeği; yakınındaki ahşabı tutuşturur, içine giren figürü yakar, zemine is izi bırakır.
## Görseller havuzlu: en çok EMITTERS alev/duman yayıcı, LIGHTS ışık + ateş sesi (mobil).

static var inst: FireSystem

const EMITTERS := 28
const LIGHTS := 3
const TICK := 0.5
const SPREAD_P := 0.22
const GROUND_MAX := 12
const GROUND_R := 2.6

var castle: Castle
var _burning := {}  # Destructible -> {"t", "life", "fx": indeks}
var _free_fx: Array[int] = []
var _fx: Array[GPUParticles3D] = []
var _smoke: Array[GPUParticles3D] = []
var _fx_owner: Array = []
var _lights: Array[OmniLight3D] = []
var _sounds: Array[AudioStreamPlayer3D] = []
var _tick := 0.0
var _char: StandardMaterial3D
var _alarm_cd := 0.0
var _ground: Array = []  # [{"node", "t", "life", "fx"}]
var _scorch: Array[Decal] = []
var _scorch_next := 0


func _init() -> void:
	inst = self


func _ready() -> void:
	var soft := GradientTexture2D.new()
	soft.fill = GradientTexture2D.FILL_RADIAL
	soft.fill_from = Vector2(0.5, 0.5)
	soft.fill_to = Vector2(1.0, 0.5)
	var g := Gradient.new()
	g.set_color(0, Color.WHITE)
	g.set_color(1, Color(1, 1, 1, 0))
	soft.gradient = g
	for i in EMITTERS:
		_fx.append(_emitter(soft, true))
		_smoke.append(_emitter(soft, false))
		_fx_owner.append(null)
		_free_fx.append(i)
	for i in LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.55, 0.2)
		l.omni_range = 18.0
		l.light_energy = 0.0
		l.shadow_enabled = false
		add_child(l)
		_lights.append(l)
		var a := AudioStreamPlayer3D.new()
		a.stream = Sfx.stream("fire_loop")
		a.bus = "SFX"
		a.unit_size = 14.0
		a.volume_db = -80.0
		add_child(a)
		_sounds.append(a)
	_setup_scorch()
	_char = StandardMaterial3D.new()
	_char.albedo_color = Color(0.09, 0.07, 0.06)
	_char.roughness = 1.0


func _emitter(tex: Texture2D, flame: bool) -> GPUParticles3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if flame else BaseMaterial3D.BLEND_MODE_MIX
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * (1.4 if flame else 3.0)
	quad.material = mat
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.8, 0.2, 0.8)
	pm.direction = Vector3.UP
	pm.spread = 12.0 if flame else 20.0
	pm.initial_velocity_min = 1.5 if flame else 1.0
	pm.initial_velocity_max = 3.5 if flame else 2.5
	pm.gravity = Vector3(0, 1.5 if flame else 0.6, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.4
	var ramp := Gradient.new()
	if flame:
		ramp.set_color(0, Color(1.0, 0.9, 0.5, 0.9))
		ramp.add_point(0.4, Color(1.0, 0.45, 0.1, 0.8))
		ramp.set_color(ramp.get_point_count() - 1, Color(0.6, 0.1, 0.02, 0.0))
	else:
		ramp.set_color(0, Color(0.25, 0.23, 0.22, 0.0))
		ramp.add_point(0.2, Color(0.22, 0.2, 0.19, 0.55))
		ramp.set_color(ramp.get_point_count() - 1, Color(0.3, 0.3, 0.3, 0.0))
	var rt := GradientTexture1D.new()
	rt.gradient = ramp
	pm.color_ramp = rt
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.6 if flame else 0.4))
	sc.add_point(Vector2(1, 0.2 if flame else 2.2))
	var sct := CurveTexture.new()
	sct.curve = sc
	pm.scale_curve = sct
	var p := GPUParticles3D.new()
	p.amount = 18 if flame else 10
	p.lifetime = 0.9 if flame else 4.0
	p.process_material = pm
	p.draw_pass_1 = quad
	p.emitting = false
	p.local_coords = false
	p.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 30, 12))
	add_child(p)
	return p


## İs izi: koyu, kenarı dağınık yanık lekesi
func _setup_scorch() -> void:
	var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.frequency = 0.12
	for y in 64:
		for x in 64:
			var d := Vector2(x - 31.5, y - 31.5).length() / 32.0
			var n := noise.get_noise_2d(x, y) * 0.5 + 0.5
			var a := clampf((1.0 - d) * 1.8 - 0.2 + (n - 0.5) * 0.8, 0.0, 1.0)
			img.set_pixel(x, y, Color(0.05, 0.04, 0.035, a * 0.9))
	var tex := ImageTexture.create_from_image(img)
	for i in GROUND_MAX:
		var dc := Decal.new()
		dc.texture_albedo = tex
		dc.visible = false
		dc.cull_mask = 1
		add_child(dc)
		_scorch.append(dc)


## Yer yangını başlat (zemine oturtulur). Havuz doluysa en eskisi söner.
func ground_fire(point: Vector3, life := 14.0) -> void:
	var space := get_viewport().get_world_3d().direct_space_state
	var rq := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 3.0, point + Vector3.DOWN * 30.0, 1 | 2)
	var hit := space.intersect_ray(rq)
	if not hit.is_empty():
		point = hit["position"]
	for z in Projectile.water_zones:
		if z.has_point(point + Vector3.UP * 0.3):
			Fx.dust(point, 1.2)  # suya düştü: söner, buhar
			return
	for g: Dictionary in _ground:
		if (g["node"] as Node3D).global_position.distance_to(point) < GROUND_R * 0.8:
			g["life"] = maxf(g["life"], g["t"] + life)  # aynı yere tekrar: daha uzun yanar
			return
	if _ground.size() >= GROUND_MAX:
		_end_ground(_ground[0])
	var node := Node3D.new()
	add_child(node)
	node.global_position = point
	var entry := {"node": node, "t": 0.0, "life": life * randf_range(0.85, 1.15), "fx": -1}
	if _free_fx.is_empty():
		# Yayıcı kalmadı: en eski yer yangınının yayıcısını al
		for g: Dictionary in _ground:
			if g["fx"] >= 0:
				entry["fx"] = g["fx"]
				g["fx"] = -1
				break
	else:
		entry["fx"] = _free_fx.pop_back()
	if entry["fx"] >= 0:
		var i: int = entry["fx"]
		_fx_owner[i] = node
		# Yer yangını: daha geniş alev öbeği
		_fx[i].scale = Vector3.ONE * 1.8
		_smoke[i].scale = Vector3.ONE * 1.5
		_fx[i].emitting = true
		_smoke[i].emitting = true
	_ground.append(entry)
	var dc := _scorch[_scorch_next]
	_scorch_next = (_scorch_next + 1) % _scorch.size()
	var sz := GROUND_R * 2.0 * randf_range(1.0, 1.4)
	dc.size = Vector3(sz, 3.0, sz)
	dc.global_position = point
	dc.rotation.y = randf() * TAU
	dc.visible = true
	ignite_area(point, GROUND_R + 2.0)
	Sfx.play("ignite", point, 6.0)


func _end_ground(g: Dictionary) -> void:
	_ground.erase(g)
	var node: Node3D = g["node"]
	var i: int = g["fx"]
	if i >= 0:
		_fx[i].emitting = false
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			if _fx_owner[i] == node:
				_release_fx(i)
			node.queue_free())
	else:
		node.queue_free()


func _ground_tick() -> void:
	if _ground.is_empty():
		return
	var space := get_viewport().get_world_3d().direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = GROUND_R
	q.shape = sph
	q.collision_mask = 16 | 2
	for g: Dictionary in _ground.duplicate():
		g["t"] += TICK
		var p: Vector3 = (g["node"] as Node3D).global_position
		q.transform = Transform3D(Basis.IDENTITY, p + Vector3.UP)
		for hit in space.intersect_shape(q, 16):
			var c: Object = hit["collider"]
			if c is Soldier and (c as Soldier).alive:
				(c as Soldier).die(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)))
			elif c is Destructible and (c as Destructible).material_kind == "wood" and randf() < 0.35:
				ignite(c as Destructible)
		if g["t"] >= g["life"]:
			_end_ground(g)


func is_burning(d: Destructible) -> bool:
	return _burning.has(d)


## Noktanın çevresindeki ahşabı tutuştur (ateş güllesi çarpınca)
func ignite_area(point: Vector3, radius: float) -> void:
	var q := PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = radius
	q.shape = sph
	q.transform = Transform3D(Basis.IDENTITY, point)
	q.collision_mask = 2
	var n := 0
	for hit in get_viewport().get_world_3d().direct_space_state.intersect_shape(q, 32):
		var d := hit["collider"] as Destructible
		if d and d.material_kind == "wood":
			ignite(d)
			n += 1
	if castle and castle.bridge and point.distance_to(castle.bridge.global_position + Vector3.UP * 4.0) < radius + 6.0:
		castle.bridge.burn()
	if n > 0:
		Sfx.play("ignite", point, 6.0)
		if Crowd.inst and _alarm_cd <= 0.0:
			_alarm_cd = 4.0
			Crowd.inst.alarm(point, 2.0e6)


func ignite(d: Destructible) -> void:
	if _burning.has(d) or not is_instance_valid(d):
		return
	var entry := {"t": 0.0, "life": randf_range(8.0, 14.0), "fx": -1}
	if not _free_fx.is_empty():
		var i: int = _free_fx.pop_back()
		entry["fx"] = i
		_fx_owner[i] = d
		_fx[i].emitting = true
		_smoke[i].emitting = true
	_burning[d] = entry


func _process(delta: float) -> void:
	_alarm_cd -= delta
	# Alev yayıcılar yanan bloğu izler (kopup düşerken de)
	for i in EMITTERS:
		var d = _fx_owner[i]
		if d == null:
			continue
		if not is_instance_valid(d):
			_release_fx(i)
			continue
		_fx[i].global_position = d.global_position + Vector3.UP * 0.3
		_smoke[i].global_position = d.global_position + Vector3.UP * 1.0
	# Işık ve ses: ilk birkaç yanan bölgede
	var spots: Array[Vector3] = []
	for g: Dictionary in _ground:
		var gp: Vector3 = (g["node"] as Node3D).global_position
		var close := false
		for s in spots:
			if s.distance_to(gp) < 14.0:
				close = true
				break
		if not close and spots.size() < LIGHTS:
			spots.append(gp)
	for d in _burning:
		if not is_instance_valid(d):
			continue
		var p: Vector3 = d.global_position
		var near := false
		for s in spots:
			if s.distance_to(p) < 14.0:
				near = true
				break
		if not near:
			spots.append(p)
			if spots.size() >= LIGHTS:
				break
	for i in LIGHTS:
		if i < spots.size():
			_lights[i].global_position = spots[i] + Vector3.UP * 2.0
			_lights[i].light_energy = 3.0 + randf() * 1.5
			_sounds[i].global_position = spots[i]
			if not _sounds[i].playing:
				_sounds[i].play()
			_sounds[i].volume_db = lerpf(_sounds[i].volume_db, 2.0, clampf(delta * 2.0, 0.0, 1.0))
		else:
			_lights[i].light_energy = 0.0
			_sounds[i].volume_db = lerpf(_sounds[i].volume_db, -80.0, clampf(delta * 1.0, 0.0, 1.0))
			if _sounds[i].volume_db < -70.0:
				_sounds[i].stop()
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	_ground_tick()
	for d in _burning.keys():
		if not is_instance_valid(d):
			_drop(d)
			continue
		var e: Dictionary = _burning[d]
		e["t"] += TICK
		# Komşu ahşaba sıçrama
		var b := d.building as BlockStructure
		if b:
			for nn in d.neighbors:
				var o = b._by_name.get(nn)
				if o and is_instance_valid(o) and (o as Destructible).material_kind == "wood" and not _burning.has(o) and randf() < SPREAD_P:
					ignite(o)
		if e["t"] >= e["life"]:
			_burn_out(d)


## Yanıp kömürleşti: kararır, sağlamsa kopar ve düşer; bir süre tüter
func _burn_out(d: Destructible) -> void:
	for mi: MeshInstance3D in d.find_children("*", "MeshInstance3D", true, false):
		mi.material_override = _char
	if d.intact:
		d.release(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * d.mass * 0.3, d.global_position)
		# Çatı bloğu MultiMesh'ten kopunca kendi mesh'ini alır: ona da kömür rengi
		await get_tree().process_frame
		if is_instance_valid(d):
			for mi: MeshInstance3D in d.find_children("*", "MeshInstance3D", true, false):
				mi.material_override = _char
	_drop(d)


func _drop(d) -> void:
	var e: Dictionary = _burning.get(d, {})
	_burning.erase(d)
	if e.get("fx", -1) >= 0:
		var i: int = e["fx"]
		_fx[i].emitting = false
		# Duman biraz daha sürer
		get_tree().create_timer(3.0).timeout.connect(func() -> void:
			if _fx_owner[i] == null or not _burning.has(_fx_owner[i]):
				_release_fx(i))


func _release_fx(i: int) -> void:
	_fx[i].scale = Vector3.ONE
	_smoke[i].scale = Vector3.ONE
	_fx[i].emitting = false
	_smoke[i].emitting = false
	_fx_owner[i] = null
	if not _free_fx.has(i):
		_free_fx.append(i)
