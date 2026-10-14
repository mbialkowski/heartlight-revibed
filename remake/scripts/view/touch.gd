extends Control
## On-screen controls for touch screens (plan 4.5 R-C6, 6): a 4-way pad and buttons for restart
## (the original's Esc), undo (when the option is on), the overview map, previous / next level,
## pause and full screen.
## Multi-touch. Landscape: over the picture's sides; portrait: below the picture. Menus are
## played by tapping their rows (main.gd).

var main
var seen_touch := false
var pad_center := Vector2.ZERO
var pad_r := 80.0
var buttons := []          # {action, center, r}
var touches := {}          # index -> {"kind": "pad"|"button", "action": String}
var pad_dir := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)


func wanted() -> bool:
	if main == null:
		return false
	var s: String = main.settings.get_value("touch")
	return s == "on" or (s == "auto" and (seen_touch or DisplayServer.is_touchscreen_available()))


func refresh() -> void:
	visible = wanted() and main.mode == "play"
	if not visible:
		_release_all()
	relayout()


func relayout() -> void:
	if main == null:
		return
	var win: Vector2 = main.get_viewport_rect().size
	var dr: Rect2 = main.display_rect
	var k: float = {"small": 0.8, "medium": 1.0, "large": 1.25}[main.settings.get_value("touch_size")]
	var left_handed: bool = main.settings.get_value("touch_hand") == "left"
	buttons.clear()
	var r: float
	var cy: float
	if main.portrait:
		var area_top := dr.end.y
		var area_h := win.y - area_top
		r = clampf(minf(win.x * 0.09, area_h * 0.13), 26.0, 80.0) * k
		cy = area_top + area_h * 0.5
		pad_r = r * 2.4
		pad_center = Vector2(win.x * 0.28, cy)
	else:
		r = clampf(win.y * 0.075, 22.0, 70.0) * k
		pad_r = r * 2.3
		pad_center = Vector2(pad_r + r * 0.6, win.y - pad_r - r * 0.6)
		cy = win.y - pad_r - r * 0.6
	var bx := win.x - pad_center.x
	if left_handed:
		var tmp := pad_center.x
		pad_center.x = bx
		bx = tmp
	var d := r * 1.5
	buttons.append({"action": "restart", "center": Vector2(bx + d * 0.6, cy + d * 0.7), "r": r})
	if main.settings.get_value("undo"):
		buttons.append({"action": "undo", "center": Vector2(bx - d * 0.9, cy + d * 0.7), "r": r})
	buttons.append({"action": "overview", "center": Vector2(bx, cy - d * 0.9), "r": r * 0.8})
	var s := r * 0.6
	var top := s * 1.6 if not main.portrait else dr.end.y + s * 1.6   # below the picture upright
	buttons.append({"action": "pause", "center": Vector2(s * 1.6, top), "r": s})
	if main.can_fullscreen() and not main.is_fullscreen():
		buttons.append({"action": "fullscreen", "center": Vector2(win.x - s * 1.6, top), "r": s})
	# previous / next level: upright in the row under the picture, sideways under pause and
	# under full screen
	if main.portrait:
		buttons.append({"action": "prev_level", "center": Vector2(win.x * 0.5 - s * 1.8, top), "r": s})
		buttons.append({"action": "next_level", "center": Vector2(win.x * 0.5 + s * 1.8, top), "r": s})
	else:
		buttons.append({"action": "prev_level", "center": Vector2(s * 1.6, top + s * 3.2), "r": s})
		buttons.append({"action": "next_level", "center": Vector2(win.x - s * 1.6, top + s * 3.2), "r": s})
	queue_redraw()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and not seen_touch:
		seen_touch = true
		refresh()
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			if event.position.distance_to(pad_center) <= pad_r:
				touches[event.index] = {"kind": "pad"}
				_pad(event.position)
				get_viewport().set_input_as_handled()
				return
			for b in buttons:
				if event.position.distance_to(b["center"]) <= b["r"] * 1.15:
					touches[event.index] = {"kind": "button", "action": b["action"]}
					_button(b["action"])
					get_viewport().set_input_as_handled()
					queue_redraw()
					return
		else:
			if touches.has(event.index):
				var t: Dictionary = touches[event.index]
				touches.erase(event.index)
				if t["kind"] == "pad":
					_set_dir("")
				get_viewport().set_input_as_handled()
				queue_redraw()
	elif event is InputEventScreenDrag and touches.has(event.index):
		if touches[event.index]["kind"] == "pad":
			_pad(event.position)
		get_viewport().set_input_as_handled()


func _pad(pos: Vector2) -> void:
	var v := pos - pad_center
	if v.length() < pad_r * 0.18:
		_set_dir("")
		return
	if absf(v.x) > absf(v.y):
		_set_dir("right" if v.x > 0 else "left")
	else:
		_set_dir("down" if v.y > 0 else "up")


func _set_dir(dir: String) -> void:
	if dir == pad_dir:
		return
	if pad_dir != "":
		Input.action_release(pad_dir)
	pad_dir = dir
	if dir != "":
		Input.action_press(dir)
		main.latched[dir] = true
	queue_redraw()


func _button(a: String) -> void:
	match a:
		"pause":
			main.open_pause()
		"fullscreen":
			main.toggle_fullscreen()
		_:
			main.latched[a] = true


func _release_all() -> void:
	_set_dir("")
	touches.clear()


func _draw() -> void:
	if main == null:
		return
	var alpha := float(main.settings.get_value("touch_alpha")) / 100.0
	var fg := Color(1, 1, 1, 0.85 * alpha)
	var bg := Color(0.1, 0.1, 0.1, 0.45 * alpha)
	draw_circle(pad_center, pad_r, bg)
	draw_arc(pad_center, pad_r, 0, TAU, 48, fg, 2.0)
	for dir in [["up", Vector2(0, -1)], ["down", Vector2(0, 1)], ["left", Vector2(-1, 0)],
			["right", Vector2(1, 0)]]:
		var v: Vector2 = dir[1]
		var c := pad_center + v * pad_r * 0.62
		var w := pad_r * 0.2
		var p := PackedVector2Array([c + v * w, c - v * w * 0.6 + v.orthogonal() * w,
				c - v * w * 0.6 - v.orthogonal() * w])
		draw_colored_polygon(p, Color(1, 0.85, 0.3, alpha) if pad_dir == dir[0] else fg)
	for b in buttons:
		var c: Vector2 = b["center"]
		var r: float = b["r"]
		var held := false
		for t in touches.values():
			if t.get("action", "") == b["action"]:
				held = true
		draw_circle(c, r, Color(0.5, 0.4, 0.1, 0.6 * alpha) if held else bg)
		draw_arc(c, r, 0, TAU, 32, fg, 2.0)
		_icon(b["action"], c, r * 0.5, fg)


func _icon(a: String, c: Vector2, s: float, col: Color) -> void:
	match a:
		"restart":
			draw_arc(c, s, -PI * 0.25, PI * 1.5, 24, col, 3.0)
			draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.71, -s * 0.71) + Vector2(-s * 0.5, -s * 0.2),
					c + Vector2(s * 0.71, -s * 0.71) + Vector2(s * 0.45, -s * 0.35),
					c + Vector2(s * 0.71, -s * 0.71) + Vector2(s * 0.2, s * 0.45)]), col)
		"undo":
			draw_arc(c + Vector2(0, s * 0.2), s * 0.8, PI * 1.1, PI * 2.1, 20, col, 3.0)
			draw_colored_polygon(PackedVector2Array([c + Vector2(-s, -s * 0.1), c + Vector2(-s * 0.2, -s * 0.5),
					c + Vector2(-s * 0.4, s * 0.4)]), col)
		"overview":
			for i in 3:
				draw_line(c + Vector2(-s, -s + i * s), c + Vector2(s, -s + i * s), col, 2.0)
				draw_line(c + Vector2(-s + i * s, -s), c + Vector2(-s + i * s, s), col, 2.0)
		"pause":
			draw_rect(Rect2(c + Vector2(-s * 0.7, -s * 0.8), Vector2(s * 0.45, s * 1.6)), col)
			draw_rect(Rect2(c + Vector2(s * 0.25, -s * 0.8), Vector2(s * 0.45, s * 1.6)), col)
		"prev_level", "next_level":
			var d := -1.0 if a == "prev_level" else 1.0      # a triangle and a bar: |< or >|
			draw_colored_polygon(PackedVector2Array([c + Vector2(d * s * 0.5, 0),
					c + Vector2(-d * s * 0.5, -s * 0.6), c + Vector2(-d * s * 0.5, s * 0.6)]), col)
			draw_rect(Rect2(c + Vector2(s * 0.5 if d > 0 else -s * 0.7, -s * 0.6), Vector2(s * 0.2, s * 1.2)), col)
		"fullscreen":
			for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
				var p: Vector2 = c + corner * s * 0.8
				draw_line(p, p - Vector2(corner.x * s * 0.6, 0), col, 3.0)
				draw_line(p, p - Vector2(0, corner.y * s * 0.6), col, 3.0)
