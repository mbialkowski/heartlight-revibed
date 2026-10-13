# Heartlight: Revibed — the Godot 4 remake

Work in progress, following [the plan](../docs/remake-plan.md). **M3 done**: all 70 levels with
the original's rules (tick for tick), graphics (pixel for pixel), sounds and music; title, pause,
options, controls with remapping, level select, three players with saving, credits, Polish and
English. Web build, touch and phones come with M4.

| title | level select | play |
|---|---|---|
| ![](../docs/images/remake/title.png) | ![](../docs/images/remake/levels.png) | ![](../docs/images/remake/level01_m2.png) |
| options | controls | pause |
| ![](../docs/images/remake/options.png) | ![](../docs/images/remake/controls.png) | ![](../docs/images/remake/pause.png) |

## Playing

`godot --path remake` (Godot 4.7.2); `-- --level=N` starts playing level N at once.

Default keys (all remappable in STEROWANIE / CONTROLS):

| action | keyboard | gamepad |
|---|---|---|
| move / push | arrows, WASD | d-pad, left stick |
| restart the level (the original's Esc) | Esc, R | Back |
| undo (option *cofanie*, off by default) | Backspace, Z | LB |
| previous / next level | Space + ←/→, PgUp / PgDn | |
| overview map | F1, Tab | Y |
| music / sound / gamepad on-off | F6 / F7 / F8 | |
| pause menu | P | Start |
| back to the title | F10 | |
| full screen | F11 | |

Menus: arrows/WASD, Enter/Space, Esc/Backspace; gamepad d-pad/stick, A, B; mouse and touch.
Settings are saved in `user://settings.cfg`, the players in `user://players.json`.

Texts use only the characters of the original's font (a–z, Polish letters, digits, `:` `.`), drawn
on a 640x400 layer over the 320x200 screen: the original's glyphs at half size, 40 per line.

## What is here

| path | what |
|---|---|
| `data/` | **generated** by `tools/build_remake_data.py` (index-image sprites/font/pictures, palette, levels, sounds, music blocks, `game.json`) and `tools/make_golden_traces.py` (`golden_traces.json`); never edit by hand |
| `scripts/sim/sim.gd` | the rules: a line-by-line port of `tools/hl_sim.py` (itself a port of `HL.EXE` segment 1633, verified against the original in DOSBox on all 70 levels) |
| `scripts/sim/levels.gd` | `LEVELS.HL` parser with the original's rules and error messages |
| `scripts/sim/rand.gd` | Borland `rand()` (start frames of hearts/balloons, heart-landing sound) |
| `scripts/game/data.gd` | autoload `Data`: loads the bundle |
| `scripts/game/audio.gd` | the original's two channels: music loop (197 blocks) and effects |
| `scripts/game/settings.gd` | options, bindings (swap on conflict, defaults), input map |
| `scripts/game/progress.gd` | three players, solved levels per level file, current level |
| `scripts/game/strings.gd` | Polish and English texts |
| `scripts/view/text_layer.gd` | the 640x400 menu layer |
| `scripts/view/screen.gd` | the 320x200 screen in palette indices: cells, status line, icons, overview |
| `scripts/view/palette.gd`, `palette.gdshader` | palette (fades, VGA mono) and sharp-bilinear scaling |
| `scripts/main.gd` | the screens and the play loop (tick, restart fade, level slide, undo) |
| `tests/` | `check.gd` (scripts parse, data present), `rules.gd` (single rules, as `tests/test_sim.py`), `golden.gd` (280 traces, 91 000 ticks: state hash, sounds and grids every tick), `scenarios.gd` (48 checks: menus, options, remapping, players, saving, undo, level change), `render_dump.gd` (renders screens for `tools/compare_render.py`, which compares them with the original's screenshot: 0 differing pixels) |

## Running the tests

```bash
python3 tools/build_remake_data.py original/ remake/data/          # after changing the converter
python3 tools/make_golden_traces.py original/LEVELS.HL tests/golden_scenarios.json remake/data/golden_traces.json
godot --headless --path remake --import
godot --headless --path remake --script res://tests/check.gd
godot --headless --path remake --script res://tests/rules.gd
godot --headless --path remake --script res://tests/golden.gd
```

CI (`.github/workflows/remake.yml`) runs the Python tests, checks that `remake/data` is up to date,
runs the Godot tests and compares the rendered level 1 with the original's screenshot. Godot 4.7.2.

## Licence

The remake's code is MIT. `data/` is converted from Heartlight PC and, like the game, licensed
under Creative Commons Attribution-ShareAlike 2.5 (credits in the main README).
