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
# returns each mesh on its own with the transform that stands it on its
# base at the origin: [{mesh, xf, height}]. The imported mesh is used as
# is, so the LODs and shadow mesh the importer generated keep working
# (rebuilding the surfaces would throw them away).
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
		var a: AABB = t * mi.mesh.get_aabb()
		var shift := Vector3(-(a.position.x + a.size.x / 2.0), -a.position.y, -(a.position.z + a.size.z / 2.0))
		for s in mi.mesh.get_surface_count():
			_leaf_edges(mi.get_active_material(s))
		out.append({"mesh": mi.mesh, "xf": Transform3D(t.basis, t.origin + shift), "height": a.size.y})
	for c in n.get_children():
		_collect(c, t, out)


# Cut-out leaf cards (glTF alphaMode MASK): soft, stable edges with
# alpha to coverage (MSAA) and a little light through the leaves.
static func _leaf_edges(m: Material) -> void:
	var bm := m as BaseMaterial3D
	if bm == null or bm.transparency != BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR:
		return
	bm.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_ALPHA_TO_COVERAGE
	bm.alpha_antialiasing_edge = 0.3
	bm.backlight_enabled = true
	bm.backlight = Color(0.22, 0.26, 0.1)


# Scatter copies of the given parts over `points` ([Vector3 pos, yaw, scale]).
# Copies are grouped into `cell`-metre chunks so each chunk picks its own
# LOD and stops drawing beyond `view` metres. `sink` buries each copy by
# that fraction of its height; `mat` replaces the model's own material.
static func scatter(parent: Node3D, id: String, points: Array, shadows := true, view := 45.0, sink := 0.0, mat: Material = null, cell := 16.0) -> void:
	var ps := parts(id)
	var groups := {}
	for i in points.size():
		var pos: Vector3 = points[i][0]
		var key := Vector3i(i % ps.size(), floori(pos.x / cell), floori(pos.z / cell))
		if not groups.has(key):
			groups[key] = []
		groups[key].append(points[i])
	for key: Vector3i in groups:
		var part: Dictionary = ps[key.x]
		var list: Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = part.mesh
		mm.instance_count = list.size()
		for i in list.size():
			var p: Array = list[i]
			var s: float = p[2]
			var origin: Vector3 = p[0] + Vector3.DOWN * sink * part.height * s
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, p[1]).scaled(Vector3.ONE * s), origin) * part.xf)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		if mat != null:
			mmi.material_override = mat
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = view
		mmi.visibility_range_end_margin = view * 0.15
		mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
		parent.add_child(mmi)


# The model's material with its colour texture desaturated and tinted, e.g.
# to turn the warm sandstone of the Poly Haven rocks into grey river stone.
static func recolor(id: String, saturation: float, tint: Color, brightness := 1.0) -> Material:
	var key := "recolor|%s|%s|%s|%s" % [id, saturation, tint.to_html(), brightness]
	if _mats.has(key):
		return _mats[key]
	var src: BaseMaterial3D = (parts(id)[0].mesh as Mesh).surface_get_material(0)
	var m: BaseMaterial3D = src.duplicate()
	if src.albedo_texture != null:
		var img := src.albedo_texture.get_image()
		if img.is_compressed():
			img.decompress()
		img.clear_mipmaps()
		img.adjust_bcs(brightness, 1.0, saturation)
		img.generate_mipmaps()
		m.albedo_texture = ImageTexture.create_from_image(img)
	m.albedo_color = tint
	_mats[key] = m
	return m
