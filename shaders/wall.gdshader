// Lime-washed plaster (tường vôi) as on old northern houses: a yellow wash
// over uneven render, blotched by years of rain, darkened by rising damp
// and splash-back at the foot with a green-black algae band, and streaked
// under the eaves where the roof drips.
shader_type spatial;
render_mode diffuse_burley;

global uniform float wetness;
global uniform float rain_amount;

uniform sampler2D plaster_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D plaster_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D stain_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 tint : source_color = vec3(1.0, 0.93, 0.78);
uniform float tile = 2.5;
uniform float base_y = 0.3; // where the wall meets the plinth or ground
uniform float top_y = 2.9; // eave line, for drip streaks
uniform float damp = 1.0; // 0 = no rising damp

varying vec3 wpos;
varying vec3 wnrm;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// Box-mapped tangent frame matching the uv chosen in fragment().
	if (abs(wnrm.x) > 0.5) {
		TANGENT = (inverse(MODEL_MATRIX) * vec4(0.0, 0.0, 1.0, 0.0)).xyz;
	} else {
		TANGENT = (inverse(MODEL_MATRIX) * vec4(1.0, 0.0, 0.0, 0.0)).xyz;
	}
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

void fragment() {
	// Along the wall horizontally (h) and up (y).
	float h = abs(wnrm.x) > 0.5 ? wpos.z : wpos.x;
	vec2 uv = abs(wnrm.y) > 0.7 ? wpos.xz : vec2(h, -wpos.y);
	vec3 alb = texture(plaster_alb, uv / tile).rgb * tint;
	// Faded wash: less saturated than the fresh plaster photo.
	alb = mix(vec3(dot(alb, vec3(0.3, 0.55, 0.15))), alb, 0.85) * 1.12;
	// Rain blotches and lime-wash patches from a weathered-wall photo.
	vec3 st = texture(stain_alb, uv / 3.3 + 0.21).rgb;
	float stain = dot(st, vec3(0.3, 0.55, 0.15)) / 0.21;
	alb *= mix(0.62, 1.1, clamp(stain, 0.0, 1.4) / 1.4);
	// Faint green from the mossy photo shows through in the darkest blotches.
	alb = mix(alb, alb * vec3(0.8, 0.95, 0.7), smoothstep(0.7, 0.3, stain) * 0.5);

	float y = wpos.y - base_y;
	float n = vnoise(vec2(h * 1.7, 0.0)) * 0.25 + vnoise(vec2(h * 6.0, wpos.y * 2.0)) * 0.12;
	// Rising damp: a dark tide mark with a ragged top, algae at the very foot.
	float tide = smoothstep(0.0, 0.85, y - n * 1.2);
	alb *= mix(mix(1.0, 0.52, damp), 1.0, tide);
	float algae = (1.0 - smoothstep(0.0, 0.3, y - n * 0.4)) * damp;
	alb = mix(alb, vec3(0.05, 0.065, 0.035), algae * 0.6);
	// Drip streaks under the eaves.
	float streak = smoothstep(0.55, 0.95, vnoise(vec2(h * 3.1, wpos.y * 0.25)));
	streak *= smoothstep(1.6, 0.0, top_y - wpos.y) * step(abs(wnrm.y), 0.7);
	alb *= mix(1.0, 0.68, streak);

	float wet = clamp(wetness + rain_amount * 0.3, 0.0, 1.0) * (1.0 - smoothstep(1.2, 2.0, y) * 0.6);
	ALBEDO = alb * mix(1.0, 0.65, wet);
	NORMAL_MAP = texture(plaster_nor, uv / tile).rgb;
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = mix(0.92, 0.55, wet);
	SPECULAR = 0.4;
}
