// Cut-out leaf cards: bamboo leaf sprays and banana leaves (flora.gd).
// Alpha scissor with alpha to coverage (MSAA) for soft, stable edges; this
// moves the material into the transparent pass, so it is used only on these
// few leaf materials, never on rice or grass. Both faces keep the canopy
// normal written by flora.gd, so a crown shades like a volume rather than
// a stack of paper. Wind: see tree_wind.gdshaderinc; UV.y (distance from
// the twig or petiole) weights the leaf flutter.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx, alpha_to_coverage;
#include "res://shaders/tree_wind.gdshaderinc"

uniform sampler2D leaf_alb : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float translucency = 0.6;
uniform float rough = 0.72;
uniform float spec = 0.2;
uniform float mip_coverage = 0.3; // keeps far foliage dense (alpha lost to mipmaps)
uniform float ao_low = 0.45;       // AO of the innermost, lowest leaves
uniform float dry = 0.0;           // 1: dead, papery brown leaves (banana)

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 off = tree_wind(root, wp, COLOR, UV2, UV.y, TIME);
	mat3 m = mat3(MODEL_MATRIX);
	VERTEX += transpose(m) * off / dot(m[0], m[0]);
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL; // keep the crown normal on both faces
	}
	// A canopy normal can face away from the camera; the Fresnel term then
	// turns the leaf into a white mirror of the sky. Tilt it back into view.
	float nv = dot(NORMAL, VIEW);
	NORMAL = normalize(NORMAL + VIEW * max(0.3 - nv, 0.0));
	vec4 a = texture(leaf_alb, UV);
	vec3 col = a.rgb * COLOR.rgb * tint;
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, lum * vec3(1.55, 1.05, 0.5), dry);
	ALBEDO = col * mix(1.0, 0.75, wetness);
	// Mipmapping averages leaves with the gaps around them, so far cards
	// would thin out and vanish below the scissor threshold: boost alpha by
	// the mip level (Ben Golus, "Anti-aliased alpha test").
	vec2 tc = UV * vec2(textureSize(leaf_alb, 0));
	vec2 dx = dFdx(tc);
	vec2 dy = dFdy(tc);
	float mip = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
	ALPHA = a.a * (1.0 + mip * mip_coverage);
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = tc;
	ROUGHNESS = mix(rough, 0.25, wetness);
	SPECULAR = spec;
	BACKLIGHT = col * vec3(1.05, 1.15, 0.6) * translucency;
	// lower, inner sprays sit deeper in the clump's shade
	AO = mix(ao_low, 1.0, smoothstep(0.25, 0.9, COLOR.a));
	AO_LIGHT_AFFECT = 0.35;
}
