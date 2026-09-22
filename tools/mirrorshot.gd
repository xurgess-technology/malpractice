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


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seed="):
			_seed = int(a.split("=")[1])
		elif a.begins_with("--tag="):
			_tag = "_" + a.split("=")[1]
		elif a == "--no-torch":
			_torch = false
		elif a == "--variants":
			_variants = true
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
		for v in ["control", "gi_off", "shadow_on"]:
			for d in [0.5]:
				await _shot("v_%s" % v, glass, out, float(d), v)
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
	var stand := glass + out * 1.6
	stand.y = glass.y
	me.teleport(game._floor_at(stand))
	_look_at(glass)
	await _seconds(1.0)
	menu.open(me)
	await _seconds(1.5)
	await _grab("menu_00_open")
	for i in 3:
		menu._cycle("outfit", 1)
		await _seconds(0.8)
		await _grab("menu_01_outfit_%d" % (i + 1))
	for i in 3:
		menu._cycle("skin", 1)
		await _seconds(0.8)
		await _grab("menu_02_skin_%d" % (i + 1))
	print("[mirrorshot] look now packed=%d %s" % [Customization.pack(me.look), str(me.look)])
	print("[mirrorshot] Net.looks=%s  Settings.look=%s"
			% [str(Net.looks), str(Settings.get_value("look"))])
	menu.close()
	await _seconds(1.0)
	await _grab("menu_03_closed")


func _grab(name: String) -> void:
	RenderingServer.force_draw()
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [OUT_DIR, name]))
	print("[mirrorshot] wrote ", name)


func _shot(tag: String, glass: Vector3, out: Vector3, dist: float, variant := "") -> void:
	var stand := glass + out * dist
	stand.y = glass.y
	me.teleport(game._floor_at(stand))
	me.bot_move = Vector2.ZERO
	# Look at the chest of the reflection, not the face: that is where the outfit is.
	_look_at(glass - Vector3(0, 0.35, 0))
	me.set_flashlight(variant != "no_torch")
	await _seconds(1.2)
	_dump(tag, dist)
	# mirrors.gd has already posed the camera this frame; nudge one thing and draw straight away.
	_apply_variant(variant)
	RenderingServer.force_draw()
	var img := get_viewport().get_texture().get_image()
	var path := "%s/%s_%03d%s.png" % [OUT_DIR, tag, int(round(dist * 100.0)), _tag]
	img.save_png(ProjectSettings.globalize_path(path))
	print("[mirrorshot] wrote ", path, " variant=", variant)


## One-frame experiments, applied after mirrors.gd's _process and before the draw.
func _apply_variant(variant: String) -> void:
	if variant == "" or variant == "control" or variant == "no_torch":
		return
	var mirrors := _mirrors_node()
	if mirrors == null:
		return
	for g in mirrors.get_children():
		var cam: Camera3D = null
		for c in g.get_children():
			if c is SubViewport:
				for cc in c.get_children():
					if cc is Camera3D:
						cam = cc
		if cam == null:
			continue
		if variant == "near_small":
			# The same view rays with the near plane pulled right in (the wall behind will show:
			# this is a diagnostic, not a fix). Frustum size and offset are measured at the near
			# plane, so both scale with it.
			var k := 0.05 / maxf(0.0001, cam.near)
			cam.size *= k
			cam.frustum_offset *= k
			cam.near = 0.05
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
	var env := get_viewport().world_3d.environment
	if env != null:
		print("  ambient mode=%d energy=%.3f sky=%.3f bg_energy=%.3f"
				% [env.ambient_light_source, env.ambient_light_energy,
					env.ambient_light_sky_contribution, env.background_energy_multiplier])


func _mirrors_node() -> Node:
	if game.level != null:
		var n := game.level.find_child("Mirrors", true, false)
		if n != null:
			return n
	return game.find_child("Mirrors", true, false)
