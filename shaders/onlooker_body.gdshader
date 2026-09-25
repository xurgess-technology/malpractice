shader_type spatial;
// The Onlooker's body (scripts/monsters/onlooker_rig.gd): a shadow you cannot quite pin down.
//
// Still unshaded near-black, for the reason the rig gives -- under every light in the game it has
// to be the same hole in the world. What changes is the EDGE. The middle of it is solid; toward the
// silhouette it is eaten away by a slow, upward-crawling noise, and the hem thins to nothing above
// the floor, so the outline never resolves into a clean shape and the thing seems to stand in its
// own smoke rather than on the floor.
//
// It stays in the OPAQUE pass on purpose: the erosion is a cut-out (discard), not
// alpha. Alpha would put the body in the transparent pass with the smoke round it, and then which
// one draws over which depends on sorting -- a body that pops in front of its own fog is the one
// failure that makes it look like a prop. A discard writes depth like any solid thing does.
//
// Fog is off, as it is on its smoke (see shaders/onlooker_smoke.gdshader for why): fogged, the
// pockets' lit volumetric air painted the body the colour of the room -- green in the Natatorium
// under a torch -- which is exactly what the unshaded near-black is there to prevent.
//
//   presence  0..1  the pop in and the poof: at 0 every pixel is gone. It dissolves rather than
//                   scaling or sinking, so going away reads as coming apart.
//   ground_y        world height of its feet (the rig sets it), for the hem.
//   axis_xz         world x, z of its centre line (the rig sets it), for how far out a bit of it is.

render_mode unshaded, cull_back, shadows_disabled, depth_draw_opaque, fog_disabled;

uniform vec3 shade : source_color = vec3(0.021, 0.021, 0.031);
uniform float presence : hint_range(0.0, 1.0) = 1.0;
uniform float ground_y = 0.0;
uniform vec2 axis_xz = vec2(0.0);   // world x, z of its centre line (the rig sets it)
uniform float tall = 2.65;
// How far in from the silhouette the noise bites (0 = a clean edge, 1 = most of the side view).
uniform float erode : hint_range(0.0, 1.0) = 0.9;
// The share of its height, from the floor up, over which the hem fades in.
uniform float hem : hint_range(0.0, 0.6) = 0.3;
uniform float drift = 0.45;   // metres a second the noise climbs

varying vec3 v_world;
varying vec3 v_normal;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Carried by hand, in world space: an unshaded fragment does not get a usable NORMAL/VIEW pair
	// (the first version read them and the edge never eroded at all).
	v_normal = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.1, 0.17, 0.13));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise3(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i + vec3(0, 0, 0)), hash3(i + vec3(1, 0, 0)), f.x),
				   mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), f.x), f.y),
			   mix(mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), f.x),
				   mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

// Interleaved gradient noise, for a little grain right at the cut so the torn edge is not a clean
// vector line.
float ign(vec2 p) {
	return fract(52.9829189 * fract(dot(p, vec2(0.06711056, 0.00583715))));
}

void fragment() {
	vec3 to_eye = normalize(CAMERA_POSITION_WORLD - v_world);
	float facing = clamp(abs(dot(normalize(v_normal), to_eye)), 0.0, 1.0);
	float rim = 1.0 - facing;
	vec3 q = v_world * vec3(3.0, 1.4, 3.0) + vec3(0.0, -TIME * drift, 0.0);
	float n = noise3(q) * 0.6 + noise3(q * 2.3 + vec3(3.1, 0.0, 1.7)) * 0.4;
	float h = (v_world.y - ground_y) / tall;
	// Solid in the middle, torn toward the silhouette: the noise decides how far in each bit of the
	// edge is eaten, so the outline is ragged in clumps and crawls upward as the noise climbs.
	// Value noise sits mostly in the middle of its range; stretched, it gives real clumps and gaps.
	float nc = smoothstep(0.3, 0.75, n);
	// How far out from its own centre line this bit of it is, as a share of how wide it is at this
	// height (the rig's profile: a hem that narrows to the shoulders, then the neck and head). The
	// arms hang out at about 0.8 of that, so they are the first thing to go to tatters. A rim term
	// on top eats whatever silhouette the camera is looking across.
	float hp = clamp(h, 0.0, 1.0);
	float width = hp < 0.68 ? mix(0.46, 0.36, hp / 0.68) : mix(0.36, 0.2, smoothstep(0.7, 0.86, hp));
	float out_r = length(v_world.xz - axis_xz) / width;
	float edge = max(smoothstep(0.45, 1.05, out_r), smoothstep(0.25, 0.95, rim) * 0.6);
	float s = 1.0 - edge * erode * (0.05 + 1.6 * nc);
	// The hem: thinning out toward the floor, broken up by the same noise.
	s *= smoothstep(0.0, hem, h - 0.05 + (n - 0.5) * 0.2);
	// The dissolve: noise decides which bits go first, so it comes apart in clumps.
	s -= (1.0 - presence) * (0.7 + 0.8 * n);
	// A hard cut at one half, blurred by a pinch of grain: clumps, not a screen door.
	if (s < 0.5 + (ign(FRAGCOORD.xy) - 0.5) * 0.3) {
		discard;
	}
	ALBEDO = shade;
}
