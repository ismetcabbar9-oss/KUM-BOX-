class_name Pendulum
extends Node3D
## Sallanan yıkım gülle sarkacı: gerçek menteşe + ağır çelik gülle (RigidBody).
## Sürtünmesiz sallanır; mermi çarparsa momentum aktarılır, gülle yoluna çıkanı ezer.

const TOP := 16.0
const LEN := 12.0

var ball: RigidBody3D
var _chain: MeshInstance3D


func _ready() -> void:
	var rust := WorldBuilder.pbr("rusty_metal_02", 0.4, Color.WHITE, false)
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var a := Vector3(sx * 9.0, 0, sz * 3.0)
			var b := Vector3(sx * 8.6, TOP, 0)
			Launcher.beam(self, Vector3(0.5, 0.5, a.distance_to(b)), Transform3D(Basis.looking_at((b - a).normalized(), Vector3.FORWARD), (a + b) * 0.5), rust)
	Launcher.beam(self, Vector3(18.0, 0.7, 0.7), Transform3D(Basis.IDENTITY, Vector3(0, TOP, 0)), rust)
	ball = RigidBody3D.new()
	ball.position = Vector3(0, TOP - LEN, 0)
	var sm := SphereMesh.new()
	sm.radius = 1.5
	sm.height = 3.0
	var steel := WorldBuilder.pbr("metal_plate", 0.5, Color(0.4, 0.4, 0.42), false).duplicate()
	steel.metallic = 1.0
	sm.material = steel
	var mi := MeshInstance3D.new()
	mi.mesh = sm
	ball.add_child(mi)
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 1.5
	cs.shape = sh
	ball.add_child(cs)
	ball.mass = 9000.0
	ball.collision_layer = 8
	ball.collision_mask = 2 | 4 | 8
	ball.can_sleep = false
	ball.linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	ball.angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	ball.linear_damp = 0.0
	ball.angular_damp = 0.0
	add_child(ball)
	var hinge := HingeJoint3D.new()
	# Eksen Z: gülle X boyunca, yani merminin yoluna dik sallanır
	hinge.transform = Transform3D(Basis.IDENTITY, Vector3(0, TOP, 0))
	add_child(hinge)
	hinge.node_a = hinge.get_path_to(ball)
	hinge.node_b = NodePath("")
	_chain = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.12
	cm.bottom_radius = 0.12
	cm.height = 1.0
	_chain.mesh = cm
	_chain.material_override = rust
	_chain.top_level = true
	add_child(_chain)
	# Başlangıç salınımı
	await get_tree().physics_frame
	ball.linear_velocity = global_transform.basis * Vector3(9.0, 0, 0)


func _process(_delta: float) -> void:
	var a := to_global(Vector3(0, TOP, 0))
	var b := ball.get_global_transform_interpolated().origin
	var d := b - a
	_chain.global_transform = Transform3D(Basis.looking_at(d.normalized(), Vector3.FORWARD) * Basis(Vector3.RIGHT, PI * 0.5), a + d * 0.5)
	_chain.scale = Vector3(1, d.length(), 1)
