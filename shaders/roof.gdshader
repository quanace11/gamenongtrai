// Ngói ta: small fired-clay tiles at their real size (about 20 cm), aged to
// a dull brown-red, blackened by lichen in patches, greened with moss
// toward the eaves and streaked down the slope where rain runs off.
// Texture coordinates come from the slab's own (local) x and z, so the
// tile rows follow the slope.
shader_type spatial;
render_mode diffuse_burley;

global uniform float wetness;
global uniform float rain_amount;

uniform sampler2D tile_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tile_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tile_arm : filter_linear_mipmap, repeat_enable;
uniform float tile = 2.4;
uniform float half_len = 2.5; // half the slab length down the slope
uniform float eave_sign = 1.0; // which local z end is the eave

varying vec3 lpos;
varying vec3 lnrm;

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
	lpos = VERTEX;
	lnrm = NORMAL;
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, 1.0);
}

void fragment() {
	vec2 uv = lpos.xz / tile;
	if (abs(lnrm.y) < 0.5) {
		uv = vec2(lpos.x + lpos.z, lpos.y) / tile;
	}
	vec3 a = texture(tile_alb, uv).rgb;
	// Weathered: less saturated, browner and darker than new terracotta.
	float l = dot(a, vec3(0.3, 0.55, 0.15));
	a = mix(vec3(l), a, 0.42) * vec3(1.05, 1.0, 0.95);
	float down = clamp(lpos.z * eave_sign / half_len * 0.5 + 0.5, 0.0, 1.0); // 0 ridge .. 1 eave
	float lichen = smoothstep(0.5, 0.8, fbm(lpos.xz * vec2(0.9, 0.6)));
	a = mix(a, vec3(0.035, 0.032, 0.03), lichen * 0.65);
	float moss = smoothstep(0.45, 0.75, fbm(lpos.xz * 1.3 + 5.0)) * smoothstep(0.4, 1.0, down);
	a = mix(a, vec3(0.06, 0.075, 0.025), moss * 0.6);
	// Run-off streaks down the slope.
	float streak = smoothstep(0.45, 0.9, vnoise(vec2(lpos.x * 2.3, lpos.z * 0.15)));
	a *= mix(1.0, 0.7, streak * down);
	a *= mix(0.85, 1.08, vnoise(lpos.xz * 0.35));

	float wet = clamp(wetness + rain_amount, 0.0, 1.0);
	vec3 arm = texture(tile_arm, uv).rgb;
	ALBEDO = a * mix(1.0, 0.6, wet);
	NORMAL_MAP = texture(tile_nor, uv).rgb;
	AO = arm.r;
	ROUGHNESS = mix(clamp(arm.g * 1.1, 0.6, 1.0), 0.3, wet);
	SPECULAR = 0.4;
}
