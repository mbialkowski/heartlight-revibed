extends RefCounted
## The VGA palette as a 256x1 texture for palette.gdshader, with the original's fades
## (FadePalette 1C85:0001: linear steps between black and the palette) and the "VGA mono" mode.

var game: PackedByteArray
var mono: PackedByteArray
var use_mono := false
var level := 1.0            # 0 = black, 1 = full palette
var image: Image
var texture: ImageTexture
var _from := 1.0
var _to := 1.0
var _t := 1.0
var _duration := 0.3


func _init(game_rgb: Array, mono_rgb: Array) -> void:
	game = _flat(game_rgb)
	mono = _flat(mono_rgb)
	image = Image.create(256, 1, false, Image.FORMAT_RGB8)
	texture = ImageTexture.create_from_image(image)
	_upload()


static func _flat(rgb: Array) -> PackedByteArray:
	var p := PackedByteArray()
	for c in rgb:
		p.append(int(c[0]))
		p.append(int(c[1]))
		p.append(int(c[2]))
	return p


func set_mono(on: bool) -> void:
	use_mono = on
	_upload()


func fade(to_level: float, seconds := 0.3) -> void:
	_from = level
	_to = to_level
	_t = 0.0
	_duration = maxf(seconds, 0.001)


func busy() -> bool:
	return _t < 1.0


func update(delta: float) -> void:
	if _t < 1.0:
		_t = minf(1.0, _t + delta / _duration)
		level = lerpf(_from, _to, _t)
		_upload()


func _upload() -> void:
	var src := mono if use_mono else game
	var p := PackedByteArray()
	p.resize(768)
	var step := int(round(level * 64.0))      # the original's discrete steps
	for i in 768:
		p[i] = src[i] * step / 64
	image.set_data(256, 1, false, Image.FORMAT_RGB8, p)
	texture.update(image)
