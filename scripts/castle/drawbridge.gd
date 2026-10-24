class_name Drawbridge
extends Node3D
## Asma köprü: kapının önünde dik (kalkık) durur, iki zincirle kapı kulesine bağlıdır.
## Zincirin bağlı olduğu taş koparsa ya da köprüye/zincire hızlı bir gövde çarparsa zincirler
## kopar; köprü alt kenarındaki menteşe etrafında dönerek hendeğin üstüne düşer.
## Düşüş, menteşeli çubuğun hareket denklemiyle (α = 3g/2L · sin θ) kinematik yürütülür:
## eklem + zemin temasında takılma olmaz, önündeki gövdeleri iter.

signal fell

var body: RigidBody3D
var _size: Vector3
var _anchors: Array[Destructible] = []
var _chains: Array[MeshInstance3D] = []
var _chain_pts: Array = []  # [köprü ucu (yerel), duvar ucu (yerel)]
var _down := false
var _angle := 0.0  # 0: kalkık, π/2: yatık
var _omega := 0.0
var _landed := false
var _rest: Transform3D
var _poll := 0.0
var _query: PhysicsShapeQueryParameters3D
var _wall: Fortress


func setup(size: Vector3, wall_part: Fortress) -> void:
	_size = size
	_wall = wall_part


func _ready() -> void:
	body = RigidBody3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = _size
	mi.mesh = bm
	mi.material_override = BlockStructure.material("wood")
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = _size
	cs.shape = sh
	body.add_child(cs)
	# Demir kuşaklar (görsel)
	var iron := WorldBuilder.pbr("rusty_metal_02", 0.5, Color.WHITE, false)
	for k in 3:
		var band := MeshInstance3D.new()
		var b2 := BoxMesh.new()
		b2.size = Vector3(_size.x + 0.05, _size.y + 0.05, 0.3)
		band.mesh = b2
		band.material_override = iron
		band.position.z = (k - 1) * _size.z * 0.35
		body.add_child(band)
	body.mass = 9000.0
	body.collision_layer = 2
	body.collision_mask = 1 | 2 | 4 | 16
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.freeze = true
	# Kalkık: köprünün uzun ekseni (yerel Z) dikey; menteşe alt kenarda (orijin)
	body.transform = Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, _size.z * 0.5, -_size.y * 0.5))
	add_child(body)
	_rest = body.transform
	# Zincirler: köprünün üst köşelerinden kapı üstü duvarına
	var iron_dark := WorldBuilder.pbr("metal_plate", 1.0, Color(0.25, 0.25, 0.27), false)
	for sx in [-1.0, 1.0]:
		var a := Vector3(sx * (_size.x * 0.5 - 0.4), _size.z - 0.3, 0.0)
		var b := Vector3(sx * (_size.x * 0.5 - 0.6), _size.z + 3.0, 4.5)
		_chain_pts.append([a, b])
		var c := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.09
		cm.bottom_radius = 0.09
		cm.height = 1.0
		cm.radial_segments = 6
		c.mesh = cm
		c.material_override = iron_dark
		add_child(c)
		_orient(c, a, b)
		_chains.append(c)
	_query = PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_size.x + 2.0, _size.z + 4.0, 9.0)
	_query.shape = box
	_query.collision_mask = 4  # yalnız mermiler (taşlar sorguyu doldurmasın)
	_query.exclude = [body.get_rid()]
	# Zincirin bağlı olduğu taşlar (kapı üstü duvarındaki en yakın bloklar)
	await get_tree().physics_frame
	for pts in _chain_pts:
		var wp: Vector3 = to_global(pts[1])
		var best: Destructible = null
		var bd := INF
		for d in _wall.chunks:
			var dist := d.global_position.distance_to(wp)
			if dist < bd:
				bd = dist
				best = d
		if best:
			_anchors.append(best)


func _orient(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	mi.transform = Transform3D(Basis(x, y, x.cross(y)).scaled_local(Vector3(1, d.length(), 1)), a + d * 0.5)


func _physics_process(delta: float) -> void:
	if _down:
		_fall(delta)
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.05
	for a in _anchors:
		if not is_instance_valid(a) or not a.intact:
			drop(Vector3.ZERO)
			return
	# Köprünün önündeki bölge: köprüye doğru (+Z yerel) hızla gelen ağır gövde zincirleri koparır
	_query.transform = global_transform * Transform3D(Basis.IDENTITY, Vector3(0, _size.z * 0.5, -3.0))
	var inward := global_transform.basis.z
	for hit in get_world_3d().direct_space_state.intersect_shape(_query, 8):
		var b := hit["collider"] as RigidBody3D
		if b and not b.freeze and b.linear_velocity.dot(inward) > 4.0 and 0.5 * b.mass * b.linear_velocity.length_squared() > 250000.0:
			drop(b.linear_velocity)
			return


## Zincirler kopar, köprü menteşesi etrafında düşer
func drop(push: Vector3) -> void:
	if _down:
		return
	_down = true
	for c in _chains:
		c.visible = false
	# Çarpan gövdenin itişi + zincir boşalınca öne yatış
	_omega = 0.12 + clampf(push.length() * 0.02, 0.0, 0.3)
	Sfx.play("chain", global_position + Vector3.UP * _size.z, 8.0, 0.9)
	Sfx.play("chain", global_position + Vector3.UP * _size.z, 6.0, 1.2)
	fell.emit()


func _fall(delta: float) -> void:
	if _landed:
		return
	var alpha := 1.5 * 9.81 / _size.z * sin(_angle + 0.02)
	_omega += alpha * delta
	var next := _angle + _omega * delta
	# Altında ağır bir gövde (ör. kaya) varsa üstüne yaslanıp durur (içinden geçirmez)
	var q := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = _size + Vector3(0, 0.3, 0)
	q.shape = box
	q.transform = global_transform * Transform3D(Basis(Vector3.RIGHT, -next), Vector3.ZERO) * _rest
	q.collision_mask = 4
	q.exclude = [body.get_rid()]
	for hit in get_world_3d().direct_space_state.intersect_shape(q, 4):
		var rb := hit["collider"] as RigidBody3D
		if rb and rb.mass > 2000.0:
			_landed = true
			_omega = 0.0
			Sfx.impact("wood", rb.global_position, 25.0)
			Fx.dust(rb.global_position, 1.5)
			return
	_angle = next
	if _angle >= PI * 0.5:
		_angle = PI * 0.5
		_landed = true
		Sfx.impact("wood", to_global(Vector3(0, 0.5, -_size.z * 0.6)), 30.0)
		Sfx.crash(to_global(Vector3(0, 0.5, -_size.z * 0.5)), "crash")
		Fx.dust(to_global(Vector3(0, 0.5, -_size.z * 0.5)), 2.5)
		Fx.shake(0.6)
	# Menteşe: yerel X ekseni, orijinde; dışa (-Z) devrilir
	body.transform = Transform3D(Basis(Vector3.RIGHT, -_angle), Vector3.ZERO) * _rest
