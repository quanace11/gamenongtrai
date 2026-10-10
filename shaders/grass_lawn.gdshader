// Lawn grass that follows the camera (scripts/grass_lawn.gd). One MultiMesh
// instance = one blade. Instance transforms are not used: each blade takes
// its cell from INSTANCE_ID and the grid wraps around the main camera every
// frame (a toroidal grid in world space), so there is no CPU work per frame.
// Density, dryness and height come from a mask painted from layout.gd; the
// root sits on a height map of layout.ground_y. Alpha-free geometry, so it
// stays in the opaque pass; it never casts shadows.
shader_type spatial;
render_mode cull_disabled, world_vertex_coords, diffuse_lambert_wrap, specular_schlick_ggx;

global uniform float wind_gust;
global uniform vec2 wind_dir;
global uniform vec3 player_pos;
global uniform float wetness;

uniform int grid = 192;              // blades per side
uniform float patch_size = 24.0;     // wrap period in metres
uniform float fade_start = 8.5;      // must stay < patch_size / 2
uniform float fade_end = 11.5;
uniform vec2 fade_in = vec2(0.0);    // far patch: grow in where the near one fades out
uniform vec4 map_rect = vec4(-40.0, -44.0, 80.0, 80.0); // x0, z0, width, depth
uniform sampler2D grass_mask : filter_linear, repeat_disable;  // R density, G dryness, B tall, A trodden
uniform sampler2D height_map : filter_linear, repeat_disable;  // R ground height (m)
uniform sampler2D noise : filter_linear_mipmap, repeat_enable; // shared wind / patch noise
uniform float blade_height = 0.2;
uniform float blade_width = 0.0028;  // half width at the root
uniform float far_widen = 1.6;       // extra width at fade_end, against shimmer
uniform vec3 lush : source_color = vec3(0.18, 0.36, 0.08);
uniform vec3 fresh : source_color = vec3(0.38, 0.54, 0.16);
uniform vec3 dry : source_color = vec3(0.60, 0.53, 0.31);
uniform vec3 soil : source_color = vec3(0.30, 0.25, 0.17);

varying vec3 v_col;
varying float v_t;

uint pcg(uint v) {
	uint s = v * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	return (w >> 22u) ^ w;
}

float rnd(uint seed) {
	return float(pcg(seed)) * (1.0 / 4294967295.0);
}

void vertex() {
	uint id = uint(INSTANCE_ID);
	uint g = uint(grid);
	uint bi = uint(UV2.x + 0.5); // blade within the tuft
	uint sd = id * 23u + bi * 7u;
	float r0 = rnd(id * 5u);
	float r1 = rnd(id * 5u + 1u);
	float r2 = rnd(id * 5u + 2u);
	float r3 = rnd(sd + 3u);
	float r4 = rnd(sd + 4u);
	float r5 = rnd(sd + 5u);
	float spacing = patch_size / float(grid);
	vec2 lay = (vec2(float(id % g), float(id / g)) + vec2(r0, r1)) * spacing;
	// the tuft's blades stand a few cm apart around the cell point
	float ba = r5 * 6.2832;
	lay += vec2(cos(ba), sin(ba)) * spacing * (0.2 + 0.15 * r4) * float(bi > 0u);
	// The main camera even in shadow and probe passes, so the patch never jumps.
	vec3 cam = MAIN_CAM_INV_VIEW_MATRIX[3].xyz;
	vec2 rel = mod(lay - cam.xz + 0.5 * patch_size, patch_size) - 0.5 * patch_size;
	vec2 root = cam.xz + rel;
	float dist = length(rel);
	vec2 muv = (root - map_rect.xy) / map_rect.zw;
	vec4 m = textureLod(grass_mask, muv, 0.0);
	float ground = textureLod(height_map, muv, 0.0).r;
	float fade = 1.0 - smoothstep(fade_start, fade_end, dist);
	if (fade_in.y > 0.0) {
		fade *= smoothstep(fade_in.x, fade_in.y, dist);
	}
	// clumpy growth: thin patches and dense tussocks
	float clump = textureLod(noise, root * 0.09 + vec2(0.13, 0.57), 0.0).r;
	float keep = m.r * mix(0.75, 1.2, smoothstep(0.3, 0.7, clump));
	float t = UV.y;                // 0 root .. 1 tip
	float side = UV.x * 2.0 - 1.0; // -1 .. 1 across
	bool outside = muv.x < 0.0 || muv.y < 0.0 || muv.x > 1.0 || muv.y > 1.0;
	if (r2 > keep || fade <= 0.001 || outside) {
		// Collapse under the ground: zero-area triangles are dropped.
		VERTEX = vec3(root.x, ground - 0.3, root.y);
		NORMAL = vec3(0.0, 1.0, 0.0);
		v_col = vec3(0.0);
		v_t = 0.0;
	} else {
		float hgt = blade_height * (0.5 + 0.9 * r3) * (1.0 + 1.6 * m.b) * mix(1.0, 0.35, m.a) * mix(0.75, 1.15, clump);
		hgt *= mix(0.35, 1.0, fade); // shrink into the ground instead of popping
		float w = blade_width * (1.0 + far_widen * smoothstep(2.5, fade_end, dist)) * (1.0 - pow(t, 1.4));
		float yaw = r4 * 6.2832;
		vec3 face = vec3(cos(yaw), 0.0, sin(yaw));
		// Blades seen edge-on turn a little toward the camera (Ghost of Tsushima trick).
		vec3 to_cam = normalize(vec3(cam.x - root.x, 0.0, cam.z - root.y) + vec3(1e-4, 0.0, 0.0));
		float edge = 1.0 - abs(dot(face, to_cam));
		face = normalize(mix(face, to_cam * sign(dot(face, to_cam) + 1e-3), 0.35 * edge));
		vec3 across = vec3(-face.z, 0.0, face.x);
		// Wind: scrolling noise gives gust bands that roll over lawn and paddy alike.
		vec2 wuv = root * 0.035 - wind_dir * TIME * (0.04 + 0.03 * wind_gust);
		float gust = textureLod(noise, wuv, 0.0).r;
		float flutter = sin(TIME * (4.0 + 4.0 * r3) + r2 * 6.2832 + dot(root, wind_dir) * 1.7);
		float wstr = (0.12 + 0.88 * smoothstep(0.35, 0.8, gust)) * 0.38 * wind_gust + flutter * 0.05 * wind_gust;
		// Trampled around the player's feet.
		vec2 away = root - player_pos.xz;
		float pd = max(length(away), 1e-3);
		float push = (1.0 - smoothstep(0.15, 0.6, pd)) * 1.3 * step(abs(player_pos.y - ground), 0.8);
		vec2 bend2 = face.xz * (0.35 + 0.8 * fract(r1 + r5)) + wind_dir * wstr + away / pd * push;
		float blen = max(length(bend2), 1e-4);
		float ang = min(blen, 1.4);
		vec2 bdir = bend2 / blen;
		// Quadratic Bezier: control point straight up, tip on the bend arc (length ~ constant).
		vec3 p1 = vec3(0.0, hgt * 0.55, 0.0);
		vec3 p2 = vec3(bdir.x * sin(ang), cos(ang), bdir.y * sin(ang)) * hgt;
		vec3 pos = 2.0 * (1.0 - t) * t * p1 + t * t * p2;
		vec3 tng = normalize(2.0 * (1.0 - t) * p1 + 2.0 * t * (p2 - p1) + vec3(0.0, 1e-4, 0.0));
		vec3 n = normalize(cross(across, tng));
		n *= sign(n.y + 1e-3);
		n = normalize(n + across * side * 0.6);            // rounded blade
		n = normalize(mix(n, vec3(0.0, 1.0, 0.0), 0.5));   // soft, lawn-like lighting
		VERTEX = vec3(root.x, ground, root.y) + across * (side * w) + pos;
		NORMAL = n;
		// Colour: patches of lush, fresh and dry grass; dark, earthy roots.
		float patchy = textureLod(noise, root * 0.011 + vec2(0.31, 0.77), 0.0).r;
		vec3 c = mix(lush, fresh, smoothstep(0.3, 0.75, patchy));
		c = mix(c, dry, clamp(m.g * 0.75 + (r3 - 0.5) * 0.3 + m.a * 0.3 - 0.05, 0.0, 1.0));
		c *= 0.8 + 0.22 * r2 + 0.16 * r4;
		v_col = mix(mix(soil, c, 0.65) * 0.85, c, smoothstep(0.0, 0.45, t));
		v_t = t;
	}
}

void fragment() {
	// cull_disabled flips NORMAL on back faces; undo it so both faces keep the sky-bent normal.
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	// Sky-bent or kept normals can face away from the eye on thin blades;
	// GGX then blows up at grazing angles into HDR fireflies that the glow
	// smears into white blobs. Keep N.V slightly positive.
	{
		float nv = dot(NORMAL, VIEW);
		NORMAL = normalize(NORMAL + VIEW * max(0.0, 0.12 - nv));
	}
	ALBEDO = v_col * mix(1.0, 0.7, wetness);
	ROUGHNESS = mix(0.62, 0.35, wetness);
	SPECULAR = 0.32;
	BACKLIGHT = v_col * 0.5;
	AO = mix(0.5, 1.0, smoothstep(0.0, 0.8, v_t));
	AO_LIGHT_AFFECT = 0.3;
}
