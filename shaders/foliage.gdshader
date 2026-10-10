// Alpha-free leaves and blades built as geometry: grass tufts, paddy weeds,
// palm leaflets, banana pseudostems. Bends in the wind with the height above
// the plant's base (whole plant) plus COLOR.a (leaf or frond flex), with a
// phase per leaf from UV2.y. Stays in the opaque pass: no ALPHA is written.
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

global uniform float wind_gust;
global uniform vec2 wind_dir;
global uniform float wetness;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable; // flora.gd wind_noise()
uniform vec3 tint : source_color = vec3(1.0);
uniform float sway = 0.06;        // metres of bend at 1 m above the base
uniform float stiffness = 1.0;
uniform float flex_sway = 0.0;    // metres of extra bend at COLOR.a = 1
uniform float flutter = 0.0;      // fast leaf flutter amplitude (m)
uniform float translucency = 0.35;
uniform float rough = 0.7;
uniform float spec = 0.4;
uniform bool keep_normal = false; // both faces keep the authored (canopy) normal

void vertex() {
	vec3 base = MODEL_MATRIX[3].xyz;
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float h = max(wp.y - base.y, 0.0);
	vec2 wuv = base.xz * 0.035 - wind_dir * TIME * (0.04 + 0.03 * wind_gust);
	float gust = (0.25 + 0.75 * smoothstep(0.3, 0.8, textureLod(noise, wuv, 0.0).r)) * wind_gust;
	float ph = TIME * (1.2 + wind_gust * 0.5) + base.x * 0.35 + base.z * 0.27 + UV2.y * 6.2832;
	vec2 osc = vec2(sin(ph) + 0.5 * sin(ph * 2.3 + 1.7), cos(ph * 0.8) * 0.5);
	float bend = pow(h, 1.5 * stiffness) * sway + COLOR.a * COLOR.a * flex_sway;
	vec3 w = vec3(wind_dir.x, 0.0, wind_dir.y);
	vec3 off = (w * (0.6 * gust) + vec3(osc.x, 0.0, osc.y) * 0.35 * wind_gust) * bend;
	off.y += flutter * COLOR.a * wind_gust * sin(TIME * 6.5 + UV2.y * 19.0 + wp.x * 3.0);
	// world offset back to model space without a 4x4 inverse (rotation + uniform scale)
	mat3 m = mat3(MODEL_MATRIX);
	VERTEX += transpose(m) * off / dot(m[0], m[0]);
}

void fragment() {
	if (keep_normal && !FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	// Vertex and instance colours are authored in sRGB.
	vec3 c = pow(COLOR.rgb, vec3(2.2)) * tint;
	ALBEDO = c * mix(1.0, 0.75, wetness);
	ROUGHNESS = mix(rough, 0.3, wetness);
	SPECULAR = spec;
	BACKLIGHT = c * vec3(1.1, 1.2, 0.6) * translucency;
	// Vertex alpha: 0 at the base where leaves shade each other, 1 at the tips.
	AO = mix(0.4, 1.0, COLOR.a);
	AO_LIGHT_AFFECT = 0.4;
}
