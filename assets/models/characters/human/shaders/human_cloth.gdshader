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
// Pinstripes: bands running down the BODY, not across the UV. The cloth's UV islands aren't laid
// out to a common axis -- the torso and the legs disagree about which way is "down" -- so stripes
// taken straight from UV.x ran ACROSS the chest and DOWN the legs, which reads as a bug to anyone
// who didn't write it. The band coordinate comes from body space instead (stripe_coord below), so
// every part of the garment agrees. Dots and splatter still use the UV: they have no direction to
// get wrong, and the islands suit them fine.
// `width` is the inked fraction of each band; `angle` in radians rotates the bands against body-up,
// so PI / 4 still gives diagonals for free. `span` is the body span `count` counts across, in
// metres -- it only sets the pitch, and 2.0 keeps roughly the pitch the UV version had.
uniform float stripe_count = 44.0;
uniform float stripe_width = 0.24;
uniform float stripe_angle = 0.0;
uniform float stripe_span = 2.0;
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
// Body space: the vertex's position and normal in the model's own frame (metres -- the humans are
// authored life-size, HEIGHTS in scripts/human/human_model.gd). Pinstripes band along this rather
// than along the UV. Skinning has already been applied by the time vertex() runs, so these follow
// the pose: on a limb that swings a long way the stripes drift a little across the cloth.
varying vec3 mpos;
varying vec3 mnrm;

float lum(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

float p_hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }

float p_noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(p_hash(i), p_hash(i + vec2(1.0, 0.0)), f.x),
			mix(p_hash(i + vec2(0.0, 1.0)), p_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Where this point falls across the pinstripes, in body space. "Sideways" is x on the front and
// back of the body and z on its sides, blended by which way the surface faces: one flat projection
// would smear into wide bands wherever the body turned edge-on to it, and blending keeps the pitch
// even the whole way round. The seam that leaves is at the body's corners, where the two agree
// least -- there the stripes bend slightly rather than break, which on scrubs reads as drape.
// Then rotate against body-up (y), so angle 0 is straight down the garment and PI / 4 is diagonal.
float stripe_coord(vec3 p, vec3 n) {
	float fx = abs(n.x);
	float fz = abs(n.z);
	// 0 = band along x, 1 = band along z. The 0.15 both biases the blend towards x (the honest
	// left-to-right of a body facing you) and keeps it stable where the surface faces straight up
	// or down and neither x nor z means anything -- the tops of the shoulders, where dividing by
	// (fx + fz) alone fanned the stripes out into chevrons.
	float side = fx / (fx + fz + 0.15);
	float h = mix(p.x, p.z, side);
	return (h * cos(stripe_angle) - p.y * sin(stripe_angle)) / max(stripe_span, 0.001);
}

// How much ink is on this point, 0 to 1.
float pattern_at(vec2 uv, vec3 p, vec3 n) {
	if (pattern == 1) {
		float f = fract(stripe_coord(p, n) * stripe_count);
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
	mpos = VERTEX;
	mnrm = NORMAL;
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
		ALBEDO = mix(ALBEDO, pattern_colour * shade, pattern_at(UV, mpos, normalize(mnrm)) * zone);
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
