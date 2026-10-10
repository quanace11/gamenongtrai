// Sky from five Poly Haven HDRI panoramas (hazy day, misty morning, sunset,
// night, overcast) blended by time of day and storm. Each panorama is turned
// so the sun baked into it sits where the DirectionalLight is (sunset glow
// around the real sun); the featureless misty sky is also warped in
// elevation so its aureole follows the sun up. A warm forward-scattering
// glow is added around a low sun, in every pass, so the fog and the
// reflections pick up the golden hour too. The baked sun itself is clamped away and a sun disk is drawn
// where the light is, coloured by the light so it reddens near the horizon.
shader_type sky;

uniform sampler2D day_tex : filter_linear, repeat_enable;
uniform sampler2D mist_tex : filter_linear, repeat_enable;
uniform sampler2D dusk_tex : filter_linear, repeat_enable;
uniform sampler2D night_tex : filter_linear, repeat_enable;
uniform sampler2D storm_tex : filter_linear, repeat_enable;
uniform float daylight = 1.0; // 0 night .. 1 day
uniform float morning = 0.0; // 1 = misty morning sky, 0 = hazy day sky
uniform float dusk = 0.0; // sunrise / sunset glow
uniform float gold = 0.0; // golden hour: the low sun warms the whole hazy sky
uniform float storm = 0.0;
uniform float flash = 0.0; // lightning
uniform float drift = 0.0; // tiny cloud wobble, in turns
uniform float night_gain = 0.04;
uniform float humid = 1.0; // milky, desaturated tropical haze
uniform float day_gain = 0.8; // the day HDRIs are bright all round: keep sun/sky contrast
uniform float mist_gain = 0.8;
uniform float glow_gain = 0.8; // warm aureole of a low sun in wet air
uniform float dusk_gain = 0.32; // the sunset HDRI is exposed for a bright horizon: keep it warm, not white
uniform float dusk_sat = 1.5; // and a little richer, as the long path through wet air reddens it
// Where the sun is in each panorama: x = u (turns), y = elevation (radians).
uniform vec2 day_sun = vec2(0.602, 0.89);
uniform vec2 mist_sun = vec2(0.470, 0.50);
uniform vec2 dusk_sun = vec2(0.596, 0.02);
uniform vec2 storm_sun = vec2(0.582, 0.40);
uniform float day_warp = 1.0; // 0 = no elevation warp, 1 = HDRI aureole sits on the sun
uniform vec3 haze_col = vec3(0.86, 0.89, 0.92);

vec3 pano(sampler2D t, vec2 uv, float cap) {
	return min(texture(t, uv).rgb, vec3(cap));
}

// Panorama UV for EYEDIR so that the HDRI's own sun lands on the real sun.
// Azimuth is a plain turn; elevation (upper hemisphere only) is bent with a
// power curve that keeps the horizon and the zenith fixed.
vec2 aligned(vec2 uv, vec2 sun_uv, vec2 hdr_sun, float warp) {
	uv.x += hdr_sun.x - sun_uv.x + drift;
	if (warp > 0.0 && uv.y < 0.5) {
		float vs = clamp(sun_uv.y, 0.03, 0.47) * 2.0;
		float vh = clamp(0.5 - hdr_sun.y / 3.14159265, 0.03, 0.47) * 2.0;
		float k = clamp(log(vh) / log(vs), 0.25, 4.0);
		uv.y = mix(uv.y, 0.5 * pow(uv.y * 2.0, k), warp);
	}
	return uv;
}

vec3 dusk_col(vec3 c) {
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	// Saturate the warm horizon, and warm the cold zenith a little: the
	// humid sky after sunset is lavender-pink, not deep blue.
	return max(mix(vec3(l), c, dusk_sat), vec3(0.0)) * vec3(1.08, 0.96, 0.86) * dusk_gain;
}

void sky() {
	vec2 uv = SKY_COORDS;
	vec3 L = LIGHT0_ENABLED ? LIGHT0_DIRECTION : vec3(0.0, 1.0, 0.0);
	vec2 sun_uv = vec2(fract(atan(L.x, -L.z) / 6.2831853), acos(clamp(L.y, -1.0, 1.0)) / 3.14159265);

	vec3 day = pano(day_tex, aligned(uv, sun_uv, day_sun, 0.0), 2.2) * day_gain;
	if (morning > 0.0) {
		day = mix(day, pano(mist_tex, aligned(uv, sun_uv, mist_sun, day_warp), 2.2) * mist_gain, morning);
	}
	vec3 sunset = dusk_col(pano(dusk_tex, aligned(uv, sun_uv, dusk_sun, 0.0), 6.0));
	vec3 night = pano(night_tex, uv + vec2(drift, 0.0), 1.0) * night_gain * vec3(0.55, 0.7, 1.0);
	vec3 grey = pano(storm_tex, aligned(uv, sun_uv, storm_sun, 0.0), 1.6);

	// Humid tropical air: less saturated blue, and a bright milky band at the
	// horizon that the fog and the far karst melt into.
	float l = dot(day, vec3(0.2126, 0.7152, 0.0722));
	day = mix(day, vec3(l) * vec3(0.97, 0.99, 1.03), 0.15 * humid);
	float low = pow(1.0 - clamp(EYEDIR.y, 0.0, 1.0), 6.0);
	day = mix(day, haze_col * max(l, 0.85 * day_gain), low * 0.4 * humid);

	day *= mix(vec3(1.0), vec3(1.1, 0.95, 0.78), gold);
	vec3 col = mix(night, day, daylight);
	col = mix(col, sunset * mix(0.4, 1.0, daylight), dusk);
	col = mix(col, grey * (0.25 + 0.55 * daylight), storm);

	float clear = 1.0 - storm;
	if (LIGHT0_ENABLED) {
		// Golden hour: forward scattering in humid air spreads the low sun's
		// colour over a wide part of the sky, strongest near the horizon.
		float d = max(dot(EYEDIR, L), 0.0);
		float low_sun = (1.0 - smoothstep(0.0, 0.5, L.y)) * smoothstep(-0.1, 0.0, L.y);
		float hor = pow(1.0 - clamp(EYEDIR.y, 0.0, 1.0), 3.0);
		float mie = 0.8 * pow(d, 16.0) + 0.25 * pow(d, 3.0);
		col += LIGHT0_COLOR * LIGHT0_ENERGY * low_sun * mie * (0.35 + 0.65 * hor) * glow_gain * clear;
	}
	if (LIGHT0_ENABLED && !AT_CUBEMAP_PASS) {
		float d = dot(EYEDIR, LIGHT0_DIRECTION);
		// Through thick, wet air the disk is soft-edged and the aureole wide.
		float disk = smoothstep(0.99984, 0.99992, d);
		float halo = pow(max(d, 0.0), 900.0) * 0.5 + pow(max(d, 0.0), 60.0) * 0.06 + pow(max(d, 0.0), 6.0) * 0.03;
		col += LIGHT0_COLOR * (disk * 14.0 + halo) * LIGHT0_ENERGY * clear * clear;
	}
	// Fade the lower hemisphere into a hazy horizon colour; the land covers it.
	float below = smoothstep(0.02, -0.15, EYEDIR.y);
	vec2 hz = vec2(uv.x, 0.49);
	vec3 hz_day = pano(day_tex, aligned(hz, sun_uv, day_sun, 0.0), 2.2) * day_gain;
	hz_day = mix(hz_day, pano(mist_tex, aligned(hz, sun_uv, mist_sun, 0.0), 2.2) * mist_gain, morning);
	vec3 haze = mix(pano(night_tex, hz, 1.0) * night_gain * vec3(0.55, 0.7, 1.0), mix(hz_day, haze_col * day_gain, 0.5 * humid), daylight);
	haze = mix(haze, dusk_col(pano(dusk_tex, aligned(hz, sun_uv, dusk_sun, 0.0), 6.0)) * mix(0.4, 1.0, daylight), dusk);
	col = mix(col, mix(haze, grey * 0.4, storm), below);
	col += vec3(0.75, 0.8, 1.0) * flash;
	COLOR = col;
}
