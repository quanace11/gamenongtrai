# Slow idle motion for a standing animal: the head nods and sways as it
# grazes or chews, the tail swishes at flies. Pure transforms, no physics.
extends Node

var head: Node3D
var tail: Node3D
var _t := randf() * 100.0


func _process(dt: float) -> void:
	_t += dt
	if head != null:
		head.rotation.z = -0.08 + sin(_t * 0.35) * 0.12 + sin(_t * 1.7) * 0.015
		head.rotation.y = sin(_t * 0.21) * 0.18
	if tail != null:
		var swish := pow(maxf(0.0, sin(_t * 0.6)), 6.0)
		tail.rotation.x = sin(_t * 7.0) * 0.25 * swish
