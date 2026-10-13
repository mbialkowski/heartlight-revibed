extends RefCounted
## The level editor's data (plan 5): a list of levels {"rows": 12 strings of 20, "author": ""},
## edited cell by cell with undo, and written as a standard LEVELS.HL that the original game reads
## (the original's legend header, "author:" comments, rows without trailing spaces, CR LF, ^Z).

const Levels = preload("res://scripts/sim/levels.gd")

const CHARS := " $@.*!&0=#%<>"     # the brushes, in the order of the original's legend
const MAX := Levels.MAX_LEVELS - 1  # the original refuses a file once it reaches 199 levels
const UNDO_LIMIT := 300

var levels := []
var undo_stack := []
var header := ""


static func from_text(text: String, p_header := "") -> RefCounted:
	"""a set from a LEVELS.HL text (it must parse without errors)"""
	var s = load("res://scripts/game/level_set.gd").new()
	s.header = p_header if p_header != "" else header_of(text)
	for l in Levels.parse(text)["levels"]:
		s.levels.append({"rows": (l["rows"] as Array).duplicate(), "author": l["author"]})
	if s.levels.is_empty():
		s.levels.append(new_level(""))
	return s


static func header_of(text: String) -> String:
	"""the comment lines before the first level's comments (the original's legend)"""
	var end := text.find("{")
	if end < 0:
		return ""
	var a := text.rfind("author", end)
	if a >= 0:
		end = text.rfind("\n", a) + 1
	var h := text.left(end)
	return h if h.strip_edges() != "" else ""


static func new_level(author: String) -> Dictionary:
	"""a metal frame filled with grass, the dwarf and the door"""
	var rows := []
	for y in 12:
		var r := ""
		for x in 20:
			r += "%" if x == 0 or y == 0 or x == 19 or y == 11 else "."
		rows.append(r)
	rows[1] = rows[1].left(1) + "*" + rows[1].substr(2)
	rows[10] = rows[10].left(18) + "!" + rows[10].substr(19)
	return {"rows": rows, "author": author}


func to_text() -> String:
	var parts := []
	for l in levels:
		var s := ""
		if l["author"] != "":
			s += "author: %s\r\n" % l["author"]
		s += "{\r\n"
		for r in l["rows"]:
			s += (r as String).rstrip(" ") + "\r\n"
		s += "}\r\n"
		parts.append(s)
	return header + "\r\n".join(parts) + "\u001a"


func to_bytes() -> PackedByteArray:
	return to_text().to_ascii_buffer()


func check() -> Dictionary:
	"""the original parser's verdict on the saved file: {"error", "level"} (level 0-based, -1)"""
	var r := Levels.parse(to_text())
	var lv := -1
	if r["error"] != "":
		lv = mini(r["levels"].size(), levels.size() - 1)
	return {"error": r["error"], "level": lv}


func cell(i: int, x: int, y: int) -> String:
	return levels[i]["rows"][y][x]


func save_undo() -> void:
	undo_stack.append(levels.duplicate(true))
	if undo_stack.size() > UNDO_LIMIT:
		undo_stack.pop_front()


func undo() -> bool:
	if undo_stack.is_empty():
		return false
	levels = undo_stack.pop_back()
	return true


func paint(i: int, x: int, y: int, ch: String) -> bool:
	"""sets one cell (no undo step: the caller saves one per stroke); true when it changed"""
	var row: String = levels[i]["rows"][y]
	if row[x] == ch:
		return false
	levels[i]["rows"][y] = row.left(x) + ch + row.substr(x + 1)
	return true


func add(after: int, copy := false) -> int:
	if levels.size() >= MAX:
		return -1
	save_undo()
	var l: Dictionary = levels[after].duplicate(true) if copy else new_level(levels[after]["author"])
	levels.insert(after + 1, l)
	return after + 1


func move(i: int, step: int) -> int:
	var j := i + step
	if j < 0 or j >= levels.size():
		return i
	save_undo()
	var l = levels[i]
	levels.remove_at(i)
	levels.insert(j, l)
	return j


func remove(i: int) -> int:
	if levels.size() <= 1:
		return i
	save_undo()
	levels.remove_at(i)
	return mini(i, levels.size() - 1)


func set_author(i: int, a: String) -> void:
	save_undo()
	levels[i]["author"] = a
