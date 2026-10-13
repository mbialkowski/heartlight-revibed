extends RefCounted
## A 640x400 layer over the 320x200 screen for menus, in palette indices like the screen and
## drawn with the original's 16x8 font (font.ggs): the same glyph shape at half the size, 40
## characters per line. Transparent where nothing is drawn.

const W := 640
const H := 400
const LINE := 10            # 8-pixel glyphs + 2 pixels of space
const YELLOW := 0
const GREEN := 1
const BLUE := 2

var image: Image
var texture: ImageTexture
var font: Image
var minis: Image
var logo: Image
var font_chars: Dictionary


func _init(screen) -> void:
	font = screen.font
	minis = screen.minis
	logo = screen.logo
	font_chars = screen.font_chars
	image = Image.create(W, H, false, Image.FORMAT_RGBA8)
	clear()
	texture = ImageTexture.create_from_image(image)


func clear() -> void:
	image.fill(Color(0, 0, 0, 0))


func update_texture() -> void:
	texture.update(image)


func fill(r: Rect2i, index := 0) -> void:
	image.fill_rect(r, Color8(index, 0, 0, 255))


func glyph(index: int, row: int, x: int, y: int, opaque := true) -> void:
	if index < 0:
		return
	if opaque:
		image.fill_rect(Rect2i(x, y, 16, 8), Color(0, 0, 0, 1))
	image.blit_rect_mask(font, font, Rect2i((index % 16) * 16, (index / 16) * 24 + row * 8, 16, 8),
			Vector2i(x, y))


func text(s: String, x: int, y: int, colour := GREEN, opaque := false) -> int:
	"""draws text already converted with Strings.glyph_text(); returns the width in pixels"""
	for i in s.length():
		var g := int(font_chars.get(s[i], -1))
		if s[i] == " ":
			if opaque:
				image.fill_rect(Rect2i(x + i * 16, y, 16, 8), Color(0, 0, 0, 1))
			continue
		glyph(g, colour, x + i * 16, y, opaque)
	return s.length() * 16


func text_centered(s: String, y: int, colour := GREEN) -> void:
	text(s, (W - s.length() * 16) / 2, y, colour)


func mini_level(sim, x: int, y: int) -> void:
	"""a level in the 8x8 overview sprites (160x96)"""
	for cy in 12:
		for cx in 20:
			var slot: int = sim.sprite(cx, cy)
			var r := Rect2i(x + cx * 8, y + cy * 8, 8, 8)
			image.fill_rect(r, Color(0, 0, 0, 1))
			image.blit_rect_mask(minis, minis, Rect2i((slot % 8) * 8, (slot / 8) * 8, 8, 8), r.position)


func frame(r: Rect2i, index: int) -> void:
	"""a 1-pixel rectangle outline"""
	fill(Rect2i(r.position.x, r.position.y, r.size.x, 1), index)
	fill(Rect2i(r.position.x, r.end.y - 1, r.size.x, 1), index)
	fill(Rect2i(r.position.x, r.position.y, 1, r.size.y), index)
	fill(Rect2i(r.end.x - 1, r.position.y, 1, r.size.y), index)
