extends SceneTree
## Loads every script so parse errors show up:  godot --headless --path remake --script res://tests/check.gd


func _initialize() -> void:
	var bad := 0
	for dir in ["res://scripts", "res://scripts/sim", "res://scripts/game", "res://scripts/view", "res://tests"]:
		if not DirAccess.dir_exists_absolute(dir):
			continue
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".gd"):
				var s = load(dir.path_join(f))
				if s == null or not s.can_instantiate():
					print("FAILED: ", dir.path_join(f))
					bad += 1
	for f in ["game.json", "palette.json", "levels.json", "LEVELS.HL", "golden_traces.json",
			"sprites.png", "sprites_mini.png", "font.png", "logo.png", "chaos.png", "snd_rock.wav",
			"music_a.wav"]:
		if not FileAccess.file_exists("res://data/" + f):
			print("MISSING: res://data/" + f)
			bad += 1
	print("scripts and data checked, %d failed" % bad)
	quit(1 if bad else 0)
