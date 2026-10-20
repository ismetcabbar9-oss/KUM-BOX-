class_name RampLauncher
extends Launcher
## Beton rampa: kaya tepede bekler, yana sürükleyerek hizalanır, itilince yuvarlanır.

var height := 55.0
var flat := 14.0
var width := 14.0
var aim_x := 0.0


func _init() -> void:
	super()
	title = "RAMPA"
	base_radius = 2.0
	view_distance = 16.0


func rolling() -> bool:
	return true


func load_projectile(p: Projectile) -> void:
	loaded = p
	aim_x = clampf(aim_x, -_limit(), _limit())
	p.global_position = to_global(Vector3(aim_x, height + p.radius * 1.05, flat * 0.5))
	p.reset_physics_interpolation()
	view_target.position = Vector3(aim_x, height + p.radius, flat * 0.5)


func _limit() -> float:
	var r := loaded.radius if loaded else base_radius
	return width * 0.5 - r - 0.2


func drag(relative: Vector2, _vs: Vector2) -> void:
	if not is_ready():
		return
	aim_x = clampf(aim_x - relative.x * 0.02, -_limit(), _limit())
	loaded.global_position = to_global(Vector3(aim_x, height + loaded.radius * 1.05, flat * 0.5))
	view_target.position.x = aim_x


func release(swipe_up_speed: float) -> bool:
	if swipe_up_speed > 0.0 and is_ready():
		fire(clampf(4.0 + swipe_up_speed * 6.0, 4.0, 20.0))
		return true
	return false


func fire(power := -1.0) -> void:
	if not is_ready():
		return
	if power < 0.0:
		power = 9.0
	var p := loaded
	var fwd := global_transform.basis.z
	p.launch(fwd * power, global_transform.basis.x * power / p.radius)
	fired.emit(p)


func hint() -> String:
	return "Sağa-sola sürükle: hizala   •   Yukarı kaydır ya da FIRLAT"
