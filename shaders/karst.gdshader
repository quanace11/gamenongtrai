// Limestone towers (núi đá vôi). Vertex colour R carries how much jungle
// covers a spot (from the final normals: ledges, crowns and the scree at
// the foot); the rest is pale grey limestone streaked dark where water runs
// down the cliffs. Rock grain comes from a desaturated photo texture,
// stretched vertically on the walls so it reads as fluting.
shader_type spatial;
render_mode diffuse_burley;

uniform sampler2D rock_alb : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 jungle : source_color = vec3(0.32, 0.4, 0.2);
uniform vec3 limestone : source_color = vec3(0.68, 0.67, 0.63);

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
	TANGENT = normalize(cross(vec3(0.0, 1.0, 0.0), NORMAL) + vec3(1e-4, 0.0, 0.0));
	BINORMAL = normalize(cross(NORMAL, TANGENT));
}

void fragment() {
	vec3 bw = pow(abs(wnrm), vec3(4.0));
	bw /= bw.x + bw.y + bw.z;
	// Walls: horizontal scale 9 m, vertical 30 m, for long vertical grain.
	vec3 tx = texture(rock_alb, vec2(wpos.z / 9.0, wpos.y / 30.0)).rgb;
	vec3 tz = texture(rock_alb, vec2(wpos.x / 9.0, wpos.y / 30.0)).rgb;
	vec3 ty = texture(rock_alb, wpos.xz / 12.0).rgb;
	vec3 t = tx * bw.x + ty * bw.y + tz * bw.z;
	float l = dot(t, vec3(0.3, 0.55, 0.15)) / 0.4;
	float h = wnrm.x * wnrm.x > wnrm.z * wnrm.z ? wpos.z : wpos.x;
	// Dark run-off streaks and orange-grey staining on the cliffs.
	float streak = smoothstep(0.5, 0.85, vnoise(vec2(h * 0.35, wpos.y * 0.02)) * 0.7 + vnoise(vec2(h * 1.3, wpos.y * 0.06)) * 0.3);
	vec3 rock = limestone * mix(0.75, 1.15, l);
	rock = mix(rock, vec3(0.3, 0.3, 0.28), streak * 0.65);
	rock = mix(rock, rock * vec3(1.05, 0.95, 0.85), smoothstep(0.5, 0.8, vnoise(wpos.xy * 0.03 + wpos.zy * 0.02)) * 0.4);
	// Jungle: clumpy canopy, darker in the gaps.
	float canopy = vnoise(wpos.xz * 0.25 + wpos.y * 0.1) * 0.6 + vnoise(wpos.xz * 0.9 - wpos.y * 0.3) * 0.4;
	vec3 green = jungle * mix(0.55, 1.15, canopy);
	float g = smoothstep(0.35, 0.65, COLOR.r + (canopy - 0.5) * 0.35);
	ALBEDO = mix(rock, green, g);
	vec3 nx = texture(rock_nor, vec2(wpos.z / 9.0, wpos.y / 30.0)).rgb;
	NORMAL_MAP = mix(nx, vec3(0.5, 0.5, 1.0), g * 0.6);
	NORMAL_MAP_DEPTH = 1.5;
	ROUGHNESS = 0.95;
	SPECULAR = 0.3;
}
