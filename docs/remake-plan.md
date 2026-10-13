# Heartlight: Revibed — remake implementation plan

Status: **M0–M4 done** (rules verified against the original; ported to Godot, 280/280 golden
traces; playable on desktop with menus, options, controls and saving; rendering pixel-exact; web build with touch controls for phones) — see [`remake/`](../remake/README.md). Decisions confirmed (section 10): Godot 4.7, Polish by
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

## 4. Menus and options — requirements

Modelled on lazarus-revibed; all texts in Polish and English (`strings.gd`), drawn with the
original's 16×8 font where its characters suffice (menus use only those characters and the
original's colours: yellow / green / blue).

### 4.1 General menu requirements

* **R-M1** Every menu is usable with keyboard (arrows/WASD, Enter/Space confirm, Esc/Backspace
  back), gamepad (d-pad/stick, A confirm, B back), mouse (hover + click) and touch (tap) — no
  screen needs a device that is not present.
* **R-M2** One highlighted item at a time; ↑/↓ moves (wraps), ←/→ changes the value of an option
  row, confirm on an option row cycles its value. Greyed-out rows are skipped.
* **R-M3** "Back" always returns to the previous screen; changes in options apply immediately and
  are saved to `user://settings.cfg` (web: browser storage) when leaving the screen.
* **R-M4** Menu sounds: the original's `key` sample on change/confirm; the title tune on the title
  screen and its submenus; the in-game music (if on) continues under the pause menu.
* **R-M5** Menus scale with the window like the game (sharp pixels) and fit both 4:3 and 16:9,
  and a phone held upright.

### 4.2 Menu tree

```
First screen (Polski / English; "turn the phone sideways" when upright)
└─ Title (logo, rotating credit pages, current player, title tune)
   ├─ NOWA GRA            start at level 1 (asks before resetting the player's progress)
   ├─ GRAJ DALEJ          continue at the player's current level (greyed out without a save)
   ├─ WYBÓR POZIOMU       level select
   ├─ EDYTOR              level editor (5)
   ├─ GRACZ               choose one of 3 players, rename, reset progress
   ├─ OPCJE               options (4.4)
   ├─ STEROWANIE          controls (4.5)
   ├─ AUTORZY             credits (original credits + CC BY-SA notice + remake credits)
   └─ WYJŚCIE             desktop: quit (the original's "press y to quit" confirmation);
                          web: thank-you screen
In game: Pause (P / Start / II)
   ├─ GRAJ DALEJ
   ├─ RESTART POZIOMU     the original's Esc
   ├─ WYBÓR POZIOMU
   ├─ OPCJE
   ├─ STEROWANIE
   └─ WYJDŹ DO MENU
```

### 4.3 Screens

* **Level select**: grid of the 70 levels (or of a loaded `LEVELS.HL`) as 8×8 mini-maps with
  number, author, solved mark (the original's ✓ icon) and hearts count; all levels playable, as
  in the original. Counter "solved / total". Confirm plays, a second action opens it in the
  editor.
* **Player** (GRACZ): the original's three slots with names and solved counts; rename with the
  keyboard or an on-screen keyboard (gamepad/touch) limited to the font's characters; reset
  progress with confirmation; import of original `PLAYERn.STT`.
* **Credits** (AUTORZY): Janusz Pelc; Maciej Miąsik, Paweł Wyrzycki, Marek Kubowicz; level
  authors; Epic MegaGames and Xland 1994; CC release 2006; the licence text link; remake credits.

### 4.4 Options (OPCJE)

Grouped in four pages (Gra / Obraz / Dźwięk / Sterowanie), stored in `user://settings.cfg`.
Defaults reproduce the original.

| page | option | values | default | note |
|---|---|---|---|---|
| Gra | Język / Language | Polski, English | first screen | |
| Gra | Pchanie | oryginalne / zawsze | oryginalne | push on odd ticks only, or on every press |
| Gra | Po ukończeniu | następny / następny nierozwiązany | następny | |
| Gra | Cofanie (undo) | tak / nie | nie | rewind moves (5) |
| Gra | Prędkość | 100 % / 75 % / 50 % | 100 % | slower tick for beginners (rules unchanged) |
| Obraz | Skalowanie | gładkie / ostre | gładkie | sharp-bilinear / nearest |
| Obraz | Kolory | VGA / VGA mono | VGA | the original's two graphics modes |
| Obraz | Płynny ruch | tak / nie | nie | smooth movement (3) |
| Obraz | Szeroki ekran | tak / nie | tak | side panels on wide screens |
| Obraz | Mapa (F1) | nie / tak | nie | start levels in the overview |
| Obraz | Pełny ekran | tak / nie | — | hidden where impossible (iPhone) |
| Dźwięk | Dźwięk | tak / nie | tak | greys out the rows below |
| Dźwięk | Muzyka w grze | tak / nie | tak | the original's F6 |
| Dźwięk | Muzyka | 0–100 % | 70 % | |
| Dźwięk | Efekty | 0–100 % | 100 % | the original's F7 = on/off |
| Dźwięk | Nakładanie efektów | oryginalne / zawsze | oryginalne | effects overlap only when music is off, or always |
| Sterowanie | → the Controls screen (4.5) | | | |

F6/F7/F8 keep working in game, change the same settings and show the original's icons; F8
(joystick) becomes "gamepad on/off".

### 4.5 Controls (STEROWANIE)

One screen, reachable from the title, the pause menu and the options, with three tabs —
**Klawiatura**, **Pad**, **Dotyk** — opening on the device last used:

* **R-C1** Shows every action with its current bindings (and, on the Dotyk tab, a picture of the
  touch layout with labelled buttons), so it doubles as the help screen.
* **R-C2** Remapping: select an action, press the new key / button (Esc or B cancels); up to two
  bindings per action on keyboard and gamepad. A key already used by another action is swapped
  with it after a warning, never silently duplicated.
* **R-C3** "Przywróć domyślne" (reset to defaults) per tab, with confirmation.
* **R-C4** Actions that can never be left unbound: the four directions, pause, menu confirm/back;
  the menu keeps working with the defaults even if game bindings are changed.
* **R-C5** Pad: stick dead zone (10–50 %, default 25 % — the original's joystick used ±50 %),
  d-pad and stick both move, vibration on death (tak/nie, default nie).
* **R-C6** Dotyk: touch controls auto / tak / nie (auto = on touch screens); pad size
  (S/M/L), opacity (25–100 %), layout for left- or right-handed play; landscape: over the picture,
  portrait: below it.
* **R-C7** "Przytrzymanie" (hold to repeat) is not an option: a held direction moves every tick
  exactly as in the original; a tap counts for one tick (the original's key latch, 6).
* **R-C8** Bindings are saved with the options and survive updates; unknown/removed actions in an
  old settings file are ignored.

Actions and default bindings are listed in section 6.

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

## 6. Controls — actions and default bindings (remappable, 4.5)

| action | keyboard | gamepad | touch |
|---|---|---|---|
| move / push | arrows, WASD | d-pad, left stick | pad |
| restart level (original Esc) | Esc, R | Back/Select | ⟲ |
| undo | Backspace, Z | LB | ↶ |
| previous / next level | Space + ←/→, PgUp/PgDn | LT / RT | in pause menu |
| overview map | F1, Tab | Y | ⊞ |
| music / sound / gamepad | F6 / F7 / F8 | | options |
| pause / menu | P | Start | II |
| menu confirm / back | Enter, Space / Esc, Backspace | A / B | tap / ✕ |
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
* `scenarios.gd` — menus (navigation with each device), options saved and restored, remapping
  (swap on conflict, reset to defaults, mandatory actions), save/load, undo, level change, custom
  LEVELS.HL errors.
* `solutions.gd` — recorded solutions for levels (collected while play-testing) must still solve
  them.
* `web_smoke.mjs` — the web build boots in headless Chromium and reaches level 1.

## 9. Milestones

| # | deliverable | done when |
|---|---|---|
| M0 ✓ | finish the verification against the original in DOSBox | 70/70 with moves |
| M1 ✓ | `build_remake_data.py`, `make_golden_traces.py`; Godot project skeleton; `sim.gd` port | `golden.gd` passes on all traces (280/280, 91 000 ticks) |
| M2 ✓ | playable core: indexed renderer, status line, input, tick loop, restart/next level, sounds, music | level 1–70 playable on desktop; level 1 renders pixel-exact |
| M3 ✓ | menus (4.2–4.3), options (4.4), controls screen with remapping (4.5), players and saving, level select, credits, PL/EN | R-M1…R-M5 and R-C1…R-C8 met; every screen reachable by keyboard, gamepad, mouse and touch |
| M4 ✓ | web export, CI + Pages, touch controls, phone layout, PWA | playable on a phone |
| M5 | extras: widescreen panels, smooth movement, undo, custom LEVELS.HL | options work, tests green |
| M6 | level editor: painting, checks, play-test, level list, LEVELS.HL save/load (desktop and web) | a saved file plays in the original in DOSBox |
| M7 | polish: screenshots, README, solutions collected for all 70 levels | first release |

## 10. Decisions (confirmed)

1. **Godot 4.7**, like lazarus-revibed.
2. **Polski by default**; English selectable on the first screen and in the options.
3. **Original behaviour by default**: next level number after a solved level, push only on odd
   ticks, no smooth movement, no undo — all of them available as options.
4. **Level editor in the first release** (milestone M6).
