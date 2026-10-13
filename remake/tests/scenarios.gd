extends SceneTree
## Drives the remake's screens like a player would (plan 4 and 8): menus with each device,
## options saved and restored, remapping (swap on conflict, defaults, mandatory actions),
## players and saving, undo, level change, the level file errors.
##     godot --headless --path remake --script res://tests/scenarios.gd

const Settings = preload("res://scripts/game/settings.gd")
const Progress = preload("res://scripts/game/progress.gd")
const Levels = preload("res://scripts/sim/levels.gd")
const Sim = preload("res://scripts/sim/sim.gd")

var failures := 0
var checks := 0
var main


func expect(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAILED: ", what)


func _initialize() -> void:
	for f in [Settings.PATH, Progress.PATH]:
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
	test_settings_file()
	for f in [Settings.PATH, Progress.PATH]:
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
	expect(main.mode == "player" and main.items.size() == 6, "players screen")
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
