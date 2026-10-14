extends SceneTree
## Drives the remake's screens like a player would (plan 4 and 8): menus with each device,
## options saved and restored, remapping (swap on conflict, defaults, mandatory actions),
## players and saving, undo, level change, the level file errors.
##     godot --headless --path remake --script res://tests/scenarios.gd

const Settings = preload("res://scripts/game/settings.gd")
const Progress = preload("res://scripts/game/progress.gd")
const Levels = preload("res://scripts/sim/levels.gd")
const Sim = preload("res://scripts/sim/sim.gd")

const CUSTOM := "user://custom_levels.hl"
const EDITOR := "user://editor.json"
const SAVED := "user://levels/TEST.HL"
const LevelSet = preload("res://scripts/game/level_set.gd")

var failures := 0
var checks := 0
var main


func expect(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAILED: ", what)


func _initialize() -> void:
	for f in [Settings.PATH, Progress.PATH, CUSTOM, EDITOR, SAVED]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	await process_frame
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	test_first_and_title()
	test_options()
	test_controls()
	test_players()
	await test_game()
	test_levels_menu()
	test_levels_touch()
	test_smooth()
	test_wide()
	test_level_file()
	await test_editor()
	test_stt()
	test_settings_file()
	for f in [Settings.PATH, Progress.PATH, CUSTOM, EDITOR, SAVED]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	print("scenarios: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)


func press(a: String) -> void:
	main.ui(a)


func test_first_and_title() -> void:
	expect(main.mode == "first", "first start shows the language screen")
	press("ui_down")
	press("ui_accept")
	expect(main.mode == "title" and main.settings.get_value("language") == "en", "english chosen")
	expect(not main.items[1]["enabled"], "continue greyed out without a save")
	expect(main.sel == 0, "cursor on new game")
	press("ui_up")
	expect(main.items[main.sel]["id"] == "quit", "up wraps to quit (editor/continue skipped)")
	press("ui_cancel")
	expect(main.mode == "confirm", "esc on the title asks before quitting")
	main._confirm(false)
	expect(main.mode == "title", "no: back to the title")


func test_options() -> void:
	main.open_options("title")
	expect(main.mode == "options", "options open")
	press("ui_down")                       # language
	press("ui_right")
	expect(main.settings.get_value("language") == "pl", "language changed with right")
	press("ui_left")
	press("ui_up")
	press("ui_right")                      # next page: video
	expect(main.page == 1, "tab changes the page")
	press("ui_down")                       # scale
	press("ui_accept")
	expect(main.settings.get_value("scale") == "sharp", "accept cycles a value")
	press("ui_cancel")
	expect(main.mode == "title", "back returns to the title")
	main.open_options("title")
	main.page = 2
	main.open_options("title")
	press("ui_down")                       # sound on/off
	press("ui_right")
	expect(main.settings.get_value("sound") == false, "sound off")
	expect(not main.items[2]["enabled"] and not main.items[3]["enabled"], "music rows greyed out (R-M2)")
	press("ui_down")
	expect(main.sel != 2 and main.sel != 3, "greyed rows are skipped")
	main.settings.set_value("sound", true)
	main.apply_settings()
	press("ui_cancel")


func test_controls() -> void:
	main.open_controls("title")
	expect(main.mode == "controls", "controls open")
	expect(main.items.size() > 14, "every action listed (R-C1)")
	var s: Settings = main.settings
	var other := s.bind("keys", "left", KEY_D)    # D belongs to right
	expect(other == "right", "conflict found")
	expect(s.keys["left"][0] == KEY_D and not s.keys["right"].has(KEY_D), "swap, not duplicate (R-C2)")
	expect(s.keys["right"].has(KEY_LEFT), "the other action got the old key")
	s.reset_keys()
	expect(s.keys["left"] == [KEY_LEFT, KEY_A], "defaults restored (R-C3)")
	expect(s.unbound_mandatory().is_empty(), "mandatory actions bound (R-C4)")
	main.sel = 1
	press("ui_accept")
	expect(main.mode == "rebind", "accept starts rebinding")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_J
	ev.pressed = true
	main._rebind_key(ev)
	expect(main.mode == "controls" and s.keys["left"][0] == KEY_J, "key rebound")
	expect(InputMap.action_has_event("left", ev), "input map updated")
	s.reset_keys()
	main.apply_settings()
	main.page = 1
	main.open_controls("title")
	expect(main.items[0]["label"] == main.t("tab_pad"), "gamepad tab")
	press("ui_cancel")


func test_players() -> void:
	main.open_player()
	expect(main.mode == "player" and main.items.size() == 7, "players screen")
	press("ui_down")
	press("ui_accept")
	expect(main.progress.current == 1, "player 2 selected")
	main._start_rename()
	main.name_edit = "ania"
	main._rename_done(true)
	expect(main.progress.player()["name"] == "ania", "renamed")
	main.progress.rename("x!@#y")
	expect(main.progress.player()["name"] == "xy", "only the font's characters")
	main._select_player(0)
	press("ui_cancel")


func ticks(n: int, d := "") -> void:
	for i in n:
		if d != "":
			main.latched[d] = true
		main.game_tick()


func test_game() -> void:
	main.start_game(0)
	expect(main.mode == "play" and main.level == 0, "playing level 1")
	var p: Vector2i = main.sim.hero_pos()
	main.settings.set_value("undo", true)
	ticks(1, "right")
	expect(main.sim.hero_pos() == p + Vector2i(1, 0), "a tap moves one cell")
	ticks(3)
	expect(main.sim.hero_pos() == p + Vector2i(1, 0), "no input, no move")
	main.latched["undo"] = true
	main.game_tick()
	expect(main.sim.hero_pos() == p, "undo")
	main.settings.set_value("undo", false)
	main.latched["next_level"] = true
	main.game_tick()
	expect(main.level == 1 and main.play_state == "slide", "next level with a slide")
	main.play_state = "play"
	expect(main.progress.level(main.set_id) == 1, "current level saved")
	# solve level 38 (no hearts): the door opens at once
	main.start_level(37)
	main.sim = Sim.new(["*!"], 37, main.rand)
	ticks(4)
	ticks(1, "right")
	ticks(20)
	expect(main.progress.is_solved(main.set_id, 37), "solved level saved")
	expect(main.level == 38, "next level number after a solved level (as the original)")
	main.play_state = "play"
	main.open_pause()
	expect(main.mode == "pause", "pause")
	press("ui_accept")
	expect(main.mode == "play", "resume")
	main.open_pause()
	main.sel = 5
	press("ui_accept")
	expect(main.mode == "title" and main.items[1]["enabled"], "continue available after playing")
	var pr := Progress.new()
	pr.load_file()
	expect(pr.players[0]["sets"].has(main.set_id), "progress written to disk")


func test_levels_menu() -> void:
	main.open_levels("title")
	expect(main.mode == "levels", "level select")
	main.sel = 0
	press("ui_right")
	press("ui_down")
	expect(main.sel == 5, "grid navigation")
	press("ui_accept")
	expect(main.mode == "play" and main.level == 5, "plays the chosen level")
	main.open_title()


func test_settings_file() -> void:
	main.settings.set_value("speed", 75)
	main.settings.save_file()
	var s2 := Settings.new()
	s2.load_file()
	expect(s2.get_value("speed") == 75 and s2.get_value("language") == "en", "options restored")
	var cf := ConfigFile.new()
	cf.load(Settings.PATH)
	cf.set_value("keys", "no_such_action", [KEY_Q])
	cf.save(Settings.PATH)
	var s3 := Settings.new()
	s3.load_file()
	expect(not s3.keys.has("no_such_action"), "unknown actions ignored (R-C8)")
	expect(Levels.parse("{\n}\n")["error"] == "Not enough lines in level #1!", "level file errors")


func test_smooth() -> void:
	main.settings.set_value("smooth", true)
	main.start_game(0)
	main.sim = Sim.new(["*  @  ", "%%%%%%", "!"], 0, main.rand)
	main.sim.tick_count = 1
	ticks(1, "right")
	expect(main.sim.moves.size() == 1 and main.screen.moving.size() == 1, "a step is one move")
	var m: Array = main.screen.moving[0]
	expect(m[1] == Vector2i(0, 0) and m[2] == Vector2i(16, 0), "from the old cell to the new one")
	ticks(1, "right")
	var pushed := false
	for k in 3:                               # the push (odd ticks): dwarf and rock move together
		ticks(1, "right")
		pushed = pushed or main.screen.moving.size() == 2
	expect(pushed, "a push moves two objects")
	main.screen.draw_moving(0.5)
	var hash_before: int = main.sim.state_hash()
	main.screen.draw_moving(1.0)
	expect(main.sim.state_hash() == hash_before, "drawing never changes the state")
	ticks(1)
	expect(main.screen.moving.is_empty(), "nothing moves, nothing slides")
	main.settings.set_value("smooth", false)
	ticks(1, "down")
	expect(main.screen.moving.is_empty(), "option off: no sliding")
	main.open_title()


func test_wide() -> void:
	var pic := Rect2(Vector2(240, 0), Vector2(1440, 1080))           # 1920x1080: 4:3 picture
	expect(main.panel_width(Vector2(1920, 1080), pic) == 106, "16:9: panels 106 pixels wide")
	expect(main.panel_width(Vector2(1440, 1080), Rect2(Vector2.ZERO, Vector2(1440, 1080))) == 0,
			"4:3: no panels")
	expect(main.panel_width(Vector2(1728, 1080), Rect2(Vector2(144, 0), Vector2(1440, 1080))) == 0,
			"16:10: too narrow")
	expect(main.panel_width(Vector2(1080, 1920), pic) == 0, "upright: no panels")
	main.start_game(0)
	main.draw_panels()
	expect(main.panels[0].image.get_pixel(0, 390).r8 != 0, "panels drawn")
	main.open_title()
	expect(not main._panels_wanted(), "no panels in menus")


func test_level_file() -> void:
	var original_id: String = main.set_id
	var n: int = root.get_node("Data").levels.size()
	var bad := "{\n*!\n}\n".to_ascii_buffer()
	expect(main.load_levels_file(bad, "bad.hl") == "Not enough lines in level #1!",
			"a broken file is refused with the original's message")
	expect(root.get_node("Data").levels.size() == n and main.set_id == original_id, "the levels stay")
	var good := ""
	for k in 2:
		good += "author: tester\r\n{\r\n*  !\r\n" + "\r\n".repeat(11) + "}\r\n"
	expect(main.load_levels_file(good.to_ascii_buffer(), "/tmp/MOJE.HL") == "", "a good file loads")
	expect(root.get_node("Data").levels.size() == 2 and main.set_id != original_id, "its levels are played")
	expect(main.mode == "levels" and main.settings.levels_name == "MOJE.HL", "level select opens")
	expect(root.get_node("Data").levels[0]["author"] == "tester", "author read")
	var s2 := Settings.new()
	s2.load_file()
	expect(s2.levels_name == "MOJE.HL" and FileAccess.file_exists(CUSTOM),
			"the file is remembered")
	main.use_original_levels()
	expect(root.get_node("Data").levels.size() == n and main.set_id == original_id, "back to the original levels")
	expect(not FileAccess.file_exists(CUSTOM), "the copy is removed")
	main.open_title()


func key(code: int, unicode := 0) -> void:
	var e := InputEventKey.new()
	e.pressed = true
	e.physical_keycode = code
	e.keycode = code
	e.unicode = unicode
	main._input(e)


func mouse(kind: String, cell: Vector2i, button := MOUSE_BUTTON_LEFT, pressed := true) -> void:
	var e: InputEvent
	if kind == "move":
		e = InputEventMouseMotion.new()
	else:
		e = InputEventMouseButton.new()
		e.button_index = button
		e.pressed = pressed
	var r: Rect2 = main.display_rect
	e.position = r.position + (Vector2(cell) * 32.0 + Vector2(16, 16)) / Vector2(640, 400) * r.size
	main._input(e)


func test_editor() -> void:
	var data = root.get_node("Data")
	main.open_title()
	main.sel = main.TITLE_ITEMS.find("editor")
	press("ui_accept")
	expect(main.mode == "editor" and main.ed.levels.size() == 70, "the editor opens with the game's levels")
	main.ed_cur = Vector2i(2, 2)
	key(KEY_2, "@".unicode_at(0))
	expect(main.ed.cell(0, 2, 2) == "@" and main.ed_cur == Vector2i(3, 2), "typing a level character puts it")
	key(KEY_Z)
	expect(main.ed.cell(0, 2, 2) != "@", "z undoes")
	key(KEY_DOWN)
	expect(main.ed_cur == Vector2i(3, 3), "arrows move the cursor")
	key(KEY_DELETE)
	expect(main.ed.cell(0, 3, 3) == " ", "delete clears")
	main.ed_brush = LevelSet.CHARS.find("#")
	var undo_n: int = main.ed.undo_stack.size()
	mouse("button", Vector2i(5, 5))
	mouse("move", Vector2i(6, 5))
	mouse("move", Vector2i(7, 5))
	mouse("button", Vector2i(7, 5), MOUSE_BUTTON_LEFT, false)
	expect(main.ed.cell(0, 5, 5) == "#" and main.ed.cell(0, 7, 5) == "#", "dragging paints")
	expect(main.ed.undo_stack.size() == undo_n + 1, "one stroke, one undo step")
	mouse("button", Vector2i(1, 1), MOUSE_BUTTON_RIGHT)
	expect(LevelSet.CHARS[main.ed_brush] == main.ed.cell(0, 1, 1), "right button picks the object")
	key(KEY_PAGEDOWN)
	expect(main.ed_i == 1, "page down: next level")
	key(KEY_ESCAPE)
	expect(main.mode == "editor_menu", "esc opens the editor menu")
	main.sel = 3
	press("ui_accept")                     # new level after level 2
	expect(main.ed.levels.size() == 71 and main.ed_i == 2 and main.mode == "editor", "new level")
	expect(main.ed.levels[2]["rows"][1][1] == "*", "a new level has the dwarf and the door")
	main.open_editor_menu(5)
	press("ui_left")
	expect(main.ed_i == 1 and main.ed.levels[1]["rows"][1][1] == "*", "level moved")
	main.open_editor_menu(6)
	press("ui_accept")
	main._confirm(true)
	expect(main.ed.levels.size() == 70, "level deleted")
	# a level without the dwarf: the original's error, before testing or saving
	main.ed_i = 3
	main.ed.paint(3, 0, 0, "%")
	for y in 12:
		for x in 20:
			if main.ed.cell(3, x, y) == "*":
				main.ed.paint(3, x, y, ".")
	main.editor_test()
	expect(main.mode == "editor" and not main.testing and main.notice.contains("no hero on level  4"),
			"testing a level without a dwarf is refused with the original message")
	main.ed.paint(3, 1, 1, "*")
	# test a tiny level: the end of the level comes back to the editor
	main.ed.levels[3]["rows"] = LevelSet.new_level("")["rows"]
	main.ed.levels[3]["rows"][1] = "%*!" + main.ed.levels[3]["rows"][1].substr(3)
	main.editor_test()
	expect(main.mode == "play" and main.testing and main.level == 3, "testing plays the edited level")
	ticks(4)
	ticks(1, "right")
	ticks(20)
	expect(main.mode == "editor" and not main.testing, "finishing the test returns to the editor")
	expect(not main.progress.is_solved(main.set_id, 3), "testing does not mark levels solved")
	main.editor_test()
	main.latched["quit"] = true
	main.game_tick()
	expect(main.mode == "editor", "f10 returns to the editor")
	# saving: a standard LEVELS.HL that the original's parser reads back
	main.ed.set_author(3, "Tester")
	expect(main.save_editor_file(SAVED), "saved")
	var bytes := FileAccess.get_file_as_bytes(SAVED)
	var text := bytes.get_string_from_ascii()
	var r := Levels.parse(text)
	expect(r["error"] == "" and r["levels"].size() == 70, "the saved file parses with the original rules")
	expect(r["levels"][3]["author"] == "Tester" and r["levels"][3]["rows"][1].begins_with("%*!"),
			"the saved file has the edits")
	expect(text.begins_with(FileAccess.get_file_as_string("res://data/LEVELS.HL").left(200))
			and text.ends_with("}\r\n\u001a") and not text.replace("\r\n", "").contains("\n"),
			"the original's header, CR LF, ^Z")
	var orig := LevelSet.from_text(FileAccess.get_file_as_string("res://data/LEVELS.HL"))
	var parsed_orig: Array = Levels.parse(orig.to_text())["levels"]
	expect(parsed_orig == Levels.parse(FileAccess.get_file_as_string("res://data/LEVELS.HL"))["levels"],
			"the original levels survive the editor unchanged")
	# the work is kept
	main.ed = null
	main._editor_load()
	expect(main.ed.levels[3]["author"] == "Tester" and main.ed_name == "TEST.HL", "the editor's work is kept")
	main.open_editor()
	main.editor_play_set()
	expect(data.levels.size() == 70 and main.settings.levels_name == "TEST.HL" and main.mode == "levels",
			"play these levels")
	main.use_original_levels()
	main.open_levels("title")
	main.sel = 3
	key(KEY_E)
	expect(main.mode == "confirm", "level select: e asks before replacing the editor's levels")
	main._confirm(true)
	expect(main.mode == "editor" and main.ed_i == 3 and main.ed.levels[3]["author"] != "Tester",
			"the game's level in the editor")
	main._editor_quit()
	expect(main.mode == "title", "back to the title")
	await process_frame


func test_stt() -> void:
	var bytes := FileAccess.get_file_as_bytes("res://tests/data/PLAYER1.STT")   # made by HL.EXE
	var r := Progress.decode_stt(bytes)
	expect(r.get("name") == "player1" and r.get("level") == 2 and r.get("solved") == [],
			"an original PLAYER1.STT is read (name, level 3)")
	var bad := bytes.duplicate()
	bad[5] ^= 1
	expect(Progress.decode_stt(bad).is_empty(), "a damaged STT is refused (checksum)")
	main.progress.current = 1
	main.open_player()
	expect(main.import_player_file(bytes), "imported")
	expect(main.progress.player()["name"] == "player1" and main.progress.level(main.set_id) == 2,
			"into the current player")
	expect(not main.import_player_file(bad) and main.notice == main.t("stt_bad"), "damaged: a message")
	main.progress.current = 0
	main.open_title()


func tap(text_pos: Vector2) -> void:
	"""a finger on the screen at a point of the 640x400 text layer"""
	for pressed in [true, false]:
		var e := InputEventScreenTouch.new()
		e.pressed = pressed
		e.position = main.display_rect.position + text_pos / Vector2(640, 400) * main.display_rect.size
		main._input(e)


func test_levels_touch() -> void:
	main.open_levels("title")
	main.sel = 0
	main.page = 0
	main.draw_ui()
	tap(Vector2(160 + 80, 22 + 60))           # level 2 (second picture of the first row)
	expect(main.mode == "levels" and main.sel == 1, "a tap selects a level")
	tap(Vector2(160 + 80, 22 + 60))
	expect(main.mode == "play" and main.level == 1, "a second tap plays it")
	main.open_levels("title")
	main.page = 0
	main.sel = 0
	main.draw_ui()
	tap(Vector2(600, 390))
	expect(main.page == 1 and main.sel == 12, "next page button")
	tap(Vector2(20, 390))
	expect(main.page == 0, "previous page button")
	tap(Vector2(20, 8))
	expect(main.mode == "title", "back button")
	main.start_game(4)
	main.touch._button("next_level")
	main.game_tick()
	expect(main.level == 5, "touch: next level button")
	main.play_state = "play"
	main.touch._button("prev_level")
	main.game_tick()
	expect(main.level == 4, "touch: previous level button")
	main.play_state = "play"
	main.open_title()
