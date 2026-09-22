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

const AXES := [
	{"key": "outfit", "label": "Scrubs", "options": OUTFITS, "default": 0},
	{"key": "skin", "label": "Skin", "options": SKINS, "default": SKIN_BAKED},
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
	var next := look.duplicate()
	next[key] = posmod(int(look.get(key, int(a.default))) + by, n)
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
	var skin := HumanModel.skin_of(root)
	if skin != null:
		skin.set_shader_parameter(&"skin_tint", skin_colour(clean))
		skin.set_shader_parameter(&"skin_baked", SKINS[SKIN_BAKED].c)
