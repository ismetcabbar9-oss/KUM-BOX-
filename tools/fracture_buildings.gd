extends SceneTree
## Bina modellerini önceden yıkılabilir parçalara böler (çevrimdışı araç).
##
## Çalıştırma:  godot --headless --path . -s res://tools/fracture_buildings.gd
## Çıktı:       res://assets/buildings/<ad>.scn
##   Intact  : modelin tek parça hâli (az draw call; bina sağlamken bu çizilir)
##   Chunks  : ızgara hücrelerine kırpılmış parça mesh'leri; her birinde "box" metası
##             (yerel çarpışma kutusu, hücre içinde kalır -> kutular hiç kesişmez).

const BUILDINGS := {
	"soviet": {"height": 17.0, "cell": 4.4},
	"tower": {"height": 26.0, "cell": 4.4},
	"oldbuilding": {"height": 8.0, "cell": 2.8},
	"factory": {"height": 20.0, "cell": 4.2},
	"booth": {"height": 3.4, "cell": 2.6},
}
const MIN_THICK := 0.35

var _mat_cache := {}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/buildings")
	for name in BUILDINGS:
		_fracture(name, BUILDINGS[name])
	quit()


# Tek tepe: konum, normal, uv
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


## Sutherland–Hodgman: çokgeni "axis koordinatı (sign) * (p - value) <= 0" yarı uzayına kırp.
func _clip(poly: Array, axis: int, value: float, keep_below: bool) -> Array:
	if poly.is_empty():
		return poly
	var out := []
	var prev: V = poly[-1]
	var prev_in := (prev.p[axis] <= value) if keep_below else (prev.p[axis] >= value)
	for cur: V in poly:
		var cur_in := (cur.p[axis] <= value) if keep_below else (cur.p[axis] >= value)
		if cur_in != prev_in:
			var t := (value - prev.p[axis]) / (cur.p[axis] - prev.p[axis])
			out.append(prev.lerp_to(cur, t))
		if cur_in:
			out.append(cur)
		prev = cur
		prev_in = cur_in
	return out


func _fracture(name: String, cfg: Dictionary) -> void:
	var src: Node3D = load("res://assets/models/%s/scene.gltf" % name).instantiate()
	root.add_child(src)
	# Tüm mesh'leri dünya uzayına topla
	var tris := []  # [V, V, V, material]
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
					var uv: Vector2 = uvv[i] if uvv != null else Vector2.ZERO
					tri.append(V.new(p, (nb * nv[i]).normalized(), uv))
					aabb = AABB(p, Vector3.ZERO) if first else aabb.expand(p)
					first = false
				tri.append(mat)
				tris.append(tri)
	src.queue_free()

	# Ölçekle: hedef yükseklik, taban merkezi orijinde
	var scale: float = cfg["height"] / aabb.size.y
	var offset := Vector3(aabb.get_center().x, aabb.position.y, aabb.get_center().z)
	for tri in tris:
		for k in 3:
			tri[k].p = (tri[k].p - offset) * scale
	var size := aabb.size * scale
	var lo := Vector3(-size.x * 0.5, 0.0, -size.z * 0.5)
	var cell: float = cfg["cell"]
	var dims := Vector3i(maxi(1, ceili(size.x / cell)), maxi(1, ceili(size.y / cell)), maxi(1, ceili(size.z / cell)))
	var cs := Vector3(size.x / dims.x, size.y / dims.y, size.z / dims.z)

	var groups := {}  # anahtar -> {mat -> [V...]}
	var cells := {}  # anahtar -> hücre sınırı
	var intact := {}  # mat -> [V...]
	for tri in tris:
		var a: V = tri[0]
		var b: V = tri[1]
		var c: V = tri[2]
		var mat: Material = tri[3]
		intact.get_or_add(mat, []).append_array([a, b, c])
		var centroid := (a.p + b.p + c.p) / 3.0
		var fn := (c.p - a.p).cross(b.p - a.p).normalized()
		if fn.dot(a.n + b.n + c.n) < 0.0:
			fn = -fn
		if centroid.y < 0.05 * size.y and fn.y > 0.5:
			continue  # zemin döşemesi: gerekmez
		var poly := [a, b, c]
		var tmin := a.p.min(b.p).min(c.p)
		var tmax := a.p.max(b.p).max(c.p)
		var i0 := ((tmin - lo) / cs).floor()
		var i1 := ((tmax - lo) / cs).floor()
		for ix in range(clampi(int(i0.x), 0, dims.x - 1), clampi(int(i1.x), 0, dims.x - 1) + 1):
			for iy in range(clampi(int(i0.y), 0, dims.y - 1), clampi(int(i1.y), 0, dims.y - 1) + 1):
				for iz in range(clampi(int(i0.z), 0, dims.z - 1), clampi(int(i1.z), 0, dims.z - 1) + 1):
					var cmin := lo + Vector3(ix, iy, iz) * cs
					var cmax := cmin + cs
					var part := poly
					for ax in 3:
						var lo_v: float = -INF if (ax == 0 and ix == 0) or (ax == 1 and iy == 0) or (ax == 2 and iz == 0) else cmin[ax]
						var hi_v: float = INF if (ax == 0 and ix == dims.x - 1) or (ax == 1 and iy == dims.y - 1) or (ax == 2 and iz == dims.z - 1) else cmax[ax]
						if lo_v > -INF:
							part = _clip(part, ax, lo_v, false)
						if hi_v < INF:
							part = _clip(part, ax, hi_v, true)
					if part.size() >= 3:
						var key := "c_%d_%d_%d" % [ix, iy, iz]
						_add_poly(groups, key, mat, part)
						cells[key] = AABB(cmin, cs)

	# Sahneyi kur
	var out := Node3D.new()
	out.name = name
	var intact_mi := MeshInstance3D.new()
	intact_mi.name = "Intact"
	intact_mi.mesh = _build_mesh(intact, Vector3.ZERO)
	out.add_child(intact_mi)
	intact_mi.owner = out
	var chunks := Node3D.new()
	chunks.name = "Chunks"
	out.add_child(chunks)
	chunks.owner = out
	var count := 0
	for key in groups:
		var g: Dictionary = groups[key]
		var bb := AABB()
		var f := true
		for mat in g:
			for v: V in g[mat]:
				bb = AABB(v.p, Vector3.ZERO) if f else bb.expand(v.p)
				f = false
		# İnce yüzeyler (tek düzlem duvar) için asgari kalınlık; kutu hücre dışına taşmaz,
		# böylece komşu parçaların kutuları asla iç içe geçmez (başlangıçta patlama olmaz).
		var cell_bb: AABB = cells[key]
		for ax in 3:
			if bb.size[ax] < MIN_THICK:
				var p := bb.position
				var s := bb.size
				p[ax] = clampf(p[ax] - (MIN_THICK - s[ax]) * 0.5, cell_bb.position[ax], cell_bb.end[ax] - MIN_THICK)
				s[ax] = MIN_THICK
				bb = AABB(p, s)
		bb = bb.intersection(cell_bb)
		var center := bb.get_center()
		var mi := MeshInstance3D.new()
		mi.name = key
		mi.mesh = _build_mesh(g, center)
		mi.position = center
		mi.set_meta("box", bb.size - Vector3.ONE * 0.012)
		chunks.add_child(mi)
		mi.owner = out
		count += 1
	var ps := PackedScene.new()
	ps.pack(out)
	ResourceSaver.save(ps, "res://assets/buildings/%s.scn" % name, ResourceSaver.FLAG_COMPRESS)
	print("%-12s boyut=%s ızgara=%s parça=%d üçgen=%d" % [name, size.snapped(Vector3.ONE * 0.1), dims, count, tris.size()])
	out.free()


func _add_poly(groups: Dictionary, key: String, mat: Material, poly: Array) -> void:
	var g: Dictionary = groups.get_or_add(key, {})
	var list: Array = g.get_or_add(mat, [])
	for i in range(1, poly.size() - 1):
		list.append_array([poly[0], poly[i], poly[i + 1]])


func _build_mesh(by_mat: Dictionary, origin: Vector3) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for mat in by_mat:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v: V in by_mat[mat]:
			st.set_normal(v.n)
			st.set_uv(v.uv)
			st.add_vertex(v.p - origin)
		st.index()
		st.generate_tangents()
		var m: Material = mat
		if m is BaseMaterial3D:
			# Parçalar dönünce iç yüzler görünsün (malzeme başına tek kopya: batching bozulmasın)
			if not _mat_cache.has(mat):
				var d: BaseMaterial3D = m.duplicate()
				d.cull_mode = BaseMaterial3D.CULL_DISABLED
				_mat_cache[mat] = d
			m = _mat_cache[mat]
		st.set_material(m)
		st.commit(mesh)
	return mesh
