extends RefCounted
## The original's three players (PLAYER1-3.STT, docs 2.11): name, solved levels and current level,
## kept per level file (a hash of its text, so custom LEVELS.HL files have their own progress),
## saved in user://players.json.

const PATH := "user://players.json"
const NAME_CHARS := "abcdefghijklmnopqrstuvwxyz0123456789 "
const NAME_LEN := 12

var players := []
var current := 0


func _init() -> void:
	reset_all()


func reset_all() -> void:
	players = []
	for i in 3:
		players.append({"name": "player%d" % (i + 1), "sets": {}})
	current = 0


func load_file() -> void:
	var t := FileAccess.get_file_as_string(PATH)
	if t == "":
		return
	var d = JSON.parse_string(t)
	if d is Dictionary and d.get("players") is Array and d["players"].size() == 3:
		players = d["players"]
		current = clampi(int(d.get("current", 0)), 0, 2)


func save_file() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"players": players, "current": current}))


func player() -> Dictionary:
	return players[current]


func _entry(set_id: String) -> Dictionary:
	var sets: Dictionary = player()["sets"]
	if not sets.has(set_id):
		sets[set_id] = {"solved": [], "level": 0, "started": false}
	return sets[set_id]


func solved(set_id: String) -> Array:
	return _entry(set_id)["solved"]


func is_solved(set_id: String, level: int) -> bool:
	return _entry(set_id)["solved"].has(level)


func mark_solved(set_id: String, level: int) -> void:
	var s: Array = _entry(set_id)["solved"]
	if not s.has(level):
		s.append(level)
		s.sort()


func level(set_id: String) -> int:
	return int(_entry(set_id)["level"])


func set_level(set_id: String, level_index: int) -> void:
	var s := _entry(set_id)
	s["level"] = level_index
	s["started"] = true


func started(set_id: String) -> bool:
	return bool(_entry(set_id)["started"])


func reset_progress(set_id := "") -> void:
	if set_id == "":
		player()["sets"] = {}
	else:
		player()["sets"].erase(set_id)


func rename(name: String) -> void:
	var n := ""
	for c in name.to_lower():
		if NAME_CHARS.contains(c):
			n += c
	player()["name"] = n.strip_edges().left(NAME_LEN) if n.strip_edges() != "" else player()["name"]


static func set_id_of(text: String) -> String:
	return text.md5_text().left(8)
