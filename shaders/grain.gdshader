// Paddy spread on the yard to dry. Vertex colour: RGB = shade of the grain
// (golden when dry, darker when damp), A = how thinly it is raked out,
// which sets the depth of the rake furrows drawn here as a normal pattern.
shader_type spatial;
render_mode diffuse_burley;

global uniform float rain_amount;

uniform sampler2D grain_nor : hint_normal, filter_linear_mipmap, repeat_enable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	// Furrows about 15 cm apart, pulled along z by the rake, slightly wavy.
	float ph = wpos.x * 42.0 + sin(wpos.z * 3.0) * 0.6;
	float slope = cos(ph) * COLOR.a;
	vec3 g = texture(grain_nor, wpos.xz * 4.0).rgb;
	g.x = clamp(g.x - slope * 0.35, 0.0, 1.0);
	// Vertex colours are authored in sRGB.
	ALBEDO = pow(COLOR.rgb, vec3(2.2)) * (1.0 + sin(ph) * 0.06 * COLOR.a) * mix(1.0, 0.7, rain_amount);
	NORMAL_MAP = g;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = mix(0.8, 0.45, rain_amount);
	SPECULAR = 0.4;
}
