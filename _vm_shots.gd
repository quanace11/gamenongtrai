extends SceneTree
# Throwaway: one shot per held tool, plus the shoulder pole.
var main

func _initialize() -> void:
	_run.call_deferred()

func _frames(n: int) -> void:
	for i in n:
		await process_frame

func _run() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await _frames(3)
	main._on_play()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	main._hide_hud(true)
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	main._debug_skip_prep()
	main._debug_plant_all()
	main.field.water = 4.0
	main.field.growth_day = 8
	main.field.rice_dirty = true
	await main._look_at(0, -6, 0, 0, -0.3)
	await main._set_time(10.0)
	for id in ["tay", "cuoc", "bua", "gau", "liem", "cao", "sao"]:
		if only != "" and not id in only.split(","):
			continue
		main._select_tool(id)
		await main._wait(0.4)
		await main._shot("vm-" + id)
	if only == "" or "ganh" in only.split(","):
		main._select_tool("tay")
		main.inv.sheaves = main.CARRY
		await main._look_at(-1, -7, 4, -12, -0.2)
		await main._wait(0.6)
		await main._shot("vm-ganh")
		main.player.pitch = -0.75
		await main._wait(0.4)
		await main._shot("vm-ganh-down")
		main.inv.sheaves = 0
	if only == "" or "swing" in only.split(","):
		main._select_tool("cuoc")
		await main._wait(0.3)
		main.tools.swing(0.6, 0.4, "chop", func(): pass)
		await main._wait(0.25)
		await main._shot("vm-cuoc-swing")
	quit(0)
