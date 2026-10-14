extends RefCounted
## Borland C++ rand(): s = s * 0x015A4E35 + 1, result (s >> 16) & 0x7FFF (docs 3.13).
## Only used for the start frames of hearts and balloons and the heart-landing sound.

var s := 1


func _init(seed_value := 1) -> void:
	s = seed_value & 0xFFFFFFFF


func next() -> int:
	s = (s * 0x015A4E35 + 1) & 0xFFFFFFFF
	return (s >> 16) & 0x7FFF
