class_name WorldBuilder
extends RefCounted
## Prosedürel dünya parçaları: PBR malzemeler, ayaklı beton rampa, zemin.

const TEX := "res://assets/textures/"

static var _mat_cache := {}


## Poly Haven CC0 dokularından PBR malzeme (dünya uzayı triplanar, UV gerekmez).
static func pbr(tex_name: String, scale: float, tint := Color.WHITE, world_triplanar := true) -> StandardMaterial3D:
	var key := "%s_%s_%s_%s" % [tex_name, scale, tint, world_triplanar]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TEX + tex_name + "_diff_1k.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(TEX + tex_name + "_nor_gl_1k.jpg")
	m.normal_scale = 1.0
	var arm: Texture2D = load(TEX + tex_name + "_arm_1k.jpg")
	m.roughness_texture = arm
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.ao_enabled = true
	m.ao_texture = arm
	m.ao_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world_triplanar
	m.uv1_triplanar_sharpness = 4.0
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_cache[key] = m
	return m


## Godot ön yüzleri saat yönünde (CW) kabul eder; üçgeni verilen normale göre sırala.
static func _tri(v: PackedVector3Array, n: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, normal: Vector3) -> void:
	if (c - a).cross(b - a).dot(normal) < 0.0:
		var t := b
		b = c
		c = t
	v.append_array([a, b, c])
	n.append_array([normal, normal, normal])


static func _quad(v: PackedVector3Array, n: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal := Vector3.ZERO) -> void:
	if normal == Vector3.ZERO:
		normal = (b - a).cross(d - a).normalized()
	_tri(v, n, a, b, c, normal)
	_tri(v, n, a, c, d, normal)


static func _mesh_from(v: PackedVector3Array, n: PackedVector3Array) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_NORMAL] = n
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Rampa yükseklik profili: üstte düz platform, sonra dikten yataya yumuşak iniş.
static func ramp_height(z: float, height: float, flat_len: float, slope_len: float) -> float:
	if z <= flat_len:
		return height
	var s := clampf((z - flat_len) / slope_len, 0.0, 1.0)
	return height * pow(1.0 - s, 2.0)


## Ayaklı beton rampa: yuvarlanma yüzeyi + yan duvarlar + tabla altı + beton ayaklar.
## Arazi üretmez; tüm yapı iki mesh (iki draw call) ve iki trimesh çarpışmadan oluşur.
static func build_ramp(parent: Node3D, width: float, height: float, flat_len: float, slope_len: float, runout: float) -> void:
	var wall_h := 2.2
	var wall_t := 0.8
	var deck := 1.4
	var lift := 0.03  # zeminle z-fighting olmasın
	var total := flat_len + slope_len + runout
	var steps := 110
	var hw := width * 0.5
	var ow := hw + wall_t
	var floor_v := PackedVector3Array()
	var floor_n := PackedVector3Array()
	var side_v := PackedVector3Array()
	var side_n := PackedVector3Array()
	for i in range(steps):
		var z0 := total * float(i) / steps
		var z1 := total * float(i + 1) / steps
		var y0 := ramp_height(z0, height, flat_len, slope_len) + lift
		var y1 := ramp_height(z1, height, flat_len, slope_len) + lift
		var up := Vector3(0, z1 - z0, -(y1 - y0)).normalized()
		_quad(floor_v, floor_n, Vector3(-hw, y0, z0), Vector3(hw, y0, z0), Vector3(hw, y1, z1), Vector3(-hw, y1, z1), up)
		for sgn in [-1.0, 1.0]:
			var xi: float = sgn * hw
			var xo: float = sgn * ow
			var out := Vector3(sgn, 0, 0)
			_quad(floor_v, floor_n, Vector3(xi, y0, z0), Vector3(xi, y1, z1), Vector3(xi, y1 + wall_h, z1), Vector3(xi, y0 + wall_h, z0), -out)
			_quad(side_v, side_n, Vector3(xi, y0 + wall_h, z0), Vector3(xi, y1 + wall_h, z1), Vector3(xo, y1 + wall_h, z1), Vector3(xo, y0 + wall_h, z0), up)
			# Dış yüz: duvar tepesinden tabla altına
			_quad(side_v, side_n, Vector3(xo, y0 - deck, z0), Vector3(xo, y1 - deck, z1), Vector3(xo, y1 + wall_h, z1), Vector3(xo, y0 + wall_h, z0), out)
		# Tabla altı
		_quad(side_v, side_n, Vector3(-ow, y0 - deck, z0), Vector3(ow, y0 - deck, z0), Vector3(ow, y1 - deck, z1), Vector3(-ow, y1 - deck, z1), -up)
	# Başlangıç ucu
	_quad(side_v, side_n, Vector3(-ow, height + lift - deck, 0), Vector3(ow, height + lift - deck, 0), Vector3(ow, height + lift + wall_h, 0), Vector3(-ow, height + lift + wall_h, 0), Vector3(0, 0, -1))
	# Ayaklar: tabla altı 1.5 m'den yüksekse her 9 m'de bir çift kolon + kiriş
	var z := 3.0
	while z < total:
		var top := ramp_height(z, height, flat_len, slope_len) + lift - deck
		if top < 1.5:
			break
		for sgn in [-1.0, 1.0]:
			_box(side_v, side_n, Vector3(sgn * (hw - 1.2), top * 0.5, z), Vector3(1.4, top, 1.4))
		if top > 8.0:
			# Ara kiriş: yüksek ayakları birbirine bağlar
			_box(side_v, side_n, Vector3(0, top * 0.55, z), Vector3(width - 2.4, 0.9, 0.9))
		z += 9.0

	var body := StaticBody3D.new()
	body.name = "Ramp"
	var pm := PhysicsMaterial.new()
	pm.friction = 0.85
	pm.bounce = 0.05
	body.physics_material_override = pm
	parent.add_child(body)
	var floor_mesh := _mesh_from(floor_v, floor_n)
	var mi := MeshInstance3D.new()
	mi.mesh = floor_mesh
	mi.material_override = pbr("concrete_floor_worn_001", 0.25, Color(0.92, 0.9, 0.88))
	body.add_child(mi)
	var side_mesh := _mesh_from(side_v, side_n)
	var mi2 := MeshInstance3D.new()
	mi2.mesh = side_mesh
	mi2.material_override = pbr("rough_concrete", 0.2, Color(0.85, 0.85, 0.82))
	body.add_child(mi2)
	for m in [floor_mesh, side_mesh]:
		var shape := (m as ArrayMesh).create_trimesh_shape()
		shape.backface_collision = true
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)


static func _box(v: PackedVector3Array, n: PackedVector3Array, c: Vector3, s: Vector3) -> void:
	var h := s * 0.5
	for ax in 3:
		for sgn in [-1.0, 1.0]:
			if ax == 1:
				continue  # üst/alt yüz görünmez
			var nrm := Vector3.ZERO
			nrm[ax] = sgn
			var u := Vector3.ZERO
			var w := Vector3.ZERO
			u[(ax + 1) % 3] = h[(ax + 1) % 3]
			w[(ax + 2) % 3] = h[(ax + 2) % 3]
			var f := c + nrm * h[ax]
			_quad(v, n, f - u - w, f + u - w, f + u + w, f - u + w, nrm)


## Tek düzlem zemin (2 üçgen) + sonsuz çarpışma düzlemi. Tekrar desenini shader kırar.
static func build_ground(parent: Node3D) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/ground.gdshader")
	mat.set_shader_parameter("albedo_tex", load(TEX + "rocky_terrain_02_diff_1k.jpg"))
	mat.set_shader_parameter("normal_tex", load(TEX + "rocky_terrain_02_nor_gl_1k.jpg"))
	mat.set_shader_parameter("arm_tex", load(TEX + "rocky_terrain_02_arm_1k.jpg"))
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var nt := NoiseTexture2D.new()
	nt.width = 256
	nt.height = 256
	nt.seamless = true
	nt.generate_mipmaps = true
	nt.noise = noise
	mat.set_shader_parameter("variation_tex", nt)
	var plane := PlaneMesh.new()
	plane.size = Vector2(3000, 3000)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var body := StaticBody3D.new()
	body.name = "Ground"
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	body.physics_material_override = pm
	body.add_child(mi)
	var cs := CollisionShape3D.new()
	cs.shape = WorldBoundaryShape3D.new()
	body.add_child(cs)
	parent.add_child(body)
