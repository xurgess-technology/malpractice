class_name HitFlash
extends RefCounted
## HIT FEEDBACK: the red "hurt" flash. When a weapon connects, the thing you hit washes red for a
## fraction of a second and is gone again -- the plain, unsubtle version everyone already knows from
## every other game, so a connecting hit reads instantly without a HUD.
##
## Every machine shows it: the host resolves the hit and broadcasts `cb_flash` (scripts/combat/
## combat.gd), and each peer runs this on its own copy of the target, so the swinger, the victim and
## the bystander all see the same flash. Purely cosmetic -- nothing here touches combat logic.
##
## Technique: `material_overlay` on the target's MeshInstance3Ds, the same trick scripts/scan_fx.gd
## uses (each mesh is drawn a second time with an additive unlit material). Unlike duplicating the
## meshes the way scripts/aim_highlight.gd does, an overlay rides the mesh's own skinning, so it
## deforms with the rig instead of hanging in the bind pose -- both the monsters and the player
## bodies are skinned glTF. The previous overlay is saved and put back, so nothing else's overlay
## (scan_fx's scan wash, item_models' rim) is lost. Warmed once in scripts/warmup.gd.

const SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back, shadows_disabled;

uniform vec3 tint : source_color = vec3(0.92, 0.05, 0.04);
uniform float amount = 0.0;

void fragment() {
	float facing = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	// Painted OVER the body rather than added to it: an additive red turns a white gown pink and
	// teal scrubs orange, where this goes red on anything. Edges go nearly solid so the silhouette
	// reads at a glance.
	ALBEDO = tint;
	ALPHA = clamp(amount * (0.90 + 0.10 * pow(1.0 - facing, 2.0)), 0.0, 1.0);
}
"""

## Full red for this long, then out over the rest of FLASH_TIME. Short and punchy on purpose: the
## hit should register and get out of the way. Tuned by eye -- move these, not the shader.
const FLASH_HOLD := 0.06
const FLASH_TIME := 0.28

const _META_MAT := "_hit_flash_mat"
const _META_SAVED := "_hit_flash_saved"
const _META_TWEEN := "_hit_flash_tween"

static var _shader: Shader = null
static var _mat: ShaderMaterial = null


static func _material() -> ShaderMaterial:
	if _mat == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
		_mat = ShaderMaterial.new()
		_mat.shader = _shader
	return _mat


## Warmup hook (scripts/warmup.gd): compile the shader up front against a throwaway mesh, so the
## first hit of a session does not hitch.
static func warm(parent: Node3D) -> void:
	var probe := MeshInstance3D.new()
	probe.name = "HitFlashWarm"
	probe.mesh = BoxMesh.new()
	parent.add_child(probe)
	probe.material_overlay = _material().duplicate()
	(probe.material_overlay as ShaderMaterial).set_shader_parameter("amount", 1.0)


## Flash `node` (and everything under it) red. `node` is the model root of the thing that was hit
## (a monster's `model`, a player's `body_visual`); nothing happens if it has no meshes. Hitting the
## same target again while it is still lit restarts the flash rather than stacking a second one.
static func flash(node: Node) -> void:
	if node == null or not is_instance_valid(node) or not node.is_inside_tree():
		return
	var mat: ShaderMaterial = node.get_meta(_META_MAT) if node.has_meta(_META_MAT) else null
	if mat == null or not is_instance_valid(mat):
		mat = _material().duplicate()
		var saved := {}
		for mi in _parts(node):
			saved[mi] = mi.material_overlay
			mi.material_overlay = mat
		if saved.is_empty():
			return
		node.set_meta(_META_MAT, mat)
		node.set_meta(_META_SAVED, saved)
	if node.has_meta(_META_TWEEN):
		var old = node.get_meta(_META_TWEEN)
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	mat.set_shader_parameter("amount", 1.0)
	var tw := node.create_tween()
	node.set_meta(_META_TWEEN, tw)
	tw.tween_interval(FLASH_HOLD)
	tw.tween_method(
		func(v: float) -> void:
			if is_instance_valid(mat):
				mat.set_shader_parameter("amount", v),
		1.0, 0.0, maxf(0.01, FLASH_TIME - FLASH_HOLD))
	tw.tween_callback(HitFlash.clear.bind(node))


## Take the flash off now (the tween does this itself when it runs out).
static func clear(node: Node) -> void:
	if node == null or not is_instance_valid(node) or not node.has_meta(_META_MAT):
		return
	var saved: Dictionary = node.get_meta(_META_SAVED, {})
	for mi in saved.keys():
		if is_instance_valid(mi):
			(mi as MeshInstance3D).material_overlay = saved[mi]
	node.remove_meta(_META_MAT)
	node.remove_meta(_META_SAVED)
	if node.has_meta(_META_TWEEN):
		node.remove_meta(_META_TWEEN)


## Every MeshInstance3D under `node` (Label3D name tags and other GeometryInstance3Ds are left
## alone: a red name tag is not what anyone means by a hurt flash).
static func _parts(node: Node) -> Array:
	var parts: Array = []
	if node is MeshInstance3D:
		parts.append(node)
	for mi in node.find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).mesh != null:
			parts.append(mi)
	return parts
