// Shared tree wind for bamboo culms, leaf cards and palm/banana geometry
// (flora.gd). Every tree mesh carries the same vertex layout so the parts of
// one plant move together:
//   COLOR.a   height fraction on the culm/trunk (culm sway ~ COLOR.a²)
//   UV2.x     branch index + 0.999 * distance along the branch, frond or
//             leaf (0 on the culm itself): branch sway with a phase per index
//   UV2.y     random phase of the culm/trunk, so a grove does not sway as one
// The gust strength comes from the seamless noise shared with rice and grass
// (world xz * 0.035, scrolled along wind_dir), so gust waves cross the paddy
// and the groves together.
global uniform float wind_gust;
global uniform vec2 wind_dir;
global uniform float wetness;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable; // flora.gd wind_noise()
uniform float plant_height = 12.0;
uniform float trunk_sway = 0.35;   // metres at the top in a moderate gust
uniform float branch_sway = 0.06;  // metres at a branch tip
uniform float flutter = 0.0;       // metres of fast leaf flutter

// World-space offset of a vertex. `leaf` weights the fast flutter.
vec3 tree_wind(vec3 root, vec3 wp, vec4 col, vec2 uv2, float leaf, float t) {
	float ph = uv2.y * 6.2832 + root.x * 0.37 + root.z * 0.23;
	vec2 wuv = root.xz * 0.035 - wind_dir * t * (0.04 + 0.03 * wind_gust);
	float s = (0.2 + 0.8 * smoothstep(0.3, 0.8, textureLod(noise, wuv, 0.0).r)) * wind_gust;
	vec3 w = vec3(wind_dir.x, 0.0, wind_dir.y);
	vec3 side = vec3(-w.z, 0.0, w.x);
	float h2 = col.a * col.a;
	// 1) culm or trunk: leans with the gust and sways slowly around it
	vec3 off = (w * (0.75 * s + 0.25 * wind_gust * sin(t * 0.9 + ph))
			+ side * 0.2 * wind_gust * sin(t * 0.63 + ph * 1.7)) * trunk_sway * h2;
	// keep the length: a bent culm drops a little at the top
	off.y -= 0.5 * dot(off.xz, off.xz) / max(col.a * plant_height, 0.5);
	// 2) branch, frond or leaf: medium frequency, its own phase
	float along = fract(uv2.x);
	float bph = ph + floor(uv2.x) * 2.39;
	off += (w * 0.6 + side * 0.4 * sin(bph) + vec3(0.0, 0.5, 0.0)) * branch_sway * (0.35 * s + 0.65 * wind_gust) * along * along * sin(t * (1.7 + 0.4 * sin(bph)) + bph);
	// 3) leaves: fast flutter, mostly vertical
	off.y += flutter * wind_gust * leaf * sin(t * 7.0 + bph * 3.0 + wp.x * 4.0 + wp.z * 3.0);
	return off;
}
