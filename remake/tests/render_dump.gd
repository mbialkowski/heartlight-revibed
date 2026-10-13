extends SceneTree
## Renders screens with screen.gd and writes their palette indices as PNG (red channel), for
## tools/compare_render.py, which compares them with DOSBox screenshots of the original.
##     godot --headless --path remake --script res://tests/render_dump.gd -- <out_dir>

const Screen = preload("res://scripts/view/screen.gd")
const Sim = preload("res://scripts/sim/sim.gd")
const Rand = preload("res://scripts/sim/rand.gd")
const Levels = preload("res://scripts/sim/levels.gd")


func _initialize() -> void:
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() else "/tmp"
	var game = JSON.parse_string(FileAccess.get_file_as_string("res://data/game.json"))
	var levels: Array = Levels.parse(FileAccess.get_file_as_string("res://data/LEVELS.HL"))["levels"]
	var scr := Screen.new(game["font_chars"])
	# level 1 at its start, with the option icons (music on, sound on, joystick off)
	var s := Sim.new(levels[0]["rows"], 0, Rand.new(1))
	scr.clear()
	scr.draw_level(s)
	scr.draw_icons(true, true, false)
	scr.draw_status(s.hearts_total, 0, 70, 0, false, 1)
	scr.image.save_png(out.path_join("level01.png"))
	scr.clear()
	scr.draw_overview(s)
	scr.draw_icons(true, true, false)
	scr.draw_status(s.hearts_total, 0, 70, 0, false, 1)
	scr.image.save_png(out.path_join("overview.png"))
	print("written to ", out)
	quit(0)
