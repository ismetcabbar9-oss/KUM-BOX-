class_name WorldBuilder
extends RefCounted
## Prosedürel dünya parçaları: malzemeler, rampa, arazi, kaya mesh'i.

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


## Uzun beton rampa: zemin + yan duvarlar + yere inen dolu gövde.
static func build_ramp(parent: Node3D, width: float, height: float, flat_len: float, slope_len: float, runout: float) -> void:
	var wall_h := 2.2
	var wall_t := 1.0
	var total := flat_len + slope_len + runout
	var steps := 120
	var hw := width * 0.5
	var floor_v := PackedVector3Array()
	var floor_n := PackedVector3Array()
	var side_v := PackedVector3Array()
	var side_n := PackedVector3Array()
	var zs: Array[float] = [0.0]
	for i in range(1, steps + 1):
		zs.append(total * float(i) / steps)
	for i in range(steps):
		var z0 := zs[i]
		var z1 := zs[i + 1]
		var y0 := ramp_height(z0, height, flat_len, slope_len)
		var y1 := ramp_height(z1, height, flat_len, slope_len)
		var up := Vector3(0, z1 - z0, -(y1 - y0)).normalized()
		# Yuvarlanma yüzeyi
		_quad(floor_v, floor_n, Vector3(-hw, y0, z0), Vector3(hw, y0, z0), Vector3(hw, y1, z1), Vector3(-hw, y1, z1), up)
		for sgn in [-1.0, 1.0]:
			var xi: float = sgn * hw
			var xo: float = sgn * (hw + wall_t)
			var out := Vector3(sgn, 0, 0)
			# Duvar iç yüzü
			_quad(floor_v, floor_n, Vector3(xi, y0, z0), Vector3(xi, y1, z1), Vector3(xi, y1 + wall_h, z1), Vector3(xi, y0 + wall_h, z0), -out)
			# Duvar üstü
			_quad(side_v, side_n, Vector3(xi, y0 + wall_h, z0), Vector3(xi, y1 + wall_h, z1), Vector3(xo, y1 + wall_h, z1), Vector3(xo, y0 + wall_h, z0), up)
			# Dış yüz: duvar tepesinden yere kadar
			_quad(side_v, side_n, Vector3(xo, -2.0, z0), Vector3(xo, -2.0, z1), Vector3(xo, y1 + wall_h, z1), Vector3(xo, y0 + wall_h, z0), out)
	# Arka yüz (başlangıç tarafı)
	_quad(side_v, side_n, Vector3(-hw - wall_t, -2.0, 0), Vector3(hw + wall_t, -2.0, 0), Vector3(hw + wall_t, height + wall_h, 0), Vector3(-hw - wall_t, height + wall_h, 0), Vector3(0, 0, -1))

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
	mi.material_override = pbr("concrete_floor_worn_001", 0.25)
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


## Oyun koridoru düz, çevresi tepelik arazi (yükseklik alanı + trimesh çarpışma).
static func build_terrain(parent: Node3D, size: float, res: int, corridor: Rect2, ramp: Dictionary = {}) -> void:
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.004
	noise.fractal_octaves = 5
	var detail := FastNoiseLite.new()
	detail.seed = 21
	detail.frequency = 0.03
	var half := size * 0.5
	var step := size / res
	var heights := PackedFloat32Array()
	heights.resize((res + 1) * (res + 1))
	for j in res + 1:
		for i in res + 1:
			var x := -half + i * step
			var z := -half + j * step + corridor.get_center().y
			# Koridora uzaklık -> tepe maskesi
			var dx := maxf(absf(x - corridor.get_center().x) - corridor.size.x * 0.5, 0.0)
			var dz := maxf(maxf(corridor.position.y - z, z - corridor.end.y), 0.0)
			var d := Vector2(dx, dz).length()
			var mask := smoothstep(0.0, 120.0, d)
			var h := (noise.get_noise_2d(x, z) * 0.5 + 0.55) * 90.0 * mask
			h += detail.get_noise_2d(x, z) * 0.6 * (0.3 + mask)
			if not ramp.is_empty():
				# Rampa bir dağ yamacına oyulmuş gibi: yanlarda rampa zeminine yakın yükselen arazi
				var rh: float = ramp["height"]
				var base := ramp_height(z, rh, ramp["flat"], ramp["slope"]) - 1.2
				if z < 0.0:
					base = rh + 2.4 - z * 0.5
				var side := 1.0 - smoothstep(ramp["width"] * 0.5 + 2.0, 110.0, absf(x))
				var hill := base * side + detail.get_noise_2d(x * 0.5, z * 0.5) * 3.0 * side
				h = maxf(h, hill)
			heights[j * (res + 1) + i] = h
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var idx := PackedInt32Array()
	for j in res + 1:
		for i in res + 1:
			var x := -half + i * step
			var z := -half + j * step + corridor.get_center().y
			verts.append(Vector3(x, heights[j * (res + 1) + i], z))
			var hl := heights[j * (res + 1) + maxi(i - 1, 0)]
			var hr := heights[j * (res + 1) + mini(i + 1, res)]
			var hd := heights[maxi(j - 1, 0) * (res + 1) + i]
			var hu := heights[mini(j + 1, res) * (res + 1) + i]
			norms.append(Vector3(hl - hr, 2.0 * step, hd - hu).normalized())
	for j in res:
		for i in res:
			var a := j * (res + 1) + i
			var b := a + 1
			var c := a + res + 1
			var d := c + 1
			# CW (yukarıdan bakınca) sıralama
			idx.append_array([a, b, c, b, d, c])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var body := StaticBody3D.new()
	body.name = "Terrain"
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	body.physics_material_override = pm
	parent.add_child(body)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = pbr("rocky_terrain_02", 0.12)
	body.add_child(mi)
	var shape := mesh.create_trimesh_shape()
	shape.backface_collision = true
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)


## Gürültüyle bozulmuş küre: doğal kaya görünümü (çarpışma yine küre).
static func rock_mesh(radius: float, seed_value: int) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 48
	sphere.rings = 24
	var arrays := sphere.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = 0.9 / radius
	noise.fractal_octaves = 4
	for i in verts.size():
		var p := verts[i]
		var dir := p.normalized()
		var k := 1.0 + noise.get_noise_3dv(dir * radius) * 0.16
		# Hafif yassılaştırma: tam küre gibi durmasın
		verts[i] = dir * radius * k * Vector3(1.0, 0.93, 1.0)
	# Dikiş yerlerinde de pürüzsüz normal için konuma göre biriktir
	var acc := {}
	for t in range(0, idx.size(), 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		var fn := (c - a).cross(b - a)
		for p in [a, b, c]:
			var key := Vector3i((p * 1000.0).round())
			acc[key] = acc.get(key, Vector3.ZERO) + fn
	var norms := PackedVector3Array()
	norms.resize(verts.size())
	for i in verts.size():
		var n: Vector3 = acc[Vector3i((verts[i] * 1000.0).round())]
		if n.dot(verts[i]) < 0.0:
			n = -n
		norms[i] = n.normalized()
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TANGENT] = null
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
