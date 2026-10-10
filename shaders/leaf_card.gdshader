// Cut-out leaf cards: bamboo leaf sprays and banana leaves (flora.gd).
// Alpha scissor with alpha to coverage (MSAA) for soft, stable edges; this
// moves the material into the transparent pass, so it is used only on these
// few leaf materials, never on rice or grass. Both faces keep the canopy
// normal written by flora.gd, so a crown shades like a volume rather than
// a stack of paper. Wind on three levels: the whole culm or stem (COLOR.a
// = height fraction), the branch (UV2.x), and leaf flutter (UV.y), each
// with its own phase (UV2.y).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx, alpha_to_coverage;

global uniform float wind_gust;
global uniform vec2 wind_dir;
global uniform float wetness;
uniform sampler2D leaf_alb : source_color, filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0);
uniform float plant_height = 12.0;
uniform float trunk_sway = 0.35;   // metres at the top in a strong gust
uniform float branch_sway = 0.06;
uniform float flutter = 0.025;
uniform float translucency = 0.6;
uniform float rough = 0.55;
uniform float spec = 0.4;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	float ph = UV2.y * 6.2832;
	vec2 wuv = root.xz * 0.035 - wind_dir * TIME * (0.04 + 0.03 * wind_gust);
	float s = (0.15 + 0.85 * smoothstep(0.3, 0.8, textureLod(noise, wuv, 0.0).r)) * wind_gust;
	vec3 w = vec3(wind_dir.x, 0.0, wind_dir.y);
	// 1) the whole culm: slow and large, follows the gust (height squared)
	vec3 off = w * trunk_sway * s * COLOR.a * COLOR.a * (1.0 + 0.25 * sin(TIME * 0.7 + ph));
	// 2) the branch: medium frequency, its own phase
	off += (w + vec3(0.0, 0.3, 0.0)) * branch_sway * s * UV2.x * sin(TIME * 1.9 + ph);
	// 3) leaves: fast flutter, mostly vertical, stronger away from the twig
	off.y += flutter * wind_gust * UV.y * sin(TIME * 7.0 + ph * 3.0 + VERTEX.x * 4.0);
	off.y -= 0.5 * dot(off.xz, off.xz) / max(COLOR.a * plant_height, 0.5);
	mat3 m = mat3(MODEL_MATRIX);
	VERTEX += transpose(m) * off / dot(m[0], m[0]);
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL; // keep the crown normal on both faces
	}
	vec4 a = texture(leaf_alb, UV);
	vec3 col = a.rgb * COLOR.rgb * tint;
	ALBEDO = col * mix(1.0, 0.75, wetness);
	ALPHA = a.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	ALPHA_ANTIALIASING_EDGE = 0.3;
	ALPHA_TEXTURE_COORDINATE = UV * vec2(textureSize(leaf_alb, 0));
	ROUGHNESS = mix(rough, 0.25, wetness);
	SPECULAR = spec;
	BACKLIGHT = col * vec3(1.05, 1.15, 0.6) * translucency;
	// lower sprays sit deeper in the clump's shade
	AO = mix(0.5, 1.0, smoothstep(0.3, 0.9, COLOR.a));
	AO_LIGHT_AFFECT = 0.3;
}
