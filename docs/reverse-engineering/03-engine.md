# 3. The engine

Everything here is read from `HL.EXE` segment `1633` (the game) and checked against the original
running in DOSBox (3.12). [`tools/hl_sim.py`](../../tools/hl_sim.py) implements these rules
routine for routine and is the executable form of this chapter; addresses name the original
routine for each rule. The annotated disassembly is in [`reference/`](../../reference/README.md).

## 3.1 The grid

The level lives in four parallel byte arrays of **22 × 14 = 308** cells (`DS:4C69`, `4D9D`,
`4ED1`, `5005`): the 20 × 12 level surrounded by a one-cell border of metal wall. A cell index is
`i = (y + 1) * 22 + (x + 1)`, so the neighbours are `i ± 1` (left/right) and `i ± 22`
(up/down). There is no other object list: every object is a cell.

| array | name | meaning |
|---|---|---|
| `5005` | `g_type` | object type, 0–13 (table below) |
| `4ED1` | `g_state` | 0 = inert (never processed), otherwise per-type state |
| `4D9D` | `g_frame` | animation frame / per-type counter |
| `4C69` | `g_pending` | set to 1 for all cells at the start of a tick, cleared in a cell an object moves into: that cell is not processed again in the same tick |

| type | object | char | states | frames (sprite = `g_spriteBase[type] + frame`) |
|---|---|---|---|---|
| 0 | empty | space | 0 | – |
| 1 | explosion | – | 1 | 0–6 (sprites grow and shrink: 0 1 2 3 2 1 0) |
| 2 | brick wall | `#` | 0 | level number mod 4 = colour |
| 3 | metal wall (also the border) | `%` | 0 | – |
| 4 | rock | `@` | 2 resting, 3 falling | – |
| 5 | heart | `$` | 2 resting, 3 falling | 0–5 beat, advances every tick |
| 6 | bomb | `&` | 2 resting, 3 falling, 8 lit | 0, 1 = lit |
| 7 | grass | `.` | 0 | – |
| 8 | dwarf | `*` | 1 | 0/1 walk left, 2/3 walk right, 4/5 dying, 6/7 leaving |
| 9 | exit door | `!` | 5 closed, 6 open | 0 closed … 3 open |
| 10 | balloon | `0` | 2 resting, 7 rising | 0–3 sway, advances every tick |
| 11 | plasma | `=` | 2 | 0–7 shimmer, advances every tick |
| 12 | tunnel `<` (to the left) | `<` | 2 idle, 1 dwarf inside, 3 dwarf leaving | 0–3 idle, +4 with the dwarf inside |
| 13 | tunnel `>` (to the right) | `>` | same | same |

Level set-up (`SetupLevel` `15BE:04F9`) is in [2.9](02-file-formats.md#29-levelshl). The number of
hearts in the level is both the target and the counter `g_heartsLeft` (`DS:4C49`).

## 3.2 The tick

`PlayGame` (`1633:1777`) runs one **tick** every 960 timer interrupts: the sound driver
programs PIT channel 0 to 8 522.7 Hz and counts 2 per interrupt, and the loop waits until the
counter reaches `0x780` (1 920) before resetting it. That is **112.6 ms per tick, 8.88 ticks per
second**, independent of the CPU (if drawing is fast enough) and of the sound device (the
no-sound driver programs the same rate).

`GameTick` (`1633:0C4D`):

1. Read the keyboard and joystick ([3.10](#310-input)); set `g_dir` (`DS:60DB`) to −1, +1, −22,
   +22 or 0. When several arrows are held the last test wins: **right > left > down > up**.
2. Esc (edge) starts the death of the dwarf (`g_deathTimer = 8`) unless he is already dying or
   leaving. F6/F7/F8/F1/F10 and the level-change keys are handled here too.
3. `g_pending[all] = 1`.
4. **Scan rows 1→12, columns 1→20** (top to bottom, left to right). A cell is processed when
   its state is non-zero and its pending flag is still 1; the handler is chosen by type:
   explosion, rock, heart, bomb, dwarf, door, balloon, plasma, tunnels. Brick, metal, grass and
   empty cells have state 0 and are never processed.
5. `g_tickCount++` (never reset between levels), `g_heroIdle--`, and the death and exit timers
   count down if non-zero.

Because the scan goes top-down and left-to-right and handlers move objects in place, the
original's behaviour depends on this order: a rock moving down or right lands in a cell that is
still to be scanned and is protected by `g_pending`; an object moving up or left lands in a cell
already scanned. Copy the scan exactly.

Every handler that "moves" an object copies type, state and frame to the destination, clears the
destination's pending flag and zeroes the source cell.

## 3.3 Level loop and its end

```
g_activity = 1; g_heroIdle = 1
while g_gameState == PLAYING and g_activity != 0 and g_heroIdle != 0:
    g_activity = 0
    GameTick(); DrawFrame()
    wait until the timer reaches 1920; reset the timer
```

`g_activity` (`DS:60D9`) counts things that moved or acted this tick; `g_heroIdle`
(`DS:60D2`) is reset to 32 whenever the dwarf (or a tunnel carrying him) is processed. The level
therefore ends:

* with `g_gameState = 6` (next level) when the dwarf has walked through the door, after his
  16-tick exit animation; the level is marked solved;
* with `g_gameState` still 1 — **restart the same level** — when the dwarf no longer exists and
  either nothing moved during a tick or 32 ticks have passed. A restart fades the screen out and
  in;
* on Space+Left/Right (previous/next level, 6/7), F10 (4, back to the title) or a fatal key.

After a completed level the game goes to the **next level number** (wrapping after the last), not
to the next unsolved one. Changing level slides the old play-field out and the new one in
(16-pixel steps, one per retrace).

## 3.4 The dwarf (`Hero_Think` `1633:00C0`, type 8)

Every tick: `g_activity++`, `g_heroIdle = 32`. Then:

* **Dying** (`g_deathTimer > 0`): while the timer is above 1 the frame alternates 4/5
  (`4 | (timer & 1)`); at 1 the `expl` sound plays and the cell becomes an explosion
  (type 1, state 1, frame 0). Esc sets the timer to 8: 7 blinking ticks, then the explosion.
* **Leaving** (`g_exitTimer > 0`): frame `6 | (timer & 1)` while above 1; at 1 the level is
  solved (`g_gameState = 6`).
* Otherwise compute the new frame `f` from the input: left `f = (f ^ 1) & 1`, right
  `f = (f ^ 1) | 2`, up/down `f ^= 1` keeping the facing. With no input the dwarf stands:
  `frame = f & 2`. With input, look at the target cell `t = i + dir`:

| target | result |
|---|---|
| empty, grass | move there (grass is dug away) |
| rock, bomb, balloon | **push** if the move is horizontal, the cell beyond is empty, the object is resting (state 2) and the cell above the object is not falling (state ≠ 3) — and only on **odd ticks** (`g_tickCount & 1`); on an even tick he just turns (frame `f`). The object moves one cell, the dwarf follows. Otherwise he stands (`f & 2`) |
| heart, resting | collect: `colect` sound, move there, `g_heartsLeft--` |
| heart, falling | nothing at all (not even the frame changes) |
| door, open (state 6) | `door` sound, move into the door cell, `g_exitTimer = 16` |
| door, closed | stand |
| tunnel `<` moving left / `>` moving right | follow the run of identical tunnel cells; if the cell after it is empty or grass, the `tunnel` sound plays, the dwarf disappears from his cell and the first tunnel cell gets state 1. Otherwise stand |
| anything else (wall, plasma, explosion, wrong-way tunnel) | stand |

So holding a direction against a rock pushes it every second tick — two ticks per cell — while
walking costs one tick per cell. A single short press may or may not push depending on parity.

## 3.5 Falling and rolling (`Gravity` `1633:05B5`; rock, heart, bomb)

Called by the rock, heart and bomb handlers. Returns 1 when the object **lands**.

**Resting** (state 2), by the type `b` of the cell below:

| below | result |
|---|---|
| empty | start falling: state 3, `g_activity++`, and fall immediately (below) |
| explosion, brick, rock, heart, plasma, or a bomb whose frame is 0 | **roll**: if left and down-left are empty and the cell up-left is not falling (state ≠ 3), move left with state 3; else the same to the right. `g_activity++` when it rolls |
| balloon | if the cell under the balloon is empty and the cell **above** this object holds a rock, heart or bomb, push the balloon down one cell and start falling (two weights sink a balloon) |
| metal, grass, dwarf, door, tunnels, lit bomb | stay |

Objects therefore roll off bricks, rocks, hearts, plasma and idle bombs, but **not off metal
walls or grass**.

**Falling** (state 3): `g_activity++`, then by the cell below:

| below | result |
|---|---|
| empty | move down one cell (still state 3) |
| bomb | the bomb is lit (state 8); this object lands (state 2) |
| dwarf | unless he is walking out through the door (frame ≥ 6), `expl` sound and he becomes an explosion (frame 0, not processed again this tick); the object lands |
| anything else | lands (state 2) |

An object moves at most one cell per tick. The first tick of a fall is the one in which the
resting object finds an empty cell below.

**Landing sounds**: rock: `rocgrass` on grass, else `rock` (`Rock_Think` `1633:07A7`); heart: the
heart frame advances (mod 6) every tick, landing on grass plays `hrtgrass`, else one of
`heart0`–`heart3` chosen with `rand()` (`Heart_Think` `1633:0824`).

## 3.6 Bombs (`Bomb_Think` `1633:098D`)

* A bomb falls like a rock. **Landing on anything but grass lights it** (state 8); on grass it
  plays `rocgrass` and rests. A bomb hit by a falling object is lit as well (3.5), and so is a
  bomb next to an explosion (below).
* A lit bomb with frame 0 sets frame 1 (the lit sprite) and waits a tick. (It also clears the
  pending flag of the cell below unless that is a bomb or a leaving dwarf, so the object below
  it skips this tick.)
* Next tick it **explodes**: `expl` sound, the bomb cell becomes an explosion with frame 1, and
  each of the four neighbours (left, right, up, down, in that order):
  * metal wall, tunnel: untouched;
  * bomb: lit (state 8, pending cleared) — chain reactions advance one bomb per two ticks;
  * the dwarf while he walks out through the door (frame ≥ 6): untouched;
  * anything else — empty, brick, grass, rock, heart, plasma, balloon, door, the dwarf, another
    explosion: becomes an explosion with frame 0.
* The new explosions to the right and below are still pending, so they age one frame in the
  same tick; those to the left and above do not. Copy this to keep the timing.

Bricks, plasma, hearts (which can make a level unsolvable) and even the exit door are
destroyed; only metal walls and tunnels resist.

## 3.7 Explosions (`Explosion_Think` `1633:0C08`)

`g_activity++`; while the frame is below 6 it advances by one; at 6 the cell becomes empty. A
fresh explosion is therefore visible for 7 ticks (6 for the bomb's own cell, which starts at 1).
Falling objects roll off explosions.

## 3.8 Balloons (`Balloon_Think` `1633:0AE5`)

Frame advances (mod 4) every tick. **Resting** (state 2), by the cell above:

* empty: start rising (state 7);
* rock, heart, bomb or the dwarf: if the cell above that is empty, lift it one cell (it keeps its
  state) and start rising;
* anything else: stay.

**Rising** (state 7): `g_activity++`; if the cell above is empty move up one cell, otherwise
state 2. A balloon rises one cell per tick and carries a load on top of it, including the dwarf;
two stacked weights make it sink (3.5). The dwarf can push balloons sideways (3.4).

## 3.9 Door, plasma, tunnels

**Door** (`Door_Think` `1633:0BAF`): while the frame is below 3 and no hearts are left, the frame
advances by one per tick (the first step plays `colected`); at frame 3 the state becomes 6
(open). Opening takes 4 ticks. A level without hearts opens its door at once. The door does not
count as activity.

**Plasma** (`Plasma_Think` `1633:0C37`): only animates (frame mod 8). It is a solid wall for the
dwarf, objects roll off it, explosions destroy it. Contact with plasma does **not** kill.

**Tunnels** (`Tunnel_Think` `1633:04AB`), direction −1 for `<`, +1 for `>`:

* state 1 (the dwarf is in this cell): `g_activity++`, `g_heroIdle = 32`, frame
  `((f + 1) & 3) | 4`, state 2; if the next cell is the same kind of tunnel it gets state 1 (and
  is not processed again this tick); if it is empty or grass this cell gets state 3;
* state 3: the frame advances, state 2, and if the next cell is still empty or grass the dwarf
  appears there facing the tunnel's direction (frame 0 for `<`, 2 for `>`); if it was filled in
  the meantime the dwarf is lost and the level restarts after 32 ticks;
* state 2: idle animation (frame mod 4).

The dwarf travels one tunnel cell per tick.

## 3.10 Input

The keyboard handler (`INT 9`, segment `2063`) keeps a "held" bitmap and a "pressed since last
poll" latch; `PollKeyboard` snapshots both once per tick and `KeyDown` is *held or pressed*, so a
tap shorter than a tick is never lost and counts for exactly one tick.

| key (scan code) | action |
|---|---|
| arrows (48 50 4B 4D) | move / push |
| Space + Left / Right | previous / next level (slide transition) |
| Esc | lose a life: the dwarf dies and the level restarts |
| F1 (3B) | overview: the whole level in 8×8 tiles, centred (also saved per player) |
| F6 (40) | music on/off |
| F7 (41) | sound effects on/off |
| F8 (42) | joystick on/off |
| F10 (44) | back to the title screen |
| Alt+Ctrl+F12 | save `PICnn.BMP` |

When play begins and after F6/F7/F8 three icons (music, sound, joystick) appear in the top-left
corner for 48 ticks, with a tick mark or a cross for on/off; the `key` sound confirms a toggle.

The joystick is read with the BIOS and mapped to virtual scan codes: `5B`/`5C`/`5D`/`5E`
up/down/left/right and `59`/`5A` for the buttons (which work like Space); a second joystick uses
`5F`–`64`. An axis counts as pushed beyond ±50 % of the centre value measured at start-up.

## 3.11 Drawing

`DrawFrame` (`1633:11D8`) redraws every cell from `g_spriteBase[type] + frame` into the back page
(Mode X), draws the status line and flips pages. Normal view: 20×12 cells of 16×16 filling
320×192. Overview (F1): the 8×8 sprites, the level as 160×96 at (16, 88), drawn over the title
picture (logo top right).

Status line (y = 192, 16×8 glyphs of `font.ggs`):

| columns | colour | contents |
|---|---|---|
| 0–7 | yellow | hearts in the level, heart icon, hearts collected (`%3d(%-3d`) |
| 8–15 | blue | levels in the file, heart icon (or the "solved" mark if this level is solved), levels solved (`%3d(%-3d` / `%3d)%-3d`) |
| 16–19 | green | current level number (`%3d`) |

## 3.12 Sound

Two software-mixed channels at 8 523 Hz. The music (F6) plays on channel 1. Effects are only
started if sound is on (F7); with music on they all go to channel 2, each new effect replacing
the previous one; with music off the driver may use either channel (it restarts a channel already
playing the same sample, else takes a free one, else the one that has played longer), so two
effects can overlap. Which effect plays when
is listed in [2.5](02-file-formats.md#25-sounds-snd). The in-game music loops the 197-block
sequence of [2.6](02-file-formats.md#26-in-game-music-sequence); the title tune loops
`title.snd`.

## 3.13 Randomness

Borland's `rand()` (LCG `s = s * 0x015A4E35 + 1`, result `(s >> 16) & 0x7FFF`), seeded with
`srand(BIOS tick count)` at start-up, is used only for the initial frames of hearts and balloons
and to choose the heart-landing sound. **Nothing in the game logic is random**: a level plays the
same way every time for the same inputs at the same tick parity.

## 3.14 Verification

`tools/golden_check.py` drives the original in DOSBox (Xvfb + xdotool), captures the screen
every ~0.1 s with DOSBox's own screenshot key, reads every cell back into (type, frame) with
`tools/screen_reader.py`, and requires each capture to be a state the simulator reaches in order.
Unknown timing is handled by keeping every simulator candidate (key press landing on any of the
next ticks, either tick parity) that agrees with all captures so far. Only the frames of hearts
and balloons (random at level start) are ignored; the plasma and tunnel animations, which count
ticks from the level start, must match too, which pins the tick count. Sprites with identical
images (the explosion plays 0 1 2 3 2 1 0) are treated as equal. `tests/test_sim.py` adds quick
emulator-free checks of individual rules.

Results: all 70 levels from their start with no input, and all 70 levels with a 16-move random
walk each (`tests/golden_scenarios.json`, chosen by `tools/make_scenarios.py` to trigger as many
different events as possible: collecting, pushing, rolling, explosions and chain reactions,
deaths and restarts, tunnels, balloons) match the original — see
[`tests/golden_report.json`](../../tests/golden_report.json).
