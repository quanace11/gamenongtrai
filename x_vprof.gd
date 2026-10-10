extends SceneTree
var m
func _initialize() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	_go.call_deferred()
func _prims() -> int:
	for i in 3:
		await process_frame
	return int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
func _vis(lod: int, on: bool) -> void:
	for ch in m.field._rice._chunks.values():
		for i in 7:
			var l := 0 if i < 2 else (1 if i < 4 else 2)
			if i == 5: l = 0
			if i == 6: l = 2
			if l == lod:
				ch.mm[i].visible = on and ch.mm[i].multimesh.instance_count > 0
func _go() -> void:
	await process_frame
	m._on_play()
	m._hide_hud(true)
	m._debug_skip_prep()
	m._debug_plant_all()
	m.field.water = 4.0
	m.field.growth_day = 8
	m.field.rice_dirty = true
	await m._look_at(-8.3, 2.0, -4.0, 1.0, -0.2)
	await m._set_time(16.6)
	print("PROF all ", await _prims())
	_vis(0, false)
	print("PROF no lod0 ", await _prims())
	_vis(1, false)
	print("PROF no lod0,1 ", await _prims())
	_vis(2, false)
	print("PROF no rice ", await _prims())
	var lawn = m.find_child("Lawn", true, false)
	lawn.visible = false
	print("PROF no rice no lawn ", await _prims())
	for n in m.find_children("*", "MultiMeshInstance3D", true, false):
		(n as Node3D).visible = false
	print("PROF no multimeshes ", await _prims())
	m.sun.shadow_enabled = false
	print("PROF no rice no sun shadow ", await _prims())
	m.sun.shadow_enabled = true
	_vis(0, true); _vis(1, true); _vis(2, true)
	m.sun.shadow_enabled = false
	print("PROF rice, no sun shadow ", await _prims())
	OS.kill(OS.get_process_id())
