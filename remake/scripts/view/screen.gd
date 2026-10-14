extends RefCounted
## The 320x200 screen in VGA palette indices (red channel; see palette.gdshader), drawn like the
## original's DrawFrame (1633:11D8): every cell from g_spriteBase[type] + frame, the status line
## (16x8 glyphs of font.ggs), the option icons and the F1 overview (docs 3.11).

const W := 320
const H := 200

var image: Image
var texture: ImageTexture
var sprites: Image          # 8 x 8 cells of 16x16 (hl.ggs slot order)
var minis: Image            # 8 x 8 cells of 8x8
var font: Image             # 16 x 4 cells of 16x24 (three colour rows of 16x8)
var logo: Image
var chaos: Image
var font_chars: Dictionary  # char -> glyph index (FontIndex 17CF:000B)
var moving := []            # smooth movement: [slot, from, to] (pixels) of the last tick's moves
var base: Image             # the picture without the moving objects


func _init(font_map: Dictionary) -> void:
	font_chars = font_map
	image = Image.create(W, H, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 1))
	texture = ImageTexture.create_from_image(image)
	sprites = _load("res://data/sprites.png")
	minis = _load("res://data/sprites_mini.png")
	font = _load("res://data/font.png")
	logo = _load("res://data/logo.png")
	chaos = _load("res://data/chaos.png")


static func _load(path: String) -> Image:
	var tex: Texture2D = load(path)
	var img := tex.get_image()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func update_texture() -> void:
	texture.update(image)


func clear(rect := Rect2i(0, 0, W, H)) -> void:
	image.fill_rect(rect, Color(0, 0, 0, 1))


func sprite(slot: int, x: int, y: int) -> void:
	"""a cell: black, then the sprite (transparent pixels stay black, as in the original)"""
	var r := Rect2i(x, y, 16, 16)
	image.fill_rect(r, Color(0, 0, 0, 1))
	image.blit_rect_mask(sprites, sprites, Rect2i((slot % 8) * 16, (slot / 8) * 16, 16, 16), r.position)


func mini_sprite(slot: int, x: int, y: int) -> void:
	var r := Rect2i(x, y, 8, 8)
	image.fill_rect(r, Color(0, 0, 0, 1))
	image.blit_rect_mask(minis, minis, Rect2i((slot % 8) * 8, (slot / 8) * 8, 8, 8), r.position)


func glyph(index: int, row: int, x: int, y: int) -> void:
	"""font.ggs glyph `index`, colour row 0 yellow / 1 green / 2 blue (or icon row), 16x8"""
	if index < 0:
		return
	var src := Rect2i((index % 16) * 16, (index / 16) * 24 + row * 8, 16, 8)
	image.fill_rect(Rect2i(x, y, 16, 8), Color(0, 0, 0, 1))     # transparent pixels show black
	image.blit_rect_mask(font, font, src, Vector2i(x, y))


func glyph_index(c: String) -> int:
	return int(font_chars.get(c, -1))


func picture(img: Image, x: int, y: int) -> void:
	image.blit_rect_mask(img, img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i(x, y))


# 1633:10DE DrawMap16
func draw_level(sim) -> void:
	for y in 12:
		for x in 20:
			sprite(sim.sprite(x, y), x * 16, y * 16)


## smooth movement (option): the objects moved by the last tick are drawn sliding from their old
## cell to the new one; the cells under them are black (an object only moves into an empty or a
## grass cell and leaves an empty one). The rules are untouched: this only draws sim.moves.
const MOVERS := [4, 5, 6, 8, 10]     # rock, heart, bomb, dwarf, balloon


func collect_moves(sim) -> void:
	moving.clear()
	for dst in sim.moves:
		var t: int = sim.type[dst]
		if not MOVERS.has(t):
			continue
		var src: int = sim.moves[dst]
		var to := Vector2i(dst % 22 - 1, dst / 22 - 1) * 16
		var from := Vector2i(src % 22 - 1, src / 22 - 1) * 16
		moving.append([sim.SPRITE_BASE[t] + sim.frame[dst], from, to])
		image.fill_rect(Rect2i(to, Vector2i(16, 16)), Color(0, 0, 0, 1))


func snap_base() -> void:
	base = image.duplicate() if not moving.is_empty() else null


func draw_moving(f: float) -> void:
	"""f: 0 = at the old cells (just after the tick), 1 = at the new ones"""
	if base == null:
		return
	for m in moving:
		var r := Rect2i(m[1], Vector2i(16, 16)).merge(Rect2i(m[2], Vector2i(16, 16)))
		image.blit_rect(base, r, r.position)
	for m in moving:
		var from: Vector2i = m[1]
		var to: Vector2i = m[2]
		var p := Vector2i((Vector2(from) + Vector2(to - from) * clampf(f, 0.0, 1.0)).round())
		var slot: int = m[0]
		image.blit_rect_mask(sprites, sprites, Rect2i((slot % 8) * 16, (slot / 8) * 16, 16, 16), p)


# 1633:115B DrawMap8 (F1): 8x8 sprites at (16, 88) over the logo
func draw_overview(sim) -> void:
	clear(Rect2i(0, 0, W, 192))
	picture(logo, 108, -4)
	for y in 12:
		for x in 20:
			mini_sprite(sim.sprite(x, y), 16 + x * 8, 88 + y * 8)


# status line of DrawFrame: "%3d(%-3d " yellow at 0, "%3d(%-3d " or "%3d)%-3d " blue at 128,
# "%3d " green at 256; a space is drawn as glyph ')' row 0 (the bar between the fields)
func draw_status(hearts_total: int, hearts_got: int, levels: int, solved_count: int,
		level_solved: bool, level_number: int) -> void:
	_field("%3d(%-3d " % [hearts_total, hearts_got], 0, 0)
	_field(("%3d)%-3d " if level_solved else "%3d(%-3d ") % [levels, solved_count], 128, 2)
	_field("%3d " % level_number, 256, 1)


func _field(text: String, x: int, row: int) -> void:
	for i in text.length():
		var c := text[i]
		if c == " ":
			glyph(glyph_index(")"), 0, x + i * 16, 192)
		else:
			glyph(glyph_index(c), row, x + i * 16, 192)


# 1633:0FD4 DrawOptionIcons: music, sound, joystick; "+" glyph = on, "-" glyph = off
func draw_icons(music: bool, sound: bool, joystick: bool) -> void:
	for x in [8, 32, 56]:
		glyph(glyph_index(" "), 0, x, 5)
	glyph(glyph_index("+" if music else "-"), 0, 4, 3)
	glyph(glyph_index("+" if sound else "-"), 1, 28, 3)
	glyph(glyph_index("+" if joystick else "-"), 2, 52, 3)


## the original's coloured text: "Gprogrammed" = green; capitals = Polish letters
func text(s: String, x: int, y: int, row := 0) -> void:
	var col := row
	var cx := x
	for i in s.length():
		var c := s[i]
		if i == 0 and c in ["G", "Y", "B"]:
			col = {"Y": 0, "G": 1, "B": 2}[c]
			continue
		glyph(glyph_index(c), col, cx, y)
		cx += 16
