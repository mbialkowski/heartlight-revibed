# 5. Notes for the remake

## 5.1 What to port

The whole game is small: one 22×14 byte grid, nine object handlers, a tick loop, a level file
and a handful of sprites and samples. Port the rules from [`tools/hl_sim.py`](../../tools/hl_sim.py)
(it follows the original routine by routine) rather than re-deriving them, and keep it as the
reference implementation for tests: the same `LEVELS.HL`, the same inputs on the same ticks and
the same tick parity must produce the same grids.

Recommended structure:

* **Simulation**: a pure, deterministic `tick(input)` over the 22×14 grid, exactly as in 3.2,
  no floating point, no `rand()` in the logic. Run it at the original 8.88 Hz (112.6 ms) and
  interpolate only the drawing if smooth movement is wanted (the original moves everything one
  cell per tick, with no in-between frames).
* **Presentation**: sprites from `assets/sprites/` (16×16, plus the 8×8 versions for an overview
  map), the palette, the font, sounds and music from `assets/`.
* **Levels**: read `LEVELS.HL` with the original rules (2.9) so that fan-made level files keep
  working; `tools/hl_levels.py` is a reference parser.

## 5.2 Fidelity checklist

Behaviour that is easy to get wrong:

1. **Scan order** top-to-bottom, left-to-right, with the per-tick pending flag (3.2). Objects
   that move down/right must not be processed twice; objects moving up/left are not processed
   again either (their new cell was already scanned).
2. Falling starts **in the same tick** an object finds empty space below (state 2 → 3 → moved).
3. **Rolling**: off brick, rock, heart, plasma, explosion and *unlit* bombs only; never off metal,
   grass, the dwarf, the door, tunnels or balloons. Try left first, then right; both need the
   side and diagonal-below cells empty and the cell diagonally above not falling.
4. **Pushing** only horizontally, only resting objects, only if the cell above the object is not
   falling, and **only on odd ticks** (the global tick counter, which is never reset). Holding a
   key pushes every second tick. A single tap pushes only half of the time: keep that, or make
   pushing deterministic as an option and keep it off by default.
5. A **falling heart blocks** the dwarf without changing his frame; a resting heart is collected.
6. **Bombs** explode when they land on anything but grass, when hit from above, or when next to an
   explosion; one tick lit (frame 1), then the explosion. Neighbour order and the "right/below
   explosions age one frame in the same tick" detail (3.6).
7. **Explosions** destroy brick, plasma, grass, rocks, hearts, balloons, the door and the dwarf;
   not metal walls, tunnels, or a dwarf already walking out through the door. A level can become unsolvable: that is the
   original's design, Esc restarts.
8. **Balloons** carry one object (including the dwarf) up; a balloon under two stacked weights is
   pushed down.
9. **Tunnels**: one cell per tick, entered only in their direction, exit cell checked again when
   the dwarf comes out.
10. **Door** opens in 4 ticks after the last heart; walking in starts a 16-tick exit animation;
    then the *next level number* starts (not the next unsolved one).
11. **Level end without the dwarf**: when nothing moves in a tick, or 32 ticks after the dwarf
    disappeared → restart with a fade.
12. **Input**: one direction per tick with priority right > left > down > up; taps shorter than a
    tick still count once.
13. Plasma does **not** kill (despite its looks).
14. Initial facing: right if the dwarf starts in the left half (x < 10), else left. Brick colour =
    level number mod 4.

## 5.3 Testing against the original

`tools/golden_check.py` (3.14) plays the original in DOSBox and compares every captured frame
with the simulator. Use it whenever `hl_sim.py` changes, and port its scenarios
(`tests/golden_scenarios.json`) to the remake's own test-suite: run the remake's simulation
next to `hl_sim.py` on all 70 levels with the same inputs and compare the grids tick by tick —
that needs no emulator.

## 5.4 Presentation ideas that keep the rules intact

* Scale the 320×200 picture by integers; the play-field is 320×192, the status line 8 pixels.
* Smooth movement: tween sprites between cells during the 112.6 ms tick, but always draw the
  logical state at tick boundaries; deaths and explosions must stay on the same ticks.
* Options worth adding: undo / rewind (the simulation is tiny and deterministic, store grids),
  a level select showing solved levels, key remapping, touch controls (four directions + Esc),
  music volume. Keep F1 (overview), F6/F7, Esc and Space+←/→ for players who know the original.
* Keep `LEVELS.HL` compatibility and maybe add a level editor: the format is plain text.

## 5.5 Open questions

* `demo.rec` (2.8) is unused and not fully decoded.
* The six bytes at offset 0x18 of the player files are rotated on every save; their meaning
  is unknown (no effect on play).
* The sound drivers other than the Sound Blaster one and the dormant EGA/CGA/Hercules graphics
  drivers were not analysed: a remake does not need them.

## 5.6 Licence

The 2006 release is licensed under **Creative Commons Attribution-ShareAlike 2.5** (see
`original/README.TXT`). A remake may reuse the graphics, sounds, music and levels, including
commercially, provided it credits the authors (Janusz Pelc and the level authors; Xland; the
2006 release by Maciej Miąsik) and distributes those assets — and anything adapted from them —
under the same licence. Code written from scratch can use any licence; this repository's code
and documentation are MIT, the original files and everything extracted from them in `assets/`
stay CC BY-SA 2.5. The release notes that Epic Games played no role in the 2006 release; do not
use Epic's name or logo beyond the factual credit.
