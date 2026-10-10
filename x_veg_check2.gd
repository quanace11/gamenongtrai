extends SceneTree


func _tris(m: Mesh) -> int:
	var n := 0
	for s in m.get_surface_count():
		n += (m.surface_get_arrays(s)[Mesh.ARRAY_INDEX] as PackedInt32Array).size() / 3
	return n


func _init() -> void:
	for p in ["res://shaders/rice.gdshader", "res://shaders/rice_panicle.gdshader"]:
		var s: Shader = load(p)
		print("SHADER ", p, " uniforms=", s.get_shader_uniform_list().size())
	var R = load("res://scripts/rice_hill.gd")
	for st in [0.0, 0.09, 0.24, 0.44, 0.62, 0.76, 1.0]:
		var t0 := Time.get_ticks_usec()
		var line := "stage %.2f:" % st
		for lod in 3:
			var m: ArrayMesh = R.hill(st, 101, lod)
			line += "  lod%d %d tris (%d surf)" % [lod, _tris(m), m.get_surface_count()]
			if lod == 0:
				line += " aabb=%s" % m.get_aabb().size
		print(line, "  %.1f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))
	print("stubble ", _tris(R.stubble(1, 0)), " / ", _tris(R.stubble(1, 1)))
	quit()
