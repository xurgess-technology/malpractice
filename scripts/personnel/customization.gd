extends RefCounted
## What a surgeon looks like, and the set of things you can change about it at the big mirror
## (scripts/personnel/mirror_menu.gd).
##
## The beginnings of a customization menu: every choice is one entry in AXES, so adding another is
## a list entry plus whatever it drives in `apply`. An entry is:
##   key        stable name; it is what the save file and the packed int are keyed on, so never
##              rename one without bumping the axis order below
##   label      what the mirror shows
##   options    the choices, each {"name": <shown>, ...payload the axis reads}
##   default    index into options for a surgeon nobody has touched
##   needs      optional {"key": <other axis>, "not": <index>}: the axis is only offered while that
##              other axis is off that index (the pattern colour is pointless without a pattern)
##
## A whole look is a Dictionary of key -> option index. `pack`/`unpack` squeeze it into one int so
## it can ride along as a single replicated field and a single settings key.

const HumanModel := preload("res://scripts/human/human_model.gd")

## Scrubs. The first is the colour they are baked in (C.PLAYER_COLORS[0]), so it is the "no change"
## option; the rest are the other player colours plus a few that read well under the ward lights.
const OUTFITS := [
	{"name": "Surgical Green", "c": Color("3d8f80")},
	{"name": "Ward Blue", "c": Color("3d5f8f")},
	{"name": "Plum", "c": Color("8f3d6e")},
	{"name": "Mustard", "c": Color("8f7a3d")},
	{"name": "Moss", "c": Color("6e8f3d")},
	{"name": "Brick", "c": Color("8f4a3d")},
	{"name": "Slate", "c": Color("4a5560")},
	{"name": "Bone", "c": Color("c9c2b0")},
]

## Skin. `c` is fed to the skin shader's `skin_tint`; the shader shifts the baked skin towards it by
## luminance, so freckles, lips and shading survive. Index 0 is the colour the model is baked in.
const SKINS := [
	{"name": "Warm", "c": Color("c08a63")},
	{"name": "Porcelain", "c": Color("e8c3a8")},
	{"name": "Fair", "c": Color("d9a583")},
	{"name": "Olive", "c": Color("a87848")},
	{"name": "Bronze", "c": Color("8a5c38")},
	{"name": "Deep", "c": Color("5e3a24")},
]

## The colour the skin texture is baked in: SKINS[SKIN_BAKED] is a no-op. It is first in the list so
## that a packed look of 0 is "exactly as the model was built", which is what an unset axis means.
const SKIN_BAKED := 0

## Scrub patterns. `id` is what the cloth shader's `pattern` uniform takes, and `knobs` are that
## pattern's shader parameters, so a preset is data and a new one is a list entry rather than a
## branch in code. "None" is a real option and the default. Every knob the shader exposes can be
## pinned here: these three are the baseline, not the limit.
const PATTERNS := [
	{"name": "None", "id": 0, "knobs": {}},
	# Pinstripes band along body space, not the UV, so `stripe_span` (metres of body the count
	# counts across) is what sets the pitch: count 46 over 2.0 m is a stripe every ~4 cm.
	{"name": "Pinstripes", "id": 1,
		"knobs": {"stripe_count": 46.0, "stripe_width": 0.22, "stripe_angle": 0.0,
			"stripe_span": 2.0}},
	{"name": "Polka Dots", "id": 2,
		"knobs": {"dot_count": 20.0, "dot_radius": 0.19, "dot_stagger": 0.5}},
	{"name": "Splatter", "id": 3,
		"knobs": {"splat_scale": 26.0, "splat_threshold": 0.62}},
	# POCKETS 2 phase 4: locked until somebody brings a set of WARM SCRUBS back from the Laundromat.
	# It goes on the END of this list and nowhere else: an index here is what a saved look and a
	# packed look over the wire both carry, so inserting one anywhere else redresses everybody.
	{"name": "Gingham", "id": 4, "unlock": "warm_scrubs",
		"knobs": {"check_count": 16.0, "check_width": 0.5, "check_span": 2.0, "check_pale": 0.45}},
]

## POCKETS 2 phase 4: which patterns this machine has earned, as a bitmask over PATTERNS indices,
## kept in the player's own settings file (Settings "patterns_unlocked"). Everything that shipped
## before the Laundromat is unlocked for everyone, so nobody loses a pattern they were already
## wearing; only entries carrying an "unlock" key start locked.
const UNLOCK_KEY := "patterns_unlocked"


## The mask a fresh save starts with: every pattern that does not name an unlock.
static func default_unlocks() -> int:
	var m := 0
	for i in PATTERNS.size():
		if not (PATTERNS[i] as Dictionary).has("unlock"):
			m |= 1 << i
	return m


## This machine's unlock mask, defaults folded in so a pattern added later is not locked by an old
## save that predates it.
static func unlocked_mask() -> int:
	return int(Settings.get_value(UNLOCK_KEY)) | default_unlocks()


## Whether pattern `i` may be chosen at the mirror on this machine. Never consulted for anybody
## else's look: a teammate's unlocks are theirs, and stripping their pattern because this machine
## has not earned it would be a bug, not a rule (see sanitize's note).
static func pattern_unlocked(i: int) -> bool:
	return (unlocked_mask() >> i) & 1 == 1


## Grant every pattern whose "unlock" is `token` (an item kind). True when this actually unlocked
## something new, so the caller can say so once and not every frame.
static func grant_unlock(token: String) -> bool:
	var mask := unlocked_mask()
	var got := mask
	for i in PATTERNS.size():
		if String((PATTERNS[i] as Dictionary).get("unlock", "")) == token:
			got |= 1 << i
	if got == mask:
		return false
	Settings.set_value(UNLOCK_KEY, got)
	return true


## The name of the pattern `token` unlocks, for the message that says so ("" if it unlocks none).
static func unlock_name(token: String) -> String:
	for pat in PATTERNS:
		if String((pat as Dictionary).get("unlock", "")) == token:
			return String(pat.name)
	return ""

## What the pattern is printed in. Only offered once a pattern is.
const PATTERN_COLOURS := [
	{"name": "Ink", "c": Color("14171a")},
	{"name": "Bone", "c": Color("e6e0d2")},
	{"name": "Blood", "c": Color("6e1414")},
	{"name": "Sky", "c": Color("6f9fc4")},
	{"name": "Gold", "c": Color("c2a03c")},
	{"name": "Moss", "c": Color("55702f")},
]

const AXES := [
	{"key": "outfit", "label": "Scrubs", "options": OUTFITS, "default": 0},
	{"key": "skin", "label": "Skin", "options": SKINS, "default": SKIN_BAKED},
	{"key": "pattern", "label": "Pattern", "options": PATTERNS, "default": 0},
	# Only offered while there is a pattern to colour in.
	{"key": "pattern_colour", "label": "Pattern colour", "options": PATTERN_COLOURS, "default": 0,
		"needs": {"key": "pattern", "not": 0}},
]

## Bits per axis in the packed int: 6 is 64 options, far more than any axis will want, and five
## axes still fit in 30 bits.
const AXIS_BITS := 6
const AXIS_MASK := (1 << AXIS_BITS) - 1


static func axis(key: String) -> Dictionary:
	for a in AXES:
		if String(a.key) == key:
			return a
	return {}


static func options_of(key: String) -> Array:
	return (axis(key) as Dictionary).get("options", [])


static func default_look() -> Dictionary:
	var d := {}
	for a in AXES:
		d[String(a.key)] = int(a.default)
	return d


## CUSTOMIZATION: the look a surgeon nobody has dressed wears. The scrubs follow the peer id, so
## four people who have never touched the mirror still turn up in four different colours, exactly as
## they did before any of this existed (OUTFITS starts with C.PLAYER_COLORS, in order).
static func default_look_for(peer_id: int) -> Dictionary:
	var d := default_look()
	d["outfit"] = posmod(peer_id - 1, OUTFITS.size())
	return d


## Every key present, every index in range, and any axis whose `needs` is unmet forced back to its
## default (so a look never carries a pattern colour for a pattern that is switched off).
##
## POCKETS 2 phase 4: this deliberately does NOT check unlocks. Every machine unpacks every other
## player's look through here, and a teammate who has earned a pattern this machine has not must
## still be seen wearing it. The gate is `cycle`, which is the only way a look is ever chosen.
static func sanitize(look: Dictionary) -> Dictionary:
	var out := default_look()
	for a in AXES:
		var key := String(a.key)
		var n: int = (a.options as Array).size()
		if look.has(key) and n > 0:
			out[key] = clampi(int(look[key]), 0, n - 1)
	for a in AXES:
		if not _needs_met(a, out):
			out[String(a.key)] = int(a.default)
	return out


static func _needs_met(a: Dictionary, look: Dictionary) -> bool:
	var needs: Dictionary = a.get("needs", {})
	if needs.is_empty():
		return true
	return int(look.get(String(needs.key), 0)) != int(needs.get("not", 0))


## The axes to show, in order, for this look.
static func visible_axes(look: Dictionary) -> Array:
	var out: Array = []
	for a in AXES:
		if _needs_met(a, look):
			out.append(a)
	return out


## Step one axis `by` places, wrapping, and sanitize the result.
static func cycle(look: Dictionary, key: String, by: int) -> Dictionary:
	var a := axis(key)
	if a.is_empty():
		return look
	var n: int = (a.options as Array).size()
	if n <= 0:
		return look
	if by == 0:
		return sanitize(look)
	var next := look.duplicate()
	var at := int(look.get(key, int(a.default)))
	# POCKETS 2 phase 4: step over anything this machine has not unlocked, so a locked pattern is
	# not a dead stop in the middle of the list. `n` tries is always enough to come back round.
	var step := 1 if by >= 0 else -1
	for _k in maxi(1, absi(by)):
		for _t in n:
			at = posmod(at + step, n)
			if key != "pattern" or pattern_unlocked(at):
				break
	next[key] = at
	return sanitize(next)


## The shown name of the chosen option on one axis.
static func option_name(look: Dictionary, key: String) -> String:
	var opts := options_of(key)
	if opts.is_empty():
		return ""
	var i: int = clampi(int(look.get(key, 0)), 0, opts.size() - 1)
	return String((opts[i] as Dictionary).get("name", ""))


static func outfit_colour(look: Dictionary) -> Color:
	var opts := OUTFITS
	return opts[clampi(int(look.get("outfit", 0)), 0, opts.size() - 1)].c


static func skin_colour(look: Dictionary) -> Color:
	return SKINS[clampi(int(look.get("skin", SKIN_BAKED)), 0, SKINS.size() - 1)].c


static func pattern_of(look: Dictionary) -> Dictionary:
	return PATTERNS[clampi(int(look.get("pattern", 0)), 0, PATTERNS.size() - 1)]


static func pattern_colour(look: Dictionary) -> Color:
	return PATTERN_COLOURS[clampi(int(look.get("pattern_colour", 0)), 0, PATTERN_COLOURS.size() - 1)].c


# ---------------------------------------------------------------------------
# packing: one int, so a look is a single replicated field and a single settings key

static func pack(look: Dictionary) -> int:
	var v := 0
	var clean := sanitize(look)
	for i in AXES.size():
		var key := String((AXES[i] as Dictionary).key)
		v |= (int(clean[key]) & AXIS_MASK) << (i * AXIS_BITS)
	return v


static func unpack(v: int) -> Dictionary:
	var look := {}
	for i in AXES.size():
		var key := String((AXES[i] as Dictionary).key)
		look[key] = (v >> (i * AXIS_BITS)) & AXIS_MASK
	return sanitize(look)


# ---------------------------------------------------------------------------
# putting it on a body

## The HumanModel root under a player's `body_visual` (null for the Kenney / primitive fallbacks,
## which this feature does not dress).
static func human_root(body_visual: Node) -> Node3D:
	if body_visual == null:
		return null
	if body_visual.has_meta("human_variant"):
		return body_visual as Node3D
	for c in body_visual.get_children():
		if c is Node3D and (c as Node).has_meta("human_variant"):
			return c as Node3D
	return null


## Dress a body (a player's `body_visual`, or the lying stand-in) in this look. Safe to call every
## frame: every write is a shader parameter.
static func apply(body_visual: Node, look: Dictionary) -> void:
	var root := human_root(body_visual)
	if root == null:
		return
	var clean := sanitize(look)
	HumanModel.set_tint(root, outfit_colour(clean))
	var cloth := HumanModel.cloth_of(root)
	if cloth != null:
		var pat := pattern_of(clean)
		cloth.set_shader_parameter(&"pattern", int(pat.id))
		cloth.set_shader_parameter(&"pattern_colour", pattern_colour(clean))
		# A preset only sets its own knobs; the others keep whatever they held, which is harmless
		# because each pattern reads only its own.
		for k in (pat.get("knobs", {}) as Dictionary).keys():
			cloth.set_shader_parameter(StringName(String(k)), (pat.knobs as Dictionary)[k])
	var skin := HumanModel.skin_of(root)
	if skin != null:
		skin.set_shader_parameter(&"skin_tint", skin_colour(clean))
		skin.set_shader_parameter(&"skin_baked", SKINS[SKIN_BAKED].c)
