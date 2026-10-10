// Palm fronds and leaflets, banana pseudostems and petioles, nuts and fruit
// (flora.gd): alpha-free geometry coloured by vertex colour (authored in
// sRGB), so it stays in the opaque pass. Both faces keep the canopy normal
// written by flora.gd. UV.x = ambient occlusion (0 deep in the crown),
// UV.y = leaf flutter weight. Wind: see tree_wind.gdshaderinc.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;
#include "res://shaders/tree_wind.gdshaderinc"

uniform float translucency = 0.45;
uniform float rough = 0.6;
uniform float spec = 0.45;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 off = tree_wind(root, wp, COLOR, UV2, UV.y, TIME);
	mat3 m = mat3(MODEL_MATRIX);
	VERTEX += transpose(m) * off / dot(m[0], m[0]);
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	vec3 c = pow(COLOR.rgb, vec3(2.2));
	ALBEDO = c * mix(1.0, 0.75, wetness);
	ROUGHNESS = mix(rough, 0.25, wetness);
	SPECULAR = spec;
	BACKLIGHT = c * vec3(1.1, 1.2, 0.6) * translucency;
	AO = mix(0.4, 1.0, UV.x);
	AO_LIGHT_AFFECT = 0.35;
}
