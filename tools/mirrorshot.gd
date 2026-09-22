extends Node
## MIRRORS: walks up to the entrance's big mirror and to a sink mirror, a shot at each distance,
## and dumps what the mirror camera and the room's lights are doing. For the "standing too close to
## a mirror turns your character completely black" report (docs/KNOWN_ISSUES.md, Mirrors).
##
##   powershell -NoProfile -ExecutionPolicy Bypass -File tools\mirrorshot.ps1
##
## Runs in a minimized window that is never activated (tools/mirrorshot.ps1, the same WMI trick as
## review.ps1), so it can't take focus. Shots land in tools/mirror_shots/.

const OUT_DIR := "res://tools/mirror_shots"
const LightRooms := preload("res://scripts/level/light_rooms.gd")
const MirrorsScript := preload("res://scripts/personnel/mirrors.gd")
const Customization := preload("res://scripts/personnel/customization.gd")

## How far in front of the glass to stand, in metres.
const DISTANCES := [0.5, 0.8, 1.2, 2.0, 3.5]

var main: Node3D
var game: Game
var me: Player
var _seed := 4242
var _tag := ""
var _torch := true
var _variants := false
var _menu := false
var _variant_list: Array = ["control", "near_small", "persp", "flat_mat"]
## Which distances the --variants run uses (--vdist=0.5,1.2).
var _variant_dists: Array = [0.5]
## The direction from the glass out into the room, for this shot (probe_front).
var _shot_out := Vector3.FORWARD


func _ready() -> void:
	# mirrorshot.ps1 passes its -Extra through as one quoted argument, so "--variants=a,b --vdist=0.5"
	# arrives glued together: split it back up before parsing.
	var args: Array = []
	for raw in OS.get_cmdline_user_args():
		for piece in String(raw).split(" ", false):
			args.append(piece)
	for a in args:
		if a.begins_with("--seed="):
			_seed = int(a.split("=")[1])
		elif a.begins_with("--tag="):
			_tag = "_" + a.split("=")[1]
		elif a == "--no-torch":
			_torch = false
		elif a == "--variants":
			_variants = true
		elif a.begins_with("--variants="):
			_variants = true
			_variant_list = Array(a.split("=")[1].split(","))
		elif a.begins_with("--vdist="):
			_variant_dists = []
			for t in a.split("=")[1].split(","):
				_variant_dists.append(float(t))
		elif a == "--menu":
			_menu = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	get_tree().create_timer(600.0).timeout.connect(func(): get_tree().quit(2))

	# main.gd sees --setup=mirror on the command line and boots straight into the shift for us
	# (solo, hosting, the world settled): the same path a review window takes.
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	game = main.game
	var waited := 0.0
	while waited < 300.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5
		if game.phase == Game.Phase.SHIFT and game.local_player() != null:
			break
	if game.phase != Game.Phase.SHIFT or game.local_player() == null:
		print("[mirrorshot] never reached the shift (phase=%d)" % game.phase)
		get_tree().quit(3)
		return
	await get_tree().create_timer(4.0).timeout
	me = game.local_player()
	me.bot_active = true
	me.bot_invulnerable = true
	me.bot_move = Vector2.ZERO
	me.set_flashlight(_torch)
	await _run()
	print("[mirrorshot] done")
	get_tree().quit(0)


func _run() -> void:
	var pr: Dictionary = game.level_info.get("personnel", {})
	var mirror: Dictionary = pr.get("mirror", {})
	if mirror.is_empty():
		print("[mirrorshot] no personnel mirror on this level")
		return
	var mp: Vector3 = mirror.position
	var myaw := float(mirror.get("yaw", 0.0))
	var out := (Basis(Vector3.UP, myaw) * Vector3(0, 0, -1)).normalized()
	var glass: Vector3 = mp + Vector3(0, MirrorsScript.BIG_CENTRE.y, 0)
	if _menu:
		await _menu_shots(glass, out)
		return
	if _variants:
		# all_lights leaves the lights changed, so it goes last.
		for v in _variant_list:
			for d in _variant_dists:
				await _shot("v_%s_%03d" % [v, int(round(float(d) * 100.0))],
						glass, out, float(d), v)
		var vsinks: Array = pr.get("sinks", [])
		if not vsinks.is_empty():
			var vs: Dictionary = vsinks[int(vsinks.size() / 2)]
			var vsout := (Basis(Vector3.UP, float(vs.get("yaw", 0.0))) * Vector3(0, 0, -1)).normalized()
			var vsglass: Vector3 = (vs.position as Vector3) \
					+ Vector3(0, MirrorsScript.SINK_CENTRE.y, 0) + vsout * MirrorsScript.SINK_CENTRE.z
			for v in _variant_list:
				await _shot("vsink_%s" % v, vsglass, vsout, 0.8, v)
		return
	for d in DISTANCES:
		await _shot("big", glass, out, float(d))
	var sinks: Array = pr.get("sinks", [])
	if sinks.is_empty():
		print("[mirrorshot] no sinks recorded")
		return
	var s: Dictionary = sinks[int(sinks.size() / 2)]
	var sp: Vector3 = s.position
	var syaw := float(s.get("yaw", 0.0))
	var sout := (Basis(Vector3.UP, syaw) * Vector3(0, 0, -1)).normalized()
	var sglass: Vector3 = sp + Vector3(0, MirrorsScript.SINK_CENTRE.y, 0) \
			+ sout * MirrorsScript.SINK_CENTRE.z
	for d in DISTANCES:
		await _shot("sink", sglass, sout, float(d))


## CUSTOMIZATION smoke look: open the mirror menu and cycle each axis, a shot at every step.
func _menu_shots(glass: Vector3, out: Vector3) -> void:
	var mirrors := _mirrors_node()
	if mirrors == null:
		print("[mirrorshot] no Mirrors node")
		return
	var menu := mirrors.find_child("MirrorMenu", true, false)
	if menu == null:
		print("[mirrorshot] the mirror has no MirrorMenu child")
		return
	# Walk up as if we had just aimed at the glass, then open it the way the E press does.
	var stand := glass + out * 1.4
	stand.y = glass.y
	me.teleport(game._floor_at(stand))
	_look_at(glass)
	await _seconds(1.0)
	# Open it the way a player does: aim at the glass, press E. Anything less would not test that
	# the mirror is really an interactable you can pick out with the crosshair.
	print("[mirrorshot] aim_id=%s prompt=%s" % [str(me.aim_id), str(me.aim_prompt)])
	Input.action_press("interact")
	await get_tree().process_frame
	Input.action_release("interact")
	await _seconds(1.5)
	print("[mirrorshot] menu open? %s" % str(menu.get("_open")))
	await _grab("menu_00_open")
	for i in 3:
		menu._cycle("outfit", 1)
		await _seconds(0.8)
		await _grab("menu_01_outfit_%d" % (i + 1))
	for i in 3:
		menu._cycle("skin", 1)
		await _seconds(0.8)
		await _grab("menu_02_skin_%d" % (i + 1))
	# Patterns, and the pattern-colour row that only exists once there is a pattern.
	print("[mirrorshot] rows with no pattern: %d" % Customization.visible_axes(me.look).size())
	for i in 3:
		menu._cycle("pattern", 1)
		await _seconds(0.8)
		print("[mirrorshot] pattern=%s rows=%d" % [Customization.option_name(me.look, "pattern"),
				Customization.visible_axes(me.look).size()])
		await _grab("menu_04_pattern_%d" % (i + 1))
	for i in 2:
		menu._cycle("pattern_colour", 1)
		await _seconds(0.8)
		await _grab("menu_05_patcol_%d" % (i + 1))
	# Back to None: the pattern-colour row must go away again.
	menu._cycle("pattern", 1)
	await _seconds(0.8)
	print("[mirrorshot] back to %s, rows=%d" % [Customization.option_name(me.look, "pattern"),
			Customization.visible_axes(me.look).size()])
	await _grab("menu_06_pattern_none")
	menu._cycle("pattern", -1)
	await _seconds(0.8)
	print("[mirrorshot] look now packed=%d %s" % [Customization.pack(me.look), str(me.look)])
	print("[mirrorshot] Net.looks=%s  Settings.look=%s"
			% [str(Net.looks), str(Settings.get_value("look"))])
	Input.action_press("interact")
	await get_tree().process_frame
	Input.action_release("interact")
	await _seconds(1.0)
	print("[mirrorshot] menu open after the second press? %s" % str(menu.get("_open")))
	await _grab("menu_03_closed")


func _grab(name: String) -> void:
	RenderingServer.force_draw()
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name]))
	print("[mirrorshot] wrote ", name)


func _shot(tag: String, glass: Vector3, out: Vector3, dist: float, variant := "") -> void:
	_shot_out = out
	var stand := glass + out * dist
	stand.y = glass.y
	me.teleport(game._floor_at(stand))
	me.bot_move = Vector2.ZERO
	var mirrors0 := _mirrors_node()
	if mirrors0 != null:
		mirrors0.set("menu_hold", false)   # hand the mirror back after a camera variant
	# flat_mat and the effect switches stick: undo them so the next shot is not still wearing them.
	if me.body_visual != null:
		for n in me.body_visual.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).material_override = null
	var env0 := get_viewport().world_3d.environment
	if env0 != null:
		env0.ssao_enabled = true
		env0.ssil_enabled = true
		env0.volumetric_fog_enabled = true
		env0.fog_enabled = true
		env0.glow_enabled = true
	# Look at the chest of the reflection, not the face: that is where the outfit is.
	_look_at(glass - Vector3(0, 0.35, 0))
	me.set_flashlight(variant != "no_torch")
	_pre_variant(variant)
	await _seconds(1.2)
	# Camera variants have to be held across real frames. Poking the camera between mirrors.gd's
	# _process and force_draw() leaves the glass blank -- which is what the first near_small and
	# persp shots actually showed, so neither of them tested anything.
	if variant in CAM_VARIANTS:
		await _hold_camera(variant)
	_dump(tag, dist)
	# mirrors.gd has already posed the camera this frame; nudge one thing and draw straight away.
	_apply_variant(variant)
	RenderingServer.force_draw()
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s_%03d%s.png" % [OUT_DIR, tag, int(round(dist * 100.0)), _tag]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[mirrorshot] wrote ", path, " variant=", variant)
	# The glass's own picture, straight off the SubViewport: no first-person frame around it, no
	# guessing which part of the screen is reflection and which is the room.
	var mirrors2 := _mirrors_node()
	if mirrors2 != null:
		for g in mirrors2.get_children():
			for c in g.get_children():
				if not (c is SubViewport):
					continue
				var vp2: SubViewport = c
				if vp2.render_target_update_mode == SubViewport.UPDATE_DISABLED:
					continue
				var vimg := vp2.get_texture().get_image()
				var vpath := "%s/%s_%03d%s_vp_%s.png" % [OUT_DIR, tag, int(round(dist * 100.0)),
						_tag, g.name]
				vimg.save_png(ProjectSettings.globalize_path(vpath))
				print("[mirrorshot] wrote ", vpath)


## Variants that change the mirror camera, and so have to be held across frames (_hold_camera).
const CAM_VARIANTS := ["near_small", "near_big", "persp", "no_offset"]


## Drive the big mirror ourselves for a few real frames, re-posing it exactly as mirrors.gd does and
## then applying the variant's change to the camera, so the SubViewport actually renders with it.
## menu_hold stops mirrors.gd from posing the camera back underneath us.
func _hold_camera(variant: String) -> void:
	var mirrors := _mirrors_node()
	if mirrors == null:
		return
	var cam: Camera3D = null
	for g in mirrors.get_children():
		if String(g.name) != "BigMirror":
			continue
		for c in g.get_children():
			if c is SubViewport:
				for cc in c.get_children():
					if cc is Camera3D:
						cam = cc
	if cam == null:
		return
	mirrors.set("menu_hold", true)
	for i in 12:
		var eye: Vector3 = me.global_position + Vector3.UP * C.EYE_H
		mirrors.call("render_for_menu", eye)
		# render_for_menu has just posed the camera; change it, then let the frame draw.
		if variant == "persp":
			# An ordinary symmetric perspective camera from the same place, with the near plane left
			# exactly where mirrors.gd put it -- on the glass. That is the only thing that isolates
			# the extreme field of view: pull the near plane in instead and the camera, which sits
			# behind the wall the mirror hangs on, simply renders the inside of that wall (which is
			# all the first near_small and persp shots ever showed).
			# ~142 degrees at 0.5 m becomes 70: same eye point, same near plane, ordinary frustum.
			cam.projection = Camera3D.PROJECTION_PERSPECTIVE
			cam.fov = 70.0
		elif variant == "no_offset":
			cam.frustum_offset = Vector2.ZERO
		elif variant == "near_small" or variant == "near_big":
			# The SAME view rays with the near plane moved: size and offset are measured at the near
			# plane, so scaling all three together leaves the frustum's shape alone and moves only
			# where the near plane sits. This is the one test that separates "the near plane is
			# pinned to the glass" from "the field of view is extreme".
			var want := 0.05 if variant == "near_small" else 3.0
			var k := want / maxf(0.0001, cam.near)
			cam.size *= k
			cam.frustum_offset *= k
			cam.near = want
		await get_tree().process_frame
	# menu_hold stays on through the capture: force_draw() does not run _process, so the camera keeps
	# what we just gave it. _shot's cleanup hands the mirror back to mirrors.gd for the next shot.


## Experiments that need to exist for a while before the shot (a new node is not registered with the
## rendering server until the frame after it is added, so a probe added at draw time draws nothing).
## Called right after the teleport, before the settle.
func _pre_variant(variant: String) -> void:
	for old in get_tree().get_nodes_in_group("mirrorshot_probe"):
		old.queue_free()
	if variant == "probe_front":
		# A bright lamp between the body and the glass, lighting every layer: the front of the body,
		# the side the mirror sees, is pointed straight at it. (The old probe_light did this at draw
		# time, when a node added that frame is not registered with the rendering server yet -- so
		# whatever it showed, it was not this.) If the front stays black under this, no light reaches
		# those surfaces at all and the room's lighting is not the fault.
		var probe := OmniLight3D.new()
		probe.add_to_group("mirrorshot_probe")
		probe.light_energy = 8.0
		probe.omni_range = 6.0
		probe.light_cull_mask = 0xFFFFFFFF
		probe.shadow_enabled = false
		probe.set_meta("light_dynamic", true)
		game.level.add_child(probe)
		probe.global_position = me.global_position + Vector3.UP * 1.2 + _shot_out * 0.6
		return
	if variant != "probe_box":
		return
	# A plain box standing beside the body, on the ordinary world layer so BOTH cameras see it: the
	# reflection of the box and the box itself, in the same frame. If the box is lit where it stands
	# and black in the glass, nothing about the player's body is at fault -- the mirror's render is.
	# If it is lit in both, the fault is the body instance and not the place it is standing in.
	var box := MeshInstance3D.new()
	box.add_to_group("mirrorshot_probe")
	var bm := BoxMesh.new()
	bm.size = Vector3(0.25, 0.25, 0.25)
	box.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.85, 0.85, 0.85)
	bmat.roughness = 0.8
	box.material_override = bmat
	box.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	box.set_meta("light_dynamic", true)   # light_rooms.gd: leave its layers alone
	game.level.add_child(box)
	box.global_position = me.global_position + Vector3.UP * 1.3 \
			+ me.global_transform.basis.x.normalized() * 0.45


## One-frame experiments, applied after mirrors.gd's _process and before the draw.
func _apply_variant(variant: String) -> void:
	if variant == "" or variant == "control" or variant == "no_torch":
		return
	# Camera changes are not done here: see CAM_VARIANTS and _hold_camera.
	# The environment's screen-space effects, one at a time. They are screen-space, so they see the
	# mirror's own picture -- a body that fills a small SubViewport at a 138-degree field of view is
	# nothing like the same body across a 1280x720 first-person frame.
	var env := get_viewport().world_3d.environment
	if env != null:
		if variant == "ssao_off" or variant == "fx_off":
			env.ssao_enabled = false
		if variant == "ssil_off" or variant == "fx_off":
			env.ssil_enabled = false
		if variant == "vfog_off" or variant == "fx_off":
			env.volumetric_fog_enabled = false
		if variant == "fog_off" or variant == "fx_off":
			env.fog_enabled = false
		if variant == "glow_off" or variant == "fx_off":
			env.glow_enabled = false
	if variant == "flat_mat" and me.body_visual != null:
		# THE DECISIVE TEST of the material theory from the other side: a plain bright
		# StandardMaterial3D over the whole body, no shader of ours anywhere. If that is black too,
		# neither human_cloth.gdshader nor the cloth/skin split has anything to do with it.
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(0.85, 0.85, 0.85)
		flat.roughness = 0.8
		for n in me.body_visual.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).material_override = flat
	if variant == "all_lights" and game.level != null:
		for n in game.level.find_children("*", "Light3D", true, false):
			(n as Light3D).light_cull_mask = 0xFFFFFFFF
	if variant == "probe_light":
		# A bright lamp right next to the body, lighting every layer. If the cloth stays black with
		# this on, no light reaches that material at all and the fault is not the room's lighting.
		var probe := OmniLight3D.new()
		probe.light_energy = 8.0
		probe.omni_range = 6.0
		probe.light_cull_mask = 0xFFFFFFFF
		probe.shadow_enabled = false
		game.level.add_child(probe)
		probe.global_position = me.global_position + Vector3.UP * 1.2 				+ (me.global_transform.basis.z.normalized() * -0.9)
		probe.set_meta("light_dynamic", true)
	if variant == "gi_off" and me.body_visual != null:
		for n in me.body_visual.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	if variant == "shadow_on" and me.body_visual != null:
		for n in me.body_visual.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if variant == "cull_margin" and me.body_visual != null:
		# A skinned mesh whose AABB does not cover where the skeleton actually puts it is not paired
		# with any light. extra_cull_margin grows that AABB.
		for n in me.body_visual.find_children("*", "GeometryInstance3D", true, false):
			(n as GeometryInstance3D).extra_cull_margin = 4.0


func _look_at(target: Vector3) -> void:
	var eye := me.global_position + Vector3.UP * C.EYE_H
	var d := target - eye
	me.bot_yaw = atan2(-d.x, -d.z)
	me.bot_pitch = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -1.2, 1.2)


func _seconds(s: float) -> void:
	var n := int(s * 60.0)
	for i in n:
		await get_tree().process_frame


## What the mirror camera and the room's lights are doing, right now.
func _dump(tag: String, dist: float) -> void:
	print("[mirrorshot] --- %s at %.2f m ---" % [tag, dist])
	var mirrors := _mirrors_node()
	if mirrors != null:
		for g in mirrors.get_children():
			if not (g is Node3D):
				continue
			var vp: SubViewport = null
			var cam: Camera3D = null
			for c in g.get_children():
				if c is SubViewport:
					vp = c
					for cc in c.get_children():
						if cc is Camera3D:
							cam = cc
			if cam == null or vp == null:
				continue
			if vp.render_target_update_mode == SubViewport.UPDATE_DISABLED:
				continue
			print("  %s: near=%.4f far=%.1f cull=0x%X self_in_cull=%s update=%d"
					% [g.name, cam.near, cam.far, cam.cull_mask,
						str((cam.cull_mask & LightRooms.SELF) != 0), vp.render_target_update_mode])
	print("  mirror_self=%s body_visible=%s torch=%s" % [str(me.get("_mirror_self")),
			str(me.body_visual.visible if me.body_visual != null else false), str(me.flashlight_on)])
	var layers := {}
	var n_mesh := 0
	if me.body_visual != null:
		for m in me.body_visual.find_children("*", "VisualInstance3D", true, false):
			var v := m as VisualInstance3D
			if v is Light3D:
				continue
			n_mesh += 1
			layers[v.layers] = int(layers.get(v.layers, 0)) + 1
	var gi_modes := {}
	if me.body_visual != null:
		for n3 in me.body_visual.find_children("*", "GeometryInstance3D", true, false):
			var g3 := n3 as GeometryInstance3D
			gi_modes["gi%d_shadow%d" % [g3.gi_mode, g3.cast_shadow]] = true
	print("  body gi/shadow flags: %s" % str(gi_modes.keys()))
	print("  body meshes=%d layers=%s (SELF=0x%X, DYNAMIC=0x%X)"
			% [n_mesh, str(layers), LightRooms.SELF, LightRooms.DYNAMIC])
	var eye: Vector3 = me.global_position + Vector3.UP * C.EYE_H
	var lit := 0
	var unlit: Array[String] = []
	for n in (game.level.find_children("*", "Light3D", true, false) if game.level != null else []):
		if n is DirectionalLight3D:
			continue
		var l := n as Light3D
		var d := eye.distance_to(l.global_position)
		if d > 14.0:
			continue
		if (l.light_cull_mask & LightRooms.SELF) != 0 and l.light_energy > 0.0 and l.visible:
			lit += 1
		else:
			unlit.append("%s d=%.1f mask=0x%X e=%.2f vis=%s"
					% [l.name, d, l.light_cull_mask, l.light_energy, str(l.visible)])
	# The body's real bounds, and which lights actually reach them.
	var box := AABB()
	var first := true
	if me.body_visual != null:
		for n in me.body_visual.find_children("*", "GeometryInstance3D", true, false):
			var gi := n as GeometryInstance3D
			var b: AABB = gi.global_transform * gi.get_aabb()
			box = b if first else box.merge(b)
			first = false
	print("  body aabb pos=%s size=%s centre=%s (player at %s)"
			% [str(box.position.snappedf(0.01)), str(box.size.snappedf(0.01)),
				str(box.get_center().snappedf(0.01)), str(me.global_position.snappedf(0.01))])
	var chest: Vector3 = me.global_position + Vector3.UP * 1.2
	for n2 in (game.level.find_children("*", "Light3D", true, false) if game.level != null else []):
		if n2 is DirectionalLight3D:
			continue
		var l2 := n2 as Light3D
		var dd := chest.distance_to(l2.global_position)
		if dd > 9.0 or l2.light_energy <= 0.0 or not l2.visible:
			continue
		var rng: float = l2.omni_range if l2 is OmniLight3D else (l2.spot_range if l2 is SpotLight3D else 0.0)
		print("    light %s type=%s d_chest=%.2f range=%.2f reaches=%s aabb_hit=%s"
				% [l2.name, l2.get_class(), dd, rng, str(dd <= rng),
					str(box.intersects(AABB(l2.global_position - Vector3.ONE * rng, Vector3.ONE * rng * 2.0)))])
	print("  lights within 14 m lighting SELF: %d; not: %d" % [lit, unlit.size()])
	for u in unlit.slice(0, 8):
		print("    no-SELF: " + u)
	_dump_incident(chest)
	var env := get_viewport().world_3d.environment
	if env != null:
		print("  ambient mode=%d energy=%.3f sky=%.3f bg_energy=%.3f"
				% [env.ambient_light_source, env.ambient_light_energy,
					env.ambient_light_sky_contribution, env.background_energy_multiplier])


## How much light actually lands on the chest, per facing. This is the measurement that decides
## whether the reflection is dark because the renderer is dropping light or because there is no
## light on that side of you to drop: `front` is the chest facing the glass (what the mirror sees),
## `up` is the same point facing the ceiling, `back` is facing into the room. Plain N.L with a
## linear range falloff -- not Godot's exact attenuation, but the same shape, and what matters here
## is the ratio between the three, not the absolute number.
func _dump_incident(chest: Vector3) -> void:
	var front := -_shot_out.normalized()   # the side of you the mirror looks at
	var sums := {"front": 0.0, "up": 0.0, "back": 0.0}
	var dirs := {"front": front, "up": Vector3.UP, "back": -front}
	for n in (game.level.find_children("*", "Light3D", true, false) if game.level != null else []):
		if n is DirectionalLight3D:
			continue
		var l := n as Light3D
		if not l.visible or l.light_energy <= 0.0:
			continue
		if (l.light_cull_mask & LightRooms.SELF) == 0:
			continue
		var rng: float = l.omni_range if l is OmniLight3D else (l.spot_range if l is SpotLight3D else 0.0)
		var to_l: Vector3 = l.global_position - chest
		var d := to_l.length()
		if rng <= 0.0 or d >= rng or d < 0.0001:
			continue
		var atten: float = 1.0 - d / rng
		for k in dirs:
			sums[k] = float(sums[k]) + l.light_energy * atten * maxf(0.0, (to_l / d).dot(dirs[k]))
	print("  incident on the chest: front(at the glass)=%.3f up=%.3f back(into the room)=%.3f"
			% [sums["front"], sums["up"], sums["back"]])


func _mirrors_node() -> Node:
	if game.level != null:
		var n := game.level.find_child("Mirrors", true, false)
		if n != null:
			return n
	return game.find_child("Mirrors", true, false)
