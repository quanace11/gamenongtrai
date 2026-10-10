extends SceneTree


func _walk(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_walk(c, out)


func _init() -> void:
	for id in ["fern_02", "shrub_04", "nettle_plant", "weed_plant_02", "rock_07", "stone_01"]:
		var scene: PackedScene = load("res://assets/models/%s/%s_1k.gltf" % [id, id])
		var root := scene.instantiate()
		var mis := []
		_walk(root, mis)
		var tris := 0
		var info := []
		for mi: MeshInstance3D in mis:
			var m: ArrayMesh = mi.mesh
			for s in m.get_surface_count():
				var idx: PackedInt32Array = m.surface_get_arrays(s)[Mesh.ARRAY_INDEX]
				tris += idx.size() / 3
			var mat := mi.get_active_material(0) as BaseMaterial3D
			var al := -1
			if mat and mat.albedo_texture:
				al = mat.albedo_texture.get_image().detect_alpha()
			info.append("%s lods=%d shadow=%s transp=%d alpha=%d aabb=%s" % [mi.name, (RenderingServer.mesh_get_surface(m.get_rid(), 0).get("lods", []) as Array).size(), m.shadow_mesh != null, mat.transparency if mat else -1, al, m.get_aabb().size])
		print(id, " parts=", mis.size(), " tris=", tris)
		for l in info:
			print("   ", l)
		root.free()
	quit()
