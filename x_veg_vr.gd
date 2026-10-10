extends SceneTree

var cam: Camera3D
var a: MultiMeshInstance3D
var b: MeshInstance3D


func _initialize() -> void:
	cam = Camera3D.new()
	root.add_child(cam)
	cam.position = Vector3(0, 1, 0)
	var sm := SphereMesh.new()
	sm.radial_segments = 64
	sm.rings = 32 # 4096 tris
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = sm
	mm.instance_count = 10
	for i in 10:
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(i * 0.5, 0, -30)))
	mm.custom_aabb = AABB(Vector3(-1, -1, -31), Vector3(6, 2, 2))
	a = MultiMeshInstance3D.new()
	a.multimesh = mm
	a.visibility_range_end = 10.0
	a.visibility_range_end_margin = 1.0
	a.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	root.add_child(a)
	b = MeshInstance3D.new()
	b.mesh = sm
	b.position = Vector3(0, 0, -30)
	b.visibility_range_end = 10.0
	root.add_child(b)
	var sun := DirectionalLight3D.new()
	sun.shadow_enabled = true
	sun.rotation = Vector3(-1.0, 0.3, 0)
	root.add_child(sun)
	var fl := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(100, 100)
	fl.mesh = pm
	fl.position.y = -1.0
	root.add_child(fl)
	_go.call_deferred()


func _p(t: String) -> void:
	for i in 3:
		await process_frame
	await RenderingServer.frame_post_draw
	print(t, " prims=", Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), " objs=", Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))


func _go() -> void:
	await _p("both ranged (expect ~0)")
	a.visibility_range_end = 0.0
	await _p("mm unranged (expect 40960)")
	a.visibility_range_end = 10.0
	a.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
	await _p("mm ranged no fade (expect 0)")
	b.visibility_range_end = 0.0
	await _p("mesh unranged (expect 4096)")
	print("VEG SHOTS DONE")
	OS.kill(OS.get_process_id())
