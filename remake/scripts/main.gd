extends Node2D
## Placeholder until M2 (the playable core): shows that the data loads.


func _ready() -> void:
	var l := Label.new()
	l.text = "Heartlight: Revibed\n%d levels loaded\n(work in progress: milestone M1)" % Data.levels.size()
	l.position = Vector2(40, 40)
	add_child(l)
