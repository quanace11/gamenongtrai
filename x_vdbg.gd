extends SceneTree
const R = preload("res://scripts/rice_hill.gd")
const RF = preload("res://scripts/rice_field.gd")
func _initialize() -> void:
	for d in 9:
		var s := RF.stage_of(d)
		var out := "day %d s=%.2f" % [d, s]
		for lod in 3:
			var m := R.hill(s, 101, lod)
			var t := 0
			for i in m.get_surface_count():
				t += m.surface_get_array_index_len(i) / 3
			out += "  lod%d=%d" % [lod, t]
		print(out)
	quit()
