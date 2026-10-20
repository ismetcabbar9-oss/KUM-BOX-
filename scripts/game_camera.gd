extends Camera3D
## Takip kamerası: kayanın arkasından gider, dokunmatik ile döndürülür/yakınlaştırılır.

var target: Node3D
var distance := 16.0
var zoom := 1.0
var user_yaw := 0.0
var user_pitch := 0.0
var _heading := 0.0
var _shake := 0.0
var _idle := 0.0
var _look := Vector3.ZERO


func _ready() -> void:
	Fx.shake_requested.connect(func(a: float) -> void: _shake = maxf(_shake, a))
	# Kamera _process'te interpolasyonlu hedefi izler; kendi interpolasyonu gereksiz
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fov = 62.0
	near = 0.2
	far = 1500.0


func orbit(dx: float, dy: float) -> void:
	user_yaw -= dx * 0.006
	user_pitch = clampf(user_pitch + dy * 0.004, -0.5, 0.9)
	_idle = 0.0


func pinch(factor: float) -> void:
	zoom = clampf(zoom / factor, 0.45, 3.0)


## Yeni hedef: istasyon bakışı ya da mermi.
func follow(node: Node3D, dist: float, heading := NAN) -> void:
	target = node
	distance = dist
	if not is_nan(heading):
		_heading = heading
	user_yaw = 0.0
	user_pitch = 0.0


func snap() -> void:
	if target:
		_look = target.global_position
		var desired := target.global_position + Vector3(-sin(_heading), 0.32, -cos(_heading)) * distance
		global_position = desired


func _process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var real_dt := delta / maxf(Engine.time_scale, 0.01)
	# Dikey ekranda yatay görüş açısını koru (sahne yanlardan kesilmesin)
	var vs := get_viewport().get_visible_rect().size
	if vs.y > vs.x:
		keep_aspect = Camera3D.KEEP_WIDTH
		fov = 78.0
	else:
		keep_aspect = Camera3D.KEEP_HEIGHT
		fov = 62.0
	var tpos := target.get_global_transform_interpolated().origin
	var rb := target as RigidBody3D
	# Yön: kayanın yatay hızına göre yumuşak dön
	if rb and not rb.freeze:
		var v := rb.linear_velocity
		v.y = 0.0
		if v.length() > 2.0:
			var h := atan2(v.x, v.z)
			_heading = lerp_angle(_heading, h, clampf(real_dt * 1.5, 0.0, 1.0))
	_idle += real_dt
	if _idle > 3.0:
		user_yaw = lerp_angle(user_yaw, 0.0, clampf(real_dt * 0.8, 0.0, 1.0))
		user_pitch = lerpf(user_pitch, 0.0, clampf(real_dt * 0.8, 0.0, 1.0))
	var r := 1.0
	if target is Projectile:
		r = maxf((target as Projectile).radius, 0.6)
	var dist := (distance + r * 3.0) * zoom
	var yaw := _heading + user_yaw
	var pitch := 0.32 + user_pitch
	var offset := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch)) * dist
	var desired := tpos + offset
	# Kamera araziye/rampaya girmesin: kayadan kameraya ışın at (sadece statik katman)
	var q := PhysicsRayQueryParameters3D.create(tpos + Vector3.UP * r, desired, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty():
		desired = hit["position"] + (hit["normal"] as Vector3) * 0.8
	global_position = global_position.lerp(desired, clampf(real_dt * 4.0, 0.0, 1.0))
	_look = _look.lerp(tpos + Vector3(sin(yaw), 0, cos(yaw)) * 6.0, clampf(real_dt * 6.0, 0.0, 1.0))
	look_at(_look, Vector3.UP)
	if _shake > 0.0:
		var s := _shake * _shake * 0.6
		rotate_object_local(Vector3.RIGHT, randf_range(-s, s) * 0.05)
		rotate_object_local(Vector3.UP, randf_range(-s, s) * 0.05)
		h_offset = randf_range(-s, s) * 0.3
		v_offset = randf_range(-s, s) * 0.3
		_shake = maxf(_shake - real_dt * 1.8, 0.0)
	else:
		h_offset = 0.0
		v_offset = 0.0
