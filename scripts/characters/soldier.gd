class_name Soldier
extends RigidBody3D
## Kale askeri: nöbet animasyonu (idle) oynatır, kapsül gövdeyle statik bekler.
## Ölür: üstüne hızlı bir şey çarparsa (mermi, tuğla, moloz), patlamada ya da altındaki
## taş koparsa. Ölünce animasyon durur, kollar savrulur, gövde fizikle düşer.

const HEIGHT := 1.8

var alive := true
## "guard" / "commander"
var role := "guard"
var _anim: AnimationPlayer
var _rig: RigPose
var _poll := 0.0
var _query: PhysicsShapeQueryParameters3D
var _rest := 0.0


func setup() -> void:
	var model := Models.instance("soldier")
	add_child(model)
	Models.fit(model, HEIGHT, "height")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = HEIGHT
	cs.shape = cap
	cs.position.y = HEIGHT * 0.5
	add_child(cs)
	mass = 90.0
	collision_layer = 16
	collision_mask = 1 | 2 | 4 | 16
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	angular_damp = 1.5
	add_to_group("soldiers")
	var aps := model.find_children("*", "AnimationPlayer", true, false)
	if aps.size() > 0:
		_anim = aps[0]
		var a := _anim.get_animation(_anim.get_animation_list()[0])
		a.loop_mode = Animation.LOOP_LINEAR
		_anim.play(_anim.get_animation_list()[0])
		_anim.seek(randf() * a.length, true)
		_anim.speed_scale = randf_range(0.85, 1.1)
	_rig = RigPose.new(model.find_children("*", "Skeleton3D", true, false)[0], self)
	_poll = randf() * 0.25
	_query = PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.85
	_query.shape = sph
	_query.collision_mask = 2 | 4
	_query.exclude = [get_rid()]


func _physics_process(delta: float) -> void:
	if not alive:
		if linear_velocity.length_squared() < 0.2:
			_rest += delta
			if _rest > 3.0:
				freeze = true
				set_physics_process(false)
		else:
			_rest = 0.0
		return
	_poll -= delta
	if _poll > 0.0:
		return
	_poll = 0.2
	var space := get_world_3d().direct_space_state
	# Çarpan hızlı gövde
	_query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP)
	for hit in space.intersect_shape(_query, 8):
		var b := hit["collider"] as RigidBody3D
		if b and not b.freeze and b.linear_velocity.length() > 3.0:
			die(b.linear_velocity.normalized() * minf(b.mass, 2000.0) * 0.02)
			return
	# Destek: ayağının altında sağlam taş ya da zemin (küre: taş ek yerlerinden kaçmaz)
	_query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.DOWN * 0.3)
	_query.collision_mask = 1 | 2
	(_query.shape as SphereShape3D).radius = 0.4
	var supported := false
	for hit in space.intersect_shape(_query, 8):
		var c: Object = hit["collider"]
		if c is Destructible:
			if (c as Destructible).intact:
				supported = true
		elif c is StaticBody3D:
			supported = true
	(_query.shape as SphereShape3D).radius = 0.85
	_query.collision_mask = 2 | 4
	if not supported:
		die(Vector3.ZERO)


## Öl: v_change hız değişimi (m/s, yön × büyüklük)
func die(v_change: Vector3) -> void:
	if not alive:
		return
	alive = false
	if _anim:
		_anim.stop()
	_rig.reset()
	# Savrulan kollar, gevşek bacaklar
	_rig.arm("Left", Vector3(1, 0.45, 0.1), Vector3(0.6, 0.7, 0.4))
	_rig.arm("Right", Vector3(1, 0.2, -0.2), Vector3(0.8, 0.5, 0.2))
	_rig.leg("Left", 0.25, 0.35, 0.18)
	_rig.leg("Right", -0.1, 0.15, 0.12)
	freeze = false
	sleeping = false
	linear_velocity = v_change.limit_length(14.0) + Vector3.UP * (1.5 if v_change != Vector3.ZERO else 0.0)
	angular_velocity = Vector3(randf_range(-2, 2), randf_range(-1, 1), randf_range(-2, 2))
