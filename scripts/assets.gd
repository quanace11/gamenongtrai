# Loads the CC0 assets in res://assets (Poly Haven textures, HDRI skies
# and glTF models, see assets/CREDITS.md) and caches the materials built
# from them.
extends RefCounted

static var _mats := {}
static var _parts := {}


# PBR material from a texture set: albedo, OpenGL normal map and ARM
# (ambient occlusion, roughness, metallic) packed the way ORMMaterial3D
# expects. `tile` is the size in metres of one repeat when `world` is on
# (world-space triplanar mapping), otherwise the UV repeat count.
static func pbr(id: String, tile := 2.0, world := true, tint := Color.WHITE, double_sided := false) -> ORMMaterial3D:
	var key := "%s|%s|%s|%s|%s" % [id, tile, world, tint.to_html(), double_sided]
	if _mats.has(key):
		return _mats[key]
	var base := "res://assets/textures/%s/%s_" % [id, id]
	var m := ORMMaterial3D.new()
	m.albedo_texture = load(base + "diff_1k.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(base + "nor_1k.jpg")
	m.orm_texture = load(base + "arm_1k.jpg")
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if world:
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / tile
		m.uv1_triplanar_sharpness = 4.0
	else:
		m.uv1_scale = Vector3(tile, tile, 1)
	if double_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


static func tex(id: String, kind: String) -> Texture2D:
	return load("res://assets/textures/%s/%s_%s_1k.jpg" % [id, id, kind])


# A glTF model as a fresh node tree, real-world scale (metres).
static func model(id: String) -> Node3D:
	var scene: PackedScene = load("res://assets/models/%s/%s_1k.gltf" % [id, id])
	var n := scene.instantiate() as Node3D
	_shadows(n)
	return n


static func _shadows(n: Node) -> void:
	if n is GeometryInstance3D:
		(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	for c in n.get_children():
		_shadows(c)


# Some Poly Haven plant files hold several variants side by side. This
# returns each mesh on its own, re-centred on its base, so they can be
# scattered with a MultiMesh: [{mesh, height}].
static func parts(id: String) -> Array:
	if _parts.has(id):
		return _parts[id]
	var out := []
	var root := model(id)
	_collect(root, Transform3D(), out)
	root.free()
	_parts[id] = out
	return out


static func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var t := xf
	if n is Node3D:
		t = xf * (n as Node3D).transform
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var src: Mesh = mi.mesh
		var a: AABB = t * src.get_aabb()
		var shift := Vector3(-(a.position.x + a.size.x / 2.0), -a.position.y, -(a.position.z + a.size.z / 2.0))
		var mesh := ArrayMesh.new()
		for s in src.get_surface_count():
			var arrays := src.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in verts.size():
				verts[i] = t * verts[i] + shift
			arrays[Mesh.ARRAY_VERTEX] = verts
			if arrays[Mesh.ARRAY_NORMAL] != null:
				var nr: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				for i in nr.size():
					nr[i] = (t.basis * nr[i]).normalized()
				arrays[Mesh.ARRAY_NORMAL] = nr
			if arrays[Mesh.ARRAY_TANGENT] != null:
				var tg: PackedFloat32Array = arrays[Mesh.ARRAY_TANGENT]
				for i in tg.size() / 4:
					var v := (t.basis * Vector3(tg[i * 4], tg[i * 4 + 1], tg[i * 4 + 2])).normalized()
					tg[i * 4] = v.x
					tg[i * 4 + 1] = v.y
					tg[i * 4 + 2] = v.z
				arrays[Mesh.ARRAY_TANGENT] = tg
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var m: Material = mi.get_active_material(s)
			mesh.surface_set_material(s, m)
		out.append({"mesh": mesh, "height": a.size.y})
	for c in n.get_children():
		_collect(c, t, out)


# Scatter copies of the given parts over `points` ([Vector3 pos, yaw, scale]).
static func scatter(parent: Node3D, id: String, points: Array, shadows := true) -> void:
	var ps := parts(id)
	var buckets := []
	for p in ps:
		buckets.append([])
	for i in points.size():
		buckets[i % ps.size()].append(points[i])
	for k in ps.size():
		if buckets[k].is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = ps[k].mesh
		mm.instance_count = buckets[k].size()
		for i in buckets[k].size():
			var p: Array = buckets[k][i]
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, p[1]).scaled(Vector3.ONE * p[2]), p[0]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mmi)
