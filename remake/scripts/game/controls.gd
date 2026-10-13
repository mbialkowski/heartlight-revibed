extends RefCounted
## Actions and default bindings (plan section 6; remapping arrives with the controls screen, M3).
## Input is sampled like the original: a key is "down" for a tick if it is held at the poll or
## was pressed since the previous poll (docs 3.10), so a tap shorter than a tick counts once.

const DEFAULTS := {
	"left": [KEY_LEFT, KEY_A, JOY_BUTTON_DPAD_LEFT],
	"right": [KEY_RIGHT, KEY_D, JOY_BUTTON_DPAD_RIGHT],
	"up": [KEY_UP, KEY_W, JOY_BUTTON_DPAD_UP],
	"down": [KEY_DOWN, KEY_S, JOY_BUTTON_DPAD_DOWN],
	"restart": [KEY_ESCAPE, KEY_R, JOY_BUTTON_BACK],
	"level_mod": [KEY_SPACE],
	"prev_level": [KEY_PAGEUP, JOY_BUTTON_LEFT_SHOULDER],
	"next_level": [KEY_PAGEDOWN, JOY_BUTTON_RIGHT_SHOULDER],
	"overview": [KEY_F1, KEY_TAB, JOY_BUTTON_Y],
	"music": [KEY_F6],
	"sound": [KEY_F7],
	"gamepad": [KEY_F8],
	"quit": [KEY_F10],
	"fullscreen": [KEY_F11],
}
const DIRECTIONS := ["left", "right", "up", "down"]

var latched := {}


static func install() -> void:
	"""codes below 32 are gamepad buttons (JOY_BUTTON_*), the others keys (KEY_*)"""
	for action in DEFAULTS:
		if InputMap.has_action(action):
			InputMap.erase_action(action)
		InputMap.add_action(action, 0.25)
		for code in DEFAULTS[action]:
			var ev: InputEvent
			if code < 32:
				ev = InputEventJoypadButton.new()
				ev.button_index = code
			else:
				ev = InputEventKey.new()
				ev.physical_keycode = code
			InputMap.action_add_event(action, ev)
	for pair in [["left", JOY_AXIS_LEFT_X, -1.0], ["right", JOY_AXIS_LEFT_X, 1.0],
			["up", JOY_AXIS_LEFT_Y, -1.0], ["down", JOY_AXIS_LEFT_Y, 1.0]]:
		var m := InputEventJoypadMotion.new()
		m.axis = pair[1]
		m.axis_value = pair[2]
		InputMap.action_add_event(pair[0], m)


func note(event: InputEvent) -> void:
	"""call from _input: remembers presses until the next tick"""
	for a in DIRECTIONS + ["restart", "prev_level", "next_level"]:
		if event.is_action_pressed(a, false, true):
			latched[a] = true


func down(action: String) -> bool:
	return Input.is_action_pressed(action, true) or latched.get(action, false)


func take(action: String) -> bool:
	"""edge: pressed since the last tick"""
	var v: bool = latched.get(action, false)
	latched.erase(action)
	return v


func direction() -> int:
	"""the original's priority when several arrows are held: right > left > down > up"""
	var d := 0
	if down("up"):
		d = -22
	if down("down"):
		d = 22
	if down("left"):
		d = -1
	if down("right"):
		d = 1
	return d


func end_tick() -> void:
	for a in DIRECTIONS:
		latched.erase(a)
