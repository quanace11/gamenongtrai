// Leaves and stems of the village trees (bamboo, banana, palms): sways in
// the wind and optionally cuts the leaf out of an alpha texture (use_leaf).
// Same uniforms as before, plus the shared wind noise. See
// foliage_body.gdshaderinc.
shader_type spatial;
#define LEAF_TEX
#include "res://shaders/foliage_body.gdshaderinc"
