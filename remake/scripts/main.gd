extends Node2D
## Heartlight: Revibed — screens and game flow (docs/remake-plan.md sections 4 and 6).
##
## The play screen is the original's PlayGame loop (docs 3.3): one tick every 112.6 ms, a restart
## with a fade when the dwarf has died, a slide to the next/previous level, F1 overview, F6/F7/F8
## with the option icons. Around it: first screen, title, pause, options, controls (remapping),
## level select, players, credits — all usable with keyboard, gamepad, mouse and touch (R-M1).
##
## Command-line (after "--"): --level=N  start playing level N;  --shots=DIR  screenshots of the
## screens and a short game (--moves=STRING: one character per tick . L R U D E), then quit.

const Sim = preload("res://scripts/sim/sim.gd")
const Rand = preload("res://scripts/sim/rand.gd")
const Screen = preload("res://scripts/view/screen.gd")
const TextLayer = preload("res://scripts/view/text_layer.gd")
const Palette = preload("res://scripts/view/palette.gd")
const AudioScript = preload("res://scripts/game/audio.gd")
const Settings = preload("res://scripts/game/settings.gd")
const Progress = preload("res://scripts/game/progress.gd")
const S = preload("res://scripts/game/strings.gd")
const TouchScript = preload("res://scripts/view/touch.gd")
const Levels = preload("res://scripts/sim/levels.gd")
const LevelSet = preload("res://scripts/game/level_set.gd")

const SLIDE_STEP := 16              # pixels per vertical retrace (NextLevelScroll 1633:14A3)
const RETRACE := 1.0 / 70.0
const ICON_TICKS := 0x30
const UNDO_LIMIT := 1000
const PANEL_MIN_W := 96             # side panels on wide screens, in text-layer pixels
const PANEL_MAX_W := 320
const CUSTOM_LEVELS := "user://custom_levels.hl"
const EDITOR_FILE := "user://editor.json"       # the editor's work, saved after every change
const AUTHOR_LEN := 30
const TITLE_ITEMS := ["new", "continue", "levels", "editor", "player", "options", "controls",
		"credits", "quit"]
const OPTION_PAGES := {
	"page_game": ["language", "push", "after", "undo", "speed", "map"],
	"page_video": ["scale", "colours", "smooth", "wide", "fullscreen"],
	"page_sound": ["sound", "music_on", "music", "fx", "overlap"],
	"page_controls": [],
}
const KEYS_PER_TICK := ["left", "right", "up", "down", "restart", "undo", "prev_level", "next_level",
		"overview", "music", "sound", "gamepad"]

var settings := Settings.new()
var progress := Progress.new()
var screen: Screen
var text: TextLayer
var palette: Palette
var audio
var display: TextureRect
var overlay: TextureRect
var base_mat: ShaderMaterial
var over_mat: ShaderMaterial
var display_rect := Rect2()
var touch
var portrait := false
var panels := []                    # left and right TextLayer (wide screens, option "wide")
var panel_rects := []
var panel_mats := []
var panels_on := false
var _js_file_cb                     # web: keeps the JavaScript callbacks alive
var _js_drop_cb

var mode := "boot"
var items := []                     # menu rows: {label, value, enabled, act, left, right}
var sel := 0
var rows := []                      # Rect2i per row (text layer coordinates), for mouse and touch
var back_to := "title"              # where options / controls / levels return to
var page := 0                       # options page, controls tab, level-select page
var confirm_text := ""
var confirm_yes: Callable
var confirm_no: Callable
var rebind_action := ""
var notice := ""
var notice_t := 0.0
var name_edit := ""
var credits_t := 0.0
var title_t := 0.0

# game
var sim: Sim
var rand := Rand.new(randi() & 0xFFFF)
var level := 0
var set_id := ""
var tick_s := 0.11264
var acc := 0.0
var play_state := "play"            # play, fade_out, fade_in, slide
var overview := false
var icons := 0
var slide_from: Image
var slide_dir := 1
var slide_t := 0.0
var tick_count := 0                 # carried over between levels like DS:60DD
var latched := {}
var undo_stack := []

# level editor
var ed                              # LevelSet
var ed_i := 0
var ed_cur := Vector2i(1, 1)
var ed_brush := 3                   # index in LevelSet.CHARS ("." grass)
var ed_name := "LEVELS.HL"
var ed_slots := []                  # mini-sprite slot of every brush
var ed_stroke := false
var ed_snap := []
var ed_snap_used := false
var testing := false                # playing a level from the editor
var edit_target := "player"         # what the text entry edits: player name or level author

# screenshots / automatic test
var shots_dir := ""
var shot_moves := ""
var shot_tick := 0


func _ready() -> void:
	settings.load_file()
	progress.load_file()
	set_id = Progress.set_id_of(Data.levels_text)
	tick_s = float(Data.game["tick_seconds"])
	screen = Screen.new(Data.game["font_chars"])
	text = TextLayer.new(screen)
	palette = Palette.new(Data.palette, Data.palette_mono)
	audio = AudioScript.new()
	add_child(audio)
	audio.setup(Data.game)
	base_mat = _material(screen.texture, Vector2(320, 200))
	over_mat = _material(text.texture, Vector2(640, 400))
	display = _rect(base_mat, screen.texture)
	overlay = _rect(over_mat, text.texture)
	for i in 2:
		var p := TextLayer.new(screen, PANEL_MIN_W, 400)
		var m := _material(p.texture, Vector2(PANEL_MIN_W, 400))
		panels.append(p)
		panel_mats.append(m)
		panel_rects.append(_rect(m, p.texture))
	get_window().files_dropped.connect(_files_dropped)
	_web_setup()
	_load_saved_levels()
	touch = TouchScript.new()
	touch.main = self
	add_child(touch)
	get_viewport().size_changed.connect(_layout)
	apply_settings()
	var start_level := -1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--level="):
			start_level = clampi(int(arg.substr(8)) - 1, 0, Data.levels.size() - 1)
		elif arg.begins_with("--shots="):
			shots_dir = arg.substr(8)
		elif arg.begins_with("--moves="):
			shot_moves = arg.substr(8)
	_layout()
	if shots_dir != "":
		_screens_tour()
	elif start_level >= 0:
		start_game(start_level)
	elif OS.has_feature("web") or not FileAccess.file_exists(Settings.PATH):
		open_first()
	else:
		open_title()


func _material(tex: Texture2D, size: Vector2) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/view/palette.gdshader")
	m.set_shader_parameter("idx_tex", tex)
	m.set_shader_parameter("pal_tex", palette.texture)
	m.set_shader_parameter("src_size", size)
	return m


func _rect(mat: ShaderMaterial, tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.material = mat
	add_child(r)
	return r


func _layout() -> void:
	"""the 320x200 picture at the 4:3 shape of a VGA monitor (pixels 1.2 times taller), centred"""
	var win := get_viewport_rect().size
	portrait = win.y > win.x
	var scale := minf(win.x / 320.0, win.y / 240.0)
	var size := Vector2(320.0 * scale, 240.0 * scale).floor()
	display_rect = Rect2(((win - size) / 2.0).floor(), size)
	if portrait and touch != null and touch.wanted():
		display_rect.position.y = 0.0               # the touch controls go below the picture
	for r in [display, overlay]:
		r.position = display_rect.position
		r.size = display_rect.size
	base_mat.set_shader_parameter("out_scale", Vector2(size.x / 320.0, size.y / 200.0))
	over_mat.set_shader_parameter("out_scale", Vector2(size.x / 640.0, size.y / 400.0))
	if touch != null:
		touch.relayout()                            # anchored to the full window
	_layout_panels()


func panel_width(win: Vector2, picture: Rect2) -> int:
	"""width of the side panels in text-layer pixels (the bands beside the picture), 0 when they
	are too narrow for six glyphs"""
	if win.y > win.x or picture.size.x <= 0.0:
		return 0
	var w := int(picture.position.x / (picture.size.x / 640.0))
	return mini(w, PANEL_MAX_W) if w >= PANEL_MIN_W else 0


func _panels_wanted() -> bool:
	return settings.get_value("wide") and mode in ["play", "pause"] and sim != null \
			and not (touch != null and touch.visible) \
			and panel_width(get_viewport_rect().size, display_rect) > 0


func _layout_panels() -> void:
	if panel_rects.is_empty():
		return
	panels_on = _panels_wanted()
	var w := panel_width(get_viewport_rect().size, display_rect)
	var sc := display_rect.size / Vector2(640, 400)
	for i in 2:
		var r: TextureRect = panel_rects[i]
		r.visible = panels_on
		if not panels_on:
			continue
		if panels[i].width != w:
			panels[i] = TextLayer.new(screen, w, 400)
			r.texture = panels[i].texture
			panel_mats[i].set_shader_parameter("idx_tex", panels[i].texture)
			panel_mats[i].set_shader_parameter("src_size", Vector2(w, 400))
		r.size = Vector2(w, 400) * sc
		r.position = Vector2(display_rect.position.x - r.size.x if i == 0 else display_rect.end.x,
				display_rect.position.y)
		panel_mats[i].set_shader_parameter("out_scale", sc)
	if panels_on:
		draw_panels()


func can_fullscreen() -> bool:
	return not OS.has_feature("web_ios") and DisplayServer.get_name() != "headless"


func is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN


func toggle_fullscreen() -> void:
	settings.set_value("fullscreen", not is_fullscreen())
	apply_settings()
	settings.save_file()


func to_text_coords(p: Vector2) -> Vector2:
	return (p - display_rect.position) / display_rect.size * Vector2(640, 400)


# settings ------------------------------------------------------------------------------------
func apply_settings() -> void:
	S.lang = settings.get_value("language")
	palette.set_mono(settings.get_value("colours") == "mono")
	var smooth: bool = settings.get_value("scale") == "smooth"
	for m in [base_mat, over_mat] + panel_mats:
		m.set_shader_parameter("smooth_scale", smooth)
	audio.sound_on = settings.get_value("sound")
	audio.music_on = settings.get_value("music_on")
	audio.music_volume = float(settings.get_value("music")) / 100.0
	audio.fx_volume = float(settings.get_value("fx")) / 100.0
	audio.overlap_always = settings.get_value("overlap") == "always"
	audio.apply_volumes()
	if not audio.sound_on:
		audio.stop_all()
	settings.apply_input_map()
	if can_fullscreen():
		var full: bool = settings.get_value("fullscreen")
		if full != is_fullscreen():
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if full
					else DisplayServer.WINDOW_MODE_WINDOWED)
	if touch != null:
		_layout()
	tick_s = float(Data.game["tick_seconds"]) * 100.0 / float(settings.get_value("speed"))


func save_all() -> void:
	settings.save_file()
	progress.save_file()


func t(key: String) -> String:
	return S.glyph_text(S.get_text(key))


# input -----------------------------------------------------------------------------------------
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and mode == "rebind":
		_rebind_key(event)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventJoypadButton and event.pressed and mode == "rebind":
		_rebind_pad(event)
		return
	if event.is_action_pressed("fullscreen") and mode != "rename":
		toggle_fullscreen()
		return
	if mode == "play":
		for a in KEYS_PER_TICK:
			if event.is_action_pressed(a, false, true):
				latched[a] = true
		if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F10:
			latched["quit"] = true
		if event.is_action_pressed("pause"):
			open_pause()
		return
	if mode == "rename":
		_rename_input(event)
		return
	if mode == "editor":
		_editor_input(event)
		return
	if mode == "editor_help":
		if (event is InputEventKey or event is InputEventJoypadButton or event is InputEventMouseButton
				or event is InputEventScreenTouch) and event.is_pressed() and not event.is_echo():
			open_editor()
		return
	if mode == "levels" and ((event is InputEventKey and event.pressed and event.physical_keycode == KEY_E)
			or (event is InputEventJoypadButton and event.pressed and event.button_index == JOY_BUTTON_X)):
		edit_from_levels(sel)
		return
	if event is InputEventMouseMotion or event is InputEventMouseButton or event is InputEventScreenTouch:
		_pointer(event)
		return
	for a in ["ui_up", "ui_down", "ui_left", "ui_right", "ui_accept", "ui_cancel"]:
		if event.is_action_pressed(a, true):
			ui(a)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo:
		_key_shortcut(event)


func _key_shortcut(e: InputEventKey) -> void:
	if mode == "first" or mode == "credits":
		ui("ui_accept")
	elif mode == "confirm":
		var c := char(e.unicode).to_lower() if e.unicode > 0 else ""
		if c == "y" or c == "t":
			_confirm(true)
		else:
			_confirm(false)


func _pointer(event: InputEvent) -> void:
	var pos: Vector2 = event.position
	var p := to_text_coords(pos)
	var hit := -1
	for i in rows.size():
		if rows[i] is Rect2i and Rect2(rows[i]).has_point(p):
			hit = i
	if event is InputEventMouseMotion:
		if hit >= 0 and hit != sel and _enabled(hit):
			sel = hit
			draw_ui()
		return
	var pressed: bool = event.pressed
	if not pressed:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		ui("ui_cancel")
		return
	if mode in ["first", "credits"] and hit < 0:
		ui("ui_accept")
		return
	if mode == "confirm":
		_confirm(hit == 0)
		return
	if hit >= 0 and _enabled(hit):
		sel = hit
		ui("ui_accept")


func _enabled(i: int) -> bool:
	return i < items.size() and items[i].get("enabled", true)


func ui(a: String) -> void:
	"""menu navigation: the same for keyboard, gamepad, mouse and touch"""
	match mode:
		"confirm":
			if a == "ui_accept":
				_confirm(sel == 0)
			elif a == "ui_cancel":
				_confirm(false)
			elif a in ["ui_left", "ui_right", "ui_up", "ui_down"]:
				sel = 1 - sel
				draw_ui()
			return
		"levels":
			_levels_ui(a)
			return
		"credits":
			if a in ["ui_accept", "ui_cancel"]:
				_back()
			return
	if items.is_empty():
		return
	match a:
		"ui_up", "ui_down":
			var step := -1 if a == "ui_up" else 1
			var n := items.size()
			for k in n:
				sel = (sel + step + n) % n
				if _enabled(sel):
					break
			audio.play("key")
		"ui_left", "ui_right":
			var it: Dictionary = items[sel]
			var fn = it.get("left" if a == "ui_left" else "right")
			if fn is Callable:
				fn.call()
				audio.play("key")
			elif mode == "title":
				sel = (sel + (4 if a == "ui_right" else -4) + items.size()) % items.size()
				if not _enabled(sel):
					sel = 0
		"ui_accept":
			var fn = items[sel].get("act")
			if fn is Callable and _enabled(sel):
				audio.play("key")
				fn.call()
				return
		"ui_cancel":
			_back()
			return
	draw_ui()


func _back() -> void:
	match mode:
		"title":
			open_quit()
		"pause":
			resume()
		"options", "controls", "player", "credits", "levels":
			save_all()
			if back_to == "pause":
				open_pause()
			else:
				open_title()
		"first":
			ui("ui_accept")
		"editor_menu":
			open_editor()
		_:
			open_title()


# screens ---------------------------------------------------------------------------------------
func set_menu(new_mode: String, new_items: Array, new_sel := 0) -> void:
	mode = new_mode
	items = new_items
	sel = clampi(new_sel, 0, maxi(items.size() - 1, 0))
	if not _enabled(sel):
		for i in items.size():
			if _enabled(i):
				sel = i
				break
	draw_ui()


func open_first() -> void:
	set_menu("first", [
		{"label": "polski", "act": func(): _choose_language("pl")},
		{"label": "english", "act": func(): _choose_language("en")},
	], 0 if settings.get_value("language") == "pl" else 1)


func _choose_language(l: String) -> void:
	settings.set_value("language", l)
	apply_settings()
	settings.save_file()
	open_title()


func open_title(new_sel := 0) -> void:
	audio.play_music(true)
	palette.level = 1.0
	palette.fade(1.0, 0.01)
	base_mat.set_shader_parameter("dim", 1.0)
	var its := []
	for k in TITLE_ITEMS:
		var it := {"id": k, "label": t(k)}
		match k:
			"new": it["act"] = _new_game
			"continue":
				it["act"] = func(): start_game(progress.level(set_id))
				it["enabled"] = progress.started(set_id)
			"levels": it["act"] = func(): open_levels("title")
			"editor": it["act"] = func(): open_editor()
			"player": it["act"] = open_player
			"options": it["act"] = func(): open_options("title")
			"controls": it["act"] = func(): open_controls("title")
			"credits": it["act"] = open_credits
			"quit": it["act"] = open_quit
		its.append(it)
	set_menu("title", its, new_sel if new_sel else (1 if progress.started(set_id) else 0))


func _new_game() -> void:
	if progress.started(set_id):
		open_confirm(t("new_q"), _new_game_yes, func(): open_title(0))
	else:
		start_game(0)


func _new_game_yes() -> void:
	progress.reset_progress(set_id)
	progress.save_file()
	start_game(0)


func open_quit() -> void:
	if OS.has_feature("web"):
		mode = "bye"
		items = []
		draw_ui()
		return
	open_confirm(t("quit_q"), func(): get_tree().quit(), func(): open_title(TITLE_ITEMS.find("quit")))


func open_confirm(question: String, yes: Callable, no: Callable) -> void:
	confirm_text = question
	confirm_yes = yes
	confirm_no = no
	mode = "confirm"
	items = [{"label": t("yes")}, {"label": t("no")}]
	sel = 1
	draw_ui()


func _confirm(yes: bool) -> void:
	if yes:
		confirm_yes.call()
	else:
		confirm_no.call()


func open_pause() -> void:
	audio.music_player.stream_paused = true
	if testing:
		set_menu("pause", [
			{"label": t("resume"), "act": resume},
			{"label": t("restart"), "act": _pause_restart},
			{"label": t("ed_back"), "act": end_test},
		])
		return
	set_menu("pause", [
		{"label": t("resume"), "act": resume},
		{"label": t("restart"), "act": _pause_restart},
		{"label": t("levels"), "act": func(): open_levels("pause")},
		{"label": t("options"), "act": func(): open_options("pause")},
		{"label": t("controls"), "act": func(): open_controls("pause")},
		{"label": t("to_menu"), "act": _pause_to_menu},
	])


func _pause_restart() -> void:
	resume()
	latched["restart"] = true


func _pause_to_menu() -> void:
	save_all()
	open_title()


func resume() -> void:
	mode = "play"
	audio.music_player.stream_paused = false
	audio.play_music()
	base_mat.set_shader_parameter("dim", 1.0)
	text.clear()
	text.update_texture()
	acc = 0.0
	latched.clear()


func open_options(from: String) -> void:
	if mode != "options":
		back_to = from
		page = 0
	var keys: Array = OPTION_PAGES.keys()
	var its := []
	its.append({"label": t(keys[page]), "kind": "tab",
		"left": func(): _option_page(-1), "right": func(): _option_page(1),
		"act": func(): _option_page(1)})
	for k in OPTION_PAGES[keys[page]]:
		var opt: String = k
		its.append({"label": t("o_" + opt), "value": _option_label(opt),
			"left": func(): _change_option(opt, -1), "right": func(): _change_option(opt, 1),
			"act": func(): _change_option(opt, 1),
			"enabled": not (opt in ["music_on", "music", "fx", "overlap"] and not settings.get_value("sound"))
					and not (opt == "fullscreen" and not can_fullscreen())})
	if keys[page] == "page_game":
		its.append({"label": t("o_levels"), "value": _levels_file_label(), "act": pick_levels_file})
		if settings.levels_name != "":
			its.append({"label": t("original_levels"), "act": _options_original_levels})
	if keys[page] == "page_controls":
		its.append({"label": t("open_controls"), "act": func(): open_controls("options")})
	its.append({"label": t("back"), "act": _back})
	set_menu("options", its, sel if mode == "options" else 0)


func _option_page(step: int) -> void:
	page = (page + step + OPTION_PAGES.size()) % OPTION_PAGES.size()
	sel = 0
	open_options(back_to)


func _option_label(k: String) -> String:
	var v = settings.get_value(k)
	if v is bool:
		return t("yes") if v else t("no")
	if v is int or v is float:
		return str(v)
	match k:
		"language":
			return "polski" if v == "pl" else "english"
		"push", "overlap":
			return t("v_" + v)
		"after":
			return t("v_next") if v == "next" else t("v_unsolved")
		"scale":
			return t("v_" + v)
		"colours":
			return t("v_" + v)
	return S.glyph_text(str(v))


func _change_option(k: String, step: int) -> void:
	settings.cycle(k, step)
	apply_settings()
	settings.save_file()
	open_options(back_to)


func open_controls(from: String) -> void:
	if mode != "controls" and mode != "rebind":
		back_to = from if from != "options" else back_to
		page = 0
	var tabs := ["tab_keys", "tab_pad", "tab_touch"]
	var its := [{"label": t(tabs[page]), "kind": "tab",
		"left": func(): _controls_tab(-1), "right": func(): _controls_tab(1),
		"act": func(): _controls_tab(1)}]
	if page == 0 or page == 1:
		var dev := "keys" if page == 0 else "pad"
		for a in Settings.ACTIONS:
			var act: String = a
			var codes: Array = settings.keys.get(act, []) if dev == "keys" else settings.pad.get(act, [])
			var names := []
			for c in codes:
				names.append(Settings.key_name(c) if dev == "keys" else Settings.pad_name(c))
			its.append({"label": t("a_" + act), "value": S.glyph_text("  ".join(names)),
				"act": func(): _start_rebind(act)})
		if page == 1:
			its.append({"label": t("o_gamepad"), "value": _option_label("gamepad"),
				"left": func(): _change_control("gamepad", -1), "right": func(): _change_control("gamepad", 1),
				"act": func(): _change_control("gamepad", 1)})
			its.append({"label": t("deadzone"), "value": _option_label("deadzone"),
				"left": func(): _change_control("deadzone", -1), "right": func(): _change_control("deadzone", 1),
				"act": func(): _change_control("deadzone", 1)})
			its.append({"label": t("vibration"), "value": _option_label("vibration"),
				"left": func(): _change_control("vibration", -1), "right": func(): _change_control("vibration", 1),
				"act": func(): _change_control("vibration", 1)})
		its.append({"label": t("defaults"), "act": func(): open_confirm(t("defaults_q"),
				_controls_defaults, _controls_back)})
	else:
		for k in ["touch", "touch_size", "touch_alpha", "touch_hand"]:
			var opt: String = k
			its.append({"label": t({"touch": "touch_on", "touch_size": "touch_size",
					"touch_alpha": "touch_alpha", "touch_hand": "touch_hand"}[opt]),
				"value": _touch_label(opt),
				"left": func(): _change_control(opt, -1), "right": func(): _change_control(opt, 1),
				"act": func(): _change_control(opt, 1)})
	its.append({"label": t("back"), "act": _back})
	var keep := sel if mode in ["controls", "rebind"] else 0
	set_menu("controls", its, keep)


func _controls_defaults() -> void:
	if page == 0:
		settings.reset_keys()
	else:
		settings.reset_pad()
	apply_settings()
	settings.save_file()
	_controls_back()


func _controls_back() -> void:
	mode = "controls"
	open_controls(back_to)


func _touch_label(k: String) -> String:
	var v = settings.get_value(k)
	match k:
		"touch":
			return {"auto": t("v_auto"), "on": t("yes"), "off": t("no")}[v]
		"touch_size":
			return t("v_" + v)
		"touch_hand":
			return t("v_right_hand") if v == "right" else t("v_left_hand")
	return str(v)


func _controls_tab(step: int) -> void:
	page = (page + step + 3) % 3
	sel = 0
	open_controls(back_to)


func _change_control(k: String, step: int) -> void:
	settings.cycle(k, step)
	apply_settings()
	settings.save_file()
	open_controls(back_to)


func _start_rebind(a: String) -> void:
	rebind_action = a
	mode = "rebind"
	draw_ui()


func _rebind_key(e: InputEventKey) -> void:
	if page != 0:
		return
	if e.physical_keycode == KEY_ESCAPE:
		mode = "controls"
		open_controls(back_to)
		return
	_finish_rebind("keys", e.physical_keycode)


func _rebind_pad(e: InputEventJoypadButton) -> void:
	if page != 1:
		return
	if e.button_index == JOY_BUTTON_B:
		mode = "controls"
		open_controls(back_to)
		return
	_finish_rebind("pad", e.button_index)


func _finish_rebind(dev: String, code: int) -> void:
	var other := settings.bind(dev, rebind_action, code)
	if other != "":
		notice = t("swapped") + " " + t("a_" + other)
		notice_t = 2.0
	apply_settings()
	settings.save_file()
	mode = "controls"
	open_controls(back_to)


func open_levels(from: String) -> void:
	back_to = from
	mode = "levels"
	sel = level if sim != null else progress.level(set_id)
	page = sel / 12
	items = []
	draw_ui()


func _levels_ui(a: String) -> void:
	var n := Data.levels.size()
	match a:
		"ui_left":
			sel = maxi(sel - 1, 0)
		"ui_right":
			sel = mini(sel + 1, n - 1)
		"ui_up":
			sel = maxi(sel - 4, 0)
		"ui_down":
			sel = mini(sel + 4, n - 1)
		"ui_accept":
			start_game(sel)
			return
		"ui_cancel":
			_back()
			return
	page = sel / 12
	audio.play("key")
	draw_ui()


func open_player() -> void:
	var its := []
	for i in 3:
		var idx := i
		var p: Dictionary = progress.players[i]
		var n := 0
		if p["sets"].has(set_id):
			n = p["sets"][set_id]["solved"].size()
		its.append({"label": S.glyph_text(p["name"]), "value": "%d %s" % [n, t("solved")],
			"act": _select_player.bind(idx), "current": i == progress.current})
	its.append({"label": t("rename"), "act": _start_rename})
	its.append({"label": t("reset"), "act": func(): open_confirm(t("defaults_q"), _reset_player, open_player)})
	its.append({"label": t("import_stt"), "act": pick_levels_file})
	its.append({"label": t("back"), "act": _back})
	back_to = "title"
	set_menu("player", its, sel if mode == "player" else progress.current)


func _select_player(i: int) -> void:
	progress.current = i
	progress.save_file()
	open_player()


func _start_rename() -> void:
	edit_target = "player"
	name_edit = progress.player()["name"]
	mode = "rename"
	draw_ui()


func _reset_player() -> void:
	progress.reset_progress(set_id)
	progress.save_file()
	open_player()


func _edit_len() -> int:
	return AUTHOR_LEN if edit_target == "author" else Progress.NAME_LEN


func _rename_input(event: InputEvent) -> void:
	var chars := Progress.NAME_CHARS
	if event is InputEventKey and event.pressed:
		match event.physical_keycode:
			KEY_ENTER, KEY_KP_ENTER:
				_rename_done(true)
				return
			KEY_ESCAPE:
				_rename_done(false)
				return
			KEY_BACKSPACE:
				name_edit = name_edit.left(name_edit.length() - 1)
				draw_ui()
				return
		var c := char(event.unicode) if event.unicode > 0 else ""
		if edit_target == "player":
			c = c.to_lower()
		if c != "" and chars.contains(c.to_lower()) and name_edit.length() < _edit_len():
			name_edit += c
			draw_ui()
		return
	# gamepad / touch: up/down change the last letter, right adds one, left deletes, A accepts
	if event.is_action_pressed("ui_accept"):
		_rename_done(true)
	elif event.is_action_pressed("ui_cancel"):
		_rename_done(false)
	elif event.is_action_pressed("ui_up", true) or event.is_action_pressed("ui_down", true):
		if name_edit == "":
			name_edit = "a"
		var last := name_edit[name_edit.length() - 1]
		var i := chars.find(last)
		i = (i + (1 if event.is_action_pressed("ui_down", true) else -1) + chars.length()) % chars.length()
		name_edit = name_edit.left(name_edit.length() - 1) + chars[i]
		draw_ui()
	elif event.is_action_pressed("ui_right", true) and name_edit.length() < _edit_len():
		name_edit += "a"
		draw_ui()
	elif event.is_action_pressed("ui_left", true):
		name_edit = name_edit.left(name_edit.length() - 1)
		draw_ui()
	elif event is InputEventScreenTouch and event.pressed:
		_rename_done(true)


func _rename_done(ok: bool) -> void:
	if edit_target == "author":
		if ok:
			ed.set_author(ed_i, name_edit.strip_edges())
			_editor_save_work()
		open_editor_menu(7)
		return
	if ok:
		progress.rename(name_edit)
		progress.save_file()
	mode = "player"
	open_player()


func open_credits() -> void:
	mode = "credits"
	items = []
	credits_t = 0.0
	draw_ui()


# drawing the menu screens ------------------------------------------------------------------
func draw_ui() -> void:
	text.clear()
	rows = []
	match mode:
		"first":
			_draw_base_logo(56)
			text.text_centered(t("press_key"), 40, TextLayer.BLUE)
			for i in items.size():
				_row(i, (640 - 160) / 2, 64 + i * 14, 160, false)
			if _portrait():
				text.text_centered(t("turn_phone"), 380, TextLayer.GREEN)
		"title":
			_draw_title_base()
			for i in items.size():
				var col := i / 5
				_row(i, 32 + col * 304, 4 + (i % 5) * 15, 288, false)
		"pause":
			base_mat.set_shader_parameter("dim", 0.35)
			_panel(t("paused"))
		"confirm":
			text.fill(Rect2i(0, 150, 640, 70), 0)
			text.text_centered(confirm_text, 160, TextLayer.YELLOW)
			for i in 2:
				_row(i, 200 + i * 140, 190, 100, false)
		"options":
			_clear_base()
			_draw_list(t("options"))
		"controls", "rebind":
			_clear_base()
			_draw_list(t("controls"))
			if mode == "rebind":
				text.fill(Rect2i(0, 170, 640, 50), 0)
				text.text_centered(t("press_new") + " " + t("a_" + rebind_action), 180, TextLayer.YELLOW)
				text.text_centered(t("esc_cancel"), 196, TextLayer.BLUE)
		"player":
			_clear_base()
			_draw_list(t("players"))
		"rename":
			_clear_base()
			text.text_centered(t("author") if edit_target == "author" else t("rename"), 120, TextLayer.YELLOW)
			text.text_centered(S.glyph_text(name_edit) + "I", 160, TextLayer.GREEN)
		"levels":
			_clear_base()
			_draw_levels()
		"credits":
			_clear_base()
			_draw_credits()
		"editor":
			_draw_editor()
		"editor_menu":
			_draw_editor_level()
			base_mat.set_shader_parameter("dim", 0.35)
			_panel(t("editor"), 80, 480)
		"editor_help":
			_clear_base()
			_draw_editor_help()
		"bye":
			_clear_base()
			text.text_centered(t("quit_web"), 196, TextLayer.YELLOW)
	if notice != "" and notice_t > 0.0:
		var lines := _wrap(notice, 40)
		var y := 392 - lines.size() * 12
		text.fill(Rect2i(0, y - 2, 640, 400 - y + 2), 0)
		for line in lines:
			text.text_centered(line, y, TextLayer.YELLOW)
			y += 12
	text.update_texture()


func _row(i: int, x: int, y: int, w: int, with_value := true) -> void:
	var it: Dictionary = items[i]
	var enabled := _enabled(i)
	var colour := TextLayer.YELLOW if i == sel else (TextLayer.GREEN if enabled else TextLayer.BLUE)
	if not enabled and i != sel:
		colour = TextLayer.BLUE
	var label: String = it["label"]
	if it.get("current", false):
		label = label + " :"
	text.text(label, x, y, colour)
	if with_value and it.has("value"):
		text.text(it["value"], x + 320, y, TextLayer.YELLOW if i == sel else TextLayer.BLUE)
	rows.append(Rect2i(x - 8, y - 3, w, 14))


func _draw_list(title: String) -> void:
	text.text_centered(title, 12, TextLayer.YELLOW)
	var y := 40
	for i in items.size():
		var it: Dictionary = items[i]
		if it.get("kind", "") == "tab":
			text.text_centered(it["label"], y, TextLayer.YELLOW if i == sel else TextLayer.GREEN)
			rows.append(Rect2i(0, y - 3, 640, 14))
			y += 24
			continue
		_row(i, 40, y, 560)
		y += 15 if items.size() < 18 else 13


func _panel(title: String, x := 160, w := 320) -> void:
	var h := items.size() * 15 + 40
	var top := (400 - h) / 2
	text.fill(Rect2i(x, top, w, h), 0)
	text.frame(Rect2i(x, top, w, h), 162)
	text.text_centered(title, top + 10, TextLayer.YELLOW)
	for i in items.size():
		_row(i, x + 40, top + 30 + i * 15, w - 80, false)


func _draw_levels() -> void:
	var n := Data.levels.size()
	var pages := (n + 11) / 12
	text.text_centered("%s %d %s %d  %d %s" % [t("levels"), page + 1, ":", pages,
			progress.solved(set_id).size(), t("solved")], 4, TextLayer.YELLOW)
	for k in 12:
		var i := page * 12 + k
		if i >= n:
			break
		var x := 0 + (k % 4) * 160
		var y := 22 + (k / 4) * 124
		var s := Sim.new(Data.levels[i]["rows"], i, Rand.new(1))
		text.mini_level(s, x, y + 12)
		text.text("%d" % (i + 1), x + 4, y, TextLayer.YELLOW if i == sel else TextLayer.GREEN)
		if progress.is_solved(set_id, i):
			text.glyph(screen.glyph_index(")"), 2, x + 52, y, false)      # the original's mark
		var hearts := str(s.hearts_total)
		text.glyph(screen.glyph_index("("), 0, x + 156 - 16 * (hearts.length() + 1), y, false)
		text.text(hearts, x + 156 - 16 * hearts.length(), y, TextLayer.BLUE)
		if i == sel:
			text.frame(Rect2i(x, y + 11, 160, 98), 195)
			text.frame(Rect2i(x + 1, y + 12, 158, 96), 195)
		rows.append(Rect2i(x, y, 160, 110))
	var author: String = Data.levels[sel]["author"]
	text.text_centered(S.glyph_text(t("author") + " " + author), 388, TextLayer.BLUE)


func _draw_credits() -> void:
	var y := 8
	for line in [["credits_title", 0], ["", 0], ["c_original", 1], ["c_prog", 2], ["c_pelc", 0],
			["c_support", 2], ["c_support_names", 1], ["c_support_names2", 1], ["c_levels", 2],
			["c_level_names1", 1], ["c_level_names2", 1], ["c_level_names3", 1], ["", 0],
			["c_pub", 2], ["c_pub2", 2], ["c_cc", 2], ["c_licence", 1], ["", 0], ["c_remake", 0],
			["c_remake2", 1]]:
		if line[0] != "":
			text.text_centered(t(line[0]), y, line[1])
		y += 15 if line[0] != "" else 8
	_draw_base_logo(-200)


func _clear_base() -> void:
	screen.clear()
	screen.update_texture()
	base_mat.set_shader_parameter("dim", 1.0)


func _draw_base_logo(y: int) -> void:
	screen.clear()
	if y > -120:
		screen.picture(screen.logo, 64, y)
	screen.update_texture()


func _draw_title_base() -> void:
	"""the original title screen: bar at y 40, logo at (64, 56), bar at the bottom with the
	current player's name (the credit lines of the original are on the AUTORZY screen)"""
	screen.clear()
	for x in range(0, 320, 16):
		screen.glyph(screen.glyph_index(")"), 0, x, 40)
		screen.glyph(screen.glyph_index(")"), 0, x, 192)
	screen.picture(screen.logo, 64, 56)
	var name := S.glyph_text(progress.player()["name"])
	for i in name.length():
		if name[i] != " ":
			screen.glyph(screen.glyph_index(name[i]), 1, 320 - (name.length() - i) * 16, 192)
	screen.update_texture()


func _portrait() -> bool:
	var s := get_viewport_rect().size
	return s.y > s.x


# the game ------------------------------------------------------------------------------------
func start_game(i: int) -> void:
	mode = "play"
	text.clear()
	text.update_texture()
	base_mat.set_shader_parameter("dim", 1.0)
	audio.play_music()
	icons = ICON_TICKS
	start_level(i)


func start_level(i: int) -> void:
	level = i
	sim = Sim.new(cur_levels()[level]["rows"], level, rand, tick_count)
	acc = 0.0
	play_state = "play"
	overview = settings.get_value("map")
	undo_stack.clear()
	if not testing:
		progress.set_level(set_id, level)
		progress.save_file()
	render()


func cur_levels() -> Array:
	"""the levels being played: the level file's, or the editor's while testing"""
	return ed.levels if testing else Data.levels


func _process(delta: float) -> void:
	palette.update(delta)
	if touch.visible != (touch.wanted() and mode == "play"):
		touch.refresh()
		_layout()
	if panels_on != _panels_wanted():
		_layout_panels()
	if notice_t > 0.0:
		notice_t -= delta
		if notice_t <= 0.0 and mode != "play":
			draw_ui()
	if mode != "play":
		return
	match play_state:
		"play":
			acc += delta
			var n := 0
			while acc >= tick_s and mode == "play" and play_state == "play" and n < 4:
				acc -= tick_s
				n += 1
				game_tick()
			if mode == "play" and play_state == "play" and not screen.moving.is_empty():
				screen.draw_moving(acc / tick_s)
				_draw_icons()
				screen.update_texture()
		"fade_out":
			if not palette.busy():
				sim.setup(cur_levels()[level]["rows"])
				undo_stack.clear()
				render()
				palette.fade(1.0, 0.25)
				play_state = "fade_in"
		"fade_in":
			if not palette.busy():
				acc = 0.0
				play_state = "play"
		"slide":
			slide_t += delta
			var off := mini(320, (int(slide_t / RETRACE) + 1) * SLIDE_STEP)
			_compose_slide(off)
			if off >= 320:
				acc = 0.0
				play_state = "play"


func _down(a: String) -> bool:
	return Input.is_action_pressed(a, true) or latched.get(a, false)


func _take(a: String) -> bool:
	var v: bool = latched.get(a, false)
	latched.erase(a)
	return v


func game_tick() -> void:
	if sim == null or mode != "play":
		return
	# keys are latched between ticks (a press between two ticks is never lost)
	if _take("music"):
		settings.set_value("music_on", not settings.get_value("music_on"))
		_option_toggled()
	if _take("sound"):
		settings.set_value("sound", not settings.get_value("sound"))
		_option_toggled()
	if _take("gamepad"):
		settings.set_value("gamepad", not settings.get_value("gamepad"))
		_option_toggled()
	if _take("overview"):
		overview = not overview
	if _take("quit"):
		if testing:
			end_test()
			return
		save_all()
		open_title()
		return
	if _take("undo") and settings.get_value("undo") and not undo_stack.is_empty():
		sim.restore(undo_stack.pop_back())
		latched.clear()
		render()
		return
	var mod := Input.is_action_pressed("level_mod")
	if (mod and _take("left")) or _take("prev_level"):
		change_level(-1)
		return
	if (mod and _take("right")) or _take("next_level"):
		change_level(1)
		return
	# the original's priority when several arrows are held: right > left > down > up
	var d := 0
	if not mod:
		if _down("up"):
			d = -22
		if _down("down"):
			d = 22
		if _down("left"):
			d = -1
		if _down("right"):
			d = 1
	var esc := _take("restart")
	if shot_moves != "":
		var c := shot_moves[shot_tick % shot_moves.length()]
		d = {"L": -1, "R": 1, "U": -22, "D": 22}.get(c, 0)
		esc = c == "E"
	for a in ["left", "right", "up", "down"]:
		latched.erase(a)
	if settings.get_value("undo") and (d != 0 or esc):
		undo_stack.append(sim.snapshot())
		if undo_stack.size() > UNDO_LIMIT:
			undo_stack.pop_front()
	if settings.get_value("push") == "always" and (d == 1 or d == -1):
		sim.tick_count |= 1               # every press pushes (the original: odd ticks only)
	sim.tick(d, esc)
	tick_count = sim.tick_count
	for snd in sim.sounds:
		audio.play(snd)
	if icons > 0:
		icons -= 1
	render()
	_shot_hook()
	if not sim.level_running():
		if sim.game_state == Sim.NEXT_LEVEL and testing:
			end_test()
		elif sim.game_state == Sim.NEXT_LEVEL:
			progress.mark_solved(set_id, level)
			progress.save_file()
			change_level(_next_level_step())
		elif sim.game_state == Sim.PLAYING:       # the dwarf is gone: restart with a fade
			palette.fade(0.0, 0.25)
			play_state = "fade_out"


func _next_level_step() -> int:
	var n := Data.levels.size()
	if settings.get_value("after") == "unsolved":
		for k in range(1, n + 1):
			if not progress.is_solved(set_id, (level + k) % n):
				return k
	return 1


func _option_toggled() -> void:
	apply_settings()
	settings.save_file()
	if settings.get_value("music_on") and settings.get_value("sound"):
		audio.play_music()
	else:
		audio.stop_music()
	audio.play("key")
	icons = ICON_TICKS


func change_level(step: int) -> void:
	if testing:
		return
	slide_from = screen.image.duplicate()
	slide_dir = 1 if step > 0 else -1
	var n := Data.levels.size()
	start_level(((level + step) % n + n) % n)
	slide_t = 0.0
	play_state = "slide"
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


func smooth_on() -> bool:
	return settings.get_value("smooth") and not overview


func render_into_screen() -> void:
	screen.moving.clear()
	if overview:
		screen.draw_overview(sim)
	else:
		screen.draw_level(sim)
		if smooth_on() and play_state == "play":
			screen.collect_moves(sim)
	_draw_icons()
	screen.draw_status(sim.hearts_total, sim.hearts_total - sim.hearts_left, cur_levels().size(),
			progress.solved(set_id).size(), progress.is_solved(set_id, level), level + 1)
	screen.snap_base()


func _draw_icons() -> void:
	if icons > 0:
		screen.draw_icons(settings.get_value("music_on"), settings.get_value("sound"),
				settings.get_value("gamepad"))


func render() -> void:
	render_into_screen()
	if not screen.moving.is_empty():
		screen.draw_moving(0.0)
		_draw_icons()
	screen.update_texture()
	if panels_on:
		draw_panels()


# wide screens: the side panels ----------------------------------------------------------------
func draw_panels() -> void:
	"""left: level number and author; right: hearts, solved levels and the option icons — the
	original's status line and icons, readable beside the picture (plan 3). The panels are on the
	menu layer's pixel grid; the bar at the bottom continues the status line."""
	var bar := screen.glyph_index(")")
	var l: TextLayer = panels[0]
	var r: TextLayer = panels[1]
	var w: int = l.width
	var chars := w / 16
	for p in panels:
		p.fill(Rect2i(0, 0, w, 400), 0)
		for x in range(0, w, 32):
			p.glyph2x(bar, 0, x if p == r else w - 32 - x, 384)
	l.text_centered(t("level"), 24, TextLayer.GREEN)
	_big_centered(l, str(level + 1), 40, TextLayer.YELLOW)
	var author: String = cur_levels()[level]["author"]
	if author != "":
		l.text_centered(t("author"), 88, TextLayer.GREEN)
		var y := 104
		for line in _wrap(S.glyph_text(author), chars):
			l.text_centered(line, y, TextLayer.BLUE)
			y += 12
	if settings.levels_name != "":
		var y := 360 - 12 * _wrap(S.glyph_text(settings.levels_name.get_basename()), chars).size()
		for line in _wrap(S.glyph_text(settings.levels_name.get_basename()), chars):
			l.text_centered(line, y, TextLayer.BLUE)
			y += 12
	r.text_centered(t("hearts"), 24, TextLayer.GREEN)
	r.text_centered("%d:%d" % [sim.hearts_total - sim.hearts_left, sim.hearts_total], 40, TextLayer.YELLOW)
	r.glyph2x(screen.glyph_index(")" if progress.is_solved(set_id, level) else "("), 2, (w - 32) / 2, 72)
	r.text_centered("%d:%d" % [progress.solved(set_id).size(), cur_levels().size()], 96, TextLayer.BLUE)
	var on := [settings.get_value("music_on"), settings.get_value("sound"), settings.get_value("gamepad")]
	for i in 3:
		var x := (w - 40) / 2
		var y := 280 + i * 28
		r.glyph2x(screen.glyph_index(" "), 0, x + 8, y + 4)
		r.glyph2x(screen.glyph_index("+" if on[i] else "-"), i, x, y)
	for p in panels:
		p.update_texture()


func _big_centered(layer: TextLayer, s: String, y: int, colour: int) -> void:
	var x := (layer.width - s.length() * 32) / 2
	for i in s.length():
		layer.glyph2x(screen.glyph_index(s[i]), colour, x + i * 32, y)


static func _wrap(s: String, width: int) -> Array:
	"""words to lines of at most `width` characters (longer words are cut)"""
	var lines := []
	var line := ""
	var words := []
	for w in s.split(" ", false):
		while w.length() > width:
			words.append(w.left(width))
			w = w.substr(width)
		words.append(w)
	for w in words:
		if line != "" and line.length() + 1 + w.length() > width:
			lines.append(line)
			line = ""
		line = w if line == "" else line + " " + w
	if line != "":
		lines.append(line)
	return lines


# custom level files ----------------------------------------------------------------------------
func _levels_file_label() -> String:
	return t("v_original") if settings.levels_name == "" else S.glyph_text(settings.levels_name)


func load_levels_file(bytes: PackedByteArray, file_name: String) -> String:
	"""plays the levels of another LEVELS.HL (checked with the original's rules); returns the
	error, or "" when loaded. Progress is kept per file (by its contents)."""
	var text := bytes.get_string_from_ascii()
	var r := Levels.parse(text)
	if r["error"] != "":
		notice = S.glyph_text("%s %d: %s" % [S.get_text("level_error"), r["line"], r["error"]])
		notice_t = 4.0
		if mode != "play":
			draw_ui()
		return r["error"]
	var f := FileAccess.open(CUSTOM_LEVELS, FileAccess.WRITE)
	if f != null:
		f.store_buffer(bytes)
		f.close()
	settings.levels_name = file_name.get_file()
	settings.save_file()
	_use_levels(text)
	return ""


func use_original_levels() -> void:
	settings.levels_name = ""
	settings.save_file()
	if FileAccess.file_exists(CUSTOM_LEVELS):
		DirAccess.remove_absolute(CUSTOM_LEVELS)
	_use_levels(FileAccess.get_file_as_string("res://data/LEVELS.HL"))


func _options_original_levels() -> void:
	use_original_levels()
	open_options(back_to)


func _use_levels(text: String) -> void:
	Data.load_levels(text)
	set_id = Progress.set_id_of(Data.levels_text)
	sim = null                          # a game in progress (pause menu) ends here
	if mode != "boot":
		open_levels("title")


func _load_saved_levels() -> void:
	if settings.levels_name == "" or not FileAccess.file_exists(CUSTOM_LEVELS):
		settings.levels_name = ""
		return
	var text := FileAccess.get_file_as_bytes(CUSTOM_LEVELS).get_string_from_ascii()
	if Levels.parse(text)["error"] != "":
		settings.levels_name = ""
		return
	Data.load_levels(text)
	set_id = Progress.set_id_of(Data.levels_text)


func pick_levels_file() -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.eval("window.hlPickFile && window.hlPickFile()", true)
	elif DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show("LEVELS.HL", OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS), "",
				false, DisplayServer.FILE_DIALOG_MODE_OPEN_FILE, PackedStringArray(["*.hl, *.HL, *.stt, *.STT", "*"]),
				_file_chosen)
	else:
		var d := FileDialog.new()
		d.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		d.access = FileDialog.ACCESS_FILESYSTEM
		d.filters = PackedStringArray(["*.hl, *.HL, *.stt, *.STT"])
		d.file_selected.connect(func(path): _file_chosen(true, PackedStringArray([path]), 0))
		add_child(d)
		d.popup_centered_ratio(0.8)


func _file_chosen(ok: bool, paths: PackedStringArray, _filter: int) -> void:
	if ok and paths.size() > 0:
		_got_file(FileAccess.get_file_as_bytes(paths[0]), paths[0])


func _files_dropped(files: PackedStringArray) -> void:
	if files.size() > 0:
		_got_file(FileAccess.get_file_as_bytes(files[0]), files[0])


func _got_file(bytes: PackedByteArray, file_name: String) -> void:
	"""a chosen or dropped file: an original PLAYER?.STT is imported, a level file goes into the
	editor when it is open, else it is played"""
	if file_name.to_lower().ends_with(".stt"):
		import_player_file(bytes)
	elif mode in ["editor", "editor_menu", "editor_help"]:
		editor_load_file(bytes, file_name)
	elif mode != "play":
		load_levels_file(bytes, file_name)


func import_player_file(bytes: PackedByteArray) -> bool:
	var ok := progress.import_stt(bytes, set_id, Data.levels.size())
	if ok:
		progress.save_file()
	notice = t("stt_done") if ok else t("stt_bad")
	notice_t = 3.0
	if mode == "player":
		open_player()
	elif mode != "play":
		draw_ui()
	return ok


func _web_setup() -> void:
	"""web: a file picker and drag-and-drop of a LEVELS.HL on the page"""
	if not OS.has_feature("web"):
		return
	_js_file_cb = JavaScriptBridge.create_callback(_web_file)
	JavaScriptBridge.get_interface("window").hlFileCallback = _js_file_cb
	JavaScriptBridge.eval("""
		window.hlSendFile = function (f) {
			f.arrayBuffer().then(function (b) {
				var a = new Uint8Array(b), s = '';
				for (var i = 0; i < a.length; i++) s += String.fromCharCode(a[i]);
				window.hlFileCallback(f.name, btoa(s));
			});
		};
		window.hlPickFile = function () {
			var i = document.createElement('input');
			i.type = 'file';
			i.accept = '.hl,.HL,.txt,.stt,.STT';
			i.onchange = function () { if (i.files.length) window.hlSendFile(i.files[0]); };
			i.click();
		};
		document.addEventListener('dragover', function (e) { e.preventDefault(); });
		document.addEventListener('drop', function (e) {
			e.preventDefault();
			if (e.dataTransfer.files.length) window.hlSendFile(e.dataTransfer.files[0]);
		});
	""", true)


func _web_file(args: Array) -> void:
	_got_file(Marshalls.base64_to_raw(str(args[1])), str(args[0]))


# level editor (plan 5) -------------------------------------------------------------------------
## The level on the screen with a cursor; the bottom line holds the 13 objects (the original's
## 8x8 sprites) and the level number. Keyboard: arrows move, Space paints, the file's own
## characters ($ @ . * ! & 0 = # % < >) choose and paint, Delete clears, Q/E/Tab change the
## object, Z undoes, PgUp/PgDn change the level, T tests, F1 help, Esc menu. Mouse and touch:
## paint by dragging, right button picks the object under it, tap the objects or "menu" below.
## Gamepad: A paints, LB/RB object, Y tests, X picks, Start/B menu.
func open_editor(at := -1) -> void:
	if ed == null:
		_editor_load()
	if at >= 0:
		ed_i = clampi(at, 0, ed.levels.size() - 1)
	ed_i = clampi(ed_i, 0, ed.levels.size() - 1)
	if ed_slots.is_empty():
		for c in LevelSet.CHARS:
			ed_slots.append(Sim.new([c], 0, Rand.new(1)).sprite(0, 0))
	testing = false
	sim = null
	ed_stroke = false
	mode = "editor"
	items = []
	audio.stop_music()
	palette.level = 1.0
	palette.fade(1.0, 0.01)
	base_mat.set_shader_parameter("dim", 1.0)
	draw_ui()


func _editor_load() -> void:
	ed = null
	if FileAccess.file_exists(EDITOR_FILE):
		var d = JSON.parse_string(FileAccess.get_file_as_string(EDITOR_FILE))
		if d is Dictionary and d.get("levels") is Array and not d["levels"].is_empty():
			ed = LevelSet.new()
			for l in d["levels"]:
				var rows := []
				for y in 12:
					var r: String = str(l["rows"][y]) if l.get("rows") is Array and y < l["rows"].size() else ""
					rows.append(r.left(20).rpad(20))
				ed.levels.append({"rows": rows, "author": str(l.get("author", ""))})
			ed.header = str(d.get("header", ""))
			ed_name = str(d.get("name", "LEVELS.HL"))
			ed_i = int(d.get("level", 0))
	if ed == null:
		_editor_from_game()


func _editor_from_game() -> void:
	var original := FileAccess.get_file_as_string("res://data/LEVELS.HL")
	ed = LevelSet.from_text(Data.levels_text, LevelSet.header_of(original))
	ed_name = settings.levels_name if settings.levels_name != "" else "LEVELS.HL"
	ed_i = 0
	_editor_save_work()


func _editor_save_work() -> void:
	var f := FileAccess.open(EDITOR_FILE, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"name": ed_name, "level": ed_i, "header": ed.header,
				"levels": ed.levels}))
		f.close()


func edit_from_levels(i: int) -> void:
	"""level select: E / gamepad X opens the level in the editor"""
	if ed == null:
		_editor_load()
	var same: bool = ed.to_text() == LevelSet.from_text(Data.levels_text, ed.header).to_text()
	if same:
		open_editor(i)
	else:
		open_confirm(t("ed_replace_q"), func(): _editor_from_game(); open_editor(i),
				func(): open_levels(back_to))


func _draw_editor_level() -> void:
	screen.draw_level(Sim.new(ed.levels[ed_i]["rows"], ed_i, Rand.new(1)))
	screen.clear(Rect2i(0, 192, 320, 8))
	for k in ed_slots.size():
		screen.mini_sprite(ed_slots[k], 2 + k * 10, 192)
	screen.update_texture()


func _draw_editor() -> void:
	_draw_editor_level()
	var c := Rect2i(ed_cur * 32, Vector2i(32, 32))
	text.frame(c, 195)
	text.frame(c.grow(-1), 0)
	text.frame(Rect2i(4, 384, 16, 16), 162)        # the empty brush
	text.frame(Rect2i(4 + ed_brush * 20 - 2, 382, 20, 18), 195)
	text.text("%d:%d" % [ed_i + 1, ed.levels.size()], 290, 388, TextLayer.YELLOW)
	var m := t("ed_menu")
	text.text(m, 632 - m.length() * 16, 388, TextLayer.GREEN)


func _draw_editor_help() -> void:
	text.text_centered(t("ed_help"), 12, TextLayer.YELLOW)
	var y := 40
	for k in range(1, 13):
		text.text(t("ed_h%d" % k), 24, y, TextLayer.GREEN if k % 2 else TextLayer.BLUE)
		y += 16 if k % 2 == 0 else 12
	var x := 24
	for k in ed_slots.size():
		var s: int = ed_slots[k]
		text.image.blit_rect_mask(text.minis, text.minis, Rect2i((s % 8) * 8, (s / 8) * 8, 8, 8),
				Vector2i(x + k * 20, 360))


func _editor_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or event is InputEventMouseMotion \
			or event is InputEventScreenTouch or event is InputEventScreenDrag:
		_editor_pointer(event)
		return
	if event is InputEventJoypadButton and event.pressed:
		match event.button_index:
			JOY_BUTTON_A: _ed_paint(ed_cur, LevelSet.CHARS[ed_brush], true)
			JOY_BUTTON_X: ed_brush = LevelSet.CHARS.find(ed.cell(ed_i, ed_cur.x, ed_cur.y))
			JOY_BUTTON_LEFT_SHOULDER: _ed_brush(-1)
			JOY_BUTTON_RIGHT_SHOULDER: _ed_brush(1)
			JOY_BUTTON_Y: editor_test()
			JOY_BUTTON_B, JOY_BUTTON_START: open_editor_menu()
		if mode == "editor" and event.button_index not in [JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN,
				JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT]:
			_editor_save_work()
			draw_ui()
			return
	if event is InputEventKey and event.pressed:
		var c := char(event.unicode) if event.unicode > 0 else ""
		if c != "" and c != " " and LevelSet.CHARS.contains(c):
			ed_brush = LevelSet.CHARS.find(c)
			_ed_paint(ed_cur, c, true)
			ed_cur.x = mini(ed_cur.x + 1, 19)
			_editor_save_work()
			draw_ui()
			return
		var handled := true
		match event.physical_keycode:
			KEY_SPACE, KEY_ENTER, KEY_KP_ENTER:
				_ed_paint(ed_cur, LevelSet.CHARS[ed_brush], true)
			KEY_DELETE:
				_ed_paint(ed_cur, " ", true)
			KEY_TAB:
				_ed_brush(-1 if event.shift_pressed else 1)
			KEY_E:
				_ed_brush(1)
			KEY_Q:
				_ed_brush(-1)
			KEY_Z:
				_ed_undo()
			KEY_PAGEUP:
				_ed_goto(ed_i - 1)
			KEY_PAGEDOWN:
				_ed_goto(ed_i + 1)
			KEY_T, KEY_F5:
				editor_test()
				return
			KEY_F1, KEY_H:
				mode = "editor_help"
				draw_ui()
				return
			KEY_ESCAPE, KEY_BACKSPACE:
				open_editor_menu()
				return
			_:
				handled = false
		if handled:
			_editor_save_work()
			draw_ui()
			return
	for a in ["ui_up", "ui_down", "ui_left", "ui_right"]:
		if event.is_action_pressed(a, true):
			var d: Vector2i = {"ui_up": Vector2i.UP, "ui_down": Vector2i.DOWN, "ui_left": Vector2i.LEFT,
					"ui_right": Vector2i.RIGHT}[a]
			ed_cur = (ed_cur + d).clamp(Vector2i.ZERO, Vector2i(19, 11))
			draw_ui()
			return


func _editor_pointer(event: InputEvent) -> void:
	var p := to_text_coords(event.position)
	var left_down: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
			and event.pressed) or (event is InputEventScreenTouch and event.pressed)
	var left_up: bool = (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT
			and not event.pressed) or (event is InputEventScreenTouch and not event.pressed)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_ed_brush(-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1)
			draw_ui()
			return
	if left_up:
		if ed_stroke:
			ed_stroke = false
			_editor_save_work()
		return
	if p.x < 0 or p.x >= 640 or p.y < 0 or p.y >= 400:
		return
	if p.y >= 384:
		if left_down:
			if p.x < 4 + LevelSet.CHARS.length() * 20:
				ed_brush = clampi(int((p.x - 4) / 20), 0, LevelSet.CHARS.length() - 1)
				audio.play("key")
				draw_ui()
			elif p.x >= 520:
				open_editor_menu()
		return
	var cell := Vector2i(clampi(int(p.x / 32), 0, 19), clampi(int(p.y / 32), 0, 11))
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		ed_brush = LevelSet.CHARS.find(ed.cell(ed_i, cell.x, cell.y))
		ed_cur = cell
		draw_ui()
		return
	if left_down:
		ed_stroke = true
		ed_cur = cell
		_ed_paint(cell, LevelSet.CHARS[ed_brush], true)
		draw_ui()
	elif ed_stroke and (event is InputEventMouseMotion or event is InputEventScreenDrag):
		ed_cur = cell
		_ed_paint(cell, LevelSet.CHARS[ed_brush], false)
		draw_ui()
	elif event is InputEventMouseMotion and cell != ed_cur:
		ed_cur = cell
		draw_ui()


func _ed_paint(cell: Vector2i, ch: String, new_stroke: bool) -> void:
	"""one undo step per stroke (a press and its drag), saved only if something changes"""
	if new_stroke:
		ed_snap = ed.levels.duplicate(true)
		ed_snap_used = false
	if ed.cell(ed_i, cell.x, cell.y) == ch:
		return
	if not ed_snap_used:
		ed.undo_stack.append(ed_snap)
		if ed.undo_stack.size() > LevelSet.UNDO_LIMIT:
			ed.undo_stack.pop_front()
		ed_snap_used = true
	ed.paint(ed_i, cell.x, cell.y, ch)


func _ed_brush(step: int) -> void:
	var n := LevelSet.CHARS.length()
	ed_brush = (ed_brush + step + n) % n


func _ed_undo() -> void:
	if ed.undo():
		ed_i = clampi(ed_i, 0, ed.levels.size() - 1)


func _ed_goto(i: int, in_menu := false) -> void:
	var n: int = ed.levels.size()
	ed_i = (i % n + n) % n
	_editor_save_work()
	if in_menu:
		open_editor_menu(sel)
	else:
		draw_ui()


func open_editor_menu(new_sel := 0) -> void:
	var n: int = ed.levels.size()
	var author: String = ed.levels[ed_i]["author"]
	set_menu("editor_menu", [
		{"label": t("ed_back"), "act": open_editor},
		{"label": t("ed_test"), "act": editor_test},
		{"label": "%s %d:%d" % [t("level"), ed_i + 1, n], "act": func(): _ed_goto(ed_i + 1, true),
			"left": func(): _ed_goto(ed_i - 1, true), "right": func(): _ed_goto(ed_i + 1, true)},
		{"label": t("ed_new"), "act": func(): _ed_add(false), "enabled": n < LevelSet.MAX},
		{"label": t("ed_copy"), "act": func(): _ed_add(true), "enabled": n < LevelSet.MAX},
		{"label": t("ed_move"), "act": func(): _ed_move(1),
			"left": func(): _ed_move(-1), "right": func(): _ed_move(1), "enabled": n > 1},
		{"label": t("ed_delete"), "act": _ed_delete_q, "enabled": n > 1},
		{"label": S.glyph_text(S.get_text("author") + " " + author).left(26), "act": _ed_author},
		{"label": t("a_undo"), "act": func(): _ed_undo(); _editor_save_work(); open_editor_menu(8),
			"enabled": not ed.undo_stack.is_empty()},
		{"label": t("ed_save"), "act": editor_save},
		{"label": t("ed_play"), "act": editor_play_set},
		{"label": t("ed_open"), "act": pick_levels_file},
		{"label": t("ed_from_game"), "act": func(): open_confirm(t("ed_replace_q"),
				func(): _editor_from_game(); open_editor(), func(): open_editor_menu(12))},
		{"label": t("ed_help"), "act": func(): mode = "editor_help"; draw_ui()},
		{"label": t("to_menu"), "act": _editor_quit},
	], new_sel)


func _ed_add(copy: bool) -> void:
	var j: int = ed.add(ed_i, copy)
	if j >= 0:
		ed_i = j
	_editor_save_work()
	open_editor()


func _ed_move(step: int) -> void:
	ed_i = ed.move(ed_i, step)
	_editor_save_work()
	open_editor_menu(5)


func _ed_delete_q() -> void:
	open_confirm(t("ed_delete_q"), func(): ed_i = ed.remove(ed_i); _editor_save_work(); open_editor(),
			func(): open_editor_menu(6))


func _ed_author() -> void:
	edit_target = "author"
	name_edit = ed.levels[ed_i]["author"]
	mode = "rename"
	draw_ui()


func _editor_quit() -> void:
	_editor_save_work()
	open_title(TITLE_ITEMS.find("editor"))


func _ed_problem(r: Dictionary) -> bool:
	"""shows the original's error for the file and goes to the level; true when there is one"""
	if r["error"] == "":
		return false
	if r["level"] >= 0:
		ed_i = r["level"]
	notice = S.glyph_text("%s: %s" % [S.get_text("level_error"), r["error"]])
	notice_t = 4.0
	mode = "editor"
	draw_ui()
	return true


func editor_test() -> void:
	"""plays the level being edited; the end of the level, F10 or the pause menu come back"""
	var one := LevelSet.new()
	one.levels = [ed.levels[ed_i]]
	var r: Dictionary = one.check()
	if r["error"] != "":
		r["error"] = r["error"].replace("#1!", "#%d!" % (ed_i + 1))
		r["level"] = ed_i
	if _ed_problem(r):
		return
	_editor_save_work()
	testing = true
	start_game(ed_i)


func end_test() -> void:
	testing = false
	audio.stop_all()
	open_editor()


func editor_save() -> void:
	"""checks the file with the original's rules, then saves it: desktop a file dialog, web a
	download"""
	if _ed_problem(ed.check()):
		return
	_editor_save_work()
	var bytes: PackedByteArray = ed.to_bytes()
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(bytes, ed_name, "application/octet-stream")
		_ed_saved(ed_name)
	elif DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE):
		DisplayServer.file_dialog_show(t("ed_save"), OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS),
				ed_name, false, DisplayServer.FILE_DIALOG_MODE_SAVE_FILE,
				PackedStringArray(["*.hl, *.HL"]), _ed_save_chosen)
	elif DisplayServer.get_name() != "headless":
		var d := FileDialog.new()
		d.file_mode = FileDialog.FILE_MODE_SAVE_FILE
		d.access = FileDialog.ACCESS_FILESYSTEM
		d.filters = PackedStringArray(["*.hl, *.HL"])
		d.current_file = ed_name
		d.file_selected.connect(func(path): _ed_save_chosen(true, PackedStringArray([path]), 0))
		add_child(d)
		d.popup_centered_ratio(0.8)
	else:
		save_editor_file("user://levels".path_join(ed_name))


func _ed_save_chosen(ok: bool, paths: PackedStringArray, _filter: int) -> void:
	if ok and paths.size() > 0:
		save_editor_file(paths[0])


func save_editor_file(path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		notice = S.glyph_text(path.get_file())
		notice_t = 3.0
		draw_ui()
		return false
	f.store_buffer(ed.to_bytes())
	f.close()
	ed_name = path.get_file()
	_editor_save_work()
	_ed_saved(ed_name)
	return true


func _ed_saved(file_name: String) -> void:
	notice = S.glyph_text(S.get_text("ed_saved") + " " + file_name)
	notice_t = 3.0
	mode = "editor"
	draw_ui()


func editor_play_set() -> void:
	if _ed_problem(ed.check()):
		return
	_editor_save_work()
	load_levels_file(ed.to_bytes(), ed_name)


func editor_load_file(bytes: PackedByteArray, file_name: String) -> void:
	var text := bytes.get_string_from_ascii()
	var r := Levels.parse(text)
	if r["error"] != "":
		notice = S.glyph_text("%s %d: %s" % [S.get_text("level_error"), r["line"], r["error"]])
		notice_t = 4.0
		draw_ui()
		return
	ed = LevelSet.from_text(text)
	ed_name = file_name.get_file()
	ed_i = 0
	_editor_save_work()
	open_editor()


# screenshots ---------------------------------------------------------------------------------
func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(shots_dir.path_join(name + ".png"))


func _screens_tour() -> void:
	"""--shots: every screen once, then a short game"""
	await get_tree().process_frame
	open_first()
	await _shot("01_first")
	open_title()
	await _shot("02_title")
	open_options("title")
	await _shot("03_options")
	open_controls("title")
	await _shot("04_controls")
	open_levels("title")
	await _shot("05_levels")
	open_player()
	await _shot("06_player")
	open_credits()
	await _shot("07_credits")
	open_editor(1)
	ed_cur = Vector2i(6, 4)
	draw_ui()
	await _shot("07_editor")
	open_editor_menu()
	await _shot("07_editor_menu")
	start_game(0)
	await _shot("08_play")
	open_pause()
	await _shot("09_pause")
	resume()
	if shot_moves == "":
		get_tree().quit()


func _shot_hook() -> void:
	if shots_dir == "" or shot_moves == "":
		return
	shot_tick += 1
	if shot_tick in [20, 60]:
		await _shot("10_play_%03d" % shot_tick)
	if shot_tick >= 60:
		get_tree().quit()
