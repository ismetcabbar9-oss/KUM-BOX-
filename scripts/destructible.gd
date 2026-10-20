class_name Destructible
extends RigidBody3D
## Yıkılabilir parça: uykuda başlar, çarpışma darbesine göre ses/toz üretir.

## "brick", "concrete", "wood", "metal"
var material_kind := "concrete"
var start_pos := Vector3.ZERO
var _cooldown := 0.0


func setup(size: Vector3, mat: Material, kind: String, density: float, shape_kind := "box") -> void:
	material_kind = kind
	var mi := MeshInstance3D.new()
	var cs := CollisionShape3D.new()
	if shape_kind == "cylinder":
		var cm := CylinderMesh.new()
		cm.top_radius = size.x * 0.5
		cm.bottom_radius = size.x * 0.5
		cm.height = size.y
		cm.radial_segments = 20
		mi.mesh = cm
		var shape := CylinderShape3D.new()
		shape.radius = size.x * 0.5
		shape.height = size.y
		cs.shape = shape
		mass = PI * pow(size.x * 0.5, 2) * size.y * density
	else:
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		mass = size.x * size.y * size.z * density
	mi.material_override = mat
	add_child(mi)
	add_child(cs)
	var pm := PhysicsMaterial.new()
	pm.friction = 0.8 if kind != "metal" else 0.5
	pm.bounce = 0.05
	physics_material_override = pm
	# Katman 1: statik dünya, 2: parçalar, 3: kayalar
	collision_layer = 2
	collision_mask = 1 | 2 | 4
	contact_monitor = true
	max_contacts_reported = 2
	can_sleep = true
	sleeping = true
	add_to_group("destructible")


func _ready() -> void:
	start_pos = global_position


func is_displaced() -> bool:
	return global_position.distance_to(start_pos) > 0.8


func _integrate_forces(state: PhysicsDirectBodyState3D) -> void:
	_cooldown -= state.step
	if _cooldown > 0.0:
		return
	var best := 0.0
	var best_pos := Vector3.ZERO
	for i in state.get_contact_count():
		var dv := state.get_contact_impulse(i).length() / mass
		if dv > best:
			best = dv
			best_pos = state.get_contact_local_position(i)
	if best > 1.2:
		_cooldown = 0.15
		Sfx.impact(material_kind, best_pos, best)
		if best > 3.5:
			Fx.dust(best_pos, clampf(best / 10.0, 0.3, 1.5))
		if best > 2.0 and material_kind != "metal":
			Sfx.debris(best_pos, best)
