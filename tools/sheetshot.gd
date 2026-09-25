extends Node
## TAB SHEET smoke look: boots the game on the `sheet` review setup, opens the character sheet,
## and saves three shots -- the sheet plain, the sheet with an ability hovered, and the sheet with
## the boots hovered (so the Unequip button and its card are in frame).
## Run minimized (WMI, like tools/review.ps1):  godot --path . tools/sheetshot.tscn -- --setup=sheet

func _ready() -> void:
	get_tree().create_timer(240.0).timeout.connect(func(): get_tree().quit(2))
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	var game: Game = main.game
	var t := 0.0
	while t < 200.0:
		await get_tree().create_timer(1.0).timeout
		t += 1.0
		if game.phase == Game.Phase.SHIFT and game.local_player() != null:
			await get_tree().create_timer(6.0).timeout
			break
	var sheet = main.char_sheet
	sheet.toggle()
	print("[sheetshot] open=", sheet.open, " boots=", game.local_player().boots)
	await _settle()
	await _shot("plain")
	# Row 2 slot 1 (Puppet) and row 3 slot 2 (the boots).
	# A minimized window has no usable cursor, so the hover is set straight on the sheet with its
	# own _process paused: the same field the mouse would fill, through the same draw path.
	var vp := get_viewport().get_visible_rect().size
	var rows: Array = sheet._rows(vp.x, vp.y)
	sheet.set_process(false)
	sheet._hover = {"row": "abilities", "i": 0, "rect": rows[1][0]}
	sheet._panel.queue_redraw()
	await _settle()
	await _shot("ability")
	print("[sheetshot] ability card=", sheet.hover_lines("abilities", 0, game.local_player(), game))
	sheet._hover = {"row": "worn", "i": 1, "rect": rows[2][1]}
	sheet._panel.queue_redraw()
	await _settle()
	await _shot("boots")
	print("[sheetshot] boots card=", sheet.hover_lines("worn", 1, game.local_player(), game))
	print("[sheetshot] drawn=", sheet.drawn)
	# And the unequip itself: bump the counter the button bumps, then look at the floor item.
	var p = game.local_player()
	p.unequip_count += 1
	await get_tree().create_timer(1.0).timeout
	var kinds := []
	for it in game.world_items.values():
		if String(it.kind) == "rocket_boots":
			kinds.append([it.state, it.global_position.distance_to(p.global_position)])
	print("[sheetshot] after unequip: boots=", p.boots, " loose rocket_boots=", kinds)
	sheet._hover = {}
	sheet._panel.queue_redraw()
	await _settle()
	await _shot("unequipped")
	get_tree().quit(0)


func _settle() -> void:
	for i in 12:
		await get_tree().process_frame


func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var path := ProjectSettings.globalize_path("res://tools/game_shots/sheet_%s.png" % name)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	img.save_png(path)
	print("[sheetshot] wrote ", path)
