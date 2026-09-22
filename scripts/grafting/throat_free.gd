extends Node3D
## GRAFTING part two: the trachea's "free" step. eye_ops.gd creates this as a child when the step is
## the `snip` variant on a throat (ctx.part_site "throat") and hands every Minigame call to it; it
## reports through the owner (owner.finish / owner.progress).
##
## The throat is open (the step before was the cut): a dark slit along the neck with the windpipe
## lying in it. It is still fixed at both ends. Aim the scalpel at each end and click to cut it
## loose; when both are, it comes free and the step finishes {"eye_removed": true}. Nothing can be
## botched and a click that misses just says so. On a Sonographer the second cut is the one that
## shrieks (dissection.gd watches the step index, not this).
##
## The windpipe lies along the plane's X (head to feet on the table) and the slit is drawn by
## `build_slit`, which the forceps step (eye_seat.gd) shares so an empty throat looks the same.

const Eyes := preload("res://scripts/grafting/eyes.gd")
const MinigameBase := preload("res://scripts/surgery/minigame.gd")

## Half the length of the windpipe as drawn, and how close the tip has to be to an end to cut it.
const HALF := 0.034
const AIM_R := 0.016
const SLICE_SECONDS := 0.5
const SETTLE_SECONDS := 0.6
const HOVER_Y := 0.035
const CUT_Y := 0.006

var owner_mg
var ctx: Dictionary = {}
var eye_kind := "trachea_sonographer"
var eye_r := 0.0135

# ---- replicated state ----
var cursor := Vector2.ZERO
var ends := [0.0, 0.0]          # how far each end is cut: 0 whole .. 1 through
var settle := 0.0
var _hint := ""
var _hint_t := 0.0
var _was_down := false

# ---- visuals ----
var _tool: Node3D
var _pipe: Node3D
var _cue: Array[MeshInstance3D] = []
var _cue_mat: Array[StandardMaterial3D] = []
var _gap: Array[MeshInstance3D] = []
var _tool_h := HOVER_Y
var _t := 0.0
var _bot_t := -1.0
var _sfx_seen := [false, false]


## The open throat: a slit with a dark, wet lip round it. `half` is half its length in metres.
static func build_slit(parent: Node3D, half: float) -> void:
	var lip := StandardMaterial3D.new()
	lip.albedo_color = Color(0.62, 0.2, 0.2)
	lip.roughness = 0.35
	var deep := StandardMaterial3D.new()
	deep.albedo_color = Color(0.13, 0.01, 0.02)
	deep.roughness = 0.1
	deep.emission_enabled = true
	deep.emission = Color(0.16, 0.0, 0.0)
	for e in [[Vector3(half * 2.0 + 0.012, 0.0008, 0.024), lip, 0.0004], [Vector3(half * 2.0, 0.0012, 0.013), deep, 0.0009]]:
		var mi := MeshInstance3D.new()
		var b := BoxMesh.new()
		b.size = e[0]
		mi.mesh = b
		mi.material_override = e[1]
		mi.position = Vector3(0.0, float(e[2]), 0.0)
		mi.name = "ThroatSlit"
		parent.add_child(mi)


func setup(owner, context: Dictionary, kind: String, radius: float) -> void:
	owner_mg = owner
	ctx = context
	name = "ThroatFree"
	eye_kind = kind
	eye_r = radius
	_build()


func _p3(p: Vector2, lift: float) -> Vector3:
	return Vector3(p.x, lift, p.y)


func _end_at(i: int) -> Vector2:
	return Vector2(-HALF if i == 0 else HALF, 0.0)


func _build() -> void:
	build_slit(self, HALF)
	# The windpipe, lying in the slit along X, half sunk.
	_pipe = Node3D.new()
	_pipe.name = "FreePipe"
	add_child(_pipe)
	var mi := MeshInstance3D.new()
	_pipe.add_child(mi)
	Eyes.as_trachea(mi, eye_kind, eye_r, HALF * 2.0)
	_pipe.position = Vector3(0.0, 0.0, 0.0)
	var cue_mesh := TorusMesh.new()
	cue_mesh.inner_radius = 0.8
	cue_mesh.outer_radius = 1.0
	cue_mesh.rings = 28
	cue_mesh.ring_segments = 6
	var cut_mat := StandardMaterial3D.new()
	cut_mat.albedo_color = Color(0.8, 0.05, 0.05)
	cut_mat.roughness = 0.2
	for i in 2:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(1.0, 0.95, 0.8, 0.8)
		m.no_depth_test = true
		m.render_priority = 2
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		var ring := MeshInstance3D.new()
		ring.mesh = cue_mesh
		ring.material_override = m
		ring.position = _p3(_end_at(i), 0.012)
		ring.scale = Vector3(AIM_R, AIM_R * 0.3, AIM_R)
		add_child(ring)
		_cue.append(ring)
		_cue_mat.append(m)
		# The mark a finished cut leaves across the pipe.
		var gap := MeshInstance3D.new()
		var gb := BoxMesh.new()
		gb.size = Vector3(0.0035, 0.014, 0.02)
		gap.mesh = gb
		gap.material_override = cut_mat
		gap.position = _p3(_end_at(i) * 0.985, 0.006)
		gap.visible = false
		add_child(gap)
		_gap.append(gap)
	_tool = owner_mg._make_cut_scalpel()
	add_child(_tool)


# =============================================================================== contract

func plane_extent() -> Vector2:
	return Vector2(HALF + 0.05, 0.06)


func camera_pose() -> Dictionary:
	if owner_mg != null and owner_mg.has_method("base_camera_pose"):
		return owner_mg.call("base_camera_pose")
	return {"height": 0.62, "back": -0.04, "fov": 54.0}


func on_jolt(_offset: Vector2, _strength: float, _duration: float) -> void:
	pass   # a stir never troubles this step


func handle_cursor(p: Vector2, buttons: int, delta: float) -> void:
	if owner_mg.done:
		return
	delta = clampf(delta, 1e-4, 0.1)
	_hint_t = maxf(0.0, _hint_t - delta)
	cursor = p
	var down := (buttons & MinigameBase.BUTTON_PRIMARY) != 0
	# Each cut that has started plays out by itself.
	for i in 2:
		if float(ends[i]) > 0.0 and float(ends[i]) < 1.0:
			ends[i] = minf(1.0, float(ends[i]) + delta / SLICE_SECONDS)
	if down and not _was_down:
		var hit := -1
		for i in 2:
			if float(ends[i]) == 0.0 and cursor.distance_to(_end_at(i)) <= AIM_R:
				hit = i
		if hit >= 0:
			ends[hit] = 0.001
		else:
			_hint = "Aim at a glowing end of the windpipe, then click."
			_hint_t = 2.5
	_was_down = down
	if float(ends[0]) >= 1.0 and float(ends[1]) >= 1.0:
		settle += delta
		if settle >= SETTLE_SECONDS:
			owner_mg.progress = 1.0
			owner_mg.finish({"eye_removed": true})
			return
	owner_mg.progress = minf(0.99, (float(ends[0]) + float(ends[1])) * 0.45 + settle * 0.1)


func tick(delta: float) -> void:
	_t += delta
	var slicing := false
	var near := -1
	for i in 2:
		var e: float = float(ends[i])
		if e > 0.0 and e < 1.0:
			slicing = true
		if e == 0.0 and cursor.distance_to(_end_at(i)) <= AIM_R:
			near = i
		_gap[i].visible = e > 0.0
		_gap[i].scale = Vector3(1.0, 1.0, 1.0)
		var on: bool = e == 0.0
		_cue[i].visible = on
		if on:
			var pulse := 0.5 + 0.5 * sin(_t * 5.0 + float(i))
			var s := AIM_R * (1.0 + 0.08 * pulse)
			_cue[i].scale = Vector3(s, s * 0.3, s)
			_cue_mat[i].albedo_color = Color(0.25, 1.0, 0.45, 0.9) if near == i else Color(1.0, 0.95, 0.8, 0.5 + 0.3 * pulse)
		if e >= 1.0 and not bool(_sfx_seen[i]):
			_sfx_seen[i] = true
			_sfx("surgery_forceps_squelch", -6.0)
	# The windpipe comes loose: it rises a touch once both ends are through.
	var free := smoothstep(0.0, 1.0, minf(float(ends[0]), float(ends[1])))
	_pipe.position.y = 0.0025 * free
	# The scalpel: hovering over the cursor, dropping onto the end it is cutting.
	var h := CUT_Y if slicing else HOVER_Y
	_tool_h = move_toward(_tool_h, h, delta * 0.4)
	_tool.basis = Basis(Vector3.RIGHT, deg_to_rad(22.0))
	_tool.position = _p3(cursor, _tool_h)


func hud_state() -> Dictionary:
	var hint := _hint if _hint_t > 0.0 else ""
	if hint == "":
		var left := 0
		for i in 2:
			if float(ends[i]) == 0.0:
				left += 1
		hint = "Cut both ends of the windpipe free." if left == 2 else ("One more end." if left == 1 else "It's free.")
	return {"title": String(ctx.get("step", {}).get("label", "Cut the windpipe free")), "hint": hint,
		"progress": owner_mg.progress, "gauges": [], "keys": keys()}


func keys() -> Array:
	return [["Mouse", "aim at an end of the windpipe"], ["Click", "cut it loose"]]


func net_state() -> Dictionary:
	return {"cx": snappedf(cursor.x, 0.0005), "cy": snappedf(cursor.y, 0.0005),
		"a": snappedf(float(ends[0]), 0.02), "b": snappedf(float(ends[1]), 0.02),
		"se": snappedf(settle, 0.02), "p": snappedf(owner_mg.progress, 0.001)}


func apply_net_state(s: Dictionary) -> void:
	cursor = Vector2(float(s.get("cx", cursor.x)), float(s.get("cy", cursor.y)))
	ends[0] = float(s.get("a", ends[0]))
	ends[1] = float(s.get("b", ends[1]))
	settle = float(s.get("se", settle))
	owner_mg.progress = float(s.get("p", owner_mg.progress))


## Aim at an end, click, wait for it, then the other.
func bot_input(t: float, _skill: float) -> Dictionary:
	var dt := 1.0 / 60.0 if _bot_t < 0.0 else clampf(t - _bot_t, 0.0, 0.1)
	_bot_t = t
	var target := 0
	if float(ends[0]) > 0.0:
		target = 1
	var aim := _end_at(target)
	var p := cursor.move_toward(aim, 0.25 * dt)
	var buttons := 0
	var busy := false
	for i in 2:
		if float(ends[i]) > 0.0 and float(ends[i]) < 1.0:
			busy = true
	if not busy and float(ends[target]) == 0.0 and p.distance_to(aim) < AIM_R * 0.4 and t > 1.5:
		buttons = MinigameBase.BUTTON_PRIMARY if int(t * 30.0) % 2 == 0 else 0
	return {"cursor": p, "buttons": buttons}


func _sfx(cue: String, vol_db := 0.0) -> void:
	var loop := Engine.get_main_loop() as SceneTree
	if loop == null:
		return
	var a = loop.root.get_node_or_null("Audio")
	if a != null:
		a.play(cue, global_position if is_inside_tree() else null, vol_db, 0.08)
