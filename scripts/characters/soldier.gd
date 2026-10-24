class_name Soldier
extends RigidBody3D
## Kale figürü: asker, okçu ya da köylü (iskeletli model + Mixamo'dan aktarılmış animasyonlar).
## Davranışlar (Crowd yönetir):
##   duran (nöbet), rota (devriye/yürüyüş), iş (demirci, odun, talim), okçu (ok atar),
##   panik (koşarak kaçar, sonra işine döner), ölü.
## Gövde: kinematik kapsül (yürürken itebilir). Ölür: üstüne hızlı bir şey çarparsa, patlamada
## ya da altındaki taş koparsa; ölüm animasyonu oynar, gövde fizikle düşer (dönmeden).
## Animasyonlar el ile ilerletilir (Crowd mesafeye göre seyrekleştirir: uzaktakiler ucuz).

signal died(s: Soldier)

const HEIGHTS := {"soldier": 1.8, "archer": 1.8, "peasant": 1.7}
const WALK := 1.35
const RUN := 4.3
## Okçu: atış animasyonunda okun bırakıldığı an (oran)
const SHOOT_RELEASE := 0.62

enum St { STAND, ROUTE, WORK, SHOOT, PANIC, DEAD }

var kind := "soldier"
## guard / commander / archer / patrol / walker / worker
var role := "guard"
var alive := true
var state := St.STAND
## Rota (dünya noktaları)
var route := PackedVector3Array()
var route_loop := true
var work_anim := "idle"
var crowd: Node  # Crowd

var _ap: AnimationPlayer
var _cur := ""
var _ri := 0
var _dir := 1
var _wait := 0.0
var _path := PackedVector3Array()  # panik yolu
var _flee := PackedVector3Array()
var _returning := false
var _pi := 0
var _calm := 0.0
var _resume := St.STAND
var _poll := 0.0
var _query: PhysicsShapeQueryParameters3D
var _rest := 0.0
var _anim_acc := 0.0
var _last_shot_pos := 0.0
var _home: Transform3D
var _dead_t := 0.0
var _tool := -1
var _sk: Skeleton3D


func setup(kind_name := "soldier") -> void:
	kind = kind_name
	var model := Models.instance(kind)
	add_child(model)
	Models.fit(model, HEIGHTS[kind], "height")
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.32
	cap.height = HEIGHTS[kind]
	cs.shape = cap
	cs.position.y = HEIGHTS[kind] * 0.5
	cs.name = "Govde"
	add_child(cs)
	mass = 85.0
	collision_layer = 16
	collision_mask = 1 | 2 | 4 | 16
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	add_to_group("soldiers")
	_ap = model.find_children("*", "AnimationPlayer", true, false)[0]
	_ap.add_animation_library("k", load("res://assets/anims/%s.res" % kind))
	_ap.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_ap.speed_scale = randf_range(0.9, 1.1)
	_sk = model.find_children("*", "Skeleton3D", true, false)[0]
	for i in _sk.get_bone_count():
		if _sk.get_bone_name(i).contains("Tool"):
			_tool = i
	show_tool(false)
	_poll = randf() * 0.25
	_query = PhysicsShapeQueryParameters3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.85
	_query.shape = sph
	_query.exclude = [get_rid()]


## Köylünün elindeki alet (kılıç/çekiç) yalnız işte görünür
func show_tool(on: bool) -> void:
	if _tool >= 0:
		_sk.set_bone_pose_scale(_tool, Vector3.ONE if on else Vector3.ZERO)


func play(anim: String, blend := 0.25) -> void:
	if _cur == anim:
		return
	_cur = anim
	_ap.play("k/" + anim, blend)
	if anim != "death":
		# Aynı animasyonu oynayanlar senkron görünmesin
		_ap.seek(randf() * _ap.current_animation_length, false)


## Crowd çağırır: animasyonu biriken süre kadar ilerlet (uzaktakiler seyrek)
func anim_tick(dt: float) -> void:
	_ap.advance(dt)


func begin_stand() -> void:
	state = St.STAND
	_home = global_transform
	if kind == "archer" and role == "archer":
		state = St.SHOOT
		play("shoot")
	else:
		play("idle")


func begin_route(pts: PackedVector3Array, loop: bool, start_i: int) -> void:
	route = pts
	route_loop = loop
	_ri = start_i % pts.size()
	state = St.ROUTE
	global_position = pts[_ri]
	_ri = (_ri + 1) % pts.size()
	play("walk")


func begin_work(anim: String) -> void:
	work_anim = anim
	state = St.WORK
	_home = global_transform
	show_tool(anim == "swing")
	play(anim)


## Kaçış yolunu izle, sonra işine dön
func panic(path: PackedVector3Array) -> void:
	if not alive or state == St.DEAD:
		return
	if state != St.PANIC:
		_resume = state
	elif _returning:
		# Dönüş yolundayken yeni tehlike: bulunduğu yerden yeniden kaç
		pass
	state = St.PANIC
	_returning = false
	_path = path
	_flee = path
	_pi = 0
	_calm = randf_range(8.0, 16.0)
	show_tool(false)
	play("run", 0.15)


func _physics_process(delta: float) -> void:
	if not alive:
		_dead_t += delta
		if linear_velocity.length_squared() < 0.2:
			_rest += delta
			if _rest > 2.5 and _dead_t > 3.0:
				freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
				freeze = true
				set_physics_process(false)
		else:
			_rest = 0.0
		return
	match state:
		St.ROUTE:
			_follow_route(delta)
		St.PANIC:
			_follow_panic(delta)
		St.SHOOT:
			_archer()
	_poll -= delta
	if _poll <= 0.0:
		_poll = 0.2
		_check_hits()


func _move_to(p: Vector3, speed: float, delta: float) -> bool:
	var to := p - global_position
	to.y = 0.0
	var d := to.length()
	var step := speed * delta
	# Yükseklik: rota noktasının yüksekliğine yumuşak geçiş (sur yolunda sabit)
	var y := lerpf(global_position.y, p.y, clampf(delta * 6.0, 0.0, 1.0))
	if d <= step:
		global_position = Vector3(p.x, y, p.z)
		return true
	var dir := to / d
	global_position = Vector3(global_position.x + dir.x * step, y, global_position.z + dir.z * step)
	var target_yaw := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, target_yaw, clampf(delta * 8.0, 0.0, 1.0))
	return false


func _follow_route(delta: float) -> void:
	if route.size() < 2:
		return
	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			play("walk")
		return
	if _move_to(route[_ri], WALK * (1.0 if kind != "peasant" else 0.9), delta):
		if route_loop:
			_ri = (_ri + 1) % route.size()
			if randf() < 0.3:
				_pause()
		else:
			# Git-gel: uçlarda bekle, geri dön
			if _ri == route.size() - 1 or _ri == 0:
				_dir = -1 if _ri == route.size() - 1 else 1
				_pause()
			_ri += _dir


func _pause() -> void:
	_wait = randf_range(1.5, 4.5)
	play("idle")


func _follow_panic(delta: float) -> void:
	if _pi < _path.size():
		if _move_to(_path[_pi], WALK if _returning else RUN, delta):
			_pi += 1
			if _pi >= _path.size():
				if _returning:
					_finish_return()
				else:
					play("idle", 0.3)
		return
	if _returning:
		return
	_calm -= delta
	if _calm <= 0.0:
		# Sakinleş: geldiği yoldan (kapılardan) geri dön
		_returning = true
		var back := PackedVector3Array()
		for i in range(_flee.size() - 2, -1, -1):
			back.append(_flee[i])
		back.append(route[_ri] if _resume == St.ROUTE and route.size() > 0 else _home.origin)
		_path = back
		_pi = 0
		play("walk")


func _finish_return() -> void:
	_returning = false
	match _resume:
		St.ROUTE:
			state = St.ROUTE
			play("walk")
		St.WORK:
			global_transform = _home
			begin_work(work_anim)
		_:
			global_transform = _home
			begin_stand()


func _archer() -> void:
	if _cur != "shoot" or crowd == null:
		return
	var pos := _ap.current_animation_position / maxf(_ap.current_animation_length, 0.01)
	if pos >= SHOOT_RELEASE and _last_shot_pos < SHOOT_RELEASE:
		crowd.archer_shot(self)
	_last_shot_pos = pos


func _check_hits() -> void:
	var space := get_world_3d().direct_space_state
	# Çarpan hızlı gövde
	_query.transform = Transform3D(Basis.IDENTITY, global_position + Vector3.UP)
	_query.collision_mask = 2 | 4
	(_query.shape as SphereShape3D).radius = 0.85
	for hit in space.intersect_shape(_query, 8):
		var b := hit["collider"] as RigidBody3D
		if b and not b.freeze and not (b is Soldier) and b.linear_velocity.length() > 3.0:
			die(b.linear_velocity.normalized() * clampf(b.linear_velocity.length() * 0.6, 2.0, 12.0))
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
	if not supported:
		die(Vector3.ZERO)


## Öl: v_change hız değişimi (m/s, yön × büyüklük)
func die(v_change: Vector3) -> void:
	if not alive:
		return
	alive = false
	state = St.DEAD
	show_tool(false)
	play("death", 0.1)
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = false
	sleeping = false
	axis_lock_angular_y = true
	died.emit(self)
	# Yere yığılınca dik kapsül yerine yatık gövde
	get_tree().create_timer(1.2).timeout.connect(_lie_down)
	# Kinematikten dinamiğe geçiş bir sonraki fizik adımında: hızı o zaman ver
	await get_tree().physics_frame
	linear_velocity = v_change.limit_length(14.0) + Vector3.UP * (1.5 if v_change != Vector3.ZERO else 0.0)


func _lie_down() -> void:
	var cs := get_node_or_null("Govde") as CollisionShape3D
	if cs == null:
		return
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 0.35, HEIGHTS[kind])
	cs.shape = box
	cs.position = Vector3(0, 0.18, 0)
