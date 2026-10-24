class_name Flag
extends RigidBody3D
## Sancak: direk + dalgalanan kumaş. Altındaki taş koparsa direk düşer (görevlerde hedef).

signal fell

var down := false
var _anchor: Destructible
var _poll := 0.0


func _ready() -> void:
	var wood := BlockStructure.material("wood")
	var pole := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.16
	cm.height = 10.0
	pole.mesh = cm
	pole.material_override = wood
	pole.position.y = 5.0
	add_child(pole)
	var cloth := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(5.0, 3.0)
	qm.subdivide_width = 16
	qm.subdivide_depth = 8
	cloth.mesh = qm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/flag.gdshader")
	cloth.material_override = mat
	cloth.position = Vector3(2.6, 8.3, 0)
	add_child(cloth)
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.4, 10.0, 0.4)
	cs.shape = box
	cs.position.y = 5.0
	add_child(cs)
	mass = 300.0
	collision_layer = 2
	collision_mask = 1 | 2
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true


## Altındaki taşı bul (ana kule döşemesi)
func attach(part: Fortress) -> void:
	await get_tree().physics_frame
	var best := INF
	for d in part.chunks:
		var dist := d.global_position.distance_to(global_position + Vector3.DOWN * 0.5)
		if dist < best:
			best = dist
			_anchor = d


func _physics_process(delta: float) -> void:
	if down or _anchor == null:
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.2
	if not is_instance_valid(_anchor) or not _anchor.intact:
		down = true
		freeze = false
		apply_impulse(Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * 200.0, global_position + Vector3.UP * 8.0)
		fell.emit()
