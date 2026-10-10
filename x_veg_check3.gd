extends SceneTree


func _initialize() -> void:
	_go.call_deferred()


func _go() -> void:
	var RF = load("res://scripts/rice_field.gd")
	var rf: Node3D = RF.new()
	root.add_child(rf)
	var clumps := []
	for l in 8:
		for r in 26:
			for s in [-0.6, 0.0, 0.6]:
				clumps.append({"x": -8.0 + 2 * l + 1 + s, "z": 7.5 - r * 0.6, "rot": 0.0, "cut": false})
	var t0 := Time.get_ticks_msec()
	rf.update(clumps, 4, 0.1, 1.0)
	print("update ms ", Time.get_ticks_msec() - t0)
	var n := 0
	var inst := 0
	for c in rf.get_children():
		var m := c as MultiMeshInstance3D
		if n < 8:
			print(n, " begin=", m.visibility_range_begin, " end=", m.visibility_range_end, " count=", m.multimesh.instance_count, " vis=", m.visible, " mesh=", m.multimesh.mesh)
		inst += m.multimesh.instance_count
		n += 1
	print("mmis ", n, " instances ", inst)
	t0 = Time.get_ticks_msec()
	rf.update(clumps, 5, 0.1, 1.0)
	print("stage change ms ", Time.get_ticks_msec() - t0)
	quit()
