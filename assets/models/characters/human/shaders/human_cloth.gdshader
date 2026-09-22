shader_type spatial;
// Reference cloth material for the human models (art pass; the game does not use it yet).
// Same maps as the imported StandardMaterial3D, plus the variation's Cloth mask texture:
//   mask R = player tint zone (scrubs, trousers, cap; blood and heavy dirt excluded)
//   mask G = reflective strips (paramedic uniform): a little retro-reflection towards the viewer
// Scrubs are baked in C.PLAYER_COLORS[0]; `tint` recolours them by luminance, keeping all the dirt.
// `expose` (patients): the cloth is cut away inside an ellipse round a surgery site, as if pulled back,
// with a shaded fold round the opening. `expose_inv` is world -> site frame (+Y out of the skin),
// `expose_c` / `expose_r` the ellipse's centre and radii on the site plane (site X, Z). Only for a
// removable panel over real skin (Bob's gunshot panel): elsewhere the gown is a shell over nothing.
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap_anisotropic;   // glTF metallicRoughness: G
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap;
uniform vec3 tint : source_color = vec3(0.239, 0.561, 0.502);
uniform vec3 baked_tint : source_color = vec3(0.239, 0.561, 0.502);
uniform float reflect_boost = 1.5;
uniform float expose = 0.0;
uniform mat4 expose_inv = mat4(1.0);
uniform vec2 expose_c = vec2(0.0);
uniform vec2 expose_r = vec2(0.1);

// CUSTOMIZATION (scripts/personnel/customization.gd): scrub patterns, printed inside the same tint
// zone as the colour (mask R), so they land on scrubs and trousers and never on skin, shoes or the
// paramedic strips. `pattern` picks one; every pattern's knobs are uniforms rather than constants,
// because the knobs are the point -- the same three shaders cover thin pro pinstripes through to
// fat circus stripes, neat machine dots through to big hand-printed bubbles, and a few camo spots
// through to scrubs this surgeon has clearly never washed.
//   0 none   1 pinstripes   2 polka dots   3 splatter
uniform int pattern = 0;
uniform vec3 pattern_colour : source_color = vec3(0.08, 0.09, 0.11);
// Pinstripes: bands across the UV, `width` the inked fraction of each band, `angle` in radians
// (PI / 4 gives diagonals for free).
uniform float stripe_count = 44.0;
uniform float stripe_width = 0.24;
uniform float stripe_angle = 0.0;
// Polka dots: cells across the UV, the dot's radius within its cell, and how far alternate rows
// shift (half a cell reads hand-printed rather than machine-perfect; a big radius reads as bubbles).
uniform float dot_count = 20.0;
uniform float dot_radius = 0.19;
uniform float dot_stagger = 0.5;
// Splatter / camo: noise cells across the UV, and the threshold above which it inks. Sliding the
// threshold goes from a few spots to mostly covered.
uniform float splat_scale = 26.0;
uniform float splat_threshold = 0.62;
// How hard every pattern's edges are.
uniform float pattern_softness = 0.02;

varying vec3 wpos;

float lum(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

float p_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float p_noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(p_hash(i), p_hash(i + vec2(1.0, 0.0)), f.x),
			mix(p_hash(i + vec2(0.0, 1.0)), p_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// How much ink is on this point, 0 to 1.
float pattern_at(vec2 uv) {
	if (pattern == 1) {
		float c = cos(stripe_angle);
		float s = sin(stripe_angle);
		float x = uv.x * c - uv.y * s;
		float f = fract(x * stripe_count);
		return 1.0 - smoothstep(stripe_width - pattern_softness, stripe_width + pattern_softness, f);
	}
	if (pattern == 2) {
		vec2 g = uv * dot_count;
		g.x += mod(floor(g.y), 2.0) * dot_stagger;
		vec2 f = fract(g) - 0.5;
		return 1.0 - smoothstep(dot_radius - pattern_softness, dot_radius + pattern_softness, length(f));
	}
	if (pattern == 3) {
		float n = p_noise(uv * splat_scale) * 0.65 + p_noise(uv * splat_scale * 2.7 + 5.1) * 0.35;
		float soft = pattern_softness * 2.0;
		return smoothstep(splat_threshold - soft, splat_threshold + soft, n);
	}
	return 0.0;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 a = texture(albedo_tex, UV).rgb;
	vec3 m = texture(mask_tex, UV).rgb;
	float shade = lum(a) / max(lum(baked_tint), 0.002);
	vec3 recol = tint * shade;
	// keep a little of the original hue variation so grime stays grime
	float zone = clamp(m.r, 0.0, 1.0);
	ALBEDO = mix(a, recol + (a - baked_tint * shade) * 0.35, zone);
	// The print, inside the tint zone only, and shaded by the same luminance as the recolour so
	// folds and grime still read through it.
	if (pattern > 0) {
		ALBEDO = mix(ALBEDO, pattern_colour * shade, pattern_at(UV) * zone);
	}
	ROUGHNESS = texture(rough_tex, UV).g;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	EMISSION = ALBEDO * m.g * reflect_boost * pow(facing, 6.0) * 0.25;
	if (expose > 0.5) {
		vec3 l = (expose_inv * vec4(wpos, 1.0)).xyz;
		if (abs(l.y) < 0.3) {
			float r = length((l.xz - expose_c) / expose_r);
			if (r < 1.0) {
				discard;
			}
			ALBEDO *= mix(0.55, 1.0, smoothstep(1.0, 1.12, r));
		}
	}
}
