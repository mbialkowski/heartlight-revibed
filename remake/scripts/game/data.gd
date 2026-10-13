extends Node
## Loads the generated data bundle (res://data, made by tools/build_remake_data.py).

const Levels = preload("res://scripts/sim/levels.gd")

var game: Dictionary = {}
var palette: Array = []
var palette_mono: Array = []
var levels: Array = []          # [{"rows": [...], "author": ""}]
var level_error := ""
var levels_text := ""


func _ready() -> void:
	load_all()


func load_all() -> void:
	game = JSON.parse_string(FileAccess.get_file_as_string("res://data/game.json"))
	var pal = JSON.parse_string(FileAccess.get_file_as_string("res://data/palette.json"))
	palette = pal["game"]
	palette_mono = pal["mono"]
	load_levels(FileAccess.get_file_as_string("res://data/LEVELS.HL"))


func load_levels(text: String) -> bool:
	var r := Levels.parse(text)
	if not r["levels"].is_empty() and r["error"] == "":
		levels_text = text
	level_error = r["error"]
	if r["levels"].is_empty():
		return false
	levels = r["levels"]
	return level_error == ""
