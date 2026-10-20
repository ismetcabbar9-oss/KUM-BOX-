extends SceneTree
## Bina modellerini önceden DOLU ve düzensiz parçalara böler (çevrimdışı araç, v2).
##
## Çalıştırma:  godot --headless --path . -s res://tools/fracture_buildings.gd
## Çıktı:       res://assets/buildings/<ad>.scn
##   Intact : modelin tek parça hâli (bina sağlamken yalnız bu çizilir: 1 draw call)
##   Chunks : parça mesh'leri. Her birinde:
##            hull      -> dışbükey çarpışma noktaları (yerel)
##            volume    -> katı hacim (m³), kütle ve dayanım için
##            layer     -> kat indeksi (0 = zemine oturan)
##            neighbors -> komşu parça adları (yapısal destek grafiği)
##
## Modeller tek yüzeyli kabuktur; kırılınca kâğıt gibi görünmemesi için her cephe parçası
## içe doğru "thickness" kadar kalınlaştırılır: iç yüz ve kesim kenarları kırık beton/tuğla
## malzemesiyle kaplanır. Kesim düzlemleri her katta kaydırılmış ve hafif eğik: parçalar
## ızgara gibi değil, kırılmış gibi durur.

const BUILDINGS := {
	"soviet": {"height": 17.0, "cell": 4.2, "inner": "concrete", "thickness": 0.4},
	"tower": {"height": 26.0, "cell": 4.3, "inner": "concrete", "thickness": 0.4},
	"oldbuilding": {"height": 8.0, "cell": 2.9, "inner": "brick", "thickness": 0.45},
	"factory": {"height": 20.0, "cell": 4.0, "inner": "brick", "thickness": 0.5},
	"booth": {"height": 3.4, "cell": 2.6, "inner": "brick", "thickness": 0.35},
}
const JITTER := 0.28  # hücre sınırı kaydırma (hücre boyutunun oranı)
const TILT := 0.22  # kesim düzlemi eğimi (radyan, ~12°)
const EPS := 0.002

var _mat_cache := {}
var _inner_mats := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/buildings")
	for name in BUILDINGS:
		_fracture(name, BUILDINGS[name])
	quit()


class V:
	var p: Vector3
	var n: Vector3
	var uv: Vector2

	func _init(p_: Vector3, n_: Vector3, uv_: Vector2) -> void:
		p = p_
		n = n_
		uv = uv_

	func lerp_to(o: V, t: float) -> V:
		return V.new(p.lerp(o.p, t), n.lerp(o.n, t).normalized(), uv.lerp(o.uv, t))


## Düzlem: Plane(normal, d). Tutulan taraf: normal·p <= d.
func _clip(poly: Array, pl: Plane) -> Array:
	if poly.is_empty():
		return poly
	var out := []
	var prev: V = poly[-1]
	var pd := pl.normal.dot(prev.p) - pl.d
	for cur: V in poly:
		var cd := pl.normal.dot(cur.p) - pl.d
		if (cd <= 0.0) != (pd <= 0.0):
			out.append(prev.lerp_to(cur, pd / (pd - cd)))
		if cd <= 0.0:
			out.append(cur)
		prev = cur
		pd = cd
	return out


func _inner_material(kind: String) -> Material:
	if _inner_mats.has(kind):
		return _inner_mats[kind]
	var tex := "rough_concrete" if kind == "concrete" else "red_brick_03"
	var m := StandardMaterial3D.new()
	m.albedo_texture = load("res://assets/textures/%s_diff_1k.jpg" % tex)
	m.albedo_color = Color(0.78, 0.76, 0.72) if kind == "concrete" else Color(0.85, 0.8, 0.78)
	m.normal_enabled = true
	m.normal_texture = load("res://assets/textures/%s_nor_gl_1k.jpg" % tex)
	m.roughness_texture = load("res://assets/textures/%s_arm_1k.jpg" % tex)
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false  # parça dönerken doku yüzeye yapışık kalsın
	m.uv1_scale = Vector3.ONE * (0.5 if kind == "concrete" else 0.9)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_inner_mats[kind] = m
	return m


func _fracture(name: String, cfg: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(name)
	var src: Node3D = load("res://assets/models/%s/scene.gltf" % name).instantiate()
	root.add_child(src)
	var tris := []
	var aabb := AABB()
	var first := true
	for mi: MeshInstance3D in src.find_children("*", "MeshInstance3D", true, false):
		var xf := mi.global_transform
		var nb := xf.basis.inverse().transposed()
		for s in mi.mesh.get_surface_count():
			var arr := mi.mesh.surface_get_arrays(s)
			var mat: Material = mi.get_active_material(s)
			var pv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var nv: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var uvv = arr[Mesh.ARRAY_TEX_UV]
			var idx = arr[Mesh.ARRAY_INDEX]
			if idx == null:
				idx = range(pv.size())
			for t in range(0, idx.size(), 3):
				var tri := []
				for k in 3:
					var i: int = idx[t + k]
					var p := xf * pv[i]
					tri.append(V.new(p, (nb * nv[i]).normalized(), uvv[i] if uvv != null else Vector2.ZERO))
					aabb = AABB(p, Vector3.ZERO) if first else aabb.expand(p)
					first = false
				tri.append(mat)
				tris.append(tri)
	src.queue_free()

	var scale: float = cfg["height"] / aabb.size.y
	var offset := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
	for tri in tris:
		for k in 3:
			tri[k].p = (tri[k].p - offset) * scale
	var size := aabb.size * scale
	var lo := Vector3(-size.x * 0.5, 0.0, -size.z * 0.5)
	var cell: float = cfg["cell"]
	var dims := Vector3i(maxi(1, roundi(size.x / cell)), maxi(1, roundi(size.y / (cell * 0.85))), maxi(1, roundi(size.z / cell)))
	var cs := Vector3(size.x / dims.x, size.y / dims.y, size.z / dims.z)

	# Her kat için kaydırılmış/eğik dikey kesim düzlemleri
	var xplanes := []  # [kat][k] -> Plane (normal·p <= d tarafı = soldaki hücre)
	var zplanes := []
	for ly in dims.y:
		var ymid := lo.y + (ly + 0.5) * cs.y
		var xp := []
		for k in range(1, dims.x):
			var bx := lo.x + k * cs.x + rng.randf_range(-JITTER, JITTER) * cs.x
			var a := rng.randf_range(-TILT, TILT)
			var n := Vector3(cos(a), sin(a), 0.0)
			xp.append(Plane(n, n.dot(Vector3(bx, ymid, 0))))
		xplanes.append(xp)
		var zp := []
		for k in range(1, dims.z):
			var bz := lo.z + k * cs.z + rng.randf_range(-JITTER, JITTER) * cs.z
			var a := rng.randf_range(-TILT, TILT)
			var n := Vector3(0.0, sin(a), cos(a))
			zp.append(Plane(n, n.dot(Vector3(0, ymid, bz))))
		zplanes.append(zp)

	var yplanes := []
	for k in range(1, dims.y):
		yplanes.append(Plane(Vector3.UP, lo.y + k * cs.y))
	var groups := {}  # anahtar -> {mat -> [poligon...]}
	var intact := {}
	var layer_of := {}
	for tri in tris:
		var a: V = tri[0]
		var b: V = tri[1]
		var c: V = tri[2]
		var mat: Material = tri[3]
		intact.get_or_add(mat, []).append([a, b, c])
		var centroid := (a.p + b.p + c.p) / 3.0
		var fn := (c.p - a.p).cross(b.p - a.p)
		if fn.length_squared() < 1e-12:
			continue
		fn = fn.normalized()
		if centroid.y < 0.05 * size.y and absf(fn.y) > 0.5:
			continue  # zemin döşemesi
		var ymin := minf(a.p.y, minf(b.p.y, c.p.y))
		var ymax := maxf(a.p.y, maxf(b.p.y, c.p.y))
		var l0 := clampi(int((ymin - lo.y) / cs.y), 0, dims.y - 1)
		var l1 := clampi(int((ymax - lo.y) / cs.y), 0, dims.y - 1)
		for ly in range(l0, l1 + 1):
			var poly := [a, b, c]
			if ly > 0:
				poly = _clip(poly, Plane(Vector3.DOWN, -(lo.y + ly * cs.y)))
			if ly < dims.y - 1:
				poly = _clip(poly, Plane(Vector3.UP, lo.y + (ly + 1) * cs.y))
			if poly.size() < 3:
				continue
			for ix in dims.x:
				var px := poly
				if ix > 0:
					var pl: Plane = xplanes[ly][ix - 1]
					px = _clip(px, Plane(-pl.normal, -pl.d))
				if ix < dims.x - 1:
					px = _clip(px, xplanes[ly][ix])
				if px.size() < 3:
					continue
				for iz in dims.z:
					var pz := px
					if iz > 0:
						var pl: Plane = zplanes[ly][iz - 1]
						pz = _clip(pz, Plane(-pl.normal, -pl.d))
					if iz < dims.z - 1:
						pz = _clip(pz, zplanes[ly][iz])
					if pz.size() < 3:
						continue
					var key := "c_%d_%d_%d" % [ix, ly, iz]
					groups.get_or_add(key, {}).get_or_add(mat, []).append(pz)
					layer_of[key] = ly

	var inner := _inner_material(cfg["inner"])
	var thick: float = cfg["thickness"]
	var out := Node3D.new()
	out.name = name
	var intact_mi := MeshInstance3D.new()
	intact_mi.name = "Intact"
	intact_mi.mesh = _intact_mesh(intact)
	out.add_child(intact_mi)
	intact_mi.owner = out
	var chunks := Node3D.new()
	chunks.name = "Chunks"
	out.add_child(chunks)
	chunks.owner = out

	var boxes := {}
	var total_tris := 0
	for key in groups:
		var g: Dictionary = groups[key]
		var res := _solid_mesh(g, inner, thick, xplanes[layer_of[key]] + zplanes[layer_of[key]] + yplanes)
		var mesh: ArrayMesh = res[0]
		var volume: float = res[1]
		if volume < 0.05:
			continue
		var bb: AABB = res[2]
		var center := bb.get_center()
		var mi := MeshInstance3D.new()
		mi.name = key
		mi.mesh = _recenter(mesh, center)
		mi.position = center
		var hull := mi.mesh.create_convex_shape(true, true) as ConvexPolygonShape3D
		mi.set_meta("hull", hull.points)
		mi.set_meta("volume", volume)
		mi.set_meta("layer", layer_of[key])
		chunks.add_child(mi)
		mi.owner = out
		boxes[key] = bb
		for s in mi.mesh.get_surface_count():
			total_tris += mi.mesh.surface_get_array_index_len(s) / 3
		_add_halves(mi, g, inner, thick, xplanes[layer_of[key]] + zplanes[layer_of[key]] + yplanes, bb, rng, out)

	# Kat döşemeleri: her kat sınırında, cephe kalınlığı kadar içeriden, çatı altında kalan
	# hücrelere beton döşeme. Duvarlar yıkılınca döşemeler düşer ve alt katları ezer.
	var roof2d := []
	for tri in tris:
		var a: V = tri[0]
		var b: V = tri[1]
		var c: V = tri[2]
		var fn := (c.p - a.p).cross(b.p - a.p)
		if fn.length_squared() > 1e-12 and absf(fn.normalized().y) > 0.3:
			roof2d.append([Vector2(a.p.x, a.p.z), Vector2(b.p.x, b.p.z), Vector2(c.p.x, c.p.z), maxf(a.p.y, maxf(b.p.y, c.p.y))])
	var inset := thick + 0.08
	var slab_count := 0
	for ly in range(1 if cs.y >= 2.5 else dims.y, dims.y):
		var y := lo.y + ly * cs.y
		for ix in dims.x:
			for iz in dims.z:
				var x0 := maxf(lo.x + ix * cs.x, lo.x + inset) + 0.02
				var x1 := minf(lo.x + (ix + 1) * cs.x, lo.x + size.x - inset) - 0.02
				var z0 := maxf(lo.z + iz * cs.z, lo.z + inset) + 0.02
				var z1 := minf(lo.z + (iz + 1) * cs.z, lo.z + size.z - inset) - 0.02
				if x1 - x0 < 1.0 or z1 - z0 < 1.0:
					continue
				var c2 := Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)
				var covered := false
				for r in roof2d:
					if r[3] > y + 1.0 and Geometry2D.point_is_inside_triangle(c2, r[0], r[1], r[2]):
						covered = true
						break
				if not covered:
					continue
				var ssize := Vector3(x1 - x0, 0.3, z1 - z0)
				var center := Vector3(c2.x, y - 0.155, c2.y)
				var key := "s_%d_%d_%d" % [ix, ly, iz]
				var bm := BoxMesh.new()
				bm.size = ssize
				bm.material = inner
				var mi := MeshInstance3D.new()
				mi.name = key
				mi.mesh = bm
				mi.position = center
				var hs := ssize * 0.5
				var pts := PackedVector3Array()
				for sx in [-1.0, 1.0]:
					for sy in [-1.0, 1.0]:
						for sz in [-1.0, 1.0]:
							pts.append(Vector3(sx * hs.x, sy * hs.y, sz * hs.z))
				mi.set_meta("hull", pts)
				mi.set_meta("volume", ssize.x * ssize.y * ssize.z)
				mi.set_meta("layer", ly)
				mi.set_meta("box", ssize)
				chunks.add_child(mi)
				mi.owner = out
				boxes[key] = AABB(center - hs, ssize)
				slab_count += 1

	# Komşuluk: sınır kutuları (tolerans ile) kesişen parçalar
	var keys := boxes.keys()
	for i in keys.size():
		var nbs := PackedStringArray()
		var bi: AABB = (boxes[keys[i]] as AABB).grow(0.25)
		for j in keys.size():
			if i != j and bi.intersects(boxes[keys[j]]):
				nbs.append(keys[j])
		chunks.get_node(NodePath(keys[i])).set_meta("neighbors", nbs)

	var ps := PackedScene.new()
	ps.pack(out)
	ResourceSaver.save(ps, "res://assets/buildings/%s.scn" % name, ResourceSaver.FLAG_COMPRESS)
	print("%-12s boyut=%s ızgara=%s parça=%d (döşeme %d) parça-üçgen=%d" % [name, size.snapped(Vector3.ONE * 0.1), dims, keys.size(), slab_count, total_tris])
	out.free()


## İkinci kademe kırılma için parçanın önceden hesaplanmış iki yarısı (çocuk "half0/1").
## Kesim düzlemi parçanın en uzun ekseninde, hafif eğik.
func _add_halves(mi: MeshInstance3D, g: Dictionary, inner: Material, thick: float, cuts: Array, bb: AABB, rng: RandomNumberGenerator, owner_node: Node) -> void:
	var axis := 0
	for a in 3:
		if bb.size[a] > bb.size[axis]:
			axis = a
	if bb.size[axis] < 1.6:
		return
	var n := Vector3.ZERO
	n[axis] = 1.0
	n = (n + Vector3(rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25), rng.randf_range(-0.25, 0.25)) * (Vector3.ONE - n.abs())).normalized()
	var c := bb.get_center() + n * rng.randf_range(-0.15, 0.15) * bb.size[axis]
	var pl := Plane(n, n.dot(c))
	var parts := []
	for side in 2:
		var cut := pl if side == 0 else Plane(-n, -pl.d)
		var gh := {}
		for mat in g:
			for poly in g[mat]:
				var q := _clip(poly, cut)
				if q.size() >= 3:
					gh.get_or_add(mat, []).append(q)
		if gh.is_empty():
			return
		var res := _solid_mesh(gh, inner, thick, cuts + [pl])
		if res[1] < 0.03:
			return
		parts.append(res)
	for side in 2:
		var res: Array = parts[side]
		var hc: Vector3 = (res[2] as AABB).get_center()
		var h := MeshInstance3D.new()
		h.name = "half%d" % side
		h.mesh = _recenter(res[0], hc)
		h.position = hc - mi.position
		h.visible = false
		h.set_meta("hull", (h.mesh.create_convex_shape(true, true) as ConvexPolygonShape3D).points)
		h.set_meta("volume", res[1])
		mi.add_child(h)
		h.owner = owner_node


func _facade_material(mat: Material) -> Material:
	if not _mat_cache.has(mat):
		var d: Material = mat
		if mat is BaseMaterial3D:
			d = mat.duplicate()
			d.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mat_cache[mat] = d
	return _mat_cache[mat]


func _intact_mesh(by_mat: Dictionary) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for mat in by_mat:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for tri in by_mat[mat]:
			for v: V in tri:
				st.set_normal(v.n)
				st.set_uv(v.uv)
				st.add_vertex(v.p)
		st.index()
		st.generate_tangents()
		st.set_material(_facade_material(mat))
		st.commit(mesh)
	return mesh


## Cephe poligonlarını katı parçaya çevirir: dış yüz (orijinal doku) + iç yüz + kesim kenarları.
## Döner: [mesh, hacim, sınır kutusu]
func _solid_mesh(by_mat: Dictionary, inner_mat: Material, thick: float, cut_planes: Array) -> Array:
	var mesh := ArrayMesh.new()
	var inner := SurfaceTool.new()
	inner.begin(Mesh.PRIMITIVE_TRIANGLES)
	var volume := 0.0
	var bb := AABB()
	var first := true
	for mat in by_mat:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for poly: Array in by_mat[mat]:
			var a: V = poly[0]
			var fn := Vector3.ZERO
			for i in range(1, poly.size() - 1):
				fn += (poly[i + 1].p - a.p).cross(poly[i].p - a.p)
			var area := fn.length() * 0.5
			if area < 1e-6:
				continue
			fn = fn.normalized()
			# Vertex normali ile yön uyumu (dışa bakan)
			if fn.dot(a.n) < 0.0:
				fn = -fn
			volume += area * thick
			var off := -fn * thick
			for i in range(1, poly.size() - 1):
				for v: V in [poly[0], poly[i], poly[i + 1]]:
					st.set_normal(v.n)
					st.set_uv(v.uv)
					st.add_vertex(v.p)
				# İç yüz (ters sarım)
				for v: V in [poly[0], poly[i + 1], poly[i]]:
					inner.set_normal(-fn)
					inner.add_vertex(v.p + off)
			for v: V in poly:
				bb = AABB(v.p, Vector3.ZERO) if first else bb.expand(v.p)
				first = false
				bb = bb.expand(v.p + off)
			# Kesim kenarları: kenarın iki ucu da aynı kesim düzlemindeyse yan yüz ekle
			for i in poly.size():
				var p0: V = poly[i]
				var p1: V = poly[(i + 1) % poly.size()]
				if not _on_cut(p0.p, p1.p, cut_planes):
					continue
				var en := (p1.p - p0.p).cross(fn).normalized()
				for v in [p0.p, p1.p, p1.p + off, p0.p, p1.p + off, p0.p + off]:
					inner.set_normal(en)
					inner.add_vertex(v)
		st.index()
		st.generate_tangents()
		st.set_material(_facade_material(mat))
		st.commit(mesh)
	inner.index()
	inner.set_material(inner_mat)
	inner.commit(mesh)
	return [mesh, volume, bb]


func _on_cut(a: Vector3, b: Vector3, planes: Array) -> bool:
	for pl: Plane in planes:
		if absf(pl.distance_to(a)) < EPS and absf(pl.distance_to(b)) < EPS:
			return true
	return false


func _recenter(mesh: ArrayMesh, c: Vector3) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		for i in v.size():
			v[i] -= c
		arr[Mesh.ARRAY_VERTEX] = v
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		out.surface_set_material(s, mesh.surface_get_material(s))
	return out
