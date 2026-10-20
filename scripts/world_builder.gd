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


## Yol tabanlı rampa: merkez çizgisi (pts) boyunca kesit süpürülür. banks: her noktada
## yatış açısı (radyan, virajda içe eğim). Yükseltilmiş kısımların altına beton ayak.
## Döner: rampanın statik gövdesi (tür değişince silinebilsin).
static func build_path_ramp(parent: Node3D, pts: PackedVector3Array, banks: PackedFloat32Array, width: float, wall_h := 2.2) -> StaticBody3D:
	var wall_t := 0.8
	var deck := 1.4
	var hw := width * 0.5
	var n := pts.size()
	var tang: Array[Vector3] = []
	var side: Array[Vector3] = []
	var up: Array[Vector3] = []
	for i in n:
		var t := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var s := Vector3.UP.cross(t).normalized()
		s = s.rotated(t, banks[i])
		tang.append(t)
		side.append(s)
		up.append(t.cross(s).normalized())
	var floor_v := PackedVector3Array()
	var floor_n := PackedVector3Array()
	var wall_v := PackedVector3Array()
	var wall_n := PackedVector3Array()
	var side_v := PackedVector3Array()
	var side_n := PackedVector3Array()
	for i in n - 1:
		var j := i + 1
		var a := pts[i]
		var b := pts[j]
		var sa := side[i]
		var sb := side[j]
		var ua := up[i]
		var ub := up[j]
		var nf := (ua + ub).normalized()
		var ns := (sa + sb).normalized()
		_quad(floor_v, floor_n, a - sa * hw, a + sa * hw, b + sb * hw, b - sb * hw, nf)
		for sg in [-1.0, 1.0]:
			var ia: Vector3 = a + sa * hw * sg
			var ib: Vector3 = b + sb * hw * sg
			var oa: Vector3 = a + sa * (hw + wall_t) * sg
			var ob: Vector3 = b + sb * (hw + wall_t) * sg
			_quad(wall_v, wall_n, ia, ib, ib + ub * wall_h, ia + ua * wall_h, -ns * sg)
			_quad(side_v, side_n, ia + ua * wall_h, ib + ub * wall_h, ob + ub * wall_h, oa + ua * wall_h, nf)
			_quad(side_v, side_n, oa - ua * deck, ob - ub * deck, ob + ub * wall_h, oa + ua * wall_h, ns * sg)
		var ow := hw + wall_t
		_quad(side_v, side_n, a - sa * ow - ua * deck, a + sa * ow - ua * deck, b + sb * ow - ub * deck, b - sb * ow - ub * deck, -nf)
	# Uç kapakları: başta tam kapak (arka duvar), sonda yalnız tabla kalınlığı (yol açık kalsın)
	for e in [0, n - 1]:
		var c := pts[e]
		var s := side[e]
		var u := up[e]
		var ow := hw + wall_t
		var nrm := -tang[e] if e == 0 else tang[e]
		var top := u * wall_h if e == 0 else Vector3.ZERO
		_quad(side_v, side_n, c - s * ow - u * deck, c + s * ow - u * deck, c + s * ow + top, c - s * ow + top, nrm)
	# Ayaklar: yol boyunca ~9 m'de bir
	var acc := 9.0
	for i in n:
		if i > 0:
			acc += pts[i].distance_to(pts[i - 1])
		if acc < 9.0:
			continue
		var bottom := pts[i] - up[i] * deck
		if bottom.y < 1.5:
			continue
		acc = 0.0
		for sg in [-1.0, 1.0]:
			var p: Vector3 = bottom + side[i] * (hw - 1.2) * sg
			# Alttan rampanın başka bir kısmı geçiyorsa (sarmal) ayak koyma: yolu keserdi
			var blocked := false
			for k in n:
				if pts[k].y < bottom.y - 2.0 and Vector2(pts[k].x - p.x, pts[k].z - p.z).length() < hw + wall_t + 1.5:
					blocked = true
					break
			if blocked:
				continue
			_box(side_v, side_n, Vector3(p.x, p.y * 0.5, p.z), Vector3(1.4, p.y, 1.4))


	var body := StaticBody3D.new()
	body.name = "Ramp"
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
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
	# İç duvarlar ayrı, kaygan gövde: virajda duvara yaslanan kaya sürtünmeyle yavaşlamasın
	var walls := StaticBody3D.new()
	var wpm := PhysicsMaterial.new()
	wpm.friction = 0.12
	walls.physics_material_override = wpm
	body.add_child(walls)
	var wall_mesh := _mesh_from(wall_v, wall_n)
	var mi3 := MeshInstance3D.new()
	mi3.mesh = wall_mesh
	mi3.material_override = mi.material_override
	walls.add_child(mi3)
	var ws := wall_mesh.create_trimesh_shape()
	ws.backface_collision = true
	var wcs := CollisionShape3D.new()
	wcs.shape = ws
	walls.add_child(wcs)
	return body
