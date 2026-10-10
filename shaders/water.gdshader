// Canal (mương) and pond (ao) water: transparent, so the banks and the bed
// show through near the edge. The water column is measured from the depth
// buffer: the bed fades into silty brown-green water with depth (Beer-
// Lambert), the background is refracted a little by the ripples, the bank
// fades in softly where the water thins out, and the sky / ReflectionProbe
// reflection on top uses the real Fresnel of water (F0 = 0.02).
// (The flooded paddy is not drawn here: soil.gdshader shades it opaque so it
// gets screen-space reflections.)
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.32, 0.36, 0.26); // colour of the silt / algae in the water
uniform float clarity = 0.55; // 0 clear .. 1 murky (how fast the bed disappears)
uniform float scale = 0.35;
uniform float wind = 1.0;
uniform float min_depth = 0.15; // read as at least this deep, even over a flat bed (m)
uniform float shore = 0.05; // bank fades in over this water depth (m)
uniform float refraction = 0.025;
global uniform float rain_amount;
global uniform float wind_gust;
global uniform vec2 wind_dir;
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Expanding rings, one per cell, restarting at random times.
vec2 ripples(vec2 p, float t) {
	vec2 g = vec2(0.0);
	for (int k = 0; k < 3; k++) {
		vec2 q = p * (2.6 + float(k) * 1.9) + float(k) * 7.31;
		vec2 cell = floor(q);
		vec2 f = fract(q) - 0.5;
		float h = hash(cell);
		vec2 c = (vec2(hash(cell + 3.1), hash(cell + 5.7)) - 0.5) * 0.6;
		float ph = fract(t * (0.9 + h) + h);
		vec2 d = f - c;
		float r = length(d);
		float ring = sin((r - ph * 0.45) * 55.0) * smoothstep(0.0, 0.05, ph * 0.45 - r + 0.05) * smoothstep(0.45, 0.0, r) * (1.0 - ph);
		g += normalize(d + 1e-4) * ring;
	}
	return g;
}

// View-space position of the opaque scene at a screen UV (since 4.3 the raw
// depth already is NDC z: reverse-Z, no remap).
vec3 scene_pos(vec2 uv, mat4 inv_proj) {
	float z = texture(depth_tex, uv).r;
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, z, 1.0);
	return v.xyz / v.w;
}

void fragment() {
	// Calm surface: two slow normal maps, a little livelier in gusts.
	vec2 p = wpos.xz * scale;
	float t = TIME * wind;
	vec2 wd = normalize(wind_dir + vec2(1e-4));
	vec3 n1 = texture(wave_a, p * 0.6 + wd * t * 0.02).xyz * 2.0 - 1.0;
	vec3 n2 = texture(wave_b, p * 1.3 - vec2(t * 0.017, -t * 0.021)).xyz * 2.0 - 1.0;
	vec2 slope = (n1.xy + n2.xy) * (0.05 + 0.04 * wind_gust);
	if (rain_amount > 0.0) {
		slope += ripples(wpos.xz, TIME) * rain_amount * 0.35;
	}
	vec3 nm = normalize(vec3(slope, 1.0));
	NORMAL_MAP = nm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	// Water in front of the opaque scene: vertical depth to the bed, and the
	// length of the view ray inside the water.
	vec3 back = scene_pos(SCREEN_UV, INV_PROJECTION_MATRIX);
	float depth_v = wpos.y - (INV_VIEW_MATRIX * vec4(back, 1.0)).y;
	vec2 ruv = SCREEN_UV + nm.xy * refraction * clamp(depth_v * 4.0, 0.0, 1.0);
	vec3 back_r = scene_pos(ruv, INV_PROJECTION_MATRIX);
	if ((INV_VIEW_MATRIX * vec4(back_r, 1.0)).y > wpos.y) {
		ruv = SCREEN_UV; // do not refract things that stand out of the water
		back_r = back;
	}
	float cosv = clamp(dot(NORMAL, VIEW), 0.05, 1.0);
	float path = max(distance(back_r, VERTEX), min_depth / cosv);
	// Silty water swallows blue first, so deep water turns brown-green.
	vec3 absorb = vec3(0.9, 0.75, 1.15) * mix(2.0, 12.0, clarity);
	vec3 T = exp(-absorb * path);
	vec3 bed = textureLod(screen_tex, ruv, 0.0).rgb;

	float fres = 0.02 + 0.98 * pow(1.0 - cosv, 5.0);
	// The lit silt glows by sunlight and skylight through ALBEDO, the bed
	// (already lit) comes through EMISSION; the engine adds the reflection.
	ALBEDO = tint * (1.0 - T) * (1.0 - fres);
	EMISSION = bed * T * (1.0 - fres);
	ROUGHNESS = 0.04 + rain_amount * 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.354; // F0 = 0.16 * 0.354^2 = 0.02, real water
	ALPHA = smoothstep(0.0, shore, depth_v);
}
