extends Area3D
## CUSTOMIZATION: the big full-length mirror in Personnel, as something you can aim at and click.
## The box sits just in front of the glass so the whole mirror is a target, not one spot on it.
##
## Opening the menu is local (scripts/personnel/mirror_menu.gd watches for the press on whichever
## machine the player is sitting at), so `interact` here does nothing: it exists because the aim
## raycast, the crosshair prompt and the highlight all want the interactable contract
## (docs/CONTRACTS.md), and because the host runs `interact` for whoever pressed.


func interact_prompt(q) -> String:
	if q == null or not q.alive or q.downed:
		return ""
	return "E: check yourself over"


func interact_hold() -> float:
	return 0.0


func interact(_q) -> void:
	pass
