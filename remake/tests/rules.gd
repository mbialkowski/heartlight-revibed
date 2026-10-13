extends SceneTree
## Single rules of docs/reverse-engineering/03-engine.md on tiny levels; the same cases as
## tests/test_sim.py for tools/hl_sim.py.
##     godot --headless --path remake --script res://tests/rules.gd

const Sim = preload("res://scripts/sim/sim.gd")
const Rand = preload("res://scripts/sim/rand.gd")
const Levels = preload("res://scripts/sim/levels.gd")

var failures := 0
var checks := 0


func _initialize() -> void:
	test_falls_one_cell_per_tick()
	test_rolls()
	test_rock_kills_dwarf()
	test_push_only_on_odd_ticks()
	test_collect_door_exit()
	test_bomb()
	test_bomb_on_grass()
	test_balloon_lifts_dwarf()
	test_tunnel()
	test_esc()
	test_level_file()
	test_idle_levels()
	print("rules: %d/%d checks passed" % [checks - failures, checks])
	quit(1 if failures else 0)


func expect(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		print("FAILED: ", what)


func sim(rows: Array, parity := 1) -> Sim:
	var r := rows.duplicate()
	while r.size() < 12:
		r.append("")
	return Sim.new(r, 0, Rand.new(1), parity)


func t(s: Sim, x: int, y: int) -> int:
	return s.type[s.cell_index(x, y)]


func test_falls_one_cell_per_tick() -> void:
	var s := sim(["@", "", "", "", "#*!"])
	s.tick()
	expect(t(s, 0, 1) == Sim.ROCK and t(s, 0, 0) == Sim.EMPTY, "falls at once")
	s.tick()
	expect(t(s, 0, 2) == Sim.ROCK, "one cell per tick")


func test_rolls() -> void:
	var s := sim([" @ ", " # ", "", "", "*!"])
	s.tick()
	expect(t(s, 0, 0) == Sim.ROCK, "rolls off brick, left first")
	s = sim([" @ ", " % ", "", "", "*!"])
	s.tick()
	expect(t(s, 1, 0) == Sim.ROCK, "does not roll off metal")
	s = sim([" @ ", " . ", "", "", "*!"])
	s.tick()
	expect(t(s, 1, 0) == Sim.ROCK, "does not roll off grass")


func test_rock_kills_dwarf() -> void:
	var s := sim(["@", "", "*", "%", "", "!"])
	s.tick()
	s.tick()
	expect(t(s, 0, 2) == Sim.EXPLOSION and s.sounds.has("expl"), "rock kills the dwarf")


func test_push_only_on_odd_ticks() -> void:
	var s := sim(["*@ ", "%%%", "!"], 0)
	s.tick(Sim.RIGHT)
	expect(s.hero_pos() == Vector2i(0, 0) and t(s, 1, 0) == Sim.ROCK, "even tick: no push")
	s.tick(Sim.RIGHT)
	expect(s.hero_pos() == Vector2i(1, 0) and t(s, 2, 0) == Sim.ROCK, "odd tick: push")


func test_collect_door_exit() -> void:
	var s := sim(["*$!", "%%%"])
	s.tick(Sim.RIGHT)
	expect(s.hearts_left == 0 and s.sounds.has("colect"), "collect")
	var d := s.cell_index(2, 0)
	expect(s.frame[d] == 1, "door starts opening in the same tick")
	s.tick()
	s.tick()
	expect(s.state[d] == 5 and s.frame[d] == 3, "door frame 3, still closed")
	s.tick()
	expect(s.state[d] == 6, "door open")
	s.tick(Sim.RIGHT)
	expect(s.sounds.has("door") and s.exit_timer == 15, "enter the door")
	var n := 0
	while s.level_running() and n < 100:
		s.tick()
		n += 1
	expect(s.game_state == Sim.NEXT_LEVEL and s.solved, "level solved")


func test_bomb() -> void:
	var s := sim(["&", "", "#", "", "", "*!"])
	s.tick()
	s.tick()
	expect(s.state[s.cell_index(0, 1)] == 8, "bomb lit on landing")
	s.tick()
	expect(s.frame[s.cell_index(0, 1)] == 1, "lit frame")
	s.tick()
	expect(t(s, 0, 1) == Sim.EXPLOSION and t(s, 0, 2) == Sim.EXPLOSION, "explodes, brick destroyed")


func test_bomb_on_grass() -> void:
	var s := sim(["&", "", ".", "", "", "*!"])
	for i in 5:
		s.tick()
	expect(t(s, 0, 1) == Sim.BOMB and s.state[s.cell_index(0, 1)] == 2, "no explosion on grass")


func test_balloon_lifts_dwarf() -> void:
	var s := sim(["", "", "*", "0", "%", "!"])
	s.tick()
	expect(s.hero_pos() == Vector2i(0, 1) and t(s, 0, 2) == Sim.BALLOON, "balloon lifts the dwarf")


func test_tunnel() -> void:
	var s := sim(["*>> ", "%%%%", "!"])
	s.tick(Sim.RIGHT)
	expect(s.hero_pos() == Vector2i(-1, -1) and s.state[s.cell_index(1, 0)] == 1, "enters the tunnel")
	s.tick()
	s.tick()
	s.tick()
	expect(s.hero_pos() == Vector2i(3, 0), "one cell per tick")


func test_esc() -> void:
	var s := sim(["*!"])
	s.tick(0, true)
	for i in 6:
		expect(t(s, 0, 0) == Sim.DWARF and s.frame[s.cell_index(0, 0)] in [4, 5], "blinking")
		s.tick()
	expect(t(s, 0, 0) == Sim.DWARF, "still blinking after 7 ticks")
	s.tick()
	expect(t(s, 0, 0) == Sim.EXPLOSION, "explodes on the 8th tick")


func test_level_file() -> void:
	var r := Levels.parse(FileAccess.get_file_as_string("res://data/LEVELS.HL"))
	expect(r["error"] == "" and r["levels"].size() == 70, "LEVELS.HL: 70 levels")
	expect(r["levels"][0]["author"] == "Janusz Pelc", "author")
	var rows := "{\n" + "*!\n".repeat(11) + "}\n"
	expect(Levels.parse(rows)["error"] == "Not enough lines in level #1!", "not enough lines")
	rows = "{\n" + "*!\n".repeat(13) + "}\n"
	expect(Levels.parse(rows)["error"] == "Too many lines in level #1!", "too many lines")
	rows = "{\n" + "  \n".repeat(11) + "*\n}\n"
	expect(Levels.parse(rows)["error"] == "No exit on level #1!", "no exit")
	rows = "{\n" + "x!\n".repeat(11) + "*\n}\n"
	expect(Levels.parse(rows)["error"] == "Invalid object on level #1!", "invalid object")


func test_idle_levels() -> void:
	var r := Levels.parse(FileAccess.get_file_as_string("res://data/LEVELS.HL"))
	var killed := []
	for i in r["levels"].size():
		var s := Sim.new(r["levels"][i]["rows"], i, Rand.new(1))
		for k in 200:
			s.tick()
			if s.hero_pos() == Vector2i(-1, -1):
				killed.append([i + 1, k])
				break
	expect(killed == [[30, 23]], "only level 30 kills an idle dwarf (tick 23): %s" % [killed])
