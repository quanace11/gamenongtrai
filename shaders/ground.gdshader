// Land around the farm. Near the house it is grass and trodden earth
// (Poly Haven textures); further out it turns into a patchwork of other
// families' paddies: young green rice, ripening gold, flooded plots that
// mirror the sky, and stubble, divided by grassy bunds.
shader_type spatial;

uniform sampler2D grass_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_arm : filter_linear_mipmap, repeat_enable;
uniform sampler2D path_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D path_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec2 near_half = vec2(36.0, 40.0);
uniform float plot = 14.0;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void fragment() {
	vec2 p = wpos.xz;
	float n = vnoise(p * 0.15) * 0.6 + vnoise(p * 0.6) * 0.4;

	// Near: grass with worn patches.
	vec2 uv = p / 3.0;
	vec3 ga = texture(grass_alb, uv).rgb;
	vec3 gn = texture(grass_nor, uv).rgb;
	vec3 go = texture(grass_arm, uv).rgb;
	float worn = smoothstep(0.62, 0.75, n);
	ga = mix(ga, texture(path_alb, uv * 0.7).rgb, worn);
	gn = mix(gn, texture(path_nor, uv * 0.7).rgb, worn);
	ga *= vec3(0.62, 0.95, 0.42) * mix(0.95, 1.25, vnoise(p * 0.05));

	// Far: paddies on a jittered grid.
	vec2 q = p / plot;
	vec2 cell = floor(q);
	vec2 f = fract(q);
	float h = hash(cell);
	float bund = 1.0 - smoothstep(0.015, 0.035, min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)));
	vec3 young = vec3(0.07, 0.22, 0.02);
	vec3 ripe = vec3(0.45, 0.3, 0.05);
	vec3 col;
	float rough = 0.85;
	if (h < 0.45) {
		col = mix(young, vec3(0.15, 0.32, 0.03), hash(cell + 1.3));
	} else if (h < 0.7) {
		col = mix(vec3(0.25, 0.3, 0.04), ripe, hash(cell + 2.1));
	} else if (h < 0.88) {
		col = texture(mud_alb, p / 4.0).rgb * 0.25 + vec3(0.01, 0.015, 0.02);
		rough = 0.08; // flooded, reflects the sky
	} else {
		col = vec3(0.27, 0.18, 0.07);
	}
	// Transplanted rows, faded out where they would shimmer.
	float rows = sin(dot(p, vec2(cos(h * 6.28), sin(h * 6.28))) * 25.0);
	float fw = fwidth(p.x) * 25.0;
	col *= 1.0 + rows * 0.08 * (1.0 - clamp(fw, 0.0, 1.0)) * step(h, 0.7);
	col *= mix(0.9, 1.08, n);
	col = mix(col, vec3(0.09, 0.17, 0.03), bund);
	rough = mix(rough, 0.9, bund);

	vec2 r = abs(p) / near_half;
	float far = smoothstep(0.92, 1.05, max(r.x, r.y) + (n - 0.5) * 0.12);
	ALBEDO = mix(ga, col, far);
	NORMAL_MAP = mix(gn, vec3(0.5, 0.5, 1.0), far);
	AO = mix(go.r, 1.0, far);
	ROUGHNESS = mix(go.g, rough, far);
	SPECULAR = 0.5;
}
