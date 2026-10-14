extends RefCounted
## LEVELS.HL reader with the original parser's rules (HL.EXE 1914:0004; docs 2.9), the same as
## tools/hl_levels.py. parse() returns {"levels": [{"rows": [12 x 20 chars], "author": ""}],
## "error": ""}; on an error the message is the original's ("Not enough lines in level #3!").

const CHARS := " $@.*!&0=#%<>"
const MAX_LEVELS := 199


static func parse(text: String) -> Dictionary:
	var levels := []
	var comments := []
	var block = null
	var lineno := 0
	for raw in text.replace("\u001a", "").split("\n"):
		lineno += 1
		var line: String = raw.trim_suffix("\r").left(20)
		if block == null:
			if line.begins_with("{"):
				block = []
			elif raw.strip_edges() != "":
				comments.append(raw.trim_suffix("\r"))
			continue
		if line.begins_with("}"):
			var n := levels.size() + 1
			if block.size() < 12:
				return _err(levels, "Not enough lines in level #%d!" % n, lineno)
			if not _has(block, "*"):
				return _err(levels, "No hero on level #%d!" % n, lineno)
			if not _has(block, "!"):
				return _err(levels, "No exit on level #%d!" % n, lineno)
			levels.append({"rows": block, "author": _author(comments)})
			if levels.size() >= MAX_LEVELS:
				return _err(levels, "Too many levels defined (max=%d)!" % MAX_LEVELS, lineno)
			block = null
			comments = []
			continue
		if block.size() == 12:
			return _err(levels, "Too many lines in level #%d!" % (levels.size() + 1), lineno)
		for c in line:
			if not CHARS.contains(c):
				return _err(levels, "Invalid object on level #%d!" % (levels.size() + 1), lineno)
		block.append(line.rpad(20))
	if levels.is_empty():
		return _err(levels, "No levels in file!", lineno)
	return {"levels": levels, "error": "", "line": 0}


static func _err(levels: Array, msg: String, line: int) -> Dictionary:
	return {"levels": levels, "error": msg, "line": line}


static func _has(block: Array, ch: String) -> bool:
	for r in block:
		if r.contains(ch):
			return true
	return false


static func _author(comments: Array) -> String:
	for c in comments:
		var s: String = c.strip_edges()
		if s.begins_with("author"):
			var i := s.find(":")
			if i >= 0:
				return s.substr(i + 1).strip_edges()
	return ""
