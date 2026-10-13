extends RefCounted
## Options (plan 4.4) and key bindings (4.5), saved in user://settings.cfg (web: browser storage).
## Defaults reproduce the original.

const PATH := "user://settings.cfg"

const OPTIONS := {
	# name: [default, values...]   (values are the stored ones; labels come from strings.gd)
	"language": ["pl", "pl", "en"],
	"push": ["original", "original", "always"],
	"after": ["next", "next", "unsolved"],
	"undo": [false, false, true],
	"speed": [100, 100, 75, 50],
	"scale": ["smooth", "smooth", "sharp"],
	"colours": ["vga", "vga", "mono"],
	"smooth": [false, false, true],
	"wide": [true, true, false],
	"map": [false, false, true],
	"fullscreen": [false, false, true],
	"sound": [true, true, false],
	"music_on": [true, true, false],
	"music": [70, 0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100],
	"fx": [100, 0, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100],
	"overlap": ["original", "original", "always"],
	"gamepad": [true, true, false],
	"deadzone": [25, 10, 15, 20, 25, 30, 35, 40, 45, 50],
	"vibration": [false, false, true],
	"touch": ["auto", "auto", "on", "off"],
	"touch_size": ["medium", "small", "medium", "large"],
	"touch_alpha": [60, 25, 40, 60, 80, 100],
	"touch_hand": ["right", "right", "left"],
}

## game actions that can be rebound; directions, pause and menu actions must keep a binding
const ACTIONS := ["left", "right", "up", "down", "restart", "undo", "prev_level", "next_level",
		"overview", "music", "sound", "gamepad", "pause", "fullscreen"]
const MANDATORY := ["left", "right", "up", "down", "pause"]
const DEFAULT_KEYS := {
	"left": [KEY_LEFT, KEY_A], "right": [KEY_RIGHT, KEY_D], "up": [KEY_UP, KEY_W],
	"down": [KEY_DOWN, KEY_S], "restart": [KEY_ESCAPE, KEY_R], "undo": [KEY_BACKSPACE, KEY_Z],
	"prev_level": [KEY_PAGEUP], "next_level": [KEY_PAGEDOWN], "overview": [KEY_F1, KEY_TAB],
	"music": [KEY_F6], "sound": [KEY_F7], "gamepad": [KEY_F8], "pause": [KEY_P],
	"fullscreen": [KEY_F11],
}
const DEFAULT_PAD := {
	"left": [JOY_BUTTON_DPAD_LEFT], "right": [JOY_BUTTON_DPAD_RIGHT], "up": [JOY_BUTTON_DPAD_UP],
	"down": [JOY_BUTTON_DPAD_DOWN], "restart": [JOY_BUTTON_BACK], "undo": [JOY_BUTTON_LEFT_SHOULDER],
	"prev_level": [], "next_level": [], "overview": [JOY_BUTTON_Y], "music": [], "sound": [],
	"gamepad": [], "pause": [JOY_BUTTON_START], "fullscreen": [],
}

var values := {}
var levels_name := ""   # the loaded LEVELS.HL's file name; "" = the original levels
var keys := {}     # action -> [keycode, keycode]
var pad := {}      # action -> [button, button]


func _init() -> void:
	reset_all()


func reset_all() -> void:
	for k in OPTIONS:
		values[k] = OPTIONS[k][0]
	reset_keys()
	reset_pad()


func reset_keys() -> void:
	keys = DEFAULT_KEYS.duplicate(true)


func reset_pad() -> void:
	pad = DEFAULT_PAD.duplicate(true)


func get_value(k: String):
	return values.get(k, OPTIONS[k][0])


func set_value(k: String, v) -> void:
	values[k] = v


func cycle(k: String, step := 1) -> void:
	var choices: Array = OPTIONS[k].slice(1)
	var i := choices.find(values[k])
	values[k] = choices[(i + step + choices.size()) % choices.size()]


func load_file() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	for k in OPTIONS:
		var v = cf.get_value("options", k, OPTIONS[k][0])
		if OPTIONS[k].slice(1).has(v):
			values[k] = v
	levels_name = str(cf.get_value("levels", "name", ""))
	for a in ACTIONS:      # unknown actions in an old file are ignored (R-C8)
		var kv = cf.get_value("keys", a, null)
		if kv is Array:
			keys[a] = kv.slice(0, 2)
		var pv = cf.get_value("pad", a, null)
		if pv is Array:
			pad[a] = pv.slice(0, 2)


func save_file() -> void:
	var cf := ConfigFile.new()
	for k in values:
		cf.set_value("options", k, values[k])
	cf.set_value("levels", "name", levels_name)
	for a in ACTIONS:
		cf.set_value("keys", a, keys.get(a, []))
		cf.set_value("pad", a, pad.get(a, []))
	cf.save(PATH)


func bind(device: String, action: String, code: int) -> String:
	"""bind `code` to `action` (as its first binding); if another action used it, swap: that
	action gets this action's old first binding (R-C2). Returns the other action's name or ''."""
	var table: Dictionary = keys if device == "keys" else pad
	var old: Array = table.get(action, [])
	var other := ""
	for a in ACTIONS:
		if a != action and table.get(a, []).has(code):
			other = a
			var lst: Array = table[a]
			var j := lst.find(code)
			if old.size() > 0 and not lst.has(old[0]):
				lst[j] = old[0]
			else:
				lst.remove_at(j)
			table[a] = lst
	var mine: Array = old.duplicate()
	mine.erase(code)
	mine.push_front(code)
	table[action] = mine.slice(0, 2)
	return other


func unbound_mandatory() -> Array:
	var out := []
	for a in MANDATORY:
		if keys.get(a, []).is_empty():
			out.append(a)
	return out


func apply_input_map() -> void:
	for a in ACTIONS:
		if InputMap.has_action(a):
			InputMap.erase_action(a)
		InputMap.add_action(a, float(values["deadzone"]) / 100.0)
		for code in keys.get(a, []):
			var ev := InputEventKey.new()
			ev.physical_keycode = code
			InputMap.action_add_event(a, ev)
		if values["gamepad"]:
			for b in pad.get(a, []):
				var ev := InputEventJoypadButton.new()
				ev.button_index = b
				InputMap.action_add_event(a, ev)
	if values["gamepad"]:
		for p in [["left", JOY_AXIS_LEFT_X, -1.0], ["right", JOY_AXIS_LEFT_X, 1.0],
				["up", JOY_AXIS_LEFT_Y, -1.0], ["down", JOY_AXIS_LEFT_Y, 1.0]]:
			var m := InputEventJoypadMotion.new()
			m.axis = p[1]
			m.axis_value = p[2]
			InputMap.action_add_event(p[0], m)
	# menu actions: fixed, so that menus always work (R-C4)
	var menu := {
		"ui_up": [KEY_UP, KEY_W], "ui_down": [KEY_DOWN, KEY_S], "ui_left": [KEY_LEFT, KEY_A],
		"ui_right": [KEY_RIGHT, KEY_D], "ui_accept": [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE],
		"ui_cancel": [KEY_ESCAPE, KEY_BACKSPACE],
	}
	var menu_pad := {
		"ui_up": [JOY_BUTTON_DPAD_UP], "ui_down": [JOY_BUTTON_DPAD_DOWN],
		"ui_left": [JOY_BUTTON_DPAD_LEFT], "ui_right": [JOY_BUTTON_DPAD_RIGHT],
		"ui_accept": [JOY_BUTTON_A], "ui_cancel": [JOY_BUTTON_B],
	}
	for a in menu:
		if InputMap.has_action(a):
			InputMap.erase_action(a)
		InputMap.add_action(a, 0.5)
		for code in menu[a]:
			var ev := InputEventKey.new()
			ev.physical_keycode = code
			InputMap.action_add_event(a, ev)
		for b in menu_pad[a]:
			var ev := InputEventJoypadButton.new()
			ev.button_index = b
			InputMap.action_add_event(a, ev)
	for p in [["ui_left", JOY_AXIS_LEFT_X, -1.0], ["ui_right", JOY_AXIS_LEFT_X, 1.0],
			["ui_up", JOY_AXIS_LEFT_Y, -1.0], ["ui_down", JOY_AXIS_LEFT_Y, 1.0]]:
		var m := InputEventJoypadMotion.new()
		m.axis = p[1]
		m.axis_value = p[2]
		InputMap.action_add_event(p[0], m)
	# Space + left/right changes the level as in the original (not rebindable)
	if InputMap.has_action("level_mod"):
		InputMap.erase_action("level_mod")
	InputMap.add_action("level_mod")
	var sp := InputEventKey.new()
	sp.physical_keycode = KEY_SPACE
	InputMap.action_add_event("level_mod", sp)


static func key_name(code: int) -> String:
	return OS.get_keycode_string(code).to_lower()


const PAD_NAMES := {JOY_BUTTON_A: "a", JOY_BUTTON_B: "b", JOY_BUTTON_X: "x", JOY_BUTTON_Y: "y",
		JOY_BUTTON_BACK: "back", JOY_BUTTON_START: "start", JOY_BUTTON_LEFT_SHOULDER: "lb",
		JOY_BUTTON_RIGHT_SHOULDER: "rb", JOY_BUTTON_DPAD_UP: "dpad up",
		JOY_BUTTON_DPAD_DOWN: "dpad down", JOY_BUTTON_DPAD_LEFT: "dpad left",
		JOY_BUTTON_DPAD_RIGHT: "dpad right", JOY_BUTTON_LEFT_STICK: "ls",
		JOY_BUTTON_RIGHT_STICK: "rs", JOY_BUTTON_GUIDE: "guide"}


static func pad_name(b: int) -> String:
	return PAD_NAMES.get(b, "button %d" % b)
