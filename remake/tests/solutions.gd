extends SceneTree
## Every recorded solution (tests/solutions.json, found by tools/solve_levels.py and checked there
## with tools/hl_sim.py) must still finish its level with the remake's rules: one input per tick
## from the level start (tick_count 0), the level must end with the dwarf through the door.
##     godot --headless --path remake --script res://tests/solutions.gd

const Sim = preload("res://scripts/sim/sim.gd")
const Rand = preload("res://scripts/sim/rand.gd")
const Levels = preload("res://scripts/sim/levels.gd")
const DIRS := {".": 0, "L": -1, "R": 1, "U": -22, "D": 22}


func _initialize() -> void:
	var levels: Array = Levels.parse(FileAccess.get_file_as_string("res://data/LEVELS.HL"))["levels"]
	if not FileAccess.file_exists("res://tests/data/solutions.json"):
		print("solutions: tests/data/solutions.json missing")
		quit(1)
		return
	var sols: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tests/data/solutions.json"))["levels"]
	var ok := 0
	var failed := []
	for key in sols:
		var i := int(key) - 1
		var sim := Sim.new(levels[i]["rows"], i, Rand.new(1), 0)
		var done := false
		for c in str(sols[key]["inputs"]):
			sim.tick(DIRS[c])
			if not sim.level_running():
				done = sim.game_state == Sim.NEXT_LEVEL
				break
		if done:
			ok += 1
		else:
			failed.append(key)
	if not failed.is_empty():
		print("FAILED levels: ", ", ".join(failed))
	print("solutions: %d/%d levels solved (%d recorded)" % [ok, levels.size(), sols.size()])
	quit(1 if not failed.is_empty() else 0)
