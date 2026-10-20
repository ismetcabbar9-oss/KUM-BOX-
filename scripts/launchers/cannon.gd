class_name AirCannon
extends Launcher
## Hava topu: sabit basınç enerjisi mermiye aktarılır (½mv² = E): hafif mermi hızlı,
## ağır mermi yavaş çıkar. Yana sürükle: yön, dikey: namlu açısı.

const PIVOT := Vector3(0, 1.9, 0)
const BARREL_LEN := 4.5
const ENERGY := 0.6e6  # J

var yaw_deg := 0.0
var pitch_deg := 14.0
var _yaw_node: Node3D
var _pitch_node: Node3D
var _barrel: MeshInstance3D


func _init() -> void:
	super()
	title = "HAVA TOPU"
	base_radius = 0.5
	view_distance = 14.0


func _ready() -> void:
	var steel := WorldBuilder.pbr("metal_plate", 0.6, Color(0.35, 0.37, 0.4), false)
	steel = steel.duplicate()
	steel.metallic = 0.85
	var wood := WorldBuilder.pbr("rough_wood", 0.5, Color(0.85, 0.8, 0.75), false)
	beam(self, Vector3(3.2, 0.5, 4.2), Transform3D(Basis.IDENTITY, Vector3(0, 0.25, 0)), wood)
	_yaw_node = Node3D.new()
	_yaw_node.position = PIVOT
	add_child(_yaw_node)
	for sx in [-0.85, 0.85]:
		beam(_yaw_node, Vector3(0.25, 1.4, 1.4), Transform3D(Basis.IDENTITY, Vector3(sx, -0.6, 0)), steel, false)
		var wheel := MeshInstance3D.new()
		var wm := CylinderMesh.new()
		wm.top_radius = 0.75
		wm.bottom_radius = 0.75
		wm.height = 0.22
		wheel.mesh = wm
		wheel.material_override = wood
		wheel.rotation_degrees = Vector3(0, 0, 90)
		wheel.position = Vector3(sx * 1.25, -1.1, 0.0)
		_yaw_node.add_child(wheel)
	_pitch_node = Node3D.new()
	_yaw_node.add_child(_pitch_node)
	_barrel = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.6
	cm.height = BARREL_LEN
	_barrel.mesh = cm
	_barrel.material_override = steel
	_barrel.rotation_degrees = Vector3(90, 0, 0)
	_barrel.position = Vector3(0, 0, BARREL_LEN * 0.35)
	_pitch_node.add_child(_barrel)
	var tank := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.75
	tm.bottom_radius = 0.75
	tm.height = 1.6
	tank.mesh = tm
	tank.material_override = steel
	tank.rotation_degrees = Vector3(90, 0, 0)
	tank.position = Vector3(0, 0, -1.2)
	_pitch_node.add_child(tank)
	_apply_aim()
	view_target.position = PIVOT + Vector3(0, 1.0, 0)


func _apply_aim() -> void:
	_yaw_node.rotation_degrees.y = yaw_deg
	_pitch_node.rotation_degrees.x = -pitch_deg


func _muzzle() -> Transform3D:
	var xf := _pitch_node.global_transform
	return Transform3D(xf.basis, xf * Vector3(0, 0, BARREL_LEN * 0.35 + BARREL_LEN * 0.5 + (loaded.radius if loaded else 0.5)))


func load_projectile(p: Projectile) -> void:
	loaded = p
	_place()


func _place() -> void:
	loaded.global_transform = _muzzle()
	loaded.reset_physics_interpolation()
	var v := _speed()
	_show_arc(loaded.global_position, _pitch_node.global_transform.basis.z * v)


func _speed() -> float:
	return minf(sqrt(2.0 * ENERGY * pow(loaded.radius / base_radius, 3.0) / loaded.mass), 46.0)


func drag(relative: Vector2, _vs: Vector2) -> void:
	if not is_ready():
		return
	yaw_deg = clampf(yaw_deg - relative.x * 0.12, -45.0, 45.0)
	pitch_deg = clampf(pitch_deg - relative.y * 0.1, 2.0, 55.0)
	_apply_aim()
	_place()


func fire(_power := -1.0) -> void:
	if not is_ready():
		return
	var p := loaded
	_hide_arc()
	var dir := _pitch_node.global_transform.basis.z
	p.launch(dir * _speed(), Vector3(randf_range(-2, 2), randf_range(-2, 2), randf_range(-2, 2)))
	Sfx.play("cannon", p.global_position, 6.0)
	Fx.dust(p.global_position, 2.0)
	Fx.shake(0.5)
	# Geri tepme animasyonu
	var tw := create_tween()
	tw.tween_property(_barrel, "position:z", BARREL_LEN * 0.35 - 0.9, 0.06)
	tw.tween_property(_barrel, "position:z", BARREL_LEN * 0.35, 0.6).set_trans(Tween.TRANS_SINE)
	fired.emit(p)


func info() -> String:
	return "Yön %+d°   Açı %d°" % [roundi(yaw_deg), roundi(pitch_deg)]


func hint() -> String:
	return "Yana sürükle: yön   •   Yukarı/aşağı: namlu açısı   •   FIRLAT"
