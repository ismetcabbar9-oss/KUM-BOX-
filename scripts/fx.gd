extends Node
## Görsel efektler: toz bulutu havuzu ve kamera sarsıntısı sinyali.

signal shake_requested(amount: float)

const POOL_SIZE := 10

var _pool: Array[GPUParticles3D] = []
var _next := 0
var _cooldown := 0.0


func _ready() -> void:
	var tex := GradientTexture2D.new()
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	tex.gradient = g

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.albedo_color = Color(0.62, 0.57, 0.5, 0.55)

	var quad := QuadMesh.new()
	quad.size = Vector2(2.5, 2.5)
	quad.material = mat

	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 80.0
	pm.initial_velocity_min = 1.5
	pm.initial_velocity_max = 5.0
	pm.gravity = Vector3(0, -0.6, 0)
	pm.damping_min = 1.5
	pm.damping_max = 3.0
	pm.scale_min = 0.6
	pm.scale_max = 1.8
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.4))
	curve.add_point(Vector2(1, 1.6))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var fade := Gradient.new()
	fade.set_color(0, Color(1, 1, 1, 0.9))
	fade.set_color(1, Color(1, 1, 1, 0))
	var ft := GradientTexture1D.new()
	ft.gradient = fade
	pm.color_ramp = ft
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.8

	for i in POOL_SIZE:
		var p := GPUParticles3D.new()
		p.one_shot = true
		p.emitting = false
		p.amount = 14
		p.lifetime = 2.2
		p.explosiveness = 0.9
		p.process_material = pm
		p.draw_pass_1 = quad
		p.visibility_aabb = AABB(Vector3(-10, -5, -10), Vector3(20, 15, 20))
		add_child(p)
		_pool.append(p)


func _process(delta: float) -> void:
	_cooldown -= delta


func dust(pos: Vector3, amount: float) -> void:
	if _cooldown > 0.0:
		return
	_cooldown = 0.04
	var p := _pool[_next]
	_next = (_next + 1) % POOL_SIZE
	p.global_position = pos
	p.scale = Vector3.ONE * clampf(amount, 0.3, 2.5)
	p.restart()


func shake(amount: float) -> void:
	if amount > 0.02:
		shake_requested.emit(amount)
