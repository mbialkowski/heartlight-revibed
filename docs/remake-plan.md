# Heartlight: Revibed — remake implementation plan

Status: **plan**, nothing implemented yet. Decisions confirmed (section 10): Godot 4.7, Polish by
default, original behaviour by default, level editor in the first release. Built on the reverse engineering in
[`reverse-engineering/`](reverse-engineering/README.md) and modelled on the
[lazarus-revibed](https://github.com/mbialkowski/lazarus-revibed) remake (same engine, same layout,
same kind of options), adapted to a single-screen puzzle game.

## 1. Goals

* **The original's rules, tick for tick.** Port `tools/hl_sim.py` (itself a routine-by-routine port of
  `HL.EXE` segment `1633`) and run it at the original **8.88 Hz (112.6 ms)** fixed tick. Same levels,
  same inputs on the same ticks → same grids. Anything that departs from the original is an
  *option*, off by default, unless listed in 1.1.
* **Plays anywhere**: a web build (GitHub Pages, installable as a PWA on phones) and desktop, with
  keyboard, gamepad and touch.
* **Modern presentation** around an untouched 320×200 core: crisp HD scaling, widescreen, smooth
  movement as an option, menus, saving.

### 1.1 Deliberate differences (on by default)

* Menus (title, pause, options, controls, level select, editor) instead of the original's
  Space/Enter title.
* Saving is automatic (the original saved solved levels per player too; we keep the three players).

After a solved level the game goes to the **next level number**, as in the original; going to the
next unsolved level is an option, off by default.

Everything else in [05-remake-guide.md §5.2](reverse-engineering/05-remake-guide.md#52-fidelity-checklist)
stays as in the original (scan order, push only on odd ticks, plasma does not kill, explosions can
make a level unsolvable, etc.).

## 2. Engine and project layout

**Godot 4.7, GDScript, "Compatibility" renderer** — as lazarus-revibed: one web export with no special
headers, the same CI and the same test style.

| path | what |
|---|---|
| `remake/data/` | **generated** by `tools/build_remake_data.py` from `original/`: index-image sprite atlas (16×16 + 8×8), font atlas, logo/chaos pictures, palette, `levels.json`, sounds and music (OGG + WAV), texts |
| `remake/scripts/sim/` | the rules: `sim.gd` (grid 22×14, `tick(input)`, the nine handlers — a line-by-line port of `hl_sim.py`), `levels.gd` (LEVELS.HL parser with the original's rules), `rand.gd` (Borland `rand()`, only for start frames and the heart sound) |
| `remake/scripts/game/` | `data.gd` (loading, settings, save), `audio.gd` (two channels like the original + volumes), `strings.gd` (PL/EN), `progress.gd` (players, solved levels) |
| `remake/scripts/view/` | `screen.gd` (draws the grid and status line as palette indices), `palette.gd` + `palette.gdshader` (palette, fades, VGA mono), `tween.gd` (optional smooth movement), `touch.gd` |
| `remake/scripts/main.gd` | screens: start, title, menus, play, pause, level select, options, controls, credits |
| `remake/tests/` | `check.gd`, `golden.gd`, `rules.gd`, `scenarios.gd`, `web_smoke.mjs` |
| `.github/workflows/remake-web.yml` | tests → web export → GitHub Pages |

**Licence**: unlike Lazarus, the whole game is CC BY-SA 2.5, so the published build may contain all
original assets. Code MIT; `remake/data/` and the build's assets CC BY-SA 2.5 with the credits on the
Autorzy/Credits screen and in the README.

## 3. Rendering

* Draw into a **320×200 indexed image** (palette indices), coloured by a shader with the current
  palette → exact restart fades, title fades and the **VGA mono** mode (grey = (r+g+b)/3) as an
  option for free.
* **Sharp-bilinear** scaling (crisp, even pixels at any size) or nearest — option *Skalowanie*.
* **Widescreen**: the 320×192 play-field stays the centre; on wider screens the side bands show a
  frame with the level number, author, hearts left, a mini-map (the original's 8×8 sprites) and the
  option icons; on 4:3 it looks exactly like the original (status line at the bottom).
* **Smooth movement** (option, default off = original look): objects slide between cells during
  the 112.6 ms tick; the logical state is always the one of the last tick, so deaths/explosions stay
  on the same ticks.
* F1 overview: kept (8×8 sprites over the title picture, as the original), also on a touch button.

## 4. Menus and options (as lazarus-revibed)

* **First screen** (needed in the browser to start audio): Polski / English, any key. Upright phone:
  "turn the phone sideways".
* **Title**: logo + the original's rotating credit pages, title tune. Menu: NOWA GRA / GRAJ DALEJ
  (continue at the last level), WYBÓR POZIOMU (level select), EDYTOR (level editor), GRACZ (choose/rename one of 3
  players), OPCJE, STEROWANIE, AUTORZY, WYJŚCIE.
* **Level select**: the 70 levels as mini-maps with solved marks and authors; locked levels? No —
  the original lets you play any level (Space+←/→), keep that.
* **Pause** (Esc is "restart level" in the original, so pause is **P / Start / II**): Graj dalej,
  Restart poziomu, Opcje, Sterowanie, Wyjdź do menu.
* **Options** (`user://settings.cfg`):

| option | values | default | note |
|---|---|---|---|
| Język / Language | Polski, English | first screen | |
| Skalowanie | gładkie / ostre | gładkie | sharp-bilinear / nearest |
| Kolory | VGA / VGA mono | VGA | the original's two graphics modes |
| Płynny ruch | tak / nie | nie | smooth movement (3) |
| Szeroki ekran | tak / nie | tak | side panels on wide screens |
| Pchanie | oryginalne / zawsze | oryginalne | push on odd ticks only, or on every press |
| Po ukończeniu | następny / następny nierozwiązany | następny | as the original |
| Cofanie (undo) | tak / nie | nie | rewind moves (5); off = the original |
| Sterowanie dotykowe | auto / tak / nie | auto | |
| Dźwięk | tak / nie | tak | greys out the rows below |
| Muzyka | 0–100 % | 70 % | in-game music exists in the original (F6) |
| Efekty | 0–100 % | 100 % | |
| Pełny ekran | tak / nie | — | hidden where impossible (iPhone) |

F6/F7/F8 keep working in game and show the original's icons; F8 (joystick) becomes "gamepad on/off".

## 5. Extras that keep the rules intact

* **Undo / rewind**: the state is 4×308 bytes + a few counters; store one snapshot per input tick
  (Backspace / Z / LB / ↶ button). A death can be undone, which makes the destructive levels much
  friendlier. Off → pure original.
* **Saving**: per player: solved levels, current level, settings — after every level and on exit.
  Original `PLAYERn.STT` files can be imported (format in 02-file-formats §2.11).
* **Custom levels**: load a `LEVELS.HL` (desktop: file dialog; web: drag-and-drop / file picker),
  parsed with the original rules and error messages.
* **Level editor** (first release): a 20×12 grid painted with the 13 objects (mouse, keyboard,
  gamepad, touch), author line, checks with the original's errors (12 rows, a dwarf, a door, no
  more than 199 levels), "play from here" with instant return to the editor, undo in the editor,
  level list (add, duplicate, move, delete), saving as a standard `LEVELS.HL` (CR LF, the
  original's legend header) so that levels also work in the original game. Web: export as a
  download, import with the file picker; desktop: `user://levels/*.hl`.
* **Statistics** (optional): moves and time per level, best result.

## 6. Controls

| action | keyboard | gamepad | touch |
|---|---|---|---|
| move / push | arrows, WASD | d-pad, left stick | pad |
| restart level (original Esc) | Esc, R | Back/Select | ⟲ |
| undo | Backspace, Z | LB | ↶ |
| previous / next level | Space + ←/→, PgUp/PgDn | LT / RT | in pause menu |
| overview map | F1, Tab | Y | ⊞ |
| music / sound / gamepad | F6 / F7 / F8 | | options |
| pause | P | Start | II |
| full screen | F11, Alt+Enter | | [ ] |

Input is sampled exactly like the original: held keys plus a latch so a tap shorter than a tick
counts once; one direction per tick with priority right > left > down > up.

## 7. Audio

Two channels like the original (music + effects; effects may overlap only when music is off — or
always, as an option). Samples at 8 522.7 Hz played through Godot's resampler (or pre-resampled by
the build script); the in-game tune as the 197-block sequence (gapless, looping) or the pre-rendered
`ingame.ogg`. Web: the lazarus head script for resuming audio and playing in iPhone silent mode.

## 8. Tests (CI)

* `check.gd` — every script parses.
* `rules.gd` — the cases of `tests/test_sim.py`, run against `sim.gd`.
* `golden.gd` — **golden traces** generated by `tools/make_golden_traces.py` from `hl_sim.py`
  (no emulator): all 70 levels × (idle 300 ticks + the 16-move scenarios + random walks with fixed
  seeds and both parities), full grid compared every tick. `hl_sim.py` itself is checked against the
  original in DOSBox by `tools/golden_check.py` (outside CI).
* `scenarios.gd` — menus, save/load, undo, level change, custom LEVELS.HL errors.
* `solutions.gd` — recorded solutions for levels (collected while play-testing) must still solve
  them.
* `web_smoke.mjs` — the web build boots in headless Chromium and reaches level 1.

## 9. Milestones

| # | deliverable | done when |
|---|---|---|
| M0 | finish the verification: the 6 remaining DOSBox mismatches (levels 20, 21, 25, 26, 42, 50) explained and `hl_sim.py` fixed if needed | 70/70 with moves |
| M1 | `build_remake_data.py`, `make_golden_traces.py`; Godot project skeleton; `sim.gd` port | `golden.gd` passes on all traces |
| M2 | playable core: indexed renderer, status line, input, tick loop, restart/next level, sounds, music | level 1–70 playable on desktop |
| M3 | menus, options, players and saving, level select, credits, PL/EN | all screens reachable by keyboard and gamepad |
| M4 | web export, CI + Pages, touch controls, phone layout, PWA | playable on a phone |
| M5 | extras: widescreen panels, smooth movement, undo, custom LEVELS.HL | options work, tests green |
| M6 | level editor: painting, checks, play-test, level list, LEVELS.HL save/load (desktop and web) | a saved file plays in the original in DOSBox |
| M7 | polish: screenshots, README, solutions collected for all 70 levels | first release |

## 10. Decisions (confirmed)

1. **Godot 4.7**, like lazarus-revibed.
2. **Polski by default**; English selectable on the first screen and in the options.
3. **Original behaviour by default**: next level number after a solved level, push only on odd
   ticks, no smooth movement, no undo — all of them available as options.
4. **Level editor in the first release** (milestone M6).
