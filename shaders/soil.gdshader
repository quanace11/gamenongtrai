// The paddy floor. Vertex colour carries the simulation: R = how well the
// soil is hoed, G = how smooth the harrowed mud is. It blends three Poly
// Haven texture sets: cracked dry earth, hoed clods and puddled mud.
shader_type spatial;

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

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz / tile;
	float t = smoothstep(0.15, 0.85, COLOR.r);
	float s = smoothstep(0.2, 0.9, COLOR.g);
	vec3 a = mix(texture(dry_alb, uv * 0.8).rgb, texture(till_alb, uv).rgb, t);
	vec3 n = mix(texture(dry_nor, uv * 0.8).rgb, texture(till_nor, uv).rgb, t);
	vec3 o = mix(texture(dry_arm, uv * 0.8).rgb, texture(till_arm, uv).rgb, t);
	a = mix(a, texture(mud_alb, uv * 1.2).rgb, s);
	n = mix(n, texture(mud_nor, uv * 1.2).rgb, s);
	o = mix(o, texture(mud_arm, uv * 1.2).rgb, s);
	// Wet soil is darker and glossier.
	float w = clamp(wet + s * 0.5, 0.0, 1.0);
	ALBEDO = a * mix(1.0, 0.55, w);
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = mix(1.0, 0.5, w);
	AO = o.r;
	ROUGHNESS = mix(o.g, 0.25, w * 0.8);
	METALLIC = 0.0;
}
