extends Node
## Sound like the original (docs 2.5, 2.6, 3.12): 8-bit samples at 8522.7 Hz, the music on one
## channel (the 197-block sequence of DS:0094, looped), effects on the other; with the music off
## the driver may use both channels for effects (it restarts a channel already playing the same
## sample, else takes a free one, else the one that has played longer). The original mixes two
## channels as (a + b) / 2, so every channel plays at half amplitude.

var rate := 8522.73
var samples := {}           # name -> AudioStreamWAV
var music_stream: AudioStreamWAV
var title_stream: AudioStreamWAV
var music_player: AudioStreamPlayer
var fx := []                # two AudioStreamPlayer
var fx_name := ["", ""]
var music_on := true
var sound_on := true
var music_volume := 0.7
var fx_volume := 1.0


func setup(game: Dictionary) -> void:
	rate = float(game["sample_rate"])
	var blob := FileAccess.get_file_as_bytes("res://data/sounds.bin")
	for name in game["sounds"]:
		var r: Array = game["sounds"][name]
		samples[name] = _stream(blob.slice(int(r[0]), int(r[0]) + int(r[1])), false)
	var seq: String = game["music_sequence"]
	var music := PackedByteArray()
	for c in seq:
		if c >= "a" and c <= "t":
			var r: Array = game["sounds"]["!" + c]
			music.append_array(blob.slice(int(r[0]), int(r[0]) + int(r[1])))
	music_stream = _stream(music, true)
	title_stream = samples["title"].duplicate()
	title_stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	title_stream.loop_end = title_stream.data.size()
	music_player = AudioStreamPlayer.new()
	add_child(music_player)
	for i in 2:
		var p := AudioStreamPlayer.new()
		add_child(p)
		fx.append(p)
	apply_volumes()


func _stream(data: PackedByteArray, loop: bool) -> AudioStreamWAV:
	# sounds.bin is already signed 8-bit (tools/build_remake_data.py)
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_8_BITS
	s.mix_rate = int(round(rate))
	s.stereo = false
	s.data = data
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = data.size()
	return s


func apply_volumes() -> void:
	var half := linear_to_db(0.5)
	music_player.volume_db = half + linear_to_db(maxf(music_volume, 0.0001))
	for p in fx:
		p.volume_db = half + linear_to_db(maxf(fx_volume, 0.0001))


func play_music(title := false) -> void:
	var s := title_stream if title else music_stream
	if not sound_on or (not title and not music_on):
		music_player.stop()
		return
	if music_player.stream != s or not music_player.playing:
		music_player.stream = s
		music_player.play()


func stop_music() -> void:
	music_player.stop()


func play(name: String) -> void:
	if not sound_on or not samples.has(name):
		return
	var ch := 0
	if not music_on:
		if fx[0].playing and fx_name[0] == name:
			ch = 0
		elif fx[1].playing and fx_name[1] == name:
			ch = 1
		elif not fx[0].playing:
			ch = 0
		elif not fx[1].playing:
			ch = 1
		else:
			ch = 0 if fx[0].get_playback_position() >= fx[1].get_playback_position() else 1
	fx[ch].stream = samples[name]
	fx_name[ch] = name
	fx[ch].play()


func stop_all() -> void:
	music_player.stop()
	for p in fx:
		p.stop()
