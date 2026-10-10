extends SceneTree
var main
func _initialize() -> void:
	_run.call_deferred()
func _frames(n: int) -> void:
	for i in n:
		await process_frame
func _run() -> void:
	var out := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main._on_play()
	await _frames(2)
	for q in [0, 1, 2]:
		main._on_quality_changed(q)
		await _frames(2)
		print("QUALITY ", q, " ssr=", main.env.ssr_enabled, " ssil=", main.env.ssil_enabled, " ssao=", main.env.ssao_enabled, " vfog=", main.env.volumetric_fog_enabled, " scale=", root.scaling_3d_scale, " msaa=", root.msaa_3d)
	main._on_fov_changed(70.0)
	await _frames(2)
	print("FOV ", main.camera.fov, " base ", main.player.fov_base)
	main._on_fov_changed(62.0)
	# walking: cadence and bob
	main.player.pos = Vector3(6, 0, -11)
	main.player.teleported()
	main.player.yaw = 0.0
	var ys := []
	var steps0: float = main.player.gait
	var t := 0.0
	var reach := -1.0
	for i in 180:
		main.player.update(1.0 / 60.0, Vector2(0, 1), false, main.field, 0.0)
		t += 1.0 / 60.0
		if reach < 0 and main.player.speed() > 1.6:
			reach = t
		if i > 60:
			ys.append(main.camera.position.y)
	print("WALK speed=%.2f steps/s=%.2f bob_pp_cm=%.1f reach_s=%.2f" % [main.player.speed(), (main.player.gait - steps0) / t, (ys.max() - ys.min()) * 100.0, reach])
	for i in 120:
		main.player.update(1.0 / 60.0, Vector2(0, 1), true, main.field, 0.0)
	print("RUN speed=%.2f fov=%.1f" % [main.player.speed(), main.camera.fov])
	main._set_paused(true)
	main.hud.perf.visible = true
	await _frames(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out + "/pause-menu.png")
	print("DONE")
	quit(0)
