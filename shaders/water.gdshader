// Still, shallow water for the paddy, the canal and the pond: two
// scrolling normal maps for the breeze, rain ripples when it rains, and a
// Fresnel term so the sky reflects at grazing angles.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, specular_schlick_ggx;

uniform vec3 tint : source_color = vec3(0.32, 0.36, 0.26);
uniform float clarity = 0.55; // alpha looking straight down
uniform float scale = 0.35;
uniform float wind = 1.0;
global uniform float rain_amount;
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap, repeat_enable;

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
	for (int k = 0; k < 2; k++) {
		vec2 q = p * (2.2 + float(k) * 1.3) + float(k) * 7.31;
		vec2 cell = floor(q);
		vec2 f = fract(q) - 0.5;
		float h = hash(cell);
		vec2 c = (vec2(hash(cell + 3.1), hash(cell + 5.7)) - 0.5) * 0.6;
		float ph = fract(t * (1.1 + h) + h);
		vec2 d = f - c;
		float r = length(d);
		float ring = sin((r - ph * 0.45) * 60.0) * smoothstep(0.0, 0.05, ph * 0.45 - r + 0.05) * smoothstep(0.45, 0.0, r) * (1.0 - ph);
		g += normalize(d + 1e-4) * ring;
	}
	return g;
}

void fragment() {
	vec2 p = wpos.xz * scale;
	float t = TIME * wind;
	vec3 n1 = texture(wave_a, p * 0.6 + vec2(t * 0.02, t * 0.013)).xyz * 2.0 - 1.0;
	vec3 n2 = texture(wave_b, p * 1.3 - vec2(t * 0.017, -t * 0.021)).xyz * 2.0 - 1.0;
	vec3 n = normalize(vec3(n1.xy + n2.xy, 4.0));
	if (rain_amount > 0.0) {
		n.xy += ripples(wpos.xz, TIME) * rain_amount * 0.6;
		n = normalize(n);
	}
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	ALBEDO = tint;
	ROUGHNESS = 0.04 + rain_amount * 0.08;
	METALLIC = 0.0;
	SPECULAR = 0.7;
	ALPHA = clamp(mix(clarity, 1.0, fres), 0.0, 1.0);
}
