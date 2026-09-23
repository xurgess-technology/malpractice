extends Area3D
## CUSTOMIZATION: the big full-length mirror in Personnel, as something you can aim at and click.
## The box sits just in front of the glass so the whole mirror is a target, not one spot on it.
##
## Opening the menu is local (scripts/personnel/mirror_menu.gd watches for the press on whichever
## machine the player is sitting at), so `interact` here does nothing: it exists because the aim
## raycast, the crosshair prompt and the highlight all want the interactable contract
## (docs/CONTRACTS.md), and because the host runs `interact` for whoever pressed.
##
## PLAYTEST 2026-09-23: the mirror lock (Net.mirror_user, net.gd). There's only one big mirror per
## level (mirrors.gd's `_add_menu_aim` runs once), so a single flag is enough to say who -- if
## anyone -- is at it. The refusal uses the same "!"-prefixed idiom as everywhere else a shared
## interactable says no and why (combat.gd's strap_problem, game.gd's "!The table is taken."):
## player.gd already skips a "!" prompt when deciding whether E does anything, and mirror_menu.gd's
## own poll checks it too before asking Net to open the menu.


func interact_prompt(q) -> String:
	if q == null or not q.alive or q.downed:
		return ""
	if Net.mirror_user != 0 and Net.mirror_user != q.peer_id:
		return "!Another Player is Using the Mirror."
	return "E: check yourself over"


func interact_hold() -> float:
	return 0.0


func interact(_q) -> void:
	pass
