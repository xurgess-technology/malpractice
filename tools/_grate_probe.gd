extends Node3D
## Scratch probe (grate-hitbox): can you aim at the furnace grate shut and open?

const FurnaceScript := preload("res://scripts/economy/furnace.gd")


func _hit(furn: Node3D, eye: Vector3, look: Vector3) -> String:
	var q := PhysicsRayQueryParameters3D.create(eye, eye + look.normalized() * C.INTERACT_RANGE)
	q.collision_mask = C.L_WORLD | C.L_INTERACT | C.L_PICKUP
	q.collide_with_areas = true
	var hit := furn.get_world_3d().direct_space_state.intersect_ray(q)
	var n: Node = hit.get("collider")
	while n != null and not n.has_meta("interact_id"):
		n = n.get_parent()
	if n != null:
		return String(n.get_meta("interact_id"))
	var c = hit.get("collider")
	return "(%s)" % (c.name if c != null else "nothing")


func _ready() -> void:
	var furn: Node3D = FurnaceScript.create(null, true)
	add_child(furn)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var aim: Node3D = furn.get_node("Hatch/HatchAim")
	var eye := Vector3(0, 1.55, 1.1)          # standing in front of the window

	print("-- shut --")
	print("  aim origin      ", aim.global_position)
	print("  reach from eye  %.2f m (limit %.2f)" % [eye.distance_to(aim.global_position), C.INTERACT_RANGE + 1.2])
	for yaw in [0.0, -20.0, 20.0]:
		var d := Vector3(sin(deg_to_rad(yaw)), 0, -cos(deg_to_rad(yaw)))
		print("  look yaw %+5.0f -> %s" % [yaw, _hit(furn, eye, d)])

	furn.hatch_open = true
	furn._hatch_k = 1.0
	furn._apply_hatch()
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("-- open (full swing, pivot y=%.1f deg) --" % furn._hatch_pivot.rotation_degrees.y)
	print("  aim origin      ", aim.global_position)
	print("  reach from eye  %.2f m (limit %.2f)" % [eye.distance_to(aim.global_position), C.INTERACT_RANGE + 1.2])
	for yaw in [-30.0, -45.0, -60.0, -75.0, -90.0, -110.0]:
		var d := Vector3(sin(deg_to_rad(yaw)), 0, -cos(deg_to_rad(yaw)))
		print("  look yaw %+5.0f -> %s" % [yaw, _hit(furn, eye, d)])
	var side := Vector3(-0.3, 1.55, 1.7)
	print("  from %s toward the leaf -> %s" % [side, _hit(furn, side, Vector3(-1.0, 0, 0.1))])
	print("  reach from there %.2f m" % side.distance_to(aim.global_position))

	furn.hatch_open = false
	furn._hatch_k = 0.5
	furn._apply_hatch()
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("-- mid-swing (k=0.50, pivot y=%.1f deg) --" % furn._hatch_pivot.rotation_degrees.y)
	print("  aim origin      ", aim.global_position, "  (unchanged = host and client agree)")
	furn.queue_free()

	# The whole swing, on the real hub build: from one fixed standing spot, which yaws can hit it?
	# This is the door-precedent check -- no pose may leave the grate unaimable.
	var deep: Node3D = FurnaceScript.create(null, false)
	add_child(deep)
	await get_tree().physics_frame
	var daim: Node3D = deep.get_node("Hatch/HatchAim")
	# Two spots: dead centre in front of the window (which the leaf itself sweeps through mid-swing,
	# so rays from inside the slab register nothing -- an artifact, not a hole in the hitbox), and
	# off to the right, clear of the leaf's arc the whole way.
	for spot in [eye, Vector3(0.8, 1.55, 1.8)]:
		print("-- deep (hub) build, whole swing, eye at ", spot, " --")
		for step in 9:
			var k := float(step) / 8.0
			deep._hatch_k = k
			deep._apply_hatch()
			await get_tree().physics_frame
			var yaws: Array = []
			for i in 73:
				var yaw := -180.0 + i * 5.0
				var d := Vector3(sin(deg_to_rad(yaw)), 0, -cos(deg_to_rad(yaw)))
				if _hit(deep, spot, d) == "furnace_hatch":
					yaws.append(yaw)
			var lo: float = yaws[0] if not yaws.is_empty() else 0.0
			var hi: float = yaws[-1] if not yaws.is_empty() else 0.0
			print("  k=%.2f (%.0f deg): %d of 73 yaws hit, span %+.0f..%+.0f, reach %.2f m" %
					[k, deep._hatch_pivot.rotation_degrees.y, yaws.size(), lo, hi,
					spot.distance_to(daim.global_position)])
	get_tree().quit()
