extends Node
## The Service Dog's drain, as the drained surgeon feels it. LOCAL ONLY, one per machine (made by the
## first dog's _dog_visual, a child of Game): nothing here is replicated and nothing reaches anyone
## else. It reads what every machine already has -- each dog's `dt` and Monster.dog_draining() -- and
## asks one question: "is a dog draining ME right now?"
##
## While it is, `amount` climbs over RAMP_SECONDS (it gets worse the longer it goes on); the moment it
## is not (a throw, going down, stepping out of range) it falls over CLEAR_SECONDS. Three things follow
## `amount`:
##   the screen desaturates   the Look environment's adjustment_saturation, down toward DESAT_TO
##   the audio goes distant   Audio.set_drain_muffle: the fog's low-pass, whichever is deeper
##   the flashlight dims      the local player's torch energy, down to FLASH_KEEP of itself.
##                            **On trial** (Zach wants to see whether it reads): FLASH_DIM false turns
##                            it off and nothing else changes.

const RAMP_SECONDS := 9.0
const CLEAR_SECONDS := 0.6
const DESAT_TO := 0.08
const FLASH_DIM := true
const FLASH_KEEP := 0.35

var amount := 0.0
var _env: Environment = null
var _base_sat := -1.0
var _flash: SpotLight3D = null
var _base_flash := -1.0


func _process(delta: float) -> void:
	var game := get_parent()
	if game == null:
		return
	var me = game.local_player() if game.has_method("local_player") else null
	var drained := false
	if me != null and "monsters" in game:
		for m in (game.monsters as Dictionary).values():
			if m != null and is_instance_valid(m) and m.has_method("dog_draining") and m.dog_draining() \
					and int(m.dog_target) == int(me.peer_id):
				drained = true
				break
	var was := amount
	if drained:
		amount = minf(1.0, amount + delta / RAMP_SECONDS)
	else:
		amount = maxf(0.0, amount - delta / CLEAR_SECONDS)
	if amount == 0.0 and was == 0.0:
		return
	_apply(me)


func _apply(me) -> void:
	var k := amount * amount * (3.0 - 2.0 * amount)
	# The screen: the Look environment's own saturation, which it sets once at start-up.
	if _env == null:
		var we := get_tree().root.find_child("LookEnvironment", true, false) as WorldEnvironment
		if we != null and we.environment != null:
			_env = we.environment
	if _env != null:
		if _base_sat < 0.0:
			_base_sat = _env.adjustment_saturation
		_env.adjustment_enabled = true
		_env.adjustment_saturation = lerpf(_base_sat, DESAT_TO, k)
		if amount == 0.0:
			_env.adjustment_saturation = _base_sat
			_base_sat = -1.0
	# The ears.
	if Audio.has_method("set_drain_muffle"):
		Audio.set_drain_muffle(k)
	# The torch (on trial).
	if FLASH_DIM and me != null and me.get("flashlight") is SpotLight3D:
		var fl: SpotLight3D = me.flashlight
		if fl != _flash:
			_flash = fl
			_base_flash = fl.light_energy
		if _base_flash < 0.0:
			_base_flash = fl.light_energy
		fl.light_energy = _base_flash * lerpf(1.0, FLASH_KEEP, k)
		if amount == 0.0:
			fl.light_energy = _base_flash
			_base_flash = -1.0


func _exit_tree() -> void:
	# Never leave a machine grey, deaf or dim because the shift ended mid-drain.
	amount = 0.0
	if _env != null and _base_sat >= 0.0:
		_env.adjustment_saturation = _base_sat
	if Audio.has_method("set_drain_muffle"):
		Audio.set_drain_muffle(0.0)
	if _flash != null and is_instance_valid(_flash) and _base_flash >= 0.0:
		_flash.light_energy = _base_flash
