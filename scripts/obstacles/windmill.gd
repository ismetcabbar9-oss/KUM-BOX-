class_name Windmill
extends Node3D
## Dönen çelik pervane engeli: kinematik (AnimatableBody3D) kanatlar sabit hızla döner,
## çarpan mermiyi saptırır, molozu savurur.

const HUB_H := 11.0
const BLADE_LEN := 9.0

var speed := 0.9  # rad/s
var _rotor: AnimatableBody3D


func _ready() -> void:
	var steel := WorldBuilder.pbr("metal_plate", 0.4, Color(0.55, 0.57, 0.6), false)
	var rust := WorldBuilder.pbr("rusty_metal_02", 0.4, Color.WHITE, false)
	# Kafes kule: dört eğik ayak + kuşaklar
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var a := Vector3(sx * 2.4, 0, sz * 2.4)
			var b := Vector3(sx * 0.5, HUB_H - 0.5, sz * 0.5 - 0.8)
			Launcher.beam(self, Vector3(0.35, 0.35, a.distance_to(b)), Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP if absf((b - a).normalized().y) < 0.99 else Vector3.FORWARD), (a + b) * 0.5), rust)
	for h: float in [3.0, 6.5]:
		var w: float = 2.4 - (2.4 - 0.5) * h / HUB_H
		for sz in [-1.0, 1.0]:
			Launcher.beam(self, Vector3(w * 2.0, 0.25, 0.25), Transform3D(Basis.IDENTITY, Vector3(0, h, sz * w - 0.4 * h / HUB_H)), rust, false)
	_rotor = AnimatableBody3D.new()
	_rotor.sync_to_physics = true
	_rotor.position = Vector3(0, HUB_H, 1.0)
	_rotor.collision_layer = 8
	_rotor.collision_mask = 0
	add_child(_rotor)
	for i in 4:
		var blade_basis := Basis(Vector3.FORWARD, i * PI * 0.5)
		var pos := blade_basis * Vector3(0, BLADE_LEN * 0.5 + 0.6, 0)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(1.4, BLADE_LEN, 0.25)
		mi.mesh = bm
		mi.material_override = steel
		mi.transform = Transform3D(blade_basis, pos)
		_rotor.add_child(mi)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = bm.size
		cs.shape = sh
		cs.transform = mi.transform
		_rotor.add_child(cs)
	var hub := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.8
	hm.bottom_radius = 0.8
	hm.height = 0.8
	hub.mesh = hm
	hub.material_override = rust
	hub.rotation_degrees = Vector3(90, 0, 0)
	_rotor.add_child(hub)


func _physics_process(delta: float) -> void:
	_rotor.rotate_z(speed * delta)
