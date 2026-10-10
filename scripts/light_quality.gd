# Quality preset hook for the lighting set up in main.gd _setup_environment.
# PLAYER's Low/Medium/High setting calls set_quality on group "quality";
# this turns off the costly extras of the light package on lower presets.
# main.gd _update_sky reads moon_shadows and vol_allowed every frame (it owns
# env.volumetric_fog_enabled while the mist is out, so the preset's choice
# goes through vol_allowed).
extends Node

var main: Node


func _ready() -> void:
	add_to_group("quality")


func set_quality(level: int) -> void:
	if main == null:
		return
	main.lamp.shadow_enabled = level >= 2
	main.moon_shadows = level >= 2
	main.vol_allowed = level >= 1
	main.probe.max_distance = [80.0, 150.0, 150.0][clampi(level, 0, 2)]
