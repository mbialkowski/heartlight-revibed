# Heartlight: Revibed — the Godot 4 remake

Work in progress, following [the plan](../docs/remake-plan.md). Current milestone: **M1 done** —
the game rules run in Godot and match the original tick for tick; nothing is drawn yet (M2).

## What is here

| path | what |
|---|---|
| `data/` | **generated** by `tools/build_remake_data.py` (index-image sprites/font/pictures, palette, levels, sounds, music blocks, `game.json`) and `tools/make_golden_traces.py` (`golden_traces.json`); never edit by hand |
| `scripts/sim/sim.gd` | the rules: a line-by-line port of `tools/hl_sim.py` (itself a port of `HL.EXE` segment 1633, verified against the original in DOSBox on all 70 levels) |
| `scripts/sim/levels.gd` | `LEVELS.HL` parser with the original's rules and error messages |
| `scripts/sim/rand.gd` | Borland `rand()` (start frames of hearts/balloons, heart-landing sound) |
| `scripts/game/data.gd` | autoload `Data`: loads the bundle |
| `tests/` | `check.gd` (scripts parse, data present), `rules.gd` (single rules, as `tests/test_sim.py`), `golden.gd` (280 traces, 91 000 ticks: state hash, sounds and grids every tick) |

## Running the tests

```bash
python3 tools/build_remake_data.py original/ remake/data/          # after changing the converter
python3 tools/make_golden_traces.py original/LEVELS.HL tests/golden_scenarios.json remake/data/golden_traces.json
godot --headless --path remake --import
godot --headless --path remake --script res://tests/check.gd
godot --headless --path remake --script res://tests/rules.gd
godot --headless --path remake --script res://tests/golden.gd
```

CI (`.github/workflows/remake.yml`) runs the Python tests, checks that `remake/data` is up to date
and runs the three Godot tests. Godot 4.7.2.

## Licence

The remake's code is MIT. `data/` is converted from Heartlight PC and, like the game, licensed
under Creative Commons Attribution-ShareAlike 2.5 (credits in the main README).
