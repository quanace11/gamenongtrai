// Sân gạch: a yard of 30 cm square fired-clay tiles (gạch lá nem) bedded
// in lime mortar. Each tile has its own shade from the kiln and its own
// wear; joints hold dirt and moss, which spreads in from the less trodden
// edges; rain darkens and glosses the whole yard.
shader_type spatial;
render_mode diffuse_burley;

global uniform float wetness;
global uniform float rain_amount;

uniform sampler2D grain_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grain_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dirt_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float size = 0.3;
uniform vec4 rect = vec4(-6.0, -20.0, 6.0, -14.0);
uniform float edge_moss = 1.0;

varying vec3 wpos;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.1 + 1.3) * 0.3 + vnoise(p * 4.3 + 2.9) * 0.2;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 p = wpos.xz;
	vec2 q = p / size;
	vec2 cell = floor(q);
	vec2 f = fract(q);
	float h1 = hash(cell);
	float h2 = hash(cell + 17.3);
	// Bevelled, slightly worn tile edges; joints about 1 cm.
	vec2 e = min(f, 1.0 - f) * size;
	float edge = min(e.x, e.y);
	float wear = 0.004 + 0.006 * vnoise(p * 9.0);
	float joint = 1.0 - smoothstep(wear, wear + 0.006, edge);
	vec2 bevel = vec2(f.x < 0.5 ? -1.0 : 1.0, f.y < 0.5 ? -1.0 : 1.0) * (1.0 - smoothstep(0.0, 0.02, e));

	// Kiln shades from orange-red to dark brown, a few blackened tiles.
	vec3 tile = mix(vec3(0.22, 0.075, 0.045), vec3(0.14, 0.06, 0.04), h1);
	tile = mix(tile, vec3(0.26, 0.11, 0.06), step(0.86, h2));
	tile = mix(tile, vec3(0.1, 0.05, 0.035), step(0.95, h1) * 0.7);
	vec3 g = texture(grain_alb, (q + vec2(h1, h2) * 7.0) * 0.18).rgb;
	tile *= mix(0.7, 1.2, dot(g, vec3(0.33)) / 0.09);
	// Dirt and dust film, moss near the edges and in shade under the eaves.
	vec3 dirt = texture(dirt_alb, p / 2.5).rgb;
	float dust = smoothstep(0.35, 0.8, fbm(p * 0.45));
	tile = mix(tile, dirt * 0.8, 0.15 + dust * 0.45);
	float border = min(min(p.x - rect.x, rect.z - p.x), min(p.y - rect.y, rect.w - p.y));
	float mossy = (1.0 - smoothstep(0.0, 1.6, border + (fbm(p * 1.2) - 0.5) * 1.2)) * smoothstep(0.35, 0.7, fbm(p * 2.0 + 3.0)) * edge_moss;
	tile = mix(tile, vec3(0.045, 0.06, 0.02), mossy * 0.55);

	vec3 mortar = mix(vec3(0.16, 0.15, 0.12), vec3(0.04, 0.05, 0.025), smoothstep(0.3, 0.7, fbm(p * 3.0)));
	vec3 alb = mix(tile, mortar, joint);

	float wet = clamp(wetness + rain_amount * 0.4, 0.0, 1.0);
	ALBEDO = alb * mix(1.0, 0.6, wet);
	vec3 gn = texture(grain_nor, (q + vec2(h2, h1) * 5.0) * 0.18).rgb;
	gn.xy += bevel * 0.25;
	NORMAL_MAP = gn;
	NORMAL_MAP_DEPTH = 0.7;
	ROUGHNESS = mix(mix(0.82, 0.95, joint), 0.18 + joint * 0.3, wet);
	SPECULAR = 0.45;
}
