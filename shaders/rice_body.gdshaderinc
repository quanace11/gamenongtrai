// Rice hills (scripts/rice_hill.gd), shared by rice.gdshader (leaves, culms,
// far panicles) and rice_panicle.gdshader (near panicles, alpha scissor).
// Stays in the opaque pass: no alpha to coverage, so the paddy keeps its
// motion vectors and screen-space reflections of the rice.
// Per hill INSTANCE_CUSTOM = (maturity offset -1..1, stress factor, random,
// random). Colour runs from pale transplant green to deep tillering green to
// straw gold; senescence starts at the lowest leaves and the tips, the flag
// leaf stays green longest. Wind uses the same scrolling gust noise as the
// lawn so gust waves roll across the paddy (sóng lúa).
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;
#ifdef PANICLE_PASS
uniform sampler2D grain_tex : filter_linear_mipmap, repeat_disable;
#endif

global uniform float wind_gust;
global uniform vec2 wind_dir;
global uniform vec3 player_pos;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float stage = 0.45;          // 0 transplant .. 0.45 tillering .. 1 ripe
uniform float ripe = 0.0;            // 0 green .. 1 golden
uniform float plant_height = 0.7;    // metres, scales the wind bend
uniform float water_y = -100.0;      // world y of the paddy water (or far below)
uniform float stubble = 0.0;         // 1: cut straw
uniform float stress = 0.0;          // yellowing from pests and poor health

uniform vec3 c_young : source_color = vec3(0.56, 0.70, 0.25);
uniform vec3 c_lush : source_color = vec3(0.25, 0.47, 0.10);
uniform vec3 c_sheath : source_color = vec3(0.66, 0.72, 0.44);
uniform vec3 c_straw : source_color = vec3(0.80, 0.66, 0.34);
uniform vec3 c_tip : source_color = vec3(0.55, 0.42, 0.23);
uniform vec3 c_chlorotic : source_color = vec3(0.76, 0.72, 0.32);
uniform vec3 c_grain_green : source_color = vec3(0.56, 0.64, 0.26);
uniform vec3 c_grain_gold : source_color = vec3(0.85, 0.65, 0.26);
uniform vec3 c_mud_water : source_color = vec3(0.15, 0.13, 0.08);

varying vec4 v_state;
varying float v_wy;

void vertex() {
	v_state = INSTANCE_CUSTOM;
	vec3 root = MODEL_MATRIX[3].xyz;
	float hrel = COLOR.a;
	vec2 wuv = root.xz * 0.035 - wind_dir * TIME * (0.04 + 0.03 * wind_gust);
	float gust = textureLod(noise, wuv, 0.0).r;
	float sway = (0.15 + 0.85 * smoothstep(0.35, 0.8, gust)) * wind_gust;
	float flutter = sin(TIME * (2.4 + 2.6 * COLOR.b) + COLOR.b * 6.2832 + dot(root.xz, wind_dir) * 1.3);
	// heavy ripe panicles lag and swing more
	float heavy = step(0.75, COLOR.r) * (0.5 + ripe);
	float bend = pow(hrel, 1.8) * plant_height * (0.09 * sway * (1.0 + heavy) + 0.018 * flutter);
	// leaf tips flutter on their own
	bend += UV.y * UV.y * 0.015 * flutter * wind_gust * (1.0 - step(0.25, COLOR.r));
	vec3 off = vec3(wind_dir.x, 0.0, wind_dir.y) * bend;
	// wading through the paddy parts the rice
	vec2 away = root.xz - player_pos.xz;
	float pd = max(length(away), 1e-3);
	float push = (1.0 - smoothstep(0.2, 0.65, pd)) * step(abs(player_pos.y - root.y), 1.2);
	off.xz += away / pd * push * pow(hrel, 1.5) * plant_height * 0.45;
	off.y -= 0.5 * dot(off.xz, off.xz) / max(hrel * plant_height, 0.05);
	// world offset back to model space without a 4x4 inverse (rotation + uniform scale)
	mat3 m = mat3(MODEL_MATRIX);
	VERTEX += transpose(m) * off / dot(m[0], m[0]);
	v_wy = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float organ = COLOR.r;
	float rank = COLOR.g;
	float rnd = COLOR.b;
	float t = UV.y;
	float mat = clamp(ripe + v_state.x * 0.12 * (0.3 + ripe * (1.0 - ripe) * 2.8), 0.0, 1.0);
	float st = stress * v_state.y;
	// per hill and per blade hue / value jitter
	vec3 green = mix(c_young, c_lush, smoothstep(0.04, 0.4, stage + v_state.x * 0.04));
	green *= mix(vec3(1.06, 1.02, 0.86), vec3(0.93, 1.0, 1.08), rnd) * (0.88 + 0.22 * fract(rnd * 7.31 + v_state.z));
	green *= 0.94 + 0.12 * v_state.w;
	vec3 col;
	if (organ > 0.75) {
		col = mix(c_grain_green, c_grain_gold, smoothstep(0.1, 0.85, mat));
		col *= 0.9 + 0.2 * fract(rnd * 3.7 + v_state.z);
		// a few darker, rust-tinged grains
		col = mix(col, col * vec3(0.8, 0.66, 0.5), smoothstep(0.72, 1.0, fract(rnd * 13.7 + rank * 3.1)) * mat);
	} else {
		col = mix(c_sheath, green, organ < 0.25 ? smoothstep(0.0, 0.25, t) : 0.15);
		// senescence: lower leaves first, from the tip down
		float sen = clamp(mat * (0.5 + 0.95 * rank) + (t - 0.55) * 0.9 * mat - 0.12, 0.0, 1.0);
		col = mix(col, c_straw * (0.92 + 0.16 * rnd), smoothstep(0.12, 0.85, sen));
		// dry tips: transplant shock on seedlings, age on ripe rice
		float tipdry = max(0.25 + 0.75 * sen, (1.0 - smoothstep(0.0, 0.12, stage)) * step(0.55, fract(rnd * 5.3)));
		col = mix(col, c_tip, smoothstep(0.86, 1.0, t) * tipdry);
		col = mix(col, c_chlorotic, clamp(st * (0.35 + 0.65 * rank), 0.0, 1.0));
		// midrib and fine parallel veins
		float mid = 1.0 - smoothstep(0.0, 0.12, abs(UV.x - 0.5));
		col *= (1.0 + 0.1 * mid * (1.0 - step(0.25, organ))) * (0.97 + 0.03 * sin(UV.x * 70.0));
		// stubble: weathered grey-buff straw, darker cut ends soaked at the
		// base, and now and then a green ratoon shoot (lúa chét)
		// (literal colours here are sRGB, hence the pow)
		vec3 straw = pow(mix(vec3(0.52, 0.45, 0.31), vec3(0.66, 0.56, 0.36), fract(rnd * 5.7 + v_state.z)), vec3(2.2)) * mix(0.7, 1.0, t);
		straw = mix(straw, c_young * 0.85, step(0.88, fract(rnd * 11.3 + v_state.w)) * step(organ, 0.25));
		col = mix(col, straw, stubble);
	}
	// below and just above the water line: wet, darker, muddy
	float under = 1.0 - smoothstep(water_y - 0.004, water_y + 0.004, v_wy);
	float wetband = 1.0 - smoothstep(water_y, water_y + 0.03, v_wy);
	col = mix(col, col * 0.62, wetband);
	col = mix(col, c_mud_water + col * 0.15, under);
#ifdef PANICLE_PASS
	vec4 g = texture(grain_tex, UV);
	col *= g.r * 1.25;
	ALPHA = g.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
#endif
	ALBEDO = col;
	ROUGHNESS = mix(0.45, 0.62, max(mat, stubble));
	SPECULAR = 0.42;
	ANISOTROPY = 0.4 * (1.0 - under) * (1.0 - step(0.75, organ));
	BACKLIGHT = col * mix(0.5, 0.28, mat) * (1.0 - under);
	AO = mix(0.35, 1.0, smoothstep(0.0, 0.75, COLOR.a));
	AO_LIGHT_AFFECT = 0.5;
}
