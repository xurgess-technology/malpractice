shader_type spatial;
// The Onlooker's smoke (scripts/monsters/onlooker_smoke.gd): one soft, dark, torn puff per
// particle, drawn on a camera-facing quad. Every puff of it uses this -- the wisps it stands in and
// the cloud it leaves when it goes.
//
// No texture: the puff is a radial falloff broken up by value noise, seeded per particle so no two
// look alike, and turning slowly as it lives. It fades out where it meets the floor or a wall
// (the scene's depth, so a puff never shows the hard line of a quad cutting through geometry) and
// as it comes right up to the camera, so running through the cloud does not paint the screen black.
//
// Particle colour carries the puff's life: COLOR.a is the colour ramp's fade in and out.
//
// **Fog is off, on purpose, and replaced by a gentler fade with distance.** The pocket spaces are
// thick with volumetric fog, and fogging a dark puff the ordinary way paints it with all the light
// the fog scatters between it and you -- in the Natatorium with a torch on, the smoke came out the
// same green as the air round it and simply was not there. Unfogged, it stays a darkness in the
// air at any range, which is what keeps the thing a dark presence at forty metres in the Factory
// rather than a pale dot; `far_fade` thins it with distance so it never reads as a cut-out.

render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 tint : source_color = vec3(0.012, 0.012, 0.02);
uniform float density : hint_range(0.0, 1.0) = 0.7;
uniform float ragged : hint_range(0.0, 1.5) = 0.5;   // how torn a puff's outline is
uniform float soft_depth = 0.5;     // metres over which a puff fades into what is behind it
uniform float near_fade = 1.2;      // metres from the camera at which a puff is gone
uniform float far_start = 10.0;     // metres at which the distance thinning starts
uniform float far_end = 45.0;       // and where it bottoms out
uniform float far_keep = 0.5;       // what is left of it there
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying float v_seed;

void vertex() {
	// Billboard, keeping the particle's own scale and spin (INSTANCE_CUSTOM.x) -- the same maths
	// StandardMaterial3D's particle billboard uses.
	mat4 w = mat4(normalize(INV_VIEW_MATRIX[0]), normalize(INV_VIEW_MATRIX[1]),
			normalize(INV_VIEW_MATRIX[2]), MODEL_MATRIX[3]);
	float a = INSTANCE_CUSTOM.x;
	w = w * mat4(vec4(cos(a), -sin(a), 0.0, 0.0), vec4(sin(a), cos(a), 0.0, 0.0),
			vec4(0.0, 0.0, 1.0, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * w;
	MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
			vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
	v_seed = fract(float(INSTANCE_ID) * 0.61803398 + 0.137);
}

float hash2(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
			   mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	vec2 o = vec2(v_seed * 31.7, v_seed * 17.3 + TIME * 0.1);
	// Low-frequency noise only: a puff should be a soft, uneven cloud, not a cluster of blobs.
	float n = noise2(uv * 1.3 + o) * 0.7 + noise2(uv * 2.9 - o) * 0.3;
	float r = length(uv) * (0.85 + ragged * (n - 0.5));
	float a = 1.0 - smoothstep(0.0, 1.0, r);
	a *= a * (3.0 - 2.0 * a) * mix(1.0, 0.2 + 1.6 * n, clamp(ragged, 0.0, 1.0));
	a *= COLOR.a * density;
	// Soft against the world behind it.
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	behind.xyz /= behind.w;
	a *= clamp((VERTEX.z - behind.z) / soft_depth, 0.0, 1.0);
	// And gone before it reaches the lens.
	a *= smoothstep(near_fade * 0.35, near_fade, -VERTEX.z);
	// Thinner the further off it is (standing in for the fog it does not get).
	a *= mix(1.0, far_keep, smoothstep(far_start, far_end, -VERTEX.z));
	ALBEDO = tint * COLOR.rgb;
	ALPHA = clamp(a, 0.0, 1.0);
}
