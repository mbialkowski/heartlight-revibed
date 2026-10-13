extends SceneTree
## Replays res://data/golden_traces.json (tools/make_golden_traces.py, from tools/hl_sim.py, which
## matches the original on all 70 levels) through sim.gd and compares every tick: state hash,
## sounds and periodic full grids.
##     godot --headless --path remake --script res://tests/golden.gd

const Sim = preload("res://scripts/sim/sim.gd")
const Rand = preload("res://scripts/sim/rand.gd")
const Levels = preload("res://scripts/sim/levels.gd")

const DIRS := {".": 0, "L": -1, "R": 1, "U": -22, "D": 22, "E": 0}


func _initialize() -> void:
	var levels: Array = Levels.parse(FileAccess.get_file_as_string("res://data/LEVELS.HL"))["levels"]
	var data = JSON.parse_string(FileAccess.get_file_as_string("res://data/golden_traces.json"))
	var ok := 0
	var ticks := 0
	var traces: Array = data["traces"]
	for tr in traces:
		var n := int(tr["level"])
		var s := Sim.new(levels[n - 1]["rows"], n - 1, Rand.new(int(tr["seed"])), int(tr["parity"]))
		var inputs: String = tr["inputs"]
		var hashes: Array = tr["hashes"]
		var bad := ""
		for i in inputs.length():
			var c := inputs[i]
			s.tick(DIRS[c], c == "E")
			ticks += 1
			var expect = hashes[i]
			var h := s.state_hash()
			var key := str(i)
			var snd: Array = tr["sounds"].get(key, [])
			if (expect is Array and h != int(expect[0])) or (not expect is Array and h != int(expect)):
				bad = "tick %d: state differs" % i
			elif Array(s.sounds) != snd:
				bad = "tick %d: sounds %s, expected %s" % [i, s.sounds, snd]
			elif tr["grids"].has(key) and Array(s.type) != tr["grids"][key].map(func(v): return int(v)):
				bad = "tick %d: grid differs" % i
			if bad != "":
				break
			if not s.level_running():
				if s.game_state != Sim.PLAYING:
					break
				s.restart_if_over()
				if expect is Array and s.state_hash() != int(expect[1]):
					bad = "tick %d: restart differs" % i
					break
		if bad == "":
			ok += 1
		else:
			print("FAILED %s: %s" % [tr["name"], bad])
	print("golden traces: %d/%d match (%d ticks)" % [ok, traces.size(), ticks])
	quit(0 if ok == traces.size() else 1)
