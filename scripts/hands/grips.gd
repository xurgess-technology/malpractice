extends RefCounted
## Grip data: where an item model sits in a hand (docs/HANDS_AND_FEEDBACK.md, docs/CONTRACTS.md
## "Player: hands"). `ItemModels.grip(kind)` returns this file's answer.
##
## A hand socket is a frame at the middle of the palm:
##   -Z  the way the fingers point
##   +Y  out of the palm (what a thing lying on an open palm rests against)
##   +X  to the right of the hand (the same for both hands, so the frame stays right-handed)
## A grip names, in the item model's own space (ItemModels.make: origin at the base of the stack):
##   pos    the point that lands in the palm
##   fwd    the model direction that follows the fingers (socket -Z)
##   up     the model direction that points out of the palm (socket +Y)
##   style  "palm" (lies on an open palm, palm up) or "fist" (a handle in a closed hand, thumb up)
##   hands  1, or 2 for bulky things carried in front with both hands
##   bundle the most copies of a stack shown in the hand (a batch is held as a small bundle)
## grip_transform(kind) is the model's transform in socket space: socket * grip_transform places it.

const LootTable := preload("res://scripts/economy/loot_table.gd")
const ItemsDB := preload("res://scripts/items.gd")
const GripBake := preload("res://scripts/hands/grip_bake.gd")

const DEFAULT := {"pos": Vector3.ZERO, "fwd": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "style": "palm", "hands": 1, "bundle": 1}

## Per kind. Anything missing takes DEFAULT (and loot its footprint-based default, see grip()).
const GRIPS := {
	# Surgical supplies (primitive models in item_models.gd).
	"anesthetic": {"pos": Vector3(0.0, 0.004, 0.012), "fwd": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "style": "palm", "bundle": 3},
	# SYRINGE DRAW: held like the epipen -- thumb rest at -X, needle out at +X, so a syringe in the
	# hand points where you are looking and reads as ready to stick something.
	"syringe": {"pos": Vector3(-0.03, 0.013, 0.0), "fwd": Vector3(1, 0, 0), "up": Vector3(0, -1, 0), "style": "fist", "bundle": 3},
	# Rolls lie across the palm (their axis along the model X).
	"gauze": {"pos": Vector3(0.0, 0.0, 0.0), "fwd": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "style": "palm", "bundle": 2},
	# Blade along +X from the handle, teeth toward +Z, flat face +Y: the teeth point down in a fist.
	"bone_saw": {"pos": Vector3(-0.17, 0.016, 0.0), "fwd": Vector3(1, 0, 0), "up": Vector3(0, -1, 0), "style": "fist"},
	# Hinge at -X, tips toward +X.
	"forceps": {"pos": Vector3(-0.05, 0.016, 0.0), "fwd": Vector3(1, 0, 0), "up": Vector3(0, -1, 0), "style": "fist"},
	# GRAFTING part one: slim tools, handle at -X, working end along +X (held like the forceps).
	"scalpel": {"pos": Vector3(-0.045, 0.008, 0.0), "fwd": Vector3(1, 0, 0), "up": Vector3(0, -1, 0), "style": "fist"},
	"eye_spoon": {"pos": Vector3(-0.06, 0.008, 0.0), "fwd": Vector3(1, 0, 0), "up": Vector3(0, -1, 0), "style": "fist"},
	"tourniquet": {"pos": Vector3(0.0, 0.0, 0.0), "fwd": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "style": "palm"},
	"suture_kit": {"pos": Vector3(0.0, 0.0, 0.0), "fwd": Vector3(1, 0, 0), "up": Vector3(0, 1, 0), "style": "palm", "bundle": 2},
	# Loot with a handle (lying models, handle along their long side).
	"reflex_hammer": {"pos": Vector3(-0.06, 0.02, 0.0), "fwd": Vector3(1, 0, 0), "up": Vector3(0, -1, 0), "style": "fist"},
	# EpiPen: cap at -X, needle end +X, held like the reflex hammer.
	"epipen": {"pos": Vector3(-0.03, 0.016, 0.0), "fwd": Vector3(1, 0, 0), "up": Vector3(0, -1, 0), "style": "fist"},
	# POCKETS 2 phase 2: the whistle's mouthpiece is at -X and its barrel runs along +X, so it is held
	# like the reflex hammer -- mouthpiece out of the fist, which is what you need to blow it.
	"lifeguard_whistle": {"pos": Vector3(-0.03, 0.017, 0.0), "fwd": Vector3(1, 0, 0), "up": Vector3(0, -1, 0), "style": "fist"},
	"pill_bottle": {"bundle": 3},
	# POCKETS 2 phase 4 (the Laundromat). The bucket hangs from its bail in a closed hand, so the
	# palm sits at the top of the wire rather than at the base of the pail.
	"quarter_bucket": {"pos": Vector3(0.0, 0.245, 0.0), "fwd": Vector3(1, 0, 0), "up": Vector3(0, 1, 0), "style": "fist"},
	# The jug is carried by the grip moulded into the back of the bottle.
	"fabric_softener": {"pos": Vector3(0.0, 0.155, -0.068), "fwd": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "style": "fist"},
	# A folded stack lies flat across an open palm.
	"warm_scrubs": {"pos": Vector3(0.0, 0.02, 0.0), "fwd": Vector3(0, 0, -1), "up": Vector3(0, 1, 0), "style": "palm"},
}


static var _cache := {}


## Where in its model a kind is held. Always every key of DEFAULT. Cached per kind: do not edit the
## returned dictionary (duplicate it first).
static func grip(kind: String) -> Dictionary:
	if _cache.has(kind):
		return _cache[kind]
	var g := DEFAULT.duplicate()
	if ItemsDB.is_bulky(kind) or (LootTable.has(kind) and bool(LootTable.LOOT[kind].get("bulky", false))):
		# Bulky loot: both hands on its sides, a little below the middle of the model.
		var fp := _footprint(kind)
		g["pos"] = Vector3(0.0, fp.y * 0.35, 0.0)
		g["hands"] = 2
	g.merge(GRIPS.get(kind, {}), true)
	_cache[kind] = g
	return g


## The model's transform in socket space (see the header).
static func grip_transform(kind: String) -> Transform3D:
	return transform_of(grip(kind))


static func transform_of(g: Dictionary) -> Transform3D:
	var fwd: Vector3 = (g.fwd as Vector3).normalized()
	var up: Vector3 = g.up
	up = (up - fwd * up.dot(fwd)).normalized()
	# The model's fwd maps to socket -Z, its up to +Y: rows of the rotation are the model axes.
	var right := up.cross(-fwd)   # model direction that maps to socket +X
	var model_to_socket := Basis(right, up, -fwd).transposed()
	return Transform3D(model_to_socket, -(model_to_socket * (g.pos as Vector3)))


## How many copies of a stack the hand shows.
static func shown_count(kind: String, count: int) -> int:
	return clampi(count, 1, maxi(1, int(grip(kind).bundle)))


static func _footprint(kind: String) -> Vector3:
	var im = load("res://scripts/item_models.gd")
	return im.footprint(kind)


# ================================================================================================
# BETTER HANDS (2026-09-24): first-person grips
#
# The first-person hands hold things differently from the body: every kind names a GRIP and where
# in its model the hand goes, and tools/gripbake.gd solves the rest offline (grip_solver.gd: the
# palm pushes the model out of itself, the fingers and thumb close until they touch it) into
# scripts/hands/grip_bake.gd. The third-person body still reads GRIPS above.
#
#   grip   "power"  a fist round a handle, the handle across the palm: saws, hammers, bottles
#          "hook"   a power grip in the fingers, the thing hanging below: bucket bails
#          "pinch"  thumb and first fingers on a small or flat thing, it points along the fingers
#          "palm"   lying on an open hand, the fingers cupped round it (the default)
#   pos    model point that goes in the hand (null: the bottom middle of the model's box)
#   axis   power/hook: model direction that comes out of the THUMB side of the fist (the working
#          end); pinch/palm: model direction that points along the fingers
#   face   power/hook: model direction that faces the front of the fist (a saw's teeth, a knife's
#          edge, a hammer's face; for a hook, the way the thing hangs); pinch/palm: model
#          direction out of the palm (up)
#   pinky  power only: the working end comes out of the little-finger side instead (an ice-pick hold)
#   size   first-person longest side (metres) instead of fp_hands.fp_scale's default
#   bundle how many of a batch the first-person hand shows (instead of GRIPS' bundle)
# Kinds missing here are "palm" with pos null. Two-handed things (bulky) keep fp_hands' own layout
# and only have their fingers solved.

const FP := {
	"__torch": {"grip": "power", "pos": Vector3(0.0, 0.0, 0.035), "axis": Vector3(0, 0, -1), "face": Vector3(0, 1, 0)},
	"__jab": {"grip": "power", "pos": Vector3(0.0, 0.0, 0.02), "axis": Vector3(0, 0, -1), "face": Vector3(0, 1, 0)},
	"bone_saw": {"grip": "power", "pos": Vector3(-0.17, 0.016, 0.0), "axis": Vector3(1, 0, 0), "face": Vector3(0, 0, 1), "size": 0.36},
	"scalpel": {"grip": "power", "pos": Vector3(-0.05, 0.008, 0.0), "axis": Vector3(1, 0, 0), "face": Vector3(0, 0, 1), "size": 0.2},
	"eye_spoon": {"grip": "power", "pos": Vector3(-0.07, 0.008, 0.0), "axis": Vector3(1, 0, 0), "face": Vector3(0, 1, 0), "size": 0.22},
	"reflex_hammer": {"grip": "power", "pos": Vector3(-0.07, 0.012, 0.0), "axis": Vector3(1, 0, 0), "face": Vector3(0, 0, 1), "size": 0.24},
	"epipen": {"grip": "power", "pos": Vector3(0.0, 0.016, 0.0), "axis": Vector3(1, 0, 0), "face": Vector3(0, 1, 0), "pinky": true},
	"lifeguard_whistle": {"grip": "power", "pos": Vector3(0.005, 0.017, 0.0), "axis": Vector3(-1, 0, 0), "face": Vector3(0, 1, 0)},
	"syringe": {"grip": "power", "pos": Vector3(-0.022, 0.013, 0.0), "axis": Vector3(1, 0, 0), "face": Vector3(0, 1, 0), "bundle": 1},
	"communion_wine": {"grip": "power", "pos": Vector3(0.0, 0.1, 0.0), "axis": Vector3(0, 1, 0), "face": Vector3(0, 0, 1)},
	"tequila": {"grip": "power", "pos": Vector3(0.0, 0.1, 0.0), "axis": Vector3(0, 1, 0), "face": Vector3(0, 0, 1)},
	"placebo_pills": {"grip": "power", "pos": Vector3(0.0, 0.035, 0.0), "axis": Vector3(0, 1, 0), "face": Vector3(0, 0, 1)},
	# THE SURGICAL ROBOT: the core is held like a bottle, round its glass middle, glowing end up.
	"robot_core": {"grip": "power", "pos": Vector3(0.0, 0.107, 0.0), "axis": Vector3(0, 1, 0), "face": Vector3(0, 0, 1)},
	"fabric_softener": {"grip": "palm", "size": 0.2},
	# The quarter bucket's bail lies flat at the rim, so the pail sits in the hand instead.
	"quarter_bucket": {"grip": "palm", "size": 0.16},
	"grease_bucket": {"grip": "hook", "pos": Vector3(0.0, 0.452, 0.0), "axis": Vector3(1, 0, 0), "face": Vector3(0, -1, 0), "size": 0.2},
	"forceps": {"grip": "pinch", "pos": Vector3(-0.1, 0.012, 0.0), "axis": Vector3(1, 0, 0), "face": Vector3(0, 1, 0)},
	"pulse_oximeter": {"grip": "pinch", "pos": Vector3(-0.026, 0.022, 0.0), "axis": Vector3(1, 0, 0), "face": Vector3(0, 1, 0)},
	"foremans_clipboard": {"grip": "palm", "size": 0.2},
	"xray_film": {"grip": "palm", "size": 0.19},
}

## How far a fist's handle slants across the palm toward the fingers (z per unit of x): 1 is 45
## degrees, from the heel under the little finger to the base of the index finger.
const GRIP_DIAG := 1.0

## Where each grip puts the model's `pos` in socket space (x mirrored by side; see fp_frame()).
const FP_SOCKET := {
	"power": Vector3(0.004, 0.0, -0.028),
	"hook": Vector3(0.0, 0.014, -0.058),
	"pinch": Vector3(0.025, 0.028, -0.078),
	"palm": Vector3(0.0, 0.0, -0.012),
}

## What each grip's hand closes to when nothing stops it (fp_arms shapes; the solver stops each bone
## on the model's surface).
const FP_TARGET := {
	"power": {"f": [[1.5, 1.75, 1.0], [1.5, 1.75, 1.0], [1.5, 1.75, 1.0], [1.5, 1.7, 1.0]], "t": [1.0, 0.25, 0.7, 0.6]},
	"hook": {"f": [[1.2, 1.75, 1.1], [1.2, 1.75, 1.1], [1.2, 1.75, 1.1], [1.2, 1.7, 1.0]], "t": [0.6, 0.1, 0.4, 0.3]},
	"pinch": {"f": [[1.0, 1.0, 0.6], [1.15, 1.25, 0.7], [1.45, 1.65, 0.95], [1.45, 1.65, 0.9]], "t": [0.95, 0.35, 0.45, 0.35]},
	"palm": {"f": [[0.9, 1.0, 0.7], [0.9, 1.0, 0.7], [0.95, 1.05, 0.7], [1.0, 1.1, 0.75]], "t": [0.55, 0.15, 0.3, 0.2]},
	"two": {"f": [[1.1, 1.2, 0.8], [1.1, 1.2, 0.8], [1.1, 1.2, 0.8], [1.1, 1.2, 0.8]], "t": [0.35, 0.1, 0.25, 0.2]},
}


static func fp_spec(kind: String) -> Dictionary:
	var s: Dictionary = {"grip": "palm", "pos": null, "axis": Vector3(0, 0, -1), "face": Vector3(0, 1, 0), "pinky": false}
	s.merge(FP.get(kind, {}), true)
	return s


## Socket-space frame of a grip for the hand on `side` (-1 the left, which holds the stack): the
## point, the direction `axis` maps to and the direction `face` maps to.
static func fp_frame(grip_name: String, side: float, pinky := false) -> Array:
	var at: Vector3 = FP_SOCKET.get(grip_name, FP_SOCKET.palm)
	at.x *= side
	var a: Vector3
	var f: Vector3
	match grip_name:
		"power":
			# Across the palm from the heel under the little finger to the base of the index finger.
			a = Vector3(side, 0.0, -GRIP_DIAG).normalized() * (-1.0 if pinky else 1.0)
			f = Vector3(0, 0, -1)
		"hook":
			# Straight across the finger roots, the thing hanging below the back of the hand.
			a = Vector3(side, 0.0, 0.0) * (-1.0 if pinky else 1.0)
			f = Vector3(0, -1, 0)
		_:
			a = Vector3(0, 0, -1)
			f = Vector3(0, 1, 0)
	return [at, a, f]


## The model's transform in socket space (a first-person "Held" pivot, the model under it scaled by
## k), before the solver's palm push. `pos` is the resolved model point (fp_spec's may be null).
static func fp_transform(spec: Dictionary, pos: Vector3, k: float, side: float, frame: Array = []) -> Transform3D:
	var fr := frame if not frame.is_empty() else fp_frame(String(spec.grip), side, bool(spec.get("pinky", false)))
	var ma: Vector3 = (spec.axis as Vector3).normalized()
	var mf: Vector3 = spec.face
	mf = (mf - ma * mf.dot(ma)).normalized()
	var sa: Vector3 = fr[1]
	var sf: Vector3 = fr[2]
	sf = (sf - sa * sf.dot(sa)).normalized()
	var model := Basis(ma, mf, ma.cross(mf))
	var sock := Basis(sa, sf, sa.cross(sf))
	var rot := sock * model.transposed()
	return Transform3D(rot, (fr[0] as Vector3) - rot * (pos * k))


## BETTER HANDS: the baked first-person hold of a kind showing `n` copies, or {} (not baked: the
## hands fall back to GRIPS and a plain curl). {xf: Transform3D of the Held pivot, k, grip,
## shape (the holding hand), shape_r (two-handed: the right hand), spread (two-handed: extra half
## width)}.
static var _fp_cache := {}


static func fp_held(kind: String, n: int) -> Dictionary:
	var key := "%s:%d" % [kind, n]
	if _fp_cache.has(key):
		return _fp_cache[key]
	var out := {}
	var bake: Dictionary = GripBake.BAKE
	var e = bake.get(key, bake.get("%s:1" % kind, null))
	if e != null:
		var x: Array = e.xf
		out = {"xf": Transform3D(Basis(Vector3(x[0], x[1], x[2]), Vector3(x[3], x[4], x[5]), Vector3(x[6], x[7], x[8])), Vector3(x[9], x[10], x[11])),
			"k": float(e.k), "grip": String(e.grip), "shape": e.shape, "shape_r": e.get("shape_r", {}), "spread": float(e.get("spread", 0.0))}
	_fp_cache[key] = out
	return out


## How many copies the first-person hand shows.
static func fp_shown_count(kind: String, count: int) -> int:
	var b: int = int(FP.get(kind, {}).get("bundle", grip(kind).bundle))
	return clampi(count, 1, maxi(1, b))
