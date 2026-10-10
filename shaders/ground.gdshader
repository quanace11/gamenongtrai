// Land around the farm. Near the house it is a lawn of short grass with
// bare patches, trodden earth paths between the yard, the field, the pond
// and the pens, muddy banks that turn dark and glossy at the water line.
// Further out it turns into a patchwork of other families' paddies: young
// green rice and ripening gold standing proud of flooded plots that mirror
// the sky. On the far mesh (relief = true) the plots are raised in vertex()
// so they cast relief and silhouettes into the haze.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

global uniform float rain_amount;
global uniform float wetness;

uniform sampler2D grass_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_arm : filter_linear_mipmap, repeat_enable;
uniform sampler2D earth_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D earth_arm : filter_linear_mipmap, repeat_enable;
uniform sampler2D mud_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_arm : filter_linear_mipmap, repeat_enable;

uniform bool relief = false;
// Near terrain mesh [x0, z0, x1, z1]; relief fades in beyond it.
uniform vec4 near_rect = vec4(-40.0, -44.0, 40.0, 36.0);
uniform vec2 near_half = vec2(36.0, 38.0);
uniform vec4 field_rect = vec4(-8.0, -8.0, 8.0, 8.0);
uniform vec4 court_rect = vec4(-6.0, -20.0, 6.0, -14.0);
uniform vec2 canal = vec2(-11.0, 1.0); // centre x, half width
uniform vec3 pond = vec3(-20.0, -10.0, 4.5); // x, z, r
uniform vec3 wallow = vec3(-3.0, 12.5, 1.6); // buffalo's trampled patch
uniform vec4 paths[16]; // segment a.xy -> b.xy, trodden earth
uniform float path_w[16];
uniform int path_count = 0;

varying vec3 wpos;
varying float plot_lift;

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
	return vnoise(p) * 0.5 + vnoise(p * 2.03 + 1.7) * 0.3 + vnoise(p * 4.1 + 3.1) * 0.2;
}

float rect_sd(vec2 p, vec4 r) {
	vec2 d = max(r.xy - p, p - r.zw);
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

// Must match layout.gd pond_r().
float pond_r(vec2 p) {
	float a = atan(p.y - pond.y, p.x - pond.x);
	return pond.z * (1.0 + 0.09 * sin(a * 2.0 - 1.57) + 0.05 * sin(a * 3.0 - 0.5) + 0.03 * sin(a * 5.0 - 0.3));
}

// Far paddies: long strips of uneven width, rows shifted against each other.
// Returns the plot's hash; f = position inside the plot, e = metres to its edge.
float plot_at(vec2 p, out vec2 f, out float e) {
	vec2 ps = vec2(19.0, 11.0);
	float row = floor(p.y / ps.y);
	float off = hash(vec2(row, 7.0)) * ps.x;
	vec2 q = vec2((p.x + off) / ps.x, p.y / ps.y);
	vec2 cell = floor(q);
	f = fract(q);
	vec2 m = min(f, 1.0 - f) * ps;
	e = min(m.x, m.y);
	return hash(cell + vec2(row * 0.37, 0.0));
}

// Height of the rice canopy above the plot floor.
float canopy(float h) {
	if (h < 0.45) return 0.25 + 0.2 * fract(h * 17.0); // young
	if (h < 0.7) return 0.6 + 0.25 * fract(h * 23.0); // ripening
	if (h < 0.88) return 0.0; // flooded
	return 0.04; // stubble
}

float lift_at(vec2 p) {
	vec2 f;
	float e;
	float h = plot_at(p, f, e);
	float edge = max(rect_sd(p, near_rect), 0.0);
	float mask = smoothstep(4.0, 14.0, edge) * smoothstep(3.0, 8.0, abs(p.x - canal.x) - canal.y);
	return canopy(h) * smoothstep(0.3, 1.4, e) * mask;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	plot_lift = 0.0;
	if (relief) {
		float l = lift_at(wpos.xz);
		float lx = lift_at(wpos.xz + vec2(0.6, 0.0));
		float lz = lift_at(wpos.xz + vec2(0.0, 0.6));
		VERTEX.y += l;
		wpos.y += l;
		plot_lift = l;
		NORMAL = normalize(vec3(l - lx, 0.6, l - lz));
	}
	// World-aligned tangent frame for the world-space texture coordinates.
	TANGENT = normalize(vec3(1.0, 0.0, 0.0) - NORMAL * NORMAL.x);
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

// Two lookups per layer, the second rotated and at another scale, chosen by
// a soft noise mask so the 1k textures don't show a repeat grid.
#define TWO(tex, a, b) mix(texture(tex, a), texture(tex, b), tm)

vec3 unrotate_normal(vec3 n) {
	// The second lookup's uv is rotated by R = [0.8 -0.6; 0.6 0.8]; turn its
	// tangent-space normal back by R^T so the lighting stays consistent.
	vec2 xy = n.xy * 2.0 - 1.0;
	xy = vec2(0.8 * xy.x + 0.6 * xy.y, -0.6 * xy.x + 0.8 * xy.y);
	return vec3(xy * 0.5 + 0.5, n.z);
}

void fragment() {
	vec2 p = wpos.xz;
	float dist = length(VERTEX);
	float n = fbm(p * 0.15);
	float tm = smoothstep(0.35, 0.65, vnoise(p * 0.11 + 4.0));
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));

	// ---- near: grass, trodden earth, mud
	vec2 ug1 = p / 2.3;
	vec2 ug2 = rot * p / 3.4 + 0.37;
	vec3 ga = TWO(grass_alb, ug1, ug2).rgb;
	vec3 gn = mix(texture(grass_nor, ug1).rgb, unrotate_normal(texture(grass_nor, ug2).rgb), tm);
	vec3 go = TWO(grass_arm, ug1, ug2).rgb;
	// A second, much larger sample fades in with distance to hide repeats.
	ga = mix(ga, texture(grass_alb, p / 9.1).rgb, smoothstep(8.0, 30.0, dist) * 0.5);
	// The photo is a brown autumn lawn; push it to the humid delta green
	// (about sRGB 96,119,47) while keeping its blade detail.
	float gl = dot(ga, vec3(0.3, 0.55, 0.15));
	vec3 lawn = vec3(0.115, 0.17, 0.03) * mix(ga / vec3(0.079, 0.046, 0.009), vec3(gl / 0.05), 0.55);
	// Macro patches: lusher, drier and sun-bleached grass.
	float m1 = vnoise(p * 0.045 + 9.0);
	float m2 = fbm(p * 0.012 + 3.0);
	lawn *= mix(0.78, 1.12, m2);
	lawn = mix(lawn, lawn * vec3(1.35, 1.12, 0.8), smoothstep(0.55, 0.85, m1) * 0.7);
	lawn = mix(lawn, lawn * vec3(0.8, 0.95, 0.7), smoothstep(0.5, 0.2, m1) * 0.5);

	vec2 ue1 = p / 2.0;
	vec2 ue2 = rot * p / 2.9 + 0.71;
	vec3 ea = TWO(earth_alb, ue1, ue2).rgb * vec3(0.95, 0.9, 0.85);
	vec3 en = mix(texture(earth_nor, ue1).rgb, unrotate_normal(texture(earth_nor, ue2).rgb), tm);
	vec3 eo = TWO(earth_arm, ue1, ue2).rgb;
	vec2 um1 = p / 2.2;
	vec2 um2 = rot * p / 3.1 + 0.13;
	vec3 ma = TWO(mud_alb, um1, um2).rgb * vec3(0.95, 0.95, 1.0);
	vec3 mn = mix(texture(mud_nor, um1).rgb, unrotate_normal(texture(mud_nor, um2).rgb), tm);
	vec3 mo = TWO(mud_arm, um1, um2).rgb;

	// Masks from the layout. Edges are broken up by noise.
	float edge_n = (fbm(p * 1.3) - 0.5) * 0.5;
	float path = 0.0;
	for (int i = 0; i < path_count; i++) {
		vec2 a = paths[i].xy;
		vec2 b = paths[i].zw;
		vec2 ab = b - a;
		float t = clamp(dot(p - a, ab) / max(dot(ab, ab), 1e-4), 0.0, 1.0);
		float d = length(p - a - ab * t);
		float w = max(path_w[i] * 0.5, 0.05);
		path = max(path, 1.0 - smoothstep(w * 0.55, w * 1.25, d + edge_n * w));
	}
	float court_d = rect_sd(p, court_rect);
	path = max(path, (1.0 - smoothstep(0.2, 1.4, court_d + edge_n)) * 0.85);
	float fd = rect_sd(p, field_rect);
	// Bund crown: trodden earth with grass creeping in from the sides.
	float crown = (1.0 - smoothstep(0.15, 0.3, abs(fd - 0.425) + edge_n * 0.2)) * step(fd, 1.0);
	path = max(path, crown * (0.55 + 0.4 * vnoise(p * 2.0)));
	float mud = (1.0 - smoothstep(0.15, 0.32, fd + edge_n * 0.1)) * step(-0.5, fd); // steep paddy side
	float cd = abs(p.x - canal.x);
	mud = max(mud, 1.0 - smoothstep(0.75, 1.4, cd + edge_n * 0.3));
	float pd = length(p - pond.xy);
	float pr = pond_r(p);
	mud = max(mud, 1.0 - smoothstep(0.35, 0.95, pd - pr + edge_n * 0.4));
	mud = max(mud, 1.0 - smoothstep(wallow.z * 0.6, wallow.z, length(p - wallow.xy) + edge_n));
	path *= 1.0 - mud;

	vec3 alb = mix(lawn, ea, path);
	vec3 nor = mix(gn, en, path);
	vec3 arm = mix(go, eo, path);
	alb = mix(alb, ma, mud);
	nor = mix(nor, mn, mud);
	arm = mix(arm, mo, mud);
	alb *= mix(0.9, 1.06, n);

	// Wet: below the water lines everything is soaked; grass around the
	// pond stays damp. The wetness global darkens it all after rain.
	float wet = 1.0 - smoothstep(-0.13, -0.025, wpos.y);
	float damp = (1.0 - smoothstep(0.0, 1.5, pd - pr)) * 0.6;
	damp = max(damp, (1.0 - smoothstep(0.9, 1.6, cd)) * 0.4);
	float w_all = clamp(max(max(wet, damp), wetness * 0.8 + rain_amount * 0.2), 0.0, 1.0);
	alb *= mix(1.0, 0.5, w_all);
	float rough = mix(arm.g, 0.22, max(wet, wetness * 0.5) * 0.85);

	// ---- far: paddies, jittered strips of plots
	vec2 f;
	float e;
	float h = plot_at(p, f, e);
	float bund = 1.0 - smoothstep(0.18, 0.45, e);
	vec3 young = vec3(0.10, 0.20, 0.035);
	vec3 ripe = vec3(0.40, 0.30, 0.08);
	vec3 col;
	float frough = 0.8;
	float fspec = 0.5;
	bool flooded = false;
	if (h < 0.45) {
		col = mix(young, vec3(0.14, 0.26, 0.04), hash(vec2(h, 1.3)));
	} else if (h < 0.7) {
		col = mix(vec3(0.26, 0.28, 0.05), ripe, hash(vec2(h, 2.1)));
	} else if (h < 0.88) {
		col = texture(mud_alb, p / 4.0).rgb * 0.18 + vec3(0.008, 0.012, 0.014);
		frough = 0.03; // flooded, mirrors the sky
		fspec = 0.35; // water F0 0.02
		flooded = true;
	} else {
		col = vec3(0.22, 0.17, 0.08);
	}
	// Transplanted rows, faded out where they would shimmer.
	vec2 dir = vec2(cos(h * 6.28), sin(h * 6.28));
	float rows = sin(dot(p, dir) * 25.0);
	float fw = fwidth(p.x) * 25.0;
	col *= 1.0 + rows * 0.08 * (1.0 - clamp(fw, 0.0, 1.0)) * step(h, 0.7);
	col *= mix(0.85, 1.1, fbm(p * 0.35 + h * 10.0)); // clumpy canopy
	col *= mix(0.92, 1.05, n);
	col = mix(col, vec3(0.09, 0.15, 0.035), bund);
	frough = mix(frough, 0.9, bund);
	fspec = mix(fspec, 0.5, bund);
	// The sides of raised canopies are darker (self-shadowed stems).
	col *= mix(0.6, 1.0, smoothstep(0.4, 0.9, NORMAL.y));

	vec2 r = abs(p - vec2(0.0, -4.0)) / near_half;
	float far = smoothstep(0.92, 1.04, max(r.x, r.y) + (n - 0.5) * 0.1);
	if (relief) far = 1.0;
	ALBEDO = mix(alb, col, far);
	NORMAL_MAP = mix(nor, vec3(0.5, 0.5, 1.0), far);
	NORMAL_MAP_DEPTH = mix(1.0, 0.4, wet);
	AO = mix(arm.r, 1.0, far);
	ROUGHNESS = mix(rough, flooded ? frough : mix(frough, 0.25, wetness * 0.6), far);
	SPECULAR = mix(mix(0.5, 0.4, wet), fspec, far);
}
