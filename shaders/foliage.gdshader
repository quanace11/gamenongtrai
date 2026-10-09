// Leaves and blades (rice, grass, bamboo, banana, palms). Sways in the
// wind in proportion to height above the plant's base, lets sunlight
// through from behind, and optionally uses an alpha-cut leaf texture.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D leaf : source_color, filter_linear_mipmap, repeat_disable;
uniform bool use_leaf = false;
uniform vec3 tint : source_color = vec3(1.0);
uniform float sway = 0.06; // metres of bend at 1 m height
global uniform float wind_gust;
uniform float stiffness = 1.0;
uniform float translucency = 0.35;
uniform float rough = 0.7;

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 base = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float h = max(wp.y - base.y, 0.0);
	float bend = pow(h, 1.5 * stiffness) * sway * wind_gust;
	float ph = TIME * (1.3 + wind_gust * 0.6) + base.x * 0.35 + base.z * 0.27;
	vec2 dir = vec2(sin(ph) + 0.6 * sin(ph * 2.3 + 1.7), cos(ph * 0.8) * 0.4 + 0.35 * wind_gust);
	// World-space offset turned back into local space.
	vec3 off = vec3(dir.x, 0.0, dir.y) * bend;
	VERTEX += (inverse(MODEL_MATRIX) * vec4(off, 0.0)).xyz;
}

void fragment() {
	// Vertex and instance colours are authored in sRGB.
	vec4 c = vec4(pow(COLOR.rgb, vec3(2.2)) * tint, 1.0);
	if (use_leaf) {
		vec4 l = texture(leaf, UV);
		c.rgb *= l.rgb;
		c.a = l.a;
	}
	ALBEDO = c.rgb;
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.35;
	ROUGHNESS = rough;
	SPECULAR = 0.35;
	BACKLIGHT = c.rgb * translucency;
	// Vertex alpha: 0 at the base where blades shade each other, 1 at the tips.
	AO = mix(0.35, 1.0, COLOR.a);
	AO_LIGHT_AFFECT = 0.5;
}
