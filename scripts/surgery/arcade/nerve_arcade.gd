extends "res://scripts/surgery/arcade/arcade_game.gd"
## ARCADE SURGERY (docs/ARCADE_SURGERY.md) 5.10 -- CUT THE RIGHT ONE! Step "snip" of an Eyeball
## Extraction: part the optic nerve. The arcade rebuild of the `snip` variant of
## scripts/surgery/games/eye_ops.gd, played on the raised panel.
##
## Rhyme: bomb defusal. A rule card, a bundle of identical-looking strands, and one cut.
##
## What you do
##   A RULE CARD comes up for a second and a half and then it is gone. It is the only thing that
##   says which strand is the nerve, and it never names a position on its own: it names a COLOUR and
##   a PATTERN, or a strand's place beside one. (It also belongs on the table's OR wall monitor for
##   the whole step so a teammate can read it out; see `rule_text` and NOT BUILT HERE, below.)
##   Hold W to pull the eye up. The strands show from `show_from` and the blade is armed at
##   `arm_at`. The bundle comes out of the socket KNOTTED -- every strand a grey rope crossing every
##   other one -- and only combs itself out while the eye is held up, faster the higher you hold it.
##   Hold it right at the top and it combs out quickest, and after `strain_grace` seconds up there
##   you are stretching the nerve and paying for it by the second. That is the whole squeeze: the
##   only way to read the strands is the thing that hurts the patient.
##   Then click the one the rule names. Right: a slice, and the eye is free. Wrong: six vitals, that
##   strand parts and bleeds over its neighbours, and the eye sags back down.
##   And if the Hive is light on sedation, every stir SWAPS two neighbouring strands, in the open,
##   in four tenths of a second. Watch them or lose them.
##
## THE RULE IS A STANDING ORDER, NOT A LABEL (judgment call, see the report). The strands are
## anonymous; the rule decides which one is the nerve FROM THE ARRANGEMENT IN FRONT OF YOU. So "the
## nerve is directly left of the amber dotted strand" means whatever is left of it NOW -- if a stir
## moves the amber one, the answer moves with it. This is what makes a swap worth watching instead
## of a gotcha, and it is what lets the invariant below be true at every instant:
##
##   AT EVERY INSTANT THE RULE RESOLVES TO EXACTLY ONE STRAND, AND THAT STRAND IS ALIVE.
##
## It is held by construction at both ends: the generator re-rolls until the rule resolves to one
## live strand (and until at least one legal swap exists, so stirs are never dead), and a stir only
## ever performs a swap that leaves it resolving to one live strand. `self_test()` asserts it over
## hundreds of seeds and thousands of swaps, loudly, because a rule that goes ambiguous or lands on
## a severed strand is an unwinnable step.
##
## Result {"eye_removed": true, "snip_quality": q}, the same flag the legacy game finishes with.
##
## NOT BUILT HERE: 5.10 also wants the rule card left up on that table's OR wall monitor for the
## whole step. That is scripts/orscreen/*, outside this file, so it is deliberately not built. The
## rule is on `rule_text` (and in `net_pack` as `rl`, plus `strand_rows()` for the strands as they
## stand) so the monitor can pick it up later without this file changing.

enum Pattern { SOLID, STRIPED, DOTTED }
## The rule templates. Everything but NTH is fixed to a strand's own colour and pattern or to the
## strands beside it -- never to an absolute position, which a stir would make a lie.
enum Rule { ONLY_PATTERN, ONLY_PAIR, LEFT_OF, RIGHT_OF, BETWEEN, NTH }

const COLOUR_NAMES := ["AMBER", "TEAL", "VIOLET", "ROSE", "PALE"]
const PATTERN_NAMES := ["SOLID", "STRIPED", "DOTTED"]
const ORDINALS := ["FIRST", "SECOND", "THIRD", "FOURTH", "FIFTH", "SIXTH"]
## Points a strand's curve is drawn and hit-tested along.
const SAMPLES := 17
const PHI := 0.6180339887498949

# -- the bundle ---------------------------------------------------------------------------------
@export_range(2, 8) var min_strands := 4
@export_range(2, 8) var max_strands := 6
## Difficulty per extra strand: 4 at shift 1-2, 5 from shift 3, 6 from shift 5.
@export_range(0.05, 1.0, 0.01) var strands_per_diff := 0.25

# -- the eye and the lift -----------------------------------------------------------------------
## Seconds of held W from resting on the socket to fully up, and seconds to sag back. As the legacy
## game (LIFT_UP_SECONDS / LIFT_DOWN_SECONDS), so it feels like the same eye.
@export_range(0.5, 6.0, 0.1) var lift_up_seconds := 2.4
@export_range(0.5, 6.0, 0.1) var lift_down_seconds := 1.5
## Lift the strands come into view at, and the lift the blade arms at.
@export_range(0.0, 1.0, 0.01) var show_from := 0.35
@export_range(0.0, 1.0, 0.01) var arm_at := 0.8
## Above this the nerve is taut; `strain_grace` cumulative seconds up there and it starts tearing.
@export_range(0.0, 1.0, 0.01) var strain_from := 0.95
@export_range(0.0, 20.0, 0.1) var strain_grace := 3.0
@export_range(0.0, 10.0, 0.5) var strain_botch := 1.0
## What a parted strand costs, and how far the eye sags when one lets go.
@export_range(0.0, 20.0, 0.5) var wrong_botch := 6.0
@export_range(0.0, 1.0, 0.01) var sag_on_wrong := 0.4

# -- combing the knot out -----------------------------------------------------------------------
## Knot per second at full lift, before difficulty. Nothing combs out below `untangle_from`.
@export_range(0.05, 3.0, 0.01) var untangle_rate := 0.45
@export_range(0.0, 1.0, 0.01) var untangle_from := 0.5
## Knot left at which colour and pattern become legible. Above it every strand is grey rope.
@export_range(0.05, 1.0, 0.01) var tangle_readable := 0.35

# -- cutting ------------------------------------------------------------------------------------
@export_range(0.5, 12.0, 0.1) var hit_mm := 3.5
@export_range(0.1, 3.0, 0.05) var slice_time := 0.8
## How long the rule card holds at the start. It is driven off `play_t`, so it freezes with the game.
@export_range(0.2, 6.0, 0.1) var rule_card_time := 1.5
@export_range(0.05, 2.0, 0.05) var swap_time := 0.4
@export_range(0.0, 1.0, 0.01) var jolt_lift_drop := 0.3

# -- the diagram, in millimetres ----------------------------------------------------------------
@export_range(3.0, 30.0, 0.5) var eye_mm := 11.0          ## the eye's radius on the panel
@export_range(-40.0, 40.0, 0.5) var eye_rest_y := 19.0    ## its centre at lift 0...
@export_range(-40.0, 40.0, 0.5) var eye_high_y := -17.0   ## ... and at lift 1
@export_range(-40.0, 40.0, 0.5) var socket_y := 30.0      ## the socket's mouth
@export var socket_mm := Vector2(30.0, 9.0)               ## and its half-size
## Half the width the bundle fans out to at the socket, and where it leaves the eye.
@export_range(4.0, 58.0, 0.5) var spread_mm := 30.0
@export_range(1.0, 20.0, 0.5) var eye_spread_mm := 8.0
@export_range(0.0, 6.0, 0.1) var sway_mm := 1.1
@export_range(0.05, 4.0, 0.05) var sway_hz := 0.45
@export_range(1.0, 30.0, 0.5) var blot_mm := 9.0          ## blood over a parted strand

# -- the strand hues (local to this game; panel_style.gd is shared and stays as it is) -----------
@export var hue_amber := Color(0.95, 0.68, 0.18)
@export var hue_teal := Color(0.24, 0.84, 0.80)
@export var hue_violet := Color(0.68, 0.46, 0.97)
@export var hue_rose := Color(0.96, 0.36, 0.55)
@export var hue_pale := Color(0.90, 0.94, 0.86)

# -- audio --------------------------------------------------------------------------------------
@export var slice_cue := "surgery_tear"
@export var wrong_cue := "surgery_saw_squelch"
@export var swap_cue := "surgery_swish"
@export var arm_cue := "surgery_beep"
@export var strain_cue := "surgery_beep_low"
@export var miss_cue := "surgery_click"
@export_range(-40.0, 0.0, 1.0) var swap_volume := -14.0

# ---- replicated state ----
## 0 resting on the socket, 1 pulled right up. Creeps: never snapped in net_pack.
var lift := 0.0
## 1 knotted, 0 combed out. Creeps too.
var tangle := 1.0
## Display position -> strand id. This is the arrangement the rule is resolved against.
var order: Array = []
## Strand id -> still whole.
var alive: Array = []
var slicing := -1                 ## the strand the blade is going through, or -1
var slice_t := 0.0
var strain_t := 0.0               ## cumulative seconds held above `strain_from`
var wrongs := 0
var swaps := 0
var cursor_mm := Vector2(0.0, 0.0)
## The rule, in plain words. THE OR WALL MONITOR READS THIS (see the header).
var rule_text := ""

# ---- derived from the seed, identical on every machine ----
## Strand id -> {"c": colour index, "p": Pattern}. Id order is the arrangement it started in.
var strands: Array = []
var rule: Array = []              ## [Rule kind, p0, p1, p2, p3]; also what goes over the wire
var hive := true

# ---- local ----
var _t := 0.0
var _rng := RandomNumberGenerator.new()
var _shown_slot: Array = []       ## strand id -> where it is drawn, eased toward its real slot
var _strain_acc := 0.0
var _strain_charges := 0
var _hint := ""
var _hint_t := 0.0
var _flash := 0.0
var _seen_wrongs := 0
var _seen_swaps := 0
var _armed_beeped := false
var _strain_beeped := false

# ---- bot ----
var _bt := 0.0
var _b_aim := Vector2(0.0, 6.0)
var _b_seq := 0
var _b_target := -1
var _b_ready_t := 0.0
var _b_click := false


# ---------------------------------------------------------------------------- setup

func card_word_for_start() -> String:
	return "CUT!"


func build_game() -> void:
	_rng.seed = int(ctx.get("seed", 1)) ^ 0x4e12
	hive = bool(ctx.get("patient", {}).get("monster", false)) or String(ctx.get("patient_id", "")) == "hive"
	_generate()
	_update_progress()


## 4 strands at shift 1-2, 5 from shift 3, 6 from shift 5.
func strand_count() -> int:
	var extra := int(floor(maxf(0.0, diff - 1.0) / maxf(0.01, strands_per_diff)))
	return clampi(min_strands + extra, min_strands, max_strands)


# ---------------------------------------------------------------------------- the strands and the rule

## Roll a bundle and a rule together until the pair is legal, then keep it. Everything comes off
## `ctx.seed`, so every machine gets the same strands, the same rule and the same swaps.
func _generate() -> void:
	var n := strand_count()
	for attempt in 80:
		_roll_strands(n)
		_roll_rule(n, attempt)
		if _rule_legal():
			rule_text = _rule_words()
			return
	# Nothing rolled clean in eighty tries (it never has): fall back to a bundle that cannot fail --
	# a full colour-by-pattern grid, where every strand has a twin in both, named by both.
	_fallback(n)
	rule_text = _rule_words()


## A grid of `nc` colours by `np` patterns with a few cells knocked out, so colours and patterns
## REPEAT. A bundle of six strands with six different colours would be a colour-matching exercise;
## this one makes you read the colour and the pattern together.
func _roll_strands(n: int) -> void:
	var grid: Array = []
	for tries in 12:
		var nc: int = _rng.randi_range(2, 3)
		var np: int = _rng.randi_range(2, 3)
		if nc * np < n or nc * np - n > 3:
			continue
		var cols: Array = _pick(COLOUR_NAMES.size(), nc)
		var pats: Array = _pick(PATTERN_NAMES.size(), np)
		grid.clear()
		for c in cols:
			for p in pats:
				grid.append({"c": int(c), "p": int(p)})
		while grid.size() > n:
			grid.remove_at(_rng.randi() % grid.size())
		break
	if grid.size() != n:
		# A 2 x 2 grid padded out: always enough for four to six.
		grid.clear()
		for i in n:
			grid.append({"c": i % 2, "p": (i / 2) % 3})
	_shuffle(grid)
	strands = grid
	order.clear()
	alive.clear()
	_shown_slot.clear()
	for i in n:
		order.append(i)
		alive.append(true)
		_shown_slot.append(float(i))


## `k` distinct indices under `count`.
func _pick(count: int, k: int) -> Array:
	var pool: Array = []
	for i in count:
		pool.append(i)
	_shuffle(pool)
	return pool.slice(0, k)


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j: int = _rng.randi() % (i + 1)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


## Pick a template and its parameters. Absolute position (NTH) is for a graft only: on a Hive the
## strands get swapped around and a position is a lie the moment they do.
func _roll_rule(n: int, attempt: int) -> void:
	var kinds: Array = [Rule.ONLY_PATTERN, Rule.ONLY_PAIR, Rule.LEFT_OF, Rule.RIGHT_OF, Rule.BETWEEN]
	if not hive:
		kinds.append(Rule.NTH)
	var kind: int = int(kinds[(_rng.randi() + attempt) % kinds.size()])
	var pick: int = _rng.randi() % n
	var other: int = (pick + 1 + _rng.randi() % maxi(1, n - 1)) % n
	match kind:
		Rule.ONLY_PATTERN:
			rule = [kind, int(strands[pick].p), 0, 0, 0]
		Rule.ONLY_PAIR:
			rule = [kind, int(strands[pick].c), int(strands[pick].p), 0, 0]
		Rule.LEFT_OF, Rule.RIGHT_OF:
			rule = [kind, int(strands[pick].c), int(strands[pick].p), 0, 0]
		Rule.BETWEEN:
			rule = [kind, int(strands[pick].c), int(strands[pick].p),
				int(strands[other].c), int(strands[other].p)]
		Rule.NTH:
			rule = [kind, _rng.randi() % n, 0, 0, 0]


## Every check a rolled bundle and rule must pass before the step will use it.
func _rule_legal() -> bool:
	if strands.is_empty() or rule.is_empty():
		return false
	# One answer, and it is a strand you can still cut.
	var m := matches_in(order)
	if m.size() != 1 or not bool(alive[int(order[m[0]])]):
		return false
	# Colour is never enough on its own: every pair the rule names must share its colour with one
	# strand and its pattern with another, so both halves have to be read.
	for pair in _named_pairs():
		if not _has_twin(int(pair[0]), int(pair[1])):
			return false
	# And a stir has to have something to do, or a badly sedated Hive is quieter than a good one.
	if legal_swaps(order).is_empty():
		return false
	return true


## The (colour, pattern) pairs the rule's words point at.
func _named_pairs() -> Array:
	match int(rule[0]):
		Rule.ONLY_PAIR, Rule.LEFT_OF, Rule.RIGHT_OF:
			return [[int(rule[1]), int(rule[2])]]
		Rule.BETWEEN:
			return [[int(rule[1]), int(rule[2])], [int(rule[3]), int(rule[4])]]
	return []


func _has_twin(c: int, p: int) -> bool:
	var same_c := 0
	var same_p := 0
	for s in strands:
		if int(s.c) == c and int(s.p) != p:
			same_c += 1
		if int(s.p) == p and int(s.c) != c:
			same_p += 1
	return same_c > 0 and same_p > 0


## The last resort: a full grid, so every pair has both twins, named by both. Permutation-proof by
## construction -- ONLY_PAIR does not care where anything is.
func _fallback(n: int) -> void:
	strands = []
	order = []
	alive = []
	_shown_slot = []
	var np: int = 2 if n <= 4 else 3
	var nc: int = int(ceil(float(n) / float(np)))
	for i in n:
		strands.append({"c": i % nc, "p": (i / nc) % np})
		order.append(i)
		alive.append(true)
		_shown_slot.append(float(i))
	# Name a strand that really does have both twins.
	for i in n:
		if _has_twin(int(strands[i].c), int(strands[i].p)):
			rule = [Rule.ONLY_PAIR, int(strands[i].c), int(strands[i].p), 0, 0]
			return
	rule = [Rule.ONLY_PAIR, int(strands[0].c), int(strands[0].p), 0, 0]


## Which DISPLAY POSITIONS in `ord` satisfy the rule. Exactly one, always -- that is the invariant
## the generator and the swap guard hold up between them.
func matches_in(ord: Array) -> Array:
	var out: Array = []
	var n := ord.size()
	match int(rule[0]):
		Rule.ONLY_PATTERN:
			for i in n:
				if int(strands[int(ord[i])].p) == int(rule[1]):
					out.append(i)
		Rule.ONLY_PAIR:
			for i in n:
				var s: Dictionary = strands[int(ord[i])]
				if int(s.c) == int(rule[1]) and int(s.p) == int(rule[2]):
					out.append(i)
		Rule.LEFT_OF:
			var a := _pos_of(ord, int(rule[1]), int(rule[2]))
			if a > 0:
				out.append(a - 1)
		Rule.RIGHT_OF:
			var b := _pos_of(ord, int(rule[1]), int(rule[2]))
			if b >= 0 and b < n - 1:
				out.append(b + 1)
		Rule.BETWEEN:
			var p := _pos_of(ord, int(rule[1]), int(rule[2]))
			var q := _pos_of(ord, int(rule[3]), int(rule[4]))
			if p >= 0 and q >= 0 and absi(p - q) == 2:
				out.append((p + q) / 2)
		Rule.NTH:
			if int(rule[1]) < n:
				out.append(int(rule[1]))
	return out


func _pos_of(ord: Array, c: int, p: int) -> int:
	for i in ord.size():
		var s: Dictionary = strands[int(ord[i])]
		if int(s.c) == c and int(s.p) == p:
			return i
	return -1


## The strand the rule names right now, or -1 if something has gone wrong (it never has).
func answer() -> int:
	var m := matches_in(order)
	return int(order[m[0]]) if m.size() == 1 else -1


## Which adjacent pairs a stir is allowed to swap: the ones that leave the rule resolving to exactly
## one strand that is still alive. THE GUARD. Without it a stir can push the rule's anchor to the
## end of the row, or onto a strand that has already been cut, and the step becomes unwinnable.
func legal_swaps(ord: Array) -> Array:
	var out: Array = []
	for i in ord.size() - 1:
		if not bool(alive[int(ord[i])]) or not bool(alive[int(ord[i + 1])]):
			continue
		var test := ord.duplicate()
		var tmp = test[i]
		test[i] = test[i + 1]
		test[i + 1] = tmp
		var m := matches_in(test)
		if m.size() == 1 and bool(alive[int(test[m[0]])]):
			out.append(i)
	return out


func _rule_words() -> String:
	var kind := int(rule[0])
	match kind:
		Rule.ONLY_PATTERN:
			return "THE NERVE IS THE ONLY %s STRAND." % PATTERN_NAMES[int(rule[1])]
		Rule.ONLY_PAIR:
			return "THE NERVE IS THE ONLY %s %s STRAND." % [COLOUR_NAMES[int(rule[1])], PATTERN_NAMES[int(rule[2])]]
		Rule.LEFT_OF:
			return "THE NERVE IS DIRECTLY LEFT OF THE %s %s STRAND." % [COLOUR_NAMES[int(rule[1])], PATTERN_NAMES[int(rule[2])]]
		Rule.RIGHT_OF:
			return "THE NERVE IS DIRECTLY RIGHT OF THE %s %s STRAND." % [COLOUR_NAMES[int(rule[1])], PATTERN_NAMES[int(rule[2])]]
		Rule.BETWEEN:
			return "THE NERVE IS BETWEEN THE %s %s AND THE %s %s." % [COLOUR_NAMES[int(rule[1])],
				PATTERN_NAMES[int(rule[2])], COLOUR_NAMES[int(rule[3])], PATTERN_NAMES[int(rule[4])]]
		Rule.NTH:
			return "THE NERVE IS THE %s STRAND FROM THE LEFT." % ORDINALS[clampi(int(rule[1]), 0, ORDINALS.size() - 1)]
	return ""


## For the OR wall monitor, later: the strands left to right as they stand, with the rule. Nothing
## in this file calls it; it is the seam so scripts/orscreen/* never has to reach inside.
func strand_rows() -> Array:
	var out: Array = []
	for pos in order.size():
		var s: Dictionary = strands[int(order[pos])]
		out.append({"colour": COLOUR_NAMES[int(s.c)], "pattern": PATTERN_NAMES[int(s.p)],
			"cut": not bool(alive[int(order[pos])])})
	return out


# ---------------------------------------------------------------------------- the diagram

func eye_at() -> Vector2:
	return Vector2(0.0, lerpf(eye_rest_y, eye_high_y, clampf(lift, 0.0, 1.0)))


## Where a strand leaves the underside of the eye, by the slot it is drawn in.
func _attach(slot: float) -> Vector2:
	var n: int = maxi(1, strands.size() - 1)
	var k: float = (slot / float(n)) * 2.0 - 1.0 if strands.size() > 1 else 0.0
	var e := eye_at()
	return e + Vector2(k * eye_spread_mm, eye_mm * 0.62 - absf(k) * eye_mm * 0.14)


## And where it goes into the socket.
func _root(slot: float) -> Vector2:
	var n: int = maxi(1, strands.size() - 1)
	var k: float = slot / float(n) if strands.size() > 1 else 0.5
	return Vector2(lerpf(-spread_mm, spread_mm, k), socket_y - 2.0)


## The knot: while `tangle` is up every strand's middle is dragged toward one bunch with its own
## seeded throw, so they cross each other and nothing can be followed from end to end.
func _knot_off(id: int) -> Vector2:
	var u := fposmod(float(id + 1) * PHI, 1.0)
	var v := fposmod(float(id + 3) * PHI * 2.0, 1.0)
	return Vector2((u - 0.5) * spread_mm * 2.2, (v - 0.5) * 9.0)


func _sway(id: int) -> Vector2:
	var ph := fposmod(float(id + 2) * PHI, 1.0) * TAU
	return Vector2(sin(_t * TAU * sway_hz + ph), cos(_t * TAU * sway_hz * 0.7 + ph) * 0.35) * sway_mm


## A point along a strand, 0 at the eye and 1 at the socket. Quadratic, so the knot is one control
## point and the comb-out is just that point sliding home.
func strand_point(id: int, t: float) -> Vector2:
	var slot: float = float(_shown_slot[id]) if id < _shown_slot.size() else 0.0
	var a := _attach(slot)
	var b := _root(slot)
	var mid := (a + b) * 0.5 + _knot_off(id) * tangle + _sway(id) * (0.35 + 0.65 * lift)
	var u := 1.0 - t
	return a * (u * u) + mid * (2.0 * u * t) + b * (t * t)


## The whole curve in millimetres, for the hit test...
func strand_points(id: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in SAMPLES:
		out.append(strand_point(id, float(i) / float(SAMPLES - 1)))
	return out


## ... and in panel pixels, for drawing it. Keep the two apart: everything this game reasons about
## is in millimetres and only the painter works in pixels.
func strand_px(id: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in SAMPLES:
		out.append(px(strand_point(id, float(i) / float(SAMPLES - 1))))
	return out


## The closest strand to a point on the panel, within `hit_mm`. A live strand wins a tie, so a
## severed one lying over it never shields it.
func strand_at(p: Vector2) -> int:
	var best := -1
	var best_d := hit_mm
	var best_dead := -1
	var best_dead_d := hit_mm
	for id in strands.size():
		var d := _distance_to(id, p)
		if bool(alive[id]):
			if d <= best_d:
				best_d = d
				best = id
		elif d <= best_dead_d:
			best_dead_d = d
			best_dead = id
	return best if best >= 0 else best_dead


func _distance_to(id: int, p: Vector2) -> float:
	var pts := strand_points(id)
	var best := 1e9
	for i in pts.size() - 1:
		best = minf(best, _seg_distance(p, pts[i], pts[i + 1]))
	return best


static func _seg_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## How much of the colour and the pattern is readable: nothing while the bundle is knotted.
func read_k() -> float:
	return clampf(1.0 - tangle / maxf(0.01, tangle_readable), 0.0, 1.0)


## The rule card holds for `rule_card_time` of PLAY -- driven straight off `play_t`, so it is the
## same on every machine for free, and it stops dead when the operator walks away.
func rule_card_k() -> float:
	if play_state == Play.DONE:
		return 0.0
	return clampf((rule_card_time - play_t) / maxf(0.01, rule_card_time), 0.0, 1.0)


# ---------------------------------------------------------------------------- playing

func keys() -> Array:
	if play_state == Play.DONE or slicing >= 0:
		return []
	if lift < show_from:
		return [["Hold W", "pull the eye up"]]
	return [["Hold W", "hold it up"], ["Mouse", "pick a strand"], ["Click", "cut it"]]


func hint() -> String:
	var base := super.hint()
	if base != "":
		return base
	if play_state == Play.DONE:
		return "Free."
	if slicing >= 0:
		return "Cutting."
	if _hint_t > 0.0:
		return _hint
	if strain_t > strain_grace:
		return "The nerve is stretching. Let it down."
	if lift < show_from:
		return "Pull the eye up: hold W."
	if tangle > tangle_readable:
		return "They are knotted. Hold it up and let them comb out."
	if lift < arm_at:
		return "Higher. The blade arms when the nerve is taut."
	return "Cut the one the rule named."


func play(p: Vector2, buttons: int, edges: int, delta: float) -> void:
	cursor_mm = p
	if slicing >= 0:
		return
	if buttons & BUTTON_UP:
		lift = minf(1.0, lift + delta / maxf(0.05, lift_up_seconds))
	else:
		lift = maxf(0.0, lift - delta / maxf(0.05, lift_down_seconds))
	if (edges & BUTTON_PRIMARY) != 0:
		_try_cut(p)


func _try_cut(p: Vector2) -> void:
	if lift < arm_at:
		_say("Pull the eye up first: hold W.", 2.0)
		return
	var id := strand_at(p)
	if id < 0:
		_say("Nothing under the blade.", 1.5)
		audio(miss_cue, -18.0, 0.1)
		return
	if not bool(alive[id]):
		_say("That one is already cut.", 1.5)
		return
	if id == answer():
		slicing = id
		slice_t = 0.0
		audio(slice_cue, -4.0, 0.1)
	else:
		_wrong(id)


func _wrong(id: int) -> void:
	alive[id] = false
	wrongs += 1
	_flash = 0.5
	lift = maxf(0.0, lift - sag_on_wrong)
	shake(0.75)
	audio(wrong_cue, -2.0, 0.1)
	cost(wrong_botch, "That wasn't the nerve")
	_say("That wasn't it. It is bleeding over the others.", 2.5)
	ghost(0.35)


func advance(delta: float) -> void:
	if slicing >= 0:
		slice_t += delta
		if slice_t >= slice_time:
			_through()
		_update_progress()
		return
	# The knot only combs out while the eye is up, and faster the higher it is held -- which is
	# exactly where the nerve starts to tear. That trade is the game.
	if lift > untangle_from and tangle > 0.0:
		tangle = maxf(0.0, tangle - untangle_rate * (lift - untangle_from) * delta / sqrt(diff))
	if lift > strain_from:
		strain_t += delta
		if strain_t > strain_grace:
			_strain_acc += delta
			while _strain_acc >= 1.0:
				_strain_acc -= 1.0
				_strain_charges += 1
				cost(strain_botch, "The nerve is stretching")
	_update_progress()


func _through() -> void:
	alive[slicing] = false
	var b = body()
	if b != null and b.has_method("apply_flags"):
		var f: Dictionary = (ctx.get("flags", {}) as Dictionary).duplicate()
		f["eye_removed"] = true
		b.apply_flags(f)
	quality = snip_quality()
	arcade_finish({"eye_removed": true, "snip_quality": quality})


func snip_quality() -> float:
	var q := 1.0 - 0.3 * float(wrongs) - 0.06 * float(_strain_charges)
	return snappedf(clampf(q, 0.05, 1.0), 0.01)


func _update_progress() -> void:
	if slicing >= 0:
		progress = clampf(0.75 + 0.25 * slice_t / maxf(0.05, slice_time), 0.0, 1.0)
		return
	progress = clampf(0.25 * minf(lift / maxf(0.05, arm_at), 1.0) + 0.5 * (1.0 - tangle), 0.0, 0.75)


func _say(text: String, seconds: float) -> void:
	_hint = text
	_hint_t = seconds


## A jerk drops the eye and shuffles the bundle: two neighbours change places in the open, over
## `swap_time`, and it is on you to keep your eye on them. Operator only, like every other stir
## reaction; the new arrangement goes out in the state blob.
func on_jolt(_offset: Vector2, strength: float, _duration: float) -> void:
	shake(clampf(0.4 + strength * 0.6, 0.0, 1.0))
	lift = maxf(0.0, lift - jolt_lift_drop)
	_stir_swap()


func _stir_swap() -> void:
	if slicing >= 0 or play_state == Play.DONE:
		return
	var legal := legal_swaps(order)
	if legal.is_empty():
		return
	var at: int = int(legal[_rng.randi() % legal.size()])
	var tmp = order[at]
	order[at] = order[at + 1]
	order[at + 1] = tmp
	swaps += 1
	_say("They moved.", 2.0)


func animate(delta: float) -> void:
	_t += delta
	_flash = maxf(0.0, _flash - delta)
	_hint_t = maxf(0.0, _hint_t - delta)
	# The swap is visible and trackable: strands slide to their new slots instead of teleporting.
	var speed := delta / maxf(0.05, swap_time)
	for pos in order.size():
		var id := int(order[pos])
		if id < _shown_slot.size():
			_shown_slot[id] = move_toward(float(_shown_slot[id]), float(pos), speed)


# ---------------------------------------------------------------------------- the body

func react() -> void:
	if wrongs > _seen_wrongs:
		_seen_wrongs = wrongs
		var b0 = body()
		if b0 != null and b0.has_method("stir"):
			b0.stir(0.5)
	if swaps > _seen_swaps:
		_seen_swaps = swaps
		audio(swap_cue, swap_volume, 0.12)
	if lift >= arm_at and not _armed_beeped:
		_armed_beeped = true
		audio(arm_cue, -16.0)
	elif lift < arm_at * 0.8:
		_armed_beeped = false
	if strain_t > strain_grace and not _strain_beeped:
		_strain_beeped = true
		audio(strain_cue, -10.0)
	elif strain_t <= strain_grace:
		_strain_beeped = false
	var b = body()
	if b != null and b.has_method("set_bleeding"):
		var site := String(ctx.get("step", {}).get("site", "eye"))
		var amount := clampf(0.12 + 0.2 * float(wrongs) + 0.25 * lift + _flash * 0.4, 0.0, 1.0)
		b.set_bleeding(site, amount if play_state != Play.DONE else 0.35)


# ---------------------------------------------------------------------------- drawing

func paint_game(c: CanvasItem) -> void:
	if panel == null or strands.is_empty():
		return
	var st := style()
	_paint_socket(c, st)
	var show := clampf((lift - show_from) / 0.12, 0.0, 1.0)
	if show > 0.0:
		for pos in order.size():
			_paint_strand(c, st, int(order[pos]), show)
		_paint_blots(c, st)
		_paint_hover(c, st)
	_paint_eye(c, st)
	if slicing >= 0:
		_paint_blade(c, st)
	_paint_lift_gauge(c, st)
	_paint_readout(c, st)
	if rule_card_k() > 0.0:
		_paint_rule_card(c, st)
	if _flash > 0.0:
		c.draw_rect(Rect2(Vector2.ZERO, panel.tex_size()), Color(st.danger, _flash * 0.18))


## The empty socket the bundle comes out of: a dark mouth with a wet rim.
func _paint_socket(c: CanvasItem, st: StyleScript) -> void:
	var pts := PackedVector2Array()
	for i in 40:
		var a := TAU * float(i) / 40.0
		pts.append(px(Vector2(0.0, socket_y) + Vector2(cos(a) * socket_mm.x, sin(a) * socket_mm.y)))
	c.draw_colored_polygon(pts, st.blood_dark)
	st.glow_poly(c, pts, Color(st.danger, 0.7), st.thin)
	c.draw_polyline(pts, Color(st.line_dim, 0.9), st.thin)
	# Hatching across the mouth, so it reads as a hole and not a puddle.
	for i in 7:
		var x := lerpf(-socket_mm.x * 0.8, socket_mm.x * 0.8, float(i) / 6.0)
		c.draw_line(px(Vector2(x, socket_y - socket_mm.y * 0.45)),
			px(Vector2(x, socket_y + socket_mm.y * 0.45)), Color(st.line_dim, 0.18), st.hair)


func colour_of(id: int) -> Color:
	match int(strands[id].c):
		0: return hue_amber
		1: return hue_teal
		2: return hue_violet
		3: return hue_rose
	return hue_pale


## One strand. While the bundle is knotted every strand is the same grey rope; the colour and the
## pattern fade in together as it combs out, so neither one ever carries the answer on its own.
func _paint_strand(c: CanvasItem, st: StyleScript, id: int, show: float) -> void:
	var pts := strand_px(id)
	var k := read_k()
	var live := bool(alive[id])
	var col: Color = Color(st.line_dim, 0.85).lerp(colour_of(id), k)
	if not live:
		col = st.blood
	col.a *= show
	if live:
		st.glow_poly(c, pts, col, st.hair)
	if int(strands[id].p) == Pattern.DOTTED and live:
		# Dotted: a faint thread with beads along it -- but only once the bundle is combed out.
		# While it is knotted this is the same grey rope as every other one, on purpose: the pattern
		# has to be as hard to read as the colour or waiting for the knot buys you nothing.
		c.draw_polyline(pts, Color(col, lerpf(1.0, 0.22, k) * show), st.thin)
		for i in range(1, pts.size(), 2):
			c.draw_circle(pts[i], st.thin * 1.5, Color(col, k * show))
	elif not live:
		# A parted strand: the two ends droop away from the cut and neither one is drawn through it.
		var half := int(pts.size() / 2)
		var top := PackedVector2Array()
		var bot := PackedVector2Array()
		for i in half - 1:
			top.append(pts[i] + Vector2(0.0, px_len(1.0) * float(i) * 0.12))
		for i in range(half + 2, pts.size()):
			bot.append(pts[i] - Vector2(0.0, px_len(1.0) * 0.6))
		if top.size() > 1:
			c.draw_polyline(top, col, st.thin)
		if bot.size() > 1:
			c.draw_polyline(bot, col, st.thin)
	else:
		c.draw_polyline(pts, col, st.thin * 1.4)
	if int(strands[id].p) == Pattern.STRIPED and live:
		# Striped: rungs across the strand, drawn in the panel's own line colour so the pattern is
		# there in black and white as well as in the hue.
		for i in range(1, pts.size() - 1, 2):
			var d: Vector2 = (pts[i + 1] - pts[i - 1]).normalized()
			var n := Vector2(-d.y, d.x) * px_len(1.6)
			c.draw_line(pts[i] - n, pts[i] + n, Color(st.line, 0.9 * k * show), st.thin)


## The blood a parted strand throws over the ones beside it.
func _paint_blots(c: CanvasItem, st: StyleScript) -> void:
	for id in strands.size():
		if bool(alive[id]):
			continue
		var at := px(strand_point(id, 0.55))
		var r := px_len(blot_mm)
		c.draw_circle(at, r * 0.78, Color(st.blood, 0.85))
		for j in 5:
			var u := fposmod(float(id * 7 + j + 1) * PHI, 1.0)
			var v := fposmod(float(id * 11 + j + 2) * PHI, 1.0)
			c.draw_circle(at + Vector2(cos(u * TAU), sin(u * TAU)) * r * v * 0.9,
				r * (0.22 + 0.3 * v), Color(st.blood, 0.75))


## The strand under the blade: brackets round it, not just a colour change.
func _paint_hover(c: CanvasItem, st: StyleScript) -> void:
	if slicing >= 0 or lift < arm_at:
		return
	var id := strand_at(cursor_mm)
	if id < 0 or not bool(alive[id]):
		return
	var pts := strand_px(id)
	c.draw_polyline(pts, Color(st.line, 0.55), st.outline * 1.4)
	var at := px(strand_point(id, 0.5))
	var r := px_len(hit_mm + 1.5)
	for s: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		c.draw_line(at + Vector2(s.x * r, s.y * r), at + Vector2(s.x * r * 0.45, s.y * r), st.good, st.thin)
		c.draw_line(at + Vector2(s.x * r, s.y * r), at + Vector2(s.x * r, s.y * r * 0.45), st.good, st.thin)


## The eye itself, on its way up. Flat shapes: a wet ball, a ring of iris, a slit pupil.
func _paint_eye(c: CanvasItem, st: StyleScript) -> void:
	var at := px(eye_at())
	var r := px_len(eye_mm)
	st.glow_circle(c, at, r, st.line, st.thin)
	c.draw_circle(at, r, Color(st.bg_inner, 0.96))
	c.draw_arc(at, r, 0.0, TAU, 40, st.line, st.outline)
	var iris := r * 0.52
	c.draw_circle(at, iris, Color(hue_amber, 0.30))
	c.draw_arc(at, iris, 0.0, TAU, 28, Color(hue_amber, 0.9), st.thin)
	# A slit, turned as the eye rolls back while it is pulled up.
	var roll := lerpf(0.0, 0.55, clampf(lift, 0.0, 1.0))
	var d := Vector2(sin(roll), -cos(roll))
	c.draw_line(at - d * iris * 0.8, at + d * iris * 0.8, st.bg, st.outline * 1.6)
	c.draw_arc(at, r * 0.82, PI * 1.15, PI * 1.45, 12, Color(st.line, 0.5), st.thin)
	if strain_t > strain_grace:
		c.draw_arc(at, r + px_len(2.5), 0.0, TAU, 32, Color(st.danger, 0.5 + 0.35 * sin(_t * 12.0)), st.thin)


func _paint_blade(c: CanvasItem, st: StyleScript) -> void:
	var k := clampf(slice_t / maxf(0.05, slice_time), 0.0, 1.0)
	var at := px(strand_point(slicing, 0.5))
	var w := px_len(9.0)
	var drop := px_len(lerpf(11.0, 0.0, minf(1.0, k * 2.0)))
	var a := at + Vector2(-w, -drop)
	var b := at + Vector2(w * 0.35, -drop)
	c.draw_line(a, b, st.steel, st.outline * 1.6)
	c.draw_line(b, b + Vector2(px_len(7.0), px_len(-5.0)), Color(st.steel, 0.8), st.outline)
	if k > 0.5:
		var flush := px_len(2.0 + 7.0 * (k - 0.5) * 2.0)
		c.draw_circle(at, flush, Color(st.blood, 0.8 * (1.0 - (k - 0.5) * 1.4)))


## The lift, as a column up the left edge: the arm line and the tear line are marks on it, not
## colours alone, and the bar hatches once it is over the tear line.
func _paint_lift_gauge(c: CanvasItem, st: StyleScript) -> void:
	var x := -54.0
	var top := -30.0
	var bottom := 30.0
	var a := px(Vector2(x, bottom))
	var b := px(Vector2(x, top))
	c.draw_line(a, b, Color(st.line_dim, 0.6), st.thin)
	var y := lerpf(bottom, top, clampf(lift, 0.0, 1.0))
	var straining := lift > strain_from
	var col: Color = st.danger if straining else (st.good if lift >= arm_at else st.line)
	st.glow_line(c, a, px(Vector2(x, y)), col, st.outline)
	c.draw_line(a, px(Vector2(x, y)), col, st.outline * 1.8)
	for mark: Array in [[arm_at, "ARM"], [strain_from, "TEAR"]]:
		var my := lerpf(bottom, top, float(mark[0]))
		c.draw_line(px(Vector2(x - 3.0, my)), px(Vector2(x + 3.5, my)), Color(st.line, 0.8), st.thin)
		c.draw_string(ThemeDB.fallback_font, px(Vector2(x + 4.5, my + 1.6)), String(mark[1]),
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 15, Color(st.line_dim, 0.9))
	if straining:
		var left := maxf(0.0, strain_grace - strain_t)
		var txt := "TEARING" if left <= 0.0 else "%.1f" % left
		c.draw_string(ThemeDB.fallback_font, px(Vector2(x - 2.0, top - 3.0)), txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, st.danger)


## One line under the bundle: how knotted it still is, and what it has cost so far.
func _paint_readout(c: CanvasItem, st: StyleScript) -> void:
	var font := ThemeDB.fallback_font
	var txt := "KNOTTED" if tangle > tangle_readable else "READABLE"
	if lift < show_from:
		txt = "EYE DOWN"
	txt += "   %d STRANDS" % strands.size()
	if wrongs > 0:
		txt += "    CUT %d WRONG" % wrongs
	var w: float = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	var col: Color = st.danger if wrongs > 0 else (st.good if tangle <= tangle_readable else Color(st.line_dim, 0.95))
	c.draw_string(font, px(Vector2(0.0, -33.0)) + Vector2(-w * 0.5, 0.0), txt,
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, col)


## The rule, big, for a second and a half, and then never again on this screen.
func _paint_rule_card(c: CanvasItem, st: StyleScript) -> void:
	var k := rule_card_k()
	var fade: float = clampf(k * 4.0, 0.0, 1.0)
	var size: Vector2 = panel.tex_size()
	var font := ThemeDB.fallback_font
	var lines := _wrap(rule_text, font, 34, size.x * 0.82)
	var band: float = 62.0 + 44.0 * float(lines.size())
	var top: float = size.y * 0.5 - band * 0.5
	c.draw_rect(Rect2(Vector2(size.x * 0.06, top), Vector2(size.x * 0.88, band)), Color(st.bg, 0.94 * fade))
	c.draw_rect(Rect2(Vector2(size.x * 0.06, top), Vector2(size.x * 0.88, band)),
		Color(st.frame, 0.9 * fade), false, st.outline)
	c.draw_string(font, Vector2(size.x * 0.08, top + 32.0), "RULE",
		HORIZONTAL_ALIGNMENT_LEFT, -1.0, 22, Color(st.frame, 0.8 * fade))
	c.draw_string(font, Vector2(size.x * 0.08, top + 32.0), "READ IT OUT",
		HORIZONTAL_ALIGNMENT_RIGHT, size.x * 0.84, 22, Color(st.line_dim, 0.8 * fade))
	for i in lines.size():
		var line := String(lines[i])
		var w: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
		c.draw_string(font, Vector2((size.x - w) * 0.5, top + 82.0 + 44.0 * float(i)), line,
			HORIZONTAL_ALIGNMENT_LEFT, -1.0, 34, Color(st.line, fade))


static func _wrap(text: String, font: Font, size: int, width: float) -> Array:
	var out: Array = []
	var line := ""
	for word in text.split(" ", false):
		var test: String = word if line == "" else line + " " + word
		if font.get_string_size(test, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > width and line != "":
			out.append(line)
			line = word
		else:
			line = test
	if line != "":
		out.append(line)
	return out


# ---------------------------------------------------------------------------- net

## Everything a spectator needs to watch it, including WHERE EVERY STRAND IS after a swap. The
## strands and the rule themselves come off the seed and are the same on every machine, but the
## rule goes out anyway so the wall monitor and the HUD can never disagree with the operator.
##
## `lf`, `tg`, `st` and `sn` all creep by less than any sensible quantum in a frame, so they go out
## RAW. Snapping a creeping value here means it never moves at all (see net_state's docstring).
func net_pack() -> Dictionary:
	var mask := 0
	for i in alive.size():
		if bool(alive[i]):
			mask |= 1 << i
	return {
		"lf": lift, "tg": tangle, "or": order.duplicate(), "al": mask,
		"sc": slicing, "st": slice_t, "sn": strain_t,
		"w": wrongs, "sw": swaps, "cu": cursor_mm, "rl": rule.duplicate(),
	}


func net_apply(s: Dictionary) -> void:
	lift = float(s.get("lf", lift))
	tangle = float(s.get("tg", tangle))
	var ord = s.get("or", null)
	if ord is Array and (ord as Array).size() == order.size():
		order = (ord as Array).duplicate()
	var mask := int(s.get("al", -1))
	if mask >= 0:
		for i in alive.size():
			alive[i] = (mask & (1 << i)) != 0
	slicing = int(s.get("sc", slicing))
	slice_t = float(s.get("st", slice_t))
	strain_t = float(s.get("sn", strain_t))
	wrongs = int(s.get("w", wrongs))
	swaps = int(s.get("sw", swaps))
	cursor_mm = s.get("cu", cursor_mm)
	var rl = s.get("rl", null)
	if rl is Array and (rl as Array).size() == 5 and (rl as Array) != rule:
		rule = (rl as Array).duplicate()
		rule_text = _rule_words()
	_update_progress()


# ---------------------------------------------------------------------------- bot

## A good hand holds the eye just under the tear line, waits for the bundle to comb out, reads the
## rule and cuts the strand it names. A bad one MASHES W instead of holding it, so the eye bobs and
## the bundle takes an age to comb out, then cuts before it can read anything -- and what its hand
## lands on comes off a golden-ratio sequence, not a dice roll, so the same bad hand makes the same
## mistakes on every run.
func bot_input(t: float, skill: float) -> Dictionary:
	var dt: float = clampf(t - _bt, 0.0, 0.1)
	_bt = t
	skill = clampf(skill, 0.0, 1.0)
	if not armed() or slicing >= 0 or strands.is_empty():
		return {"cursor": _out(_b_aim), "buttons": 0}
	# Hold the eye where this hand likes it. A steady one sits under the tear line; a panicking one
	# pulls it as high as it goes and pays for it.
	var want_lift: float = lerpf(1.0, strain_from - 0.03, skill)
	# Even a bad hand works out what the screaming is about, eventually, and lets it down off the
	# tear line. It just pays for seven seconds of nerve first.
	if strain_t > strain_grace + lerpf(7.0, 0.0, skill):
		want_lift = minf(want_lift, strain_from - 0.02)
	var buttons: int = BUTTON_UP if lift < want_lift else 0
	# ... and a panicking one lets go of the key a fifth of the time without meaning to.
	if fposmod(t * 3.7 * PHI, 1.0) < 0.12 * (1.0 - skill):
		buttons &= ~BUTTON_UP
	# How combed out it insists on before it will cut anything.
	var patience: float = lerpf(0.66, 0.02, skill)
	if lift < arm_at or tangle > patience:
		_b_target = -1
		_b_ready_t = 0.0
		return {"cursor": _out(_b_aim), "buttons": buttons}
	# And then it dithers, with the eye held right up at the top while it does. That is where the
	# sloppy hand's vitals actually go: not the wrong strand, the seconds spent stretching the nerve
	# trying to remember a rule card that went away eight seconds ago.
	_b_ready_t += dt
	if _b_ready_t < lerpf(3.6, 0.0, skill):
		return {"cursor": _out(_b_aim), "buttons": buttons}
	if _b_target < 0 or _b_target >= alive.size() or not bool(alive[_b_target]):
		_b_target = _b_pick(skill)
	if _b_target < 0:
		return {"cursor": _out(_b_aim), "buttons": buttons}
	var want := strand_point(_b_target, 0.5)
	_b_aim = _b_aim.move_toward(want, lerpf(55.0, 220.0, skill) * dt)
	if _b_aim.distance_to(want) < 1.2:
		# Release between presses: the cut is on the press EDGE, not the hold.
		_b_click = not _b_click
		if _b_click:
			buttons |= BUTTON_PRIMARY
	return {"cursor": _out(_b_aim), "buttons": buttons}


## What it thinks the nerve is. With the bundle combed out it reads the rule; half read, it gets it
## right about `skill` of the time; knotted, it guesses off the golden-ratio sequence -- which is
## what a player who cannot wait is doing too.
func _b_pick(skill: float) -> int:
	_b_seq += 1
	var u := fposmod(float(_b_seq) * PHI, 1.0)
	if read_k() > 0.0 and u < skill:
		return answer()
	var live: Array = []
	for pos in order.size():
		if bool(alive[int(order[pos])]):
			live.append(int(order[pos]))
	if live.is_empty():
		return -1
	var v := fposmod(float(_b_seq) * PHI * 3.0, 1.0)
	return int(live[clampi(int(v * float(live.size())), 0, live.size() - 1)])


func _out(mm: Vector2) -> Vector2:
	return panel.metres_of(mm) if panel != null else mm


# ---------------------------------------------------------------------------- self-test

## Headless check: `tools/minigame_lab.tscn -- --selftest=eye:snip:arcade`.
## Targets: skill 1.0 finishes in 8-20 s losing 0-2 vitals; skill 0.0 under 40 s losing 15-25.
## And the one that matters most: over hundreds of seeds, and after any number of adjacent swaps,
## the rule resolves to EXACTLY ONE LIVE STRAND. Everything else here is tuning; that is the bug
## that would make the step unwinnable.
static func self_test() -> Array:
	var script: GDScript = load("res://scripts/surgery/arcade/nerve_arcade.gd")
	var out: Array = []
	var ok := true
	ok = _test_rules(script, out) and ok
	ok = _test_bots(script, out) and ok
	ok = _test_wrong_cut(script, out) and ok
	ok = _test_net(script, out) and ok
	print("[nerve-arcade self-test] %s" % ("PASS" if ok else "FAIL"))
	return out


## THE BIG ONE. Every seed, every shift: one answer at generation, one answer after every legal
## swap, one answer after a long walk of them, and one answer after a strand has been cut out.
static func _test_rules(script: GDScript, out: Array) -> bool:
	var ok := true
	var seeds := 240
	var kinds := {}
	var swaps_done := 0
	var worst_illegal := 0
	for i in seeds:
		var shift: int = 1 + (i % 6)
		var g = script.new()
		g.setup(_ctx(hash("nerve|%d" % i), shift, 1.0))
		var n: int = g.strands.size()
		kinds[int(g.rule[0])] = int(kinds.get(int(g.rule[0]), 0)) + 1
		var m: Array = g.matches_in(g.order)
		if m.size() != 1 or not bool(g.alive[int(g.order[m[0]])]):
			print("[nerve-arcade self-test] MISS: seed %d generated a rule matching %d strands (%s)" % [i, m.size(), g.rule_text])
			ok = false
			g.free()
			continue
		if int(g.rule[0]) == Rule.NTH:
			print("[nerve-arcade self-test] MISS: seed %d used an absolute position on a Hive" % i)
			ok = false
		# Every adjacent swap, exhaustively: it is either refused or it leaves exactly one live answer.
		for pos in n - 1:
			var test: Array = g.order.duplicate()
			var tmp = test[pos]
			test[pos] = test[pos + 1]
			test[pos + 1] = tmp
			var mm: Array = g.matches_in(test)
			var legal: bool = g.legal_swaps(g.order).has(pos)
			if legal and (mm.size() != 1 or not bool(g.alive[int(test[mm[0]])])):
				print("[nerve-arcade self-test] MISS: seed %d allowed a swap leaving %d answers" % [i, mm.size()])
				ok = false
		if g.legal_swaps(g.order).is_empty():
			print("[nerve-arcade self-test] MISS: seed %d has no legal swap, so stirs do nothing" % i)
			ok = false
		# And a long walk of real stirs, the way a badly sedated Hive delivers them.
		for step_i in 40:
			var before: Array = g.order.duplicate()
			g.on_jolt(Vector2.ZERO, 0.6, 0.35)
			if g.order != before:
				swaps_done += 1
			var mw: Array = g.matches_in(g.order)
			if mw.size() != 1 or not bool(g.alive[int(g.order[mw[0]])]):
				print("[nerve-arcade self-test] MISS: seed %d went ambiguous after %d stirs" % [i, step_i])
				ok = false
				break
			if g.legal_swaps(g.order).is_empty():
				worst_illegal += 1
		# Cut a wrong strand out and walk it again: a severed strand must never become the answer.
		var wrong := -1
		for id in n:
			if id != g.answer():
				wrong = id
				break
		if wrong >= 0:
			g.lift = 1.0
			g.tangle = 0.0
			g._wrong(wrong)
			for step_i in 20:
				g.on_jolt(Vector2.ZERO, 0.6, 0.35)
				var mc: Array = g.matches_in(g.order)
				if mc.size() != 1 or not bool(g.alive[int(g.order[mc[0]])]):
					print("[nerve-arcade self-test] MISS: seed %d resolved onto a cut strand" % i)
					ok = false
					break
		g.free()
	print("[nerve-arcade self-test] %d seeds x every swap + %d stirred swaps: %s" % [
		seeds, swaps_done, "EXACTLY ONE LIVE STRAND EVERY TIME" if ok else "BROKEN"])
	print("[nerve-arcade self-test] templates used %s (%d arrangements had no legal swap left mid-walk)" % [
		str(_named_kinds(kinds)), worst_illegal])
	# And the graft side, where a strapped Hive is not the patient and a position CAN be named.
	var graft := {}
	for i in 60:
		var g = script.new()
		var c := _ctx(hash("nervegraft|%d" % i), 1 + (i % 4), 1.0)
		c["patient_id"] = "player"
		c["patient"] = {}
		g.setup(c)
		graft[int(g.rule[0])] = int(graft.get(int(g.rule[0]), 0)) + 1
		if g.matches_in(g.order).size() != 1:
			print("[nerve-arcade self-test] MISS: graft seed %d does not resolve to one strand" % i)
			ok = false
		g.free()
	print("[nerve-arcade self-test] off a Hive, 60 seeds, templates %s" % str(_named_kinds(graft)))
	out.append({"seeds": seeds, "swaps": swaps_done, "rules_ok": ok})
	return ok


static func _named_kinds(kinds: Dictionary) -> Dictionary:
	var names := ["ONLY_PATTERN", "ONLY_PAIR", "LEFT_OF", "RIGHT_OF", "BETWEEN", "NTH"]
	var out := {}
	for k in kinds.keys():
		out[names[int(k)]] = kinds[k]
	return out


static func _test_bots(script: GDScript, out: Array) -> bool:
	var ok := true
	var sloppy: Array = []
	for sed: float in [1.0, 0.4]:
		for shift: int in [1, 3, 5]:
			for skill: float in [1.0, 0.5, 0.0]:
				var g = script.new()
				var tally := {"n": 0, "v": 0.0, "done": false, "q": 0.0, "reasons": {}}
				g.botched.connect(func(a, r): tally.n += 1; tally.v += a; tally.reasons[r] = int(tally.reasons.get(r, 0)) + 1)
				g.finished.connect(func(r): tally.done = true; tally.q = float(r.get("snip_quality", 0.0)))
				g.setup(_ctx(hash("nervebot|%d" % shift), shift, sed))
				var t: float = run_bot(g, skill, sed, 4700 + shift * 31 + int(skill * 100))
				print("[nerve-arcade self-test] shift=%d sed=%.1f skill=%.1f  %s  strands=%d  wrong=%d  time=%5.1fs  botches=%2d vitals=%5.1f  q=%.2f  %s" % [
					shift, sed, skill, "DONE" if tally.done else "UNFINISHED", g.strands.size(),
					g.wrongs, t, tally.n, tally.v, tally.q, str(tally.reasons)])
				out.append({"shift": shift, "sed": sed, "skill": skill, "done": tally.done,
					"time": t, "vitals": tally.v, "q": tally.q, "wrongs": g.wrongs})
				if sed > 0.9:
					if skill == 1.0 and (not tally.done or t < 8.0 or t > 20.0 or tally.v > 2.0):
						print("[nerve-arcade self-test] MISS: skill 1.0 wants 8-20 s and 0-2 vitals")
						ok = false
					if skill == 0.0:
						sloppy.append(tally.v)
						if not tally.done or t > 40.0:
							print("[nerve-arcade self-test] MISS: skill 0.0 wants to finish under 40 s")
							ok = false
				elif not tally.done:
					print("[nerve-arcade self-test] MISS: a stirring Hive should still finish")
					ok = false
				g.free()
	var mean := 0.0
	for v: float in sloppy:
		mean += v
	mean /= maxf(1.0, float(sloppy.size()))
	# On the mean, as the saw's band is: a wrong strand is a flat six vitals, so whether a sloppy
	# hand's guess happens to land first or last swings one shift a whole six either side of the
	# next on its own. The mean is the number that says anything.
	print("[nerve-arcade self-test] skill 0.0 mean vitals %.1f across %d shifts (want 15-25)" % [mean, sloppy.size()])
	if mean < 15.0 or mean > 25.0:
		print("[nerve-arcade self-test] MISS: skill 0.0 wants 15-25 vitals on average")
		ok = false
	return ok


## A wrong cut: six vitals, that strand gone, and the answer exactly where it was.
static func _test_wrong_cut(script: GDScript, out: Array) -> bool:
	var ok := true
	var g = script.new()
	var tally := {"v": 0.0, "n": 0}
	g.botched.connect(func(a, _r): tally.n += 1; tally.v += a)
	g.setup(_ctx(hash("nervewrong"), 3, 1.0))
	# Clicking before the eye is up costs nothing.
	g.play_state = 1
	g.lift = 0.5
	g.play(Vector2.ZERO, 1, 1, 1.0 / 60.0)
	var free_click: bool = tally.n == 0
	g.lift = 1.0
	g.tangle = 0.0
	var right: int = g.answer()
	var wrong: int = (right + 1) % g.strands.size()
	g._wrong(wrong)
	var kept: bool = g.answer() == right
	var sagged: bool = g.lift < 1.0
	print("[nerve-arcade self-test] wrong cut: cost %.1f (want %.1f), answer kept %s, eye sagged %s, early click free %s" % [
		tally.v, g.wrong_botch, str(kept), str(sagged), str(free_click)])
	if not free_click or absf(tally.v - g.wrong_botch) > 0.01 or not kept or not sagged or bool(g.alive[wrong]):
		print("[nerve-arcade self-test] MISS: a wrong cut should cost %.1f, kill that strand and keep the answer" % g.wrong_botch)
		ok = false
	out.append({"wrong_cost": tally.v, "answer_kept": kept})
	g.free()
	return ok


## A spectator's copy tracks the operator exactly, swaps included.
static func _test_net(script: GDScript, out: Array) -> bool:
	var a = script.new()
	var b = script.new()
	a.setup(_ctx(hash("nervenet"), 4, 0.4))
	b.setup(_ctx(hash("nervenet"), 4, 0.4))
	b.ctx["operator"] = false
	var dt := 1.0 / 60.0
	var stirs := 0
	var seen_swaps := 0
	var moved := false
	for i in 1800:
		var inp: Dictionary = a.bot_input(float(i) * dt, 1.0)
		a.handle_cursor(inp.get("cursor", Vector2.ZERO), int(inp.get("buttons", 0)), dt)
		a.tick(dt)
		if i % 75 == 74:
			a.on_jolt(Vector2.ZERO, 0.6, 0.35)
			stirs += 1
		b.apply_net_state(a.net_state())
		b.tick(dt)
		if b.lift > 0.5 and b.tangle < 0.9:
			moved = true   # the creeping values really do creep through the blob
		if a.swaps > seen_swaps:
			seen_swaps = a.swaps
			if b.order != a.order:
				print("[nerve-arcade self-test] MISS: the spectator missed a swap")
		if a.done:
			break
	var same: bool = b.order == a.order and absf(b.lift - a.lift) < 0.001 and absf(b.tangle - a.tangle) < 0.001 \
		and b.rule_text == a.rule_text and b.wrongs == a.wrongs and b.progress > 0.99 and moved
	print("[nerve-arcade self-test] net round-trip: %d stirs, %d swaps, order %s, lift %.3f vs %.3f, knot %.3f vs %.3f, rule matched %s, creep survived %s" % [
		stirs, seen_swaps, "matched" if b.order == a.order else "DRIFTED", a.lift, b.lift,
		a.tangle, b.tangle, str(b.rule_text == a.rule_text), str(moved)])
	if not same:
		print("[nerve-arcade self-test] MISS: a spectator must see the same arrangement as the operator")
	out.append({"net_ok": same, "swaps": seen_swaps})
	a.free()
	b.free()
	return same


static func _ctx(seed_v: int, shift: int, sed: float) -> Dictionary:
	return {"patient_id": "hive", "patient": Procedures.patient("hive"), "ailment_id": "eye_extraction",
		"step": Procedures.step("eye_extraction", 2), "variant": "snip", "shift": shift,
		"difficulty": Procedures.difficulty(shift), "flags": {"sedation": sed},
		"seed": seed_v, "body": null, "operator": true, "operating": true}
