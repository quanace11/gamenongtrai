extends SceneTree
# Quick look-dev shots: the same cameras and states as main.gd _run_tour,
# plus a few extras. Usage:
#   godot --path . -s res://_q.gd -- --out=DIR [--only=t1,t12] [--frames=N]

var main
var outdir := "."
var only: PackedStringArray = []
var frames := 1


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			outdir = a.substr(6)
		elif a.begins_with("--only="):
			only = a.substr(7).split(",")
		elif a.begins_with("--frames="):
			frames = int(a.substr(9))
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	_run.call_deferred()


func want(n: String) -> bool:
	return only.is_empty() or n in only


func snap(n: String) -> void:
	if not want(n):
		return
	for i in frames:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(outdir + "/" + n + ".png")
	print("SHOT %s prims=%d draws=%d t=%.1f" % [n, Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Time.get_ticks_msec() / 1000.0])


func _run() -> void:
	await process_frame
	main._on_play()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main._hide_hud(true)
	if want("t1"):
		await main._look_at(-3, -10.5, 2, 2, -0.15)
		await main._set_time(7.0)
		await snap("t1")
	if want("t2"):
		await main._look_at(6, -11, 0, -24, -0.05)
		await main._set_time(9.0)
		await snap("t2")
	if want("lamp"):
		await main._look_at(3, -15, 0, -22.5, 0.02)
		await main._set_time(20.5)
		await snap("lamp")
	main._debug_skip_prep()
	main.field.water = 5.0
	if want("t12"):
		await main._look_at(-7.5, 7.5, 8, -6, -0.1)
		await main._set_time(8.0)
		await snap("t12")
	if want("mist"):
		await main._look_at(0, 9.3, 0, -10, -0.05)
		await main._set_time(6.6)
		await snap("mist")
	if want("noon12"):
		await main._look_at(-7.5, 7.5, 8, -6, -0.1)
		await main._set_time(12.5)
		await snap("noon12")
	main._debug_plant_all()
	main.field.water = 4.0
	main.field.growth_day = 2
	main.field.rice_dirty = true
	if want("t3"):
		await main._look_at(-7.5, 9.0, 2, -4, -0.18)
		await main._set_time(10.0)
		await snap("t3")
	if want("t4"):
		await main._look_at(-14.5, -4, -21, -11, -0.15)
		await main._set_time(11.0)
		await snap("t4")
	main.field.growth_day = 8
	main.field.rice_dirty = true
	if want("t5"):
		await main._look_at(7.5, 3, -4, -1, -0.12)
		await main._set_time(16.8)
		await snap("t5")
	if want("t15"):
		await main._look_at(0, 9.3, 0, 60, 0.03)
		await main._set_time(9.5)
		await snap("t15")
	await main._set_time(12.0)
	main.stage = "drying"
	main.court.pour(140.0)
	for k in 4:
		for i in main.court.mass.size():
			main.court.spread(i)
	if want("t7") or want("t8"):
		await main._look_at(0.5, -11.5, 0, -19, -0.3)
		await main._set_time(12.5)
		await snap("t7")
		main.storm.phase = "warning"
		main.storm.t = 60.0
		main.storm.level = 0.85
		await main._wait(1.0)
		await snap("t8")
	main.storm.phase = "rain"
	main.storm.level = 1.0
	main.raining = true
	if want("t9"):
		await main._look_at(0, -12, 0, 0, -0.15)
		await main._wait(2.0)
		await snap("t9")
	if want("wet"):
		await main._look_at(-3, -10.5, 2, 2, -0.3)
		await main._wait(2.0)
		await snap("wet")
	main.storm.phase = "done"
	main.storm.level = 0.0
	main.raining = false
	if want("t10") or want("t11"):
		await main._look_at(7, -2, -8, -2, -0.05)
		await main._set_time(17.85)
		await snap("t10")
		await main._set_time(22.0)
		await snap("t11")
	if want("sunrise"):
		await main._look_at(-7, 2, 8, 2, -0.05)
		await main._set_time(6.25)
		await snap("sunrise")
	quit(0)
