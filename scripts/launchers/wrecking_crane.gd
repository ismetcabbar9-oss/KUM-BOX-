class_name WreckingCrane
extends Launcher
## Sarkaçlı yıkım vinci: bom ucuna zincirle (PinJoint) asılı çelik gülle.
## Parmağı koy, aşağı çek: gülle geriye kaldırılır (açı = güç). Bırakınca sarkaç gibi
## binaya savrulur. Sallanırken KES: zincir kopar, gülle savrulduğu hızla uçar.
## Vinç yerel -X yönüne uzanır; kamera arkadan bom yönüne bakar.

const TIP_H := 24.0
const BOOM := 16.0  # kule ile bom ucu arası (yerel -X)
const ROPE := 15.0
const MAX_DEG := 80.0
const MIN_DEG := 10.0

var angle := 0.0
var _anchor: StaticBody3D
var _joint: PinJoint3D
var _chain: MeshInstance3D
var _ball: Projectile
var _pulling := false


func _init() -> void:
	super()
	title = "YIKIM VİNCİ"
	base_radius = 1.1
	view_distance = 22.0


func _ready() -> void:
	var steel := WorldBuilder.pbr("rusty_metal_02", 0.5, Color(0.9, 0.62, 0.15), false)
	var conc := WorldBuilder.pbr("rough_concrete", 0.3, Color(0.8, 0.79, 0.76))
	# Beton taban + kafes kule (4 dikme + kuşaklar) + bom + karşı ağırlık
	beam(self, Vector3(6, 1.2, 6), Transform3D(Basis.IDENTITY, Vector3(0, 0.6, 0)), conc)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			beam(self, Vector3(0.3, TIP_H, 0.3), Transform3D(Basis.IDENTITY, Vector3(sx * 0.9, 1.2 + TIP_H * 0.5, sz * 0.9)), steel, false)
	for k in 8:
		var y := 1.2 + 3.0 * (k + 1)
		for sz in [-1.0, 1.0]:
			beam(self, Vector3(2.1, 0.15, 0.15), Transform3D(Basis.IDENTITY, Vector3(0, y, sz * 0.9)), steel, false)
		for sx in [-1.0, 1.0]:
			beam(self, Vector3(0.15, 0.15, 2.1), Transform3D(Basis.IDENTITY, Vector3(sx * 0.9, y, 0)), steel, false)
	var top := 1.2 + TIP_H
	beam(self, Vector3(BOOM + 6.0, 0.9, 1.2), Transform3D(Basis.IDENTITY, Vector3(-BOOM * 0.5 + 3.0, top + 0.45, 0)), steel, false)
	beam(self, Vector3(2.4, 2.4, 2.4), Transform3D(Basis.IDENTITY, Vector3(5.0, top - 0.8, 0)), conc, false)
	beam(self, Vector3(2.2, 2.0, 2.0), Transform3D(Basis.IDENTITY, Vector3(0, top + 1.9, 0)), steel, false)  # kabin
	_anchor = StaticBody3D.new()
	_anchor.position = Vector3(-BOOM, top, 0)
	_anchor.collision_layer = 0
	_anchor.collision_mask = 0
	add_child(_anchor)
	_chain = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.06
	cm.height = 1.0
	cm.radial_segments = 6
	_chain.mesh = cm
	_chain.material_override = WorldBuilder.pbr("metal_plate", 1.0, Color(0.25, 0.25, 0.27), false)
	_chain.top_level = true
	_chain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_chain)


func forced_ammo() -> String:
	return "steel"


## Kamera vincin arkasından bom yönüne (-X yerel) bakar
func heading() -> float:
	var d := global_transform.basis * Vector3.LEFT
	return atan2(d.x, d.z)


func _ball_pos(r: float) -> Vector3:
	var a := deg_to_rad(angle)
	# Geri çekiş yerel +X yönünde (binadan uzağa)
	return _anchor.position + Vector3(sin(a), -cos(a), 0) * (ROPE + r)


func load_projectile(p: Projectile) -> void:
	_cut(false)
	loaded = p
	_ball = p
	angle = 0.0
	_place()


func _place() -> void:
	loaded.global_transform = Transform3D(global_transform.basis, to_global(_ball_pos(loaded.radius)))
	loaded.reset_physics_interpolation()
	view_target.position = _ball_pos(loaded.radius) + Vector3(4, 2, 0)


func press() -> void:
	_pulling = true


func drag(relative: Vector2, vs: Vector2) -> void:
	if not is_ready():
		return
	angle = clampf(angle + relative.y / vs.y * 160.0 - relative.x / vs.x * 40.0, 0.0, MAX_DEG)
	_place()


func uses_button() -> bool:
	return false


func release(_swipe: float) -> bool:
	_pulling = false
	if angle >= MIN_DEG and is_ready():
		fire()
		return true
	angle = 0.0
	if loaded:
		_place()
	return false


func fire(_power := -1.0) -> void:
	if not is_ready():
		return
	if angle < MIN_DEG:
		angle = 55.0
		_place()
	var p := loaded
	p.launch(Vector3.ZERO)
	_joint = PinJoint3D.new()
	add_child(_joint)
	_joint.global_position = _anchor.global_position
	_joint.node_a = _joint.get_path_to(_anchor)
	_joint.node_b = _joint.get_path_to(p)
	Sfx.play("chain", _anchor.global_position, 4.0, 0.8)
	fired.emit(p)


func secondary() -> bool:
	if _joint == null:
		return false
	_cut(true)
	return true


func flight_hint() -> String:
	return "KES: zinciri kopar, gülle uçsun" if _joint else ""


func _cut(sound: bool) -> void:
	if _joint:
		_joint.queue_free()
		_joint = null
		if sound and is_instance_valid(_ball):
			Sfx.play("chain", _ball.global_position, 6.0, 1.2)
	_ball = null if not sound else _ball


func _process(_delta: float) -> void:
	var holding := is_instance_valid(_ball) and (_joint != null or (loaded == _ball and not _ball.launched))
	_chain.visible = holding
	if not holding:
		return
	var a := _anchor.global_position
	var b := _ball.get_global_transform_interpolated().origin
	var d := b - a
	var len := d.length() - _ball.radius
	if len < 0.1:
		return
	var y := d.normalized()
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	_chain.global_transform = Transform3D(Basis(x, y, x.cross(y)).scaled_local(Vector3(1, len, 1)), a + y * len * 0.5)


func info() -> String:
	return "Açı %d°" % roundi(angle)


func hint() -> String:
	return "Parmağı koy, aşağı çek: gülleyi kaldır   •   Bırak: savur   •   Sallanırken KES"
