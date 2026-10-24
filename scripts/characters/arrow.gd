class_name Arrow
extends Node3D
## Ok: balistik uçar (yerçekimi), uçtuğu yöne bakar; çarptığı yere saplanır, bir süre kalır.
## Fizik gövdesi yok: her adımda ışın sorgusu (ucuz).

const LIFE := 30.0

var velocity := Vector3.ZERO
var stuck := false
var _age := 0.0
static var _mesh: Mesh


func _ready() -> void:
	if _mesh == null:
		_mesh = _build_mesh()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


## Şaft + uç + tüyler (tek mesh, -Z ileri)
static func _build_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.5, 0.36, 0.22)
	var am := ArrayMesh.new()
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.02
	shaft.bottom_radius = 0.02
	shaft.height = 1.1
	shaft.radial_segments = 4
	shaft.rings = 1
	st.append_from(shaft, 0, Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO))
	var tip := CylinderMesh.new()
	tip.top_radius = 0.0
	tip.bottom_radius = 0.03
	tip.height = 0.08
	tip.radial_segments = 4
	tip.rings = 1
	st.append_from(tip, 0, Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0, 0, -0.59)))
	for a in [0.0, PI * 0.5]:
		var f := BoxMesh.new()
		f.size = Vector3(0.12, 0.006, 0.2)
		st.append_from(f, 0, Transform3D(Basis(Vector3.BACK, a), Vector3(0, 0, 0.45)))
	st.generate_normals()
	st.set_material(wood)
	return st.commit(am)


func _physics_process(delta: float) -> void:
	_age += delta
	if _age > LIFE:
		queue_free()
		return
	if stuck:
		return
	velocity += Vector3(0, -9.81, 0) * delta
	var from := global_position
	var to := from + velocity * delta
	var q := PhysicsRayQueryParameters3D.create(from, to, 1 | 2 | 16)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		stuck = true
		global_position = hit["position"] - velocity.normalized() * 0.25
		Sfx.play("arrow_hit", global_position, -4.0)
		var s := hit["collider"] as Soldier
		if s:
			s.die(velocity.normalized() * 2.0)
		return
	global_position = to
	if velocity.length_squared() > 0.01:
		look_at(to + velocity, Vector3.UP)
	if to.y < -5.0:
		queue_free()
