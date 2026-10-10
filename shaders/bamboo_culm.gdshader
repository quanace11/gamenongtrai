// Bamboo culms and branches, and ringed palm trunks (flora.gd). Nodes come
// from UV.y (metres along the culm): a dark node line, a raised ridge (normal
// tilt), a whitish waxy band just below each node, fine vertical streaks,
// older culms greyer with lichen, dead papery sheaths at the base. Uses the
// same culm sway as leaf_card.gdshader so the leaves stay attached.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

global uniform float wind_gust;
global uniform vec2 wind_dir;
global uniform float wetness;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float internode = 0.38;
uniform float plant_height = 12.0;
uniform float trunk_sway = 0.35;
uniform vec3 young : source_color = vec3(0.45, 0.55, 0.22);
uniform vec3 old : source_color = vec3(0.58, 0.57, 0.42);
uniform vec3 sheath : source_color = vec3(0.50, 0.40, 0.25);
uniform float wax = 0.35;          // strength of the white band under the node
uniform float node_dark = 0.45;    // darkening of the node line
uniform float streaks = 0.08;

void vertex() {
	vec3 root = MODEL_MATRIX[3].xyz;
	vec2 wuv = root.xz * 0.035 - wind_dir * TIME * (0.04 + 0.03 * wind_gust);
	float s = (0.15 + 0.85 * smoothstep(0.3, 0.8, textureLod(noise, wuv, 0.0).r)) * wind_gust;
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * trunk_sway * s * COLOR.a * COLOR.a * (1.0 + 0.25 * sin(TIME * 0.7 + UV2.y * 6.2832));
	mat3 m = mat3(MODEL_MATRIX);
	VERTEX += transpose(m) * off / dot(m[0], m[0]);
}

void fragment() {
	// COLOR = (brightness, yellowing, age, height fraction)
	float age = COLOR.b;
	float y = UV.y + UV2.y * internode; // nodes staggered per culm
	float k = fract(y / internode);
	float dn = min(k, 1.0 - k) * internode; // metres to the nearest node
	vec3 col = mix(young, old, age) * COLOR.r;
	col = mix(col, col * vec3(1.12, 1.0, 0.62), COLOR.g);
	col *= (1.0 - streaks) + streaks * sin(UV.x * 140.0 + sin(y * 3.0));
	col = mix(col, vec3(0.78, 0.80, 0.70), (1.0 - smoothstep(0.0, 0.05, k * internode - 0.012)) * wax);
	col *= mix(1.0 - node_dark, 1.0, smoothstep(0.004, 0.014, dn));
	float lichen = smoothstep(0.62, 0.7, texture(noise, vec2(UV.x * 0.6, y * 0.4)).r) * age;
	col = mix(col, vec3(0.62, 0.63, 0.55), lichen * 0.6);
	col = mix(sheath, col, smoothstep(0.02, 0.1, COLOR.a)); // dead sheaths at the base
	ALBEDO = col * mix(1.0, 0.7, wetness);
	float ridge = (1.0 - smoothstep(0.0, 0.015, dn)) * sign(0.5 - k);
	NORMAL_MAP = normalize(vec3(0.0, ridge * 0.6, 1.0)) * 0.5 + 0.5;
	ROUGHNESS = mix(mix(0.38, 0.75, age), 0.2, wetness);
	SPECULAR = 0.5;
}
