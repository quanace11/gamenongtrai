# Quality preset hook for the village trees: shortens the bamboo and palm
# LOD distances on Low and Medium (PLAYER's settings call set_quality on the
# "quality" group with 0, 1 or 2). flora.gd registers each LOD node with its
# High-quality range.
extends Node

const SCALE := [0.55, 0.8, 1.0]

var nodes: Array[GeometryInstance3D] = []


func _ready() -> void:
	add_to_group("quality")


func set_quality(level: int) -> void:
	var k: float = SCALE[clampi(level, 0, 2)]
	for gi in nodes:
		var r: Vector2 = gi.get_meta("lod_range")
		gi.visibility_range_begin = r.x * k
		gi.visibility_range_end = r.y * k
