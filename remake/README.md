# Heartlight: Revibed — the Godot 4 remake

Work in progress, following [the plan](../docs/remake-plan.md). **M2 done**: all 70 levels are
playable on desktop with the original's rules (tick for tick), graphics (pixel for pixel), status
line, sounds and music. Menus, options and saving come with M3.

![Level 1](../docs/images/remake/level01_m2.png)

## Playing

`godot --path remake` (Godot 4.7.2), or `godot --path remake -- --level=N` to start at level N.

| key | |
|---|---|
| arrows, WASD (gamepad: d-pad, stick) | move / push |
| Esc, R | restart the level (the dwarf explodes, as in the original) |
| Space + ←/→, PgUp/PgDn | previous / next level |
| F1, Tab | overview map |
| F6 / F7 / F8 | music / sound / gamepad on-off (with the original's icons) |
| F11 | full screen |
| F10 | quit (until the title screen exists) |

## What is here

| path | what |
|---|---|
| `data/` | **generated** by `tools/build_remake_data.py` (index-image sprites/font/pictures, palette, levels, sounds, music blocks, `game.json`) and `tools/make_golden_traces.py` (`golden_traces.json`); never edit by hand |
| `scripts/sim/sim.gd` | the rules: a line-by-line port of `tools/hl_sim.py` (itself a port of `HL.EXE` segment 1633, verified against the original in DOSBox on all 70 levels) |
| `scripts/sim/levels.gd` | `LEVELS.HL` parser with the original's rules and error messages |
| `scripts/sim/rand.gd` | Borland `rand()` (start frames of hearts/balloons, heart-landing sound) |
| `scripts/game/data.gd` | autoload `Data`: loads the bundle |
| `scripts/game/audio.gd` | the original's two channels: music loop (197 blocks) and effects |
| `scripts/game/controls.gd` | actions, default bindings, the original's input latch and priority |
| `scripts/view/screen.gd` | the 320x200 screen in palette indices: cells, status line, icons, overview |
| `scripts/view/palette.gd`, `palette.gdshader` | palette (fades, VGA mono) and sharp-bilinear scaling |
| `scripts/main.gd` | the play screen: tick loop, restart fade, level slide |
| `tests/` | `check.gd` (scripts parse, data present), `rules.gd` (single rules, as `tests/test_sim.py`), `golden.gd` (280 traces, 91 000 ticks: state hash, sounds and grids every tick), `render_dump.gd` (renders screens for `tools/compare_render.py`, which compares them with the original's screenshot: 0 differing pixels) |

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
