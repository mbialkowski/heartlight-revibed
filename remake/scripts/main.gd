extends Node2D
## The play screen (milestone M2): the original's PlayGame loop (docs 3.3) — one tick every
## 112.6 ms, restart with a fade when the dwarf has died, slide to the next/previous level,
## F1 overview, F6/F7/F8 with the option icons. Menus, options and saving arrive with M3.
##
## Command-line (after "--"): --level=N  start level;  --shots=DIR  write a few screenshots
## while playing --moves=STRING (one character per tick: . L R U D E) and quit.

const Sim = preload("res://scripts/sim/sim.gd")
const Rand = preload("res://scripts/sim/rand.gd")
const Screen = preload("res://scripts/view/screen.gd")
const Palette = preload("res://scripts/view/palette.gd")
const Controls = preload("res://scripts/game/controls.gd")
const AudioScript = preload("res://scripts/game/audio.gd")

const SLIDE_STEP := 16              # pixels per vertical retrace (NextLevelScroll 1633:14A3)
const RETRACE := 1.0 / 70.0
const ICON_TICKS := 0x30

var screen: Screen
var palette: Palette
var controls := Controls.new()
var audio
var display: TextureRect
var sim: Sim
var rand := Rand.new(randi() & 0xFFFF)
var level := 0
var solved := {}                    # level index -> true (saving arrives with M3)
var tick_s := 0.11264
var acc := 0.0
var mode := "play"                  # play, fade_out, fade_in, slide
var overview := false
var music_on := true
var sound_on := true
var gamepad_on := false
var icons := ICON_TICKS
var slide_from: Image
var slide_dir := 1
var slide_t := 0.0
var tick_count := 0                 # carried over between levels like DS:60DD
var shots_dir := ""
var shot_moves := ""
var shot_tick := 0


func _ready() -> void:
	Controls.install()
	tick_s = float(Data.game["tick_seconds"])
	screen = Screen.new(Data.game["font_chars"])
	palette = Palette.new(Data.palette, Data.palette_mono)
	audio = AudioScript.new()
	add_child(audio)
	audio.setup(Data.game)
	display = TextureRect.new()
	display.texture = screen.texture
	display.stretch_mode = TextureRect.STRETCH_SCALE
	display.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/view/palette.gdshader")
	mat.set_shader_parameter("idx_tex", screen.texture)
	mat.set_shader_parameter("pal_tex", palette.texture)
	display.material = mat
	add_child(display)
	get_viewport().size_changed.connect(_layout)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			level = clampi(int(arg.substr(8)) - 1, 0, Data.levels.size() - 1)
		elif arg.begins_with("--shots="):
			shots_dir = arg.substr(8)
		elif arg.begins_with("--moves="):
			shot_moves = arg.substr(8)
	start_level(level)
	audio.play_music()
	_layout()


func _layout() -> void:
	"""the 320x200 picture at the 4:3 shape of a VGA monitor (pixels 1.2 times taller), centred"""
	var win := get_viewport_rect().size
	var scale := minf(win.x / 320.0, win.y / 240.0)
	var size := Vector2(320.0 * scale, 240.0 * scale)
	display.position = ((win - size) / 2.0).floor()
	display.size = size.floor()
	display.material.set_shader_parameter("out_scale", Vector2(size.x / 320.0, size.y / 200.0))


func start_level(i: int) -> void:
	level = i
	sim = Sim.new(Data.levels[level]["rows"], level, rand, tick_count)
	acc = 0.0
	render()


func _input(event: InputEvent) -> void:
	controls.note(event)
	if event.is_action_pressed("fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full
				else DisplayServer.WINDOW_MODE_FULLSCREEN)


func _process(delta: float) -> void:
	palette.update(delta)
	match mode:
		"play":
			acc += delta
			var n := 0
			while acc >= tick_s and mode == "play" and n < 4:
				acc -= tick_s
				n += 1
				game_tick()
		"fade_out":
			if not palette.busy():
				sim.setup(Data.levels[level]["rows"])
				render()
				palette.fade(1.0, 0.25)
				mode = "fade_in"
		"fade_in":
			if not palette.busy():
				acc = 0.0
				mode = "play"
		"slide":
			slide_t += delta
			var steps := int(slide_t / RETRACE)
			var off := mini(320, (steps + 1) * SLIDE_STEP)
			_compose_slide(off)
			if off >= 320:
				acc = 0.0
				mode = "play"


func game_tick() -> void:
	# the keys GameTick handles besides the directions
	if Input.is_action_just_pressed("music"):
		music_on = not music_on
		audio.music_on = music_on
		if music_on:
			audio.play_music()
		else:
			audio.stop_music()
		_option_toggled()
	if Input.is_action_just_pressed("sound"):
		sound_on = not sound_on
		audio.sound_on = sound_on
		if not sound_on:
			audio.stop_all()
		else:
			audio.play_music()
		_option_toggled()
	if Input.is_action_just_pressed("gamepad"):
		gamepad_on = not gamepad_on
		_option_toggled()
	if Input.is_action_just_pressed("overview"):
		overview = not overview
	if Input.is_action_just_pressed("quit"):
		get_tree().quit()                 # M3: back to the title screen
		return
	var mod := controls.down("level_mod")
	if (mod and controls.take("left")) or controls.take("prev_level"):
		change_level(-1)
		return
	if (mod and controls.take("right")) or controls.take("next_level"):
		change_level(1)
		return
	var d := 0 if mod else controls.direction()
	if shots_dir != "" and shot_moves != "":
		d = {"L": -1, "R": 1, "U": -22, "D": 22}.get(shot_moves[shot_tick % shot_moves.length()], 0)
	var esc := controls.take("restart")
	if shots_dir != "" and shot_moves != "" and shot_moves[shot_tick % shot_moves.length()] == "E":
		esc = true
	controls.end_tick()
	sim.tick(d, esc)
	tick_count = sim.tick_count
	for s in sim.sounds:
		audio.play(s)
	render()
	if icons > 0:
		icons -= 1
	_shot_hook()
	if not sim.level_running():
		if sim.game_state == Sim.NEXT_LEVEL:
			solved[level] = true
			change_level(1)
		elif sim.game_state == Sim.PLAYING:       # the dwarf is gone: restart with a fade
			palette.fade(0.0, 0.25)
			mode = "fade_out"


func _option_toggled() -> void:
	audio.play("key")
	icons = ICON_TICKS


func change_level(step: int) -> void:
	slide_from = screen.image.duplicate()
	slide_dir = step
	var n := Data.levels.size()
	start_level((level + step + n) % n)
	slide_t = 0.0
	mode = "slide"
	_compose_slide(SLIDE_STEP)


func _compose_slide(off: int) -> void:
	"""the old level slides out, the new one in (only the play-field; the status line is new)"""
	render_into_screen()
	var new_img := screen.image.duplicate()
	var out := Image.create(320, 200, false, Image.FORMAT_RGBA8)
	out.fill(Color(0, 0, 0, 1))
	if slide_dir > 0:
		out.blit_rect(slide_from, Rect2i(off, 0, 320 - off, 192), Vector2i(0, 0))
		out.blit_rect(new_img, Rect2i(0, 0, off, 192), Vector2i(320 - off, 0))
	else:
		out.blit_rect(slide_from, Rect2i(0, 0, 320 - off, 192), Vector2i(off, 0))
		out.blit_rect(new_img, Rect2i(320 - off, 0, off, 192), Vector2i(0, 0))
	out.blit_rect(new_img, Rect2i(0, 192, 320, 8), Vector2i(0, 192))
	screen.image.copy_from(out)
	screen.update_texture()
	if off >= 320:
		render()


func render_into_screen() -> void:
	if overview:
		screen.draw_overview(sim)
	else:
		screen.draw_level(sim)
	if icons > 0:
		screen.draw_icons(music_on, sound_on, gamepad_on)
	screen.draw_status(sim.hearts_total, sim.hearts_total - sim.hearts_left, Data.levels.size(),
			solved.size(), solved.has(level), level + 1)


func render() -> void:
	render_into_screen()
	screen.update_texture()


func _shot_hook() -> void:
	if shots_dir == "":
		return
	shot_tick += 1
	if shot_tick in [1, 20, 60]:
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.save_png(shots_dir.path_join("play_%03d.png" % shot_tick))
	if shot_tick >= 60:
		get_tree().quit()
