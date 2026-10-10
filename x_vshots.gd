extends SceneTree
# Throwaway: take selected vegetation shots. args: --shots=DIR --only=a,b,c

var m: Node


func _init() -> void:
	var sc: PackedScene = load("res://scenes/main.tscn")
	m = sc.instantiate()
	root.add_child(m)
	_run.call_deferred()


func _want(n: String) -> bool:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			return n in a.substr(7).split(",")
	return true


func _run() -> void:
	await m._wait(0.5)
	m._on_play()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	m._hide_hud(true)
	if _want("lawn"):
		await m._look_at(12, -9, 20, -14, -0.25)
		await m._set_time(11.0)
		await m._shot("v-lawn")
	if _want("lawnlow"):
		await m._look_at(-2, -11, -14, 4, -0.35)
		await m._set_time(10.0)
		await m._shot("v-lawnlow")
	if _want("pond"):
		await m._look_at(-14.5, -4, -21, -11, -0.15)
		await m._set_time(11.0)
		await m._shot("v-pond")
	if _want("bamboo"):
		await m._look_at(16, 14, 22, 22, 0.25)
		await m._set_time(10.0)
		await m._shot("v-bamboo")
	if _want("palms"):
		await m._look_at(4, -18, 10, -26, 0.15)
		await m._set_time(10.0)
		await m._shot("v-palms")
	if _want("far"):
		await m._look_at(0, 9.3, 0, 60, 0.03)
		await m._set_time(9.5)
		await m._shot("v-far")
	if _want("nursery"):
		m.nursery.state = "ready"
		m._refresh_nursery()
		await m._look_at(13, -12.5, 13, -16, -0.45)
		await m._set_time(10.0)
		await m._shot("v-nursery")
	m._debug_skip_prep()
	m.field.water = 4.0
	m._debug_plant_all()
	for d in [2, 4, 5, 8]:
		if _want("rice%d" % d) or _want("ricefar%d" % d):
			m.field.growth_day = d
			m.field.rice_dirty = true
			await m._wait(0.3)
			if _want("rice%d" % d):
				await m._look_at(-8.6, 6.5, -2, 6.5, -0.12)
				await m._set_time(10.0 if d < 8 else 16.8)
				await m._shot("v-rice%d" % d)
			if _want("ricefar%d" % d):
				await m._look_at(7.5, 3, -4, -1, -0.12)
				await m._set_time(10.0 if d < 8 else 16.8)
				await m._shot("v-ricefar%d" % d)
	if _want("stubble"):
		m.field.growth_day = 8
		for c in m.field.clumps:
			if c.z > 0.0:
				c.cut = true
		m.field.rice_dirty = true
		await m._look_at(-8.6, 6.5, -2, 6.5, -0.2)
		await m._set_time(12.0)
		await m._shot("v-stubble")
	quit(0)
