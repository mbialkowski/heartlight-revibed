extends RefCounted
## The game rules of Heartlight PC: a line-by-line port of tools/hl_sim.py, which ports HL.EXE
## segment 1633 routine by routine and matches the original on all 70 levels (docs 3.14).
## One call of tick() is one game tick (112.6 ms in the original). Do not "improve" anything here:
## behavioural options (push on every press...) are applied by the caller, not in these rules.
##
## The grid is the original's 22 x 14 array (the 20 x 12 level with a metal border);
## cell index = (y + 1) * 22 + (x + 1).

const Rand = preload("res://scripts/sim/rand.gd")

const W := 22
const H := 14
const N := W * H

enum { EMPTY, EXPLOSION, BRICK, METAL, ROCK, HEART, BOMB, GRASS, DWARF, DOOR, BALLOON, PLASMA,
		TUNNEL_L, TUNNEL_R }
const PLAYING := 1
const QUIT := 4
const NEXT_LEVEL := 6
const PREV_LEVEL := 7

const LEFT := -1
const RIGHT := 1
const UP := -W
const DOWN := W

const SPRITE_BASE := [0, 9, 56, 60, 8, 1, 61, 7, 16, 24, 28, 32, 40, 48]
const HEART_SOUNDS := ["heart0", "heart1", "heart2", "heart3"]

var type := PackedByteArray()
var state := PackedByteArray()
var frame := PackedByteArray()
var pending := PackedByteArray()

var rows: Array = []
var level_index := 0
var rand
var tick_count := 0        # DS:60DD, never reset between levels: push parity
var hearts_total := 0
var hearts_left := 0       # DS:4C49
var game_state := PLAYING  # DS:4C45
var death_timer := 0       # DS:60D8
var exit_timer := 0        # DS:60D7
var idle := 1              # DS:60D2
var activity := 1          # DS:60D9
var dir := 0               # DS:60DB
var solved := false
var sounds: Array[String] = []   # sounds started during the last tick
var moves := {}            # dst cell -> src cell of the objects moved during the last tick; only
                           # for drawing (smooth movement), the rules never read it


func _init(p_rows: Array, p_level_index := 0, p_rand = null, p_tick_count := 0) -> void:
	rand = p_rand if p_rand != null else Rand.new(randi() & 0xFFFF)
	level_index = p_level_index
	tick_count = p_tick_count
	type.resize(N)
	state.resize(N)
	frame.resize(N)
	pending.resize(N)
	setup(p_rows)


# 15BE:04F9 SetupLevel
func setup(p_rows: Array) -> void:
	rows = p_rows
	type.fill(METAL)
	state.fill(0)
	frame.fill(0)
	pending.fill(1)
	hearts_left = 0
	for x in 20:
		for y in 12:
			var row: String = rows[y] if y < rows.size() else ""
			var c := row[x] if x < row.length() else " "
			var si := (y + 1) * W + (x + 1)
			var t := METAL
			var s := 2
			var f := 0
			match c:
				" ":
					t = EMPTY; s = 0
				"#":
					t = BRICK; s = 0; f = level_index % 4
				"%":
					t = METAL; s = 0
				"@":
					t = ROCK
				"$":
					t = HEART; f = rand.next() * 6 / 0x8000
					hearts_left += 1
				"*":
					t = DWARF; s = 1; f = 2 if x < 10 else 0
				"!":
					t = DOOR; s = 5
				"&":
					t = BOMB
				".":
					t = GRASS; s = 0
				"0":
					t = BALLOON; f = rand.next() * 4 / 0x8000
				"=":
					t = PLASMA
				"<":
					t = TUNNEL_L
				">":
					t = TUNNEL_R
			type[si] = t
			state[si] = s
			frame[si] = f
	hearts_total = hearts_left
	moves.clear()
	game_state = PLAYING
	death_timer = 0
	exit_timer = 0
	idle = 1
	activity = 1
	dir = 0
	solved = false


func _moved(src: int, dst: int) -> void:
	var origin: int = moves.get(src, src)
	moves.erase(src)
	moves[dst] = origin


func _move(src: int, dst: int, new_state := -1) -> void:
	_moved(src, dst)
	type[dst] = type[src]
	state[dst] = state[src] if new_state < 0 else new_state
	frame[dst] = frame[src]
	pending[dst] = 0
	type[src] = 0
	state[src] = 0
	frame[src] = 0


func _clear(i: int) -> void:
	type[i] = 0
	state[i] = 0
	frame[i] = 0


# 1633:0C4D GameTick
func tick(direction := 0, escape := false) -> void:
	sounds.clear()
	moves.clear()
	activity = 0
	dir = direction
	if escape and death_timer == 0 and exit_timer == 0:
		death_timer = 8
	pending.fill(1)
	for y in range(1, 13):
		for x in range(1, 21):
			var si := y * W + x
			if state[si] == 0 or pending[si] == 0:
				continue
			match type[si]:
				EXPLOSION:
					_explosion_think(si)
				ROCK:
					_rock_think(si)
				HEART:
					_heart_think(si)
				BOMB:
					_bomb_think(si)
				DWARF:
					_hero_think(si)
				DOOR:
					_door_think(si)
				BALLOON:
					_balloon_think(si)
				PLASMA:
					_plasma_think(si)
				TUNNEL_L, TUNNEL_R:
					_tunnel_think(si)
	tick_count = (tick_count + 1) & 0xFFFF
	idle -= 1
	if death_timer:
		death_timer -= 1
	if exit_timer:
		exit_timer -= 1


## the PlayGame loop condition (1633:1956)
func level_running() -> bool:
	return game_state == PLAYING and activity != 0 and idle != 0


## PlayGame restarts the level when it ends without a level change (the dwarf died)
func restart_if_over() -> bool:
	if not level_running() and game_state == PLAYING:
		setup(rows)
		return true
	return false


# 1633:00C0 Hero_Think
func _hero_think(si: int) -> void:
	activity += 1
	idle = 0x20
	if death_timer:
		if death_timer > 1:
			frame[si] = 4 | (death_timer & 1)
		else:
			sounds.append("expl")
			type[si] = EXPLOSION
			state[si] = 1
			frame[si] = 0
		return
	if exit_timer:
		if exit_timer > 1:
			frame[si] = 6 | (exit_timer & 1)
		else:
			game_state = NEXT_LEVEL
			solved = true
		return
	var f: int = frame[si]
	var d := dir
	if d == -1:
		f = (f ^ 1) & 1
	elif d == 1:
		f = (f ^ 1) | 2
	elif d == -W or d == W:
		f = (f & 2) | (f ^ 1)
	if d == 0:
		frame[si] = f & 2
		return
	var di := si + d
	var t: int = type[di]
	if t == EMPTY or t == GRASS:                                        # 02AB
		_hero_to(si, di, f)
	elif t == ROCK or t == BOMB or t == BALLOON:                        # 01F9 push
		if type[si + 2 * d] == EMPTY and state[di] == 2 and state[di - W] != 3 \
				and d != -W and d != W:
			if tick_count & 1:
				var j := si + 2 * d
				_moved(di, j)
				type[j] = type[di]
				state[j] = state[di]
				frame[j] = frame[di]
				pending[j] = 0
				_hero_to(si, di, f)
			else:
				frame[si] = f
		else:
			frame[si] = f & 2
	elif t == HEART:                                                    # 038A
		if state[di] == 2:
			sounds.append("colect")
			_hero_to(si, di, f)
			hearts_left -= 1
		# a falling heart blocks the dwarf; his frame is left unchanged
	elif t == DOOR:                                                     # 03F7
		if state[di] == 6:
			sounds.append("door")
			_hero_to(si, di, f)
			exit_timer = 0x10
		else:
			frame[si] = f & 2
	elif t == TUNNEL_L or t == TUNNEL_R:                                # 02D4
		if (t == TUNNEL_L and d == -1) or (t == TUNNEL_R and d == 1):
			var j := di
			while type[j] == t:
				j += d
			if type[j] == EMPTY or type[j] == GRASS:
				sounds.append("tunnel")
				state[di] = 1
				pending[di] = 0
				_clear(si)
				return
		frame[si] = f & 2
	else:                                                               # 0471
		frame[si] = f & 2


func _hero_to(si: int, di: int, f: int) -> void:
	_moved(si, di)
	type[di] = DWARF
	state[di] = 1
	frame[di] = f
	pending[di] = 0
	_clear(si)


# 1633:04AB Tunnel_Think
func _tunnel_think(si: int) -> void:
	var st: int = state[si]
	var d := -1 if type[si] == TUNNEL_L else 1
	if st == 1:                         # the dwarf is inside this cell
		activity += 1
		idle = 0x20
		frame[si] = ((frame[si] + 1) & 3) | 4
		state[si] = 2
		var n := si + d
		var t: int = type[n]
		if t == TUNNEL_L or t == TUNNEL_R:
			if t == type[si]:
				state[n] = 1
				pending[n] = 0
		elif t == EMPTY or t == GRASS:
			state[si] = 3
	elif st == 2:
		frame[si] = (frame[si] + 1) & 3
	elif st == 3:                       # the dwarf leaves the tunnel
		activity += 1
		idle = 0x20
		frame[si] = (frame[si] + 1) & 3
		state[si] = 2
		var n := si + d
		if type[n] == GRASS or type[n] == EMPTY:
			type[n] = DWARF
			state[n] = 1
			frame[n] = 0 if type[si] == TUNNEL_L else 2
			pending[n] = 0


# 1633:05B5 Gravity (rock, heart, bomb); returns true when the object lands
func _gravity(di: int) -> bool:
	var landed := false
	if state[di] == 2:
		var b: int = type[di + W]
		if b == EMPTY:
			state[di] = 3
			activity += 1
		elif b == EXPLOSION or b == BRICK or b == ROCK or b == HEART or b == PLASMA \
				or (b == BOMB and frame[di + W] == 0):
			if type[di - 1] == EMPTY and type[di + W - 1] == EMPTY and state[di - W - 1] != 3:
				_move(di, di - 1, 3)
				activity += 1
			elif type[di + 1] == EMPTY and type[di + W + 1] == EMPTY and state[di - W + 1] != 3:
				_move(di, di + 1, 3)
				activity += 1
		elif b == BALLOON:
			var a: int = type[di - W]
			if type[di + 2 * W] == EMPTY and (a == ROCK or a == HEART or a == BOMB):
				_move(di + W, di + 2 * W)
				state[di] = 3
	if state[di] == 3:
		activity += 1
		var b: int = type[di + W]
		if b == EMPTY:
			_move(di, di + W)
		elif b == BOMB:
			state[di + W] = 8
			state[di] = 2
			landed = true
		elif b == DWARF:
			if frame[di + W] < 6:
				sounds.append("expl")
				type[di + W] = EXPLOSION
				state[di + W] = 1
				frame[di + W] = 0
				pending[di + W] = 0
			state[di] = 2
			landed = true
		else:
			state[di] = 2
			landed = true
	return landed


# 1633:07A7 Rock_Think
func _rock_think(si: int) -> void:
	if _gravity(si):
		sounds.append("rocgrass" if type[si + W] == GRASS else "rock")


# 1633:0824 Heart_Think
func _heart_think(si: int) -> void:
	frame[si] = (frame[si] + 1) % 6
	if _gravity(si):
		if type[si + W] == GRASS:
			sounds.append("hrtgrass")
		else:
			sounds.append(HEART_SOUNDS[rand.next() * 4 / 0x8000])


# 1633:098D Bomb_Think
func _bomb_think(di: int) -> void:
	if _gravity(di):
		if type[di + W] != GRASS:
			state[di] = 8
		else:
			sounds.append("rocgrass")
	if state[di] != 8:
		return
	if frame[di] == 0:                  # lit: explodes on its next turn
		frame[di] = 1
		var b := di + W
		if type[b] == DWARF and frame[b] >= 6:
			return
		if type[b] == BOMB:
			return
		pending[b] = 0
		return
	sounds.append("expl")
	type[di] = EXPLOSION
	state[di] = 1
	frame[di] = 1
	for d in [-1, 1, -W, W]:
		var n: int = di + d
		var t: int = type[n]
		if t == METAL or t == TUNNEL_L or t == TUNNEL_R:
			continue
		if t == BOMB:
			state[n] = 8
			pending[n] = 0
			continue
		if t == DWARF and frame[n] >= 6:
			continue
		type[n] = EXPLOSION
		state[n] = 1
		frame[n] = 0


# 1633:0AE5 Balloon_Think
func _balloon_think(di: int) -> void:
	frame[di] = (frame[di] + 1) & 3
	if state[di] == 2:
		var a: int = type[di - W]
		if a == EMPTY:
			state[di] = 7
			activity += 1
		elif a == ROCK or a == HEART or a == BOMB or a == DWARF:
			if type[di - 2 * W] == EMPTY:
				var j := di - 2 * W
				var k := di - W
				_moved(k, j)
				type[j] = type[k]
				state[j] = state[k]
				frame[j] = frame[k]
				_clear(k)
				state[di] = 7
	if state[di] == 7:
		activity += 1
		if type[di - W] == EMPTY:
			_move(di, di - W)
		else:
			state[di] = 2


# 1633:0BAF Door_Think
func _door_think(si: int) -> void:
	if frame[si] < 3:
		if hearts_left == 0:
			if frame[si] == 0:
				sounds.append("colected")
			frame[si] += 1
	else:
		state[si] = 6


# 1633:0C08 Explosion_Think
func _explosion_think(si: int) -> void:
	activity += 1
	if frame[si] < 6:
		frame[si] += 1
	else:
		_clear(si)


# 1633:0C37 Plasma_Think
func _plasma_think(si: int) -> void:
	frame[si] = (frame[si] + 1) & 7


# views ---------------------------------------------------------------------------------------
func cell_index(x: int, y: int) -> int:
	return (y + 1) * W + (x + 1)


func sprite(x: int, y: int) -> int:
	var i := cell_index(x, y)
	return SPRITE_BASE[type[i]] + frame[i]


func hero_pos() -> Vector2i:
	for i in N:
		if type[i] == DWARF:
			return Vector2i(i % W - 1, i / W - 1)
	return Vector2i(-1, -1)


## FNV-1a 32 of the whole state; tools/make_golden_traces.py computes the same
func state_hash() -> int:
	var h := 0x811C9DC5
	for arr in [type, state, frame]:
		for b in arr:
			h = ((h ^ b) * 0x01000193) & 0xFFFFFFFF
	for v in [hearts_left, death_timer, exit_timer, game_state, idle, activity, tick_count]:
		h = ((h ^ (v & 0xFF)) * 0x01000193) & 0xFFFFFFFF
	return h


func snapshot() -> Dictionary:
	return {"type": type.duplicate(), "state": state.duplicate(), "frame": frame.duplicate(),
			"hearts_left": hearts_left, "death_timer": death_timer, "exit_timer": exit_timer,
			"game_state": game_state, "idle": idle, "activity": activity, "tick_count": tick_count,
			"solved": solved, "rand": rand.s}


func restore(snap: Dictionary) -> void:
	type = snap["type"].duplicate()
	state = snap["state"].duplicate()
	frame = snap["frame"].duplicate()
	hearts_left = snap["hearts_left"]
	death_timer = snap["death_timer"]
	exit_timer = snap["exit_timer"]
	game_state = snap["game_state"]
	idle = snap["idle"]
	activity = snap["activity"]
	tick_count = snap["tick_count"]
	solved = snap["solved"]
	rand.s = snap["rand"]
	moves.clear()
