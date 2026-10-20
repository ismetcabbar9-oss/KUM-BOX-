extends SceneTree
## Taranmış kaya modellerinin açık tabanlarını kapatır, LOD üretir (çevrimdışı araç).
##
## Çalıştırma:  godot --headless --path . -s res://tools/prepare_rocks.gd
## Çıktı:       res://assets/rocks/<ad>.res  (ArrayMesh, malzemeli, orijin merkezli, en büyük boyut = 1)
##
## Fotogrametri taramalarında yere oturan yüz hiç taranmaz: mesh'te delik kalır ve kaya
## döndüğünde içi boş görünür. Burada sınır kenarları (tek üçgene ait kenarlar) zincirlenir
## ve her delik merkezden yelpaze üçgenlerle kapatılır.

const SOURCES := {
	"granite": ["rock_hero", -1],
	"basalt": ["rock_boulder2", -1],
	"mossy": ["rock_medium", -1],
	"sandstone": ["border_stone", -1],
	"river_0": ["smooth_rocks", 0],
	"river_1": ["smooth_rocks", 1],
	"river_2": ["smooth_rocks", 2],
	"pebble_0": ["rocks4", 0],
	"pebble_1": ["rocks4", 1],
	"pebble_2": ["rocks4", 2],
	"pebble_3": ["rocks4", 3],
}


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/rocks")
	for out_name in SOURCES:
		var src: Array = SOURCES[out_name]
		_prepare(out_name, src[0], src[1])
	quit()


func _prepare(out_name: String, model: String, index: int) -> void:
	var scene: Node3D = load("res://assets/models/%s/scene.gltf" % model).instantiate()
	root.add_child(scene)
	var mis := scene.find_children("*", "MeshInstance3D", true, false)
	if index >= 0:
		if index >= mis.size():
			scene.free()
			return
		mis = [mis[index]]
	# Tüm yüzeyleri tek listeye (dünya uzayında) topla
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var mat: Material = null
	for mi: MeshInstance3D in mis:
		var xf := mi.global_transform
		var nb := xf.basis.inverse().transposed()
		for s in mi.mesh.get_surface_count():
			var a := mi.mesh.surface_get_arrays(s)
			if mat == null:
				mat = mi.get_active_material(s)
			var base := verts.size()
			for i in (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size():
				verts.append(xf * a[Mesh.ARRAY_VERTEX][i])
				norms.append((nb * a[Mesh.ARRAY_NORMAL][i]).normalized())
				uvs.append(a[Mesh.ARRAY_TEX_UV][i] if a[Mesh.ARRAY_TEX_UV] != null else Vector2.ZERO)
			var ii = a[Mesh.ARRAY_INDEX]
			if ii == null:
				ii = range((a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
			for i in ii:
				idx.append(base + i)
	scene.free()

	# Orijin merkezli, en büyük boyut 1
	var aabb := AABB(verts[0], Vector3.ZERO)
	for v in verts:
		aabb = aabb.expand(v)
	var c := aabb.get_center()
	var k := 1.0 / maxf(aabb.size.x, maxf(aabb.size.y, aabb.size.z))
	for i in verts.size():
		verts[i] = (verts[i] - c) * k

	# Konuma göre kaynak (UV dikişlerindeki kopyalar aynı noktayı paylaşsın)
	var weld := {}
	var wid := PackedInt32Array()
	wid.resize(verts.size())
	for i in verts.size():
		var key := Vector3i((verts[i] * 100000.0).round())
		if not weld.has(key):
			weld[key] = i
		wid[i] = weld[key]
	# Yönlü kenar sayımı: tek kullanılan kenar = sınır
	var edge_count := {}
	for t in range(0, idx.size(), 3):
		for e in 3:
			var a := wid[idx[t + e]]
			var b := wid[idx[t + (e + 1) % 3]]
			var key := Vector2i(mini(a, b), maxi(a, b))
			edge_count[key] = edge_count.get(key, 0) + 1
	var next := {}  # sınır kenarı a -> b (üçgenin kendi yönünde)
	for t in range(0, idx.size(), 3):
		for e in 3:
			var a := wid[idx[t + e]]
			var b := wid[idx[t + (e + 1) % 3]]
			if edge_count[Vector2i(mini(a, b), maxi(a, b))] == 1:
				next[a] = b
	# Döngüleri zincirle
	var loops := []
	var used := {}
	for start in next:
		if used.has(start):
			continue
		var loop := PackedInt32Array()
		var cur: int = start
		while not used.has(cur) and next.has(cur):
			used[cur] = true
			loop.append(cur)
			cur = next[cur]
		if loop.size() >= 3:
			loops.append(loop)

	# Delikleri yelpazeyle kapat: yeni üçgenler mevcut kenarın ters yönünde -> tutarlı sarım
	var filled := 0
	for loop: PackedInt32Array in loops:
		var center := Vector3.ZERO
		var cuv := Vector2.ZERO
		for i in loop:
			center += verts[i]
			cuv += uvs[i]
		center /= loop.size()
		cuv /= loop.size()
		# Newell normali
		var n := Vector3.ZERO
		for j in loop.size():
			var p := verts[loop[j]]
			var q := verts[loop[(j + 1) % loop.size()]]
			n += Vector3((p.y - q.y) * (p.z + q.z), (p.z - q.z) * (p.x + q.x), (p.x - q.x) * (p.y + q.y))
		n = n.normalized()
		if n.dot(center) < 0.0:
			n = -n  # dışa baksın (merkez orijinde)
		var ci := verts.size()
		verts.append(center)
		norms.append(n)
		uvs.append(cuv)
		var dup := {}
		for i in loop:
			dup[i] = verts.size()
			verts.append(verts[i])
			norms.append(n)
			uvs.append(uvs[i])
		for j in loop.size():
			var a: int = dup[loop[j]]
			var b: int = dup[loop[(j + 1) % loop.size()]]
			idx.append_array([ci, b, a])
		filled += 1

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var st := SurfaceTool.new()
	st.create_from_arrays(arrays)
	st.generate_tangents()
	# Bazı taramaların malzemesi alfa saydamlığıyla gelir: kaya opak olmalı
	if mat is BaseMaterial3D:
		mat = mat.duplicate()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
		mat.cull_mode = BaseMaterial3D.CULL_BACK
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, mat)
	im.generate_lods(25.0, 60.0, [])
	var mesh := im.get_mesh()
	ResourceSaver.save(mesh, "res://assets/rocks/%s.res" % out_name, ResourceSaver.FLAG_COMPRESS)
	print("%-10s üçgen=%6d  kapatılan delik=%d" % [out_name, idx.size() / 3, filled])
