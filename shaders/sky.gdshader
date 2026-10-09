// Sky from four Poly Haven HDRI panoramas (day, sunset, night, overcast)
// blended by time of day and storm. The sun baked into the HDRIs is
// clamped away and a sun disk is drawn where the DirectionalLight is.
shader_type sky;
render_mode use_half_res_pass;

uniform sampler2D day_tex : filter_linear, repeat_enable;
uniform sampler2D dusk_tex : filter_linear, repeat_enable;
uniform sampler2D night_tex : filter_linear, repeat_enable;
uniform sampler2D storm_tex : filter_linear, repeat_enable;
uniform float daylight = 1.0; // 0 night .. 1 day
uniform float dusk = 0.0; // sunrise / sunset glow
uniform float storm = 0.0;
uniform float flash = 0.0; // lightning
uniform float drift = 0.0; // slow cloud rotation, 0..1 around
uniform float night_gain = 0.04;
uniform vec3 sun_tint = vec3(1.0, 0.95, 0.85);

vec3 pano(sampler2D t, vec2 uv, float cap) {
	return min(texture(t, uv).rgb, vec3(cap));
}

void sky() {
	vec2 uv = SKY_COORDS + vec2(drift, 0.0);
	vec3 day = pano(day_tex, uv, 2.2);
	vec3 sunset = pano(dusk_tex, uv + vec2(0.25, 0.0), 3.0);
	vec3 night = pano(night_tex, uv, 1.0) * night_gain * vec3(0.55, 0.7, 1.0);
	vec3 grey = pano(storm_tex, uv, 1.6);

	vec3 col = mix(night, day, daylight);
	col = mix(col, sunset * max(daylight, 0.35), dusk * 0.85);
	col = mix(col, grey * (0.25 + 0.55 * daylight), storm);

	if (LIGHT0_ENABLED && AT_CUBEMAP_PASS == false) {
		float d = dot(EYEDIR, LIGHT0_DIRECTION);
		float disk = smoothstep(0.99985, 0.99993, d);
		float halo = pow(max(d, 0.0), 300.0) * 0.6 + pow(max(d, 0.0), 12.0) * 0.08;
		col += sun_tint * (disk * 18.0 + halo) * LIGHT0_ENERGY * (1.0 - storm);
	}
	// Fade the lower hemisphere into a hazy horizon colour; the land covers it.
	float below = smoothstep(0.02, -0.15, EYEDIR.y);
	vec2 hz = vec2(uv.x, 0.49);
	vec3 haze = mix(pano(night_tex, hz, 1.0) * night_gain * vec3(0.55, 0.7, 1.0), pano(day_tex, hz, 2.2), daylight);
	col = mix(col, mix(haze, grey * 0.4, storm), below);
	col += vec3(0.75, 0.8, 1.0) * flash;
	COLOR = col;
}
