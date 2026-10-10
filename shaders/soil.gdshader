// The paddy floor, and the flooded paddy's water. Vertex colour carries the
// simulation: R = how well the soil is hoed, G = how smooth the harrowed mud
// is, B = a crack; A = 0 marks the skirt along the bunds (see field.gd). It
// blends three Poly Haven texture sets: cracked dry earth, hoed clods and
// puddled mud.
//
// Water is decided per pixel: wherever the soil lies below water_y it is
// shaded as an OPAQUE, mirror-calm, silty water surface and its depth is
// moved up onto the water plane. Being opaque, it gets Godot 4.6's
// screen-space reflections (rice, bunds, bamboo, the house) and the box
// ReflectionProbe; the parts of rice stems, stakes and bund faces under the
// water are hidden by it, as in a real muddy paddy.
shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D dry_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dry_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D dry_arm : filter_linear_mipmap, repeat_enable;
uniform sampler2D till_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D till_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D till_arm : filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_arm : filter_linear_mipmap, repeat_enable;
uniform float tile = 2.5;
uniform float wet = 0.0; // 0 dry field .. 1 flooded
// Albedo calibration. The cracked-earth photo averages a salmon (0.63, 0.40,
// 0.23) linear; dry Red River silt is a grey-brown of about 0.2-0.27.
uniform vec3 dry_tint = vec3(0.42, 0.50, 0.62);
uniform vec3 till_tint = vec3(0.95, 1.1, 1.35);
uniform vec3 mud_tint = vec3(1.0, 1.0, 1.05);

// Water: world height of the surface (-10 = dry), the silt colour of the
// water body and how fast it swallows the mud below (per metre).
uniform float water_y = -10.0;
uniform vec3 silt : source_color = vec3(0.33, 0.31, 0.25);
uniform float murk = 28.0;
uniform sampler2D wave_a : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wave_b : hint_normal, filter_linear_mipmap, repeat_enable;

global uniform float rain_amount;
global uniform float wetness;
global uniform float wind_gust;
global uniform vec2 wind_dir;
global uniform vec3 player_pos;

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
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Rain rings: one per cell, restarting at random times; three sizes.
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

void fragment() {
	vec2 uv = wpos.xz / tile;
	float t = smoothstep(0.15, 0.85, COLOR.r);
	float s = smoothstep(0.2, 0.9, COLOR.g);
	bool skirt = COLOR.a < 0.5;
	vec3 a = mix(texture(dry_alb, uv * 0.8).rgb * dry_tint, texture(till_alb, uv).rgb * till_tint, t);
	vec3 n = mix(texture(dry_nor, uv * 0.8).rgb, texture(till_nor, uv).rgb, t);
	vec3 o = mix(texture(dry_arm, uv * 0.8).rgb, texture(till_arm, uv).rgb, t);
	a = mix(a, texture(mud_alb, uv * 1.2).rgb * mud_tint, s);
	n = mix(n, texture(mud_nor, uv * 1.2).rgb, s);
	o = mix(o, texture(mud_arm, uv * 1.2).rgb, s);

	// The soil mesh has no tangents: build the frame of the planar UVs.
	TANGENT = normalize((VIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	BINORMAL = normalize((VIEW_MATRIX * vec4(0.0, 0.0, -1.0, 0.0)).xyz);

	// Wet soil is darker and glossier: flooded field, puddled mud, rain, and
	// a damp band just above the water line.
	float depth = water_y - wpos.y; // > 0 under water
	float damp = 1.0 - smoothstep(0.0, 0.05, -depth);
	float w = clamp(max(max(wet + s * 0.5, wetness * 0.9), damp), 0.0, 1.0);
	vec3 soil = a * mix(1.0, 0.5, w);
	float soil_rough = mix(o.g, 0.22, w * 0.85);

	// --- water -------------------------------------------------------------
	// Anti-aliased waterline from the screen-space change of the depth.
	float sub = clamp(depth / max(fwidth(depth) * 1.5, 1e-4) + 0.5, 0.0, 1.0);
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 V = normalize(cam - wpos);
	// Murky water: the refracted ray's path to the mud (Snell, n = 1.333).
	float cosi = max(V.y, 0.05);
	float sint = sqrt(1.0 - cosi * cosi) / 1.333;
	float path = max(depth, 0.0) / sqrt(1.0 - sint * sint);
	float T = exp(-murk * path);
	vec3 under = soil * T + silt * (1.0 - T);

	// Surface: almost still. Slow fine ripples, cat's-paw gust patches
	// drifting with the wind, rain rings, rings around the player's legs.
	float tm = TIME;
	vec2 p = wpos.xz;
	vec2 wd = normalize(wind_dir + vec2(1e-4));
	float gust = smoothstep(0.5, 0.9, vnoise(p * 0.11 - wd * tm * 0.22)) * wind_gust;
	vec3 n1 = texture(wave_a, p * 0.23 + wd * tm * 0.015).xyz * 2.0 - 1.0;
	vec3 n2 = texture(wave_b, p * 0.61 - vec2(tm * 0.011, -tm * 0.017)).xyz * 2.0 - 1.0;
	vec2 slope = (n1.xy + n2.xy * 0.6) * (0.012 + 0.05 * gust);
	slope += ripples(p, tm) * rain_amount * 0.22;
	vec2 pd = p - player_pos.xz;
	float pr = length(pd);
	if (pr < 3.0 && player_pos.y < water_y) {
		float wave = sin(pr * 18.0 - tm * 7.0) * exp(-pr * 1.4) * smoothstep(0.15, 0.4, pr);
		slope += pd / max(pr, 1e-3) * wave * 0.05;
	}
	vec3 nw = normalize(vec3(slope.x, 1.0, slope.y));

	// Seen from the camera, the surface is the water plane, not the mud: put
	// the depth there so SSR starts from it and things under it are hidden.
	float plane_depth = FRAGCOORD.z;
	if (depth > 0.0 && cam.y > water_y + 0.01) {
		vec3 ray = wpos - cam;
		vec3 hit = cam + ray * clamp((water_y - cam.y) / min(ray.y, -1e-4), 0.0, 1.0);
		vec4 clip = PROJECTION_MATRIX * (VIEW_MATRIX * vec4(hit, 1.0));
		plane_depth = clip.z / clip.w;
	}
	DEPTH = sub > 0.5 ? plane_depth : FRAGCOORD.z;

	NORMAL = normalize(mix(NORMAL, (VIEW_MATRIX * vec4(nw, 0.0)).xyz, sub));
	NORMAL_MAP = mix(n, vec3(0.5, 0.5, 1.0), sub);
	NORMAL_MAP_DEPTH = mix(1.0, 0.5, w);
	ALBEDO = mix(soil, under, sub);
	AO = mix(o.r, 1.0, sub);
	AO_LIGHT_AFFECT = mix(0.3, 0.0, sub);
	ROUGHNESS = mix(soil_rough, 0.035 + 0.05 * rain_amount + 0.035 * gust, sub);
	SPECULAR = mix(0.5, 0.354, sub); // water: F0 = 0.16 * 0.354^2 = 0.02
	METALLIC = 0.0;
	// The skirt only exists to carry the water surface in front of the
	// submerged bund faces.
	if (skirt && depth <= 0.0) {
		discard;
	}
}
