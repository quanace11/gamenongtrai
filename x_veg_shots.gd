extends SceneTree
# Throwaway: take selected tour-like shots. Args after --: --shots=DIR --only=a,b,c

var m


func _initialize() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	_go.call_deferred()


func _arg(k: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(k + "="):
			return a.substr(k.length() + 1)
	return ""


func _go() -> void:
	await process_frame
	var only := _arg("--only").split(",")
	m._on_play()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	m._hide_hud(true)
	for id in only:
		match id:
			"1":
				await m._look_at(-3, -10.5, 2, 2, -0.15)
				await m._set_time(7.0)
				await m._shot("tour-1-dry-field")
			"2":
				await m._look_at(6, -11, 0, -24, -0.05)
				await m._set_time(9.0)
				await m._shot("tour-2-house")
			"12":
				m._debug_skip_prep()
				m.field.water = 5.0
				await m._look_at(-7.5, 7.5, 8, -6, -0.1)
				await m._set_time(8.0)
				await m._shot("tour-12-flooded-mirror")
			"3":
				_plant(2)
				await m._look_at(-7.5, 9.0, 2, -4, -0.18)
				await m._set_time(10.0)
				await m._shot("tour-3-young-rice")
			"4":
				await m._look_at(-14.5, -4, -21, -11, -0.15)
				await m._set_time(11.0)
				await m._shot("tour-4-pond")
			"5":
				_plant(8)
				await m._look_at(7.5, 3, -4, -1, -0.12)
				await m._set_time(16.8)
				await m._shot("tour-5-ripe-golden-hour")
			"6":
				_plant(8)
				await m._look_at(0, -6, 0, 0, -0.35)
				await m._set_time(12.0)
				m._select_tool("liem")
				await m._shot("tour-6-sickle")
				m._select_tool("tay")
			"14":
				await m._look_at(12, -9, 20, -14, -0.25)
				await m._set_time(11.0)
				await m._shot("tour-14-lawn")
			"15":
				await m._look_at(0, 9.3, 0, 60, 0.03)
				await m._set_time(9.5)
				await m._shot("tour-15-far-karst")
			"10":
				_plant(8)
				await m._look_at(7, -2, -8, -2, -0.05)
				await m._set_time(17.85)
				await m._shot("tour-10-sunset")
			"11":
				_plant(8)
				await m._look_at(7, -2, -8, -2, -0.05)
				await m._set_time(22.0)
				await m._shot("tour-11-night")
			_:
				# rice close-ups: r<day> e.g. r0 r2 r4 r6 r8, rc = harvested
				if id.begins_with("r"):
					var d := id.substr(1)
					if d == "c":
						_plant(8)
						for c in m.field.clumps:
							if c.z > -2.0:
								c.cut = true
						m.field.rice_dirty = true
					else:
						_plant(int(d))
					await m._look_at(-6.9, 8.3, -4.5, 4.0, -0.3)
					await m._set_time(9.5 if d != "8" else 16.5)
					await m._shot("rice-close-" + d)
					for c in m.field.clumps:
						c.cut = false
				elif id.begins_with("n"):
					# nursery bed at day state
					m.nursery.state = "ready"
					m.nursery.bundles = 0
					m._refresh_nursery()
					var sd: MultiMeshInstance3D = m.world.seedlings
					print("SEED ", sd.multimesh.visible_instance_count, " ", sd.global_transform, " ", sd.multimesh.get_aabb(), " ", sd.get_aabb())
					if _arg("--dbg") == "std":
						var sm := StandardMaterial3D.new()
						sm.vertex_color_use_as_albedo = true
						sm.cull_mode = BaseMaterial3D.CULL_DISABLED
						sd.material_override = sm
					elif _arg("--dbg").begins_with("p:"):
						var mt: ShaderMaterial = sd.material_override.duplicate()
						for kv in _arg("--dbg").substr(2).split(";"):
							var q := kv.split("=")
							mt.set_shader_parameter(q[0], str_to_var(q[1]))
						sd.material_override = mt
					elif _arg("--dbg") == "hide":
						sd.visible = false
					await m._look_at(13, -12.3, 13, -16, -0.45)
					await m._set_time(10.0)
					await m._shot("nursery")
				elif id == "w":
					await m._look_at(-1.2, -18.6, -2.6, -21.3, -0.35)
					await m._set_time(10.0)
					await m._shot("fern-pots")
				elif id == "x":
					var best: Vector3 = Vector3.ZERO
					for n in m.find_children("*", "MultiMeshInstance3D", true, false):
						var mi := n as MultiMeshInstance3D
						if mi.visibility_range_end == 40.0 and mi.multimesh.instance_count > 1 and mi.multimesh.mesh is ArrayMesh and (mi.multimesh.mesh as ArrayMesh).get_surface_count() > 0:
							var o := mi.multimesh.get_instance_transform(0).origin
							if best == Vector3.ZERO or o.length() < best.length():
								best = o
					print("WEED at ", best)
					await m._look_at(best.x + 1.6, best.z + 1.6, best.x, best.z, -0.4)
					await m._set_time(10.0)
					await m._shot("weeds")
				elif id.begins_with("k"):
					await m._look_at(-15.0, -8.0, -19.0, -12.5, -0.5)
					await m._set_time(10.0)
					await m._shot("rocks")
				elif id.begins_with("e"):
					# eye-level rice close-up from the bund
					_plant(int(id.substr(1)))
					await m._look_at(-8.3, 2.0, -4.0, 1.0, -0.2)
					await m._set_time(9.5 if id != "e8" else 16.6)
					await m._shot("rice-eye-" + id.substr(1))
				elif id.begins_with("b"):
					await m._look_at(18, -18, 24, -26, 0.12)
					await m._set_time(10.0)
					await m._shot("bamboo-close")
				elif id.begins_with("p"):
					await m._look_at(-10, -16, -17, -6, 0.05)
					await m._set_time(10.5)
					await m._shot("palms")
	print("VEG SHOTS DONE")
	OS.kill(OS.get_process_id())
	quit()


func _plant(day: int) -> void:
	if m.field.clumps.is_empty():
		m._debug_skip_prep()
		m._debug_plant_all()
	m.field.water = 4.0
	m.field.growth_day = day
	m.field.rice_dirty = true
