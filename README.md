# Heartlight: Revibed

A modern remake of **Heartlight PC**, built on a complete reverse engineering of the original, (Janusz Pelc / Xland,
published by Epic MegaGames in 1994, released under Creative Commons BY-SA 2.5 in 2006) — a
*Boulder Dash*-style puzzle game: guide the dwarf, collect every heart, reach the door, and don't
let a rock fall on your head.

| the original (DOSBox) | the remake | the remake's level editor |
|---|---|---|
| ![](docs/images/original/05_level01.png) | ![](docs/images/remake/wide.png) | ![](docs/images/remake/editor.png) |

## The remake

[`remake/`](remake/README.md) — Godot 4.7, for desktop (Linux, Windows) and the web (also on
phones, installable as an app):

* **The original's rules tick for tick** (a line-by-line port of the verified simulator; 280 golden
  traces in CI) and **its graphics pixel for pixel** (indexed rendering with the original palette,
  checked against the original's screenshot in CI), sounds and music.
* Menus in Polish and English with the original's font; options (the original's behaviour by
  default: pushing on odd ticks, the next level after a solved one); controls remappable for
  keyboard and gamepad, touch controls for phones; three players with saving, import of the
  original's `PLAYER?.STT`.
* Extras, all optional: wide-screen side panels, smooth movement, undo, slower speed, VGA mono.
* Other `LEVELS.HL` files and a **level editor** whose files play in the original game.
* Recorded solutions for 32 levels (found by a solver running the same rules) are replayed in CI.

Builds: the *Release* workflow attaches Linux, Windows and web archives to a GitHub release when
a `v*` tag is pushed; the *Remake* workflow publishes the web build on GitHub Pages from `main`.

## What is here

* [`docs/reverse-engineering/`](docs/reverse-engineering/README.md) — complete write-up of the
  executable, every file format (including the encrypted, packed resource volume hidden in
  `HL.EXE`), **the exact game rules** (grid, tick, scan order, falling, rolling, pushing, bombs,
  balloons, tunnels, timing, input), the 70 levels, and a remake guide with a fidelity checklist.
* [`assets/`](assets/README.md) — every asset converted to modern formats: sprites (PNG, sheets,
  Tiled tileset), font, pictures, palette, sound effects and music (WAV), the 70 levels (JSON,
  PNG, Tiled maps), texts and a game-data table.
* [`tools/`](tools/) — the Python tools that produced all of this, including
  [`hl_sim.py`](tools/hl_sim.py), the game rules ported routine by routine from the executable,
  and [`golden_check.py`](tools/golden_check.py), which plays the original in DOSBox and checks
  every captured frame against the simulator.
* [`reference/`](reference/README.md) — annotated disassembly of `HL.EXE`.
* [`docs/remake-plan.md`](docs/remake-plan.md) — the plan for the Godot remake (requirements, decisions, milestones); [`remake/`](remake/README.md) — the remake.
* [`tests/`](tests/README.md) — simulator unit tests, the DOSBox scenarios and their report.
* [`original/`](original/README.md) — the original 2006 release files (CC BY-SA 2.5) and a
  DOSBox config.

## Verified against the original

The simulator matches the original on all 70 levels, both left alone and with a 16-move
random walk per level that collects, pushes, rolls, blows up, dies, restarts and travels through
tunnels — every frame captured from DOSBox is a state the simulator reaches
([3.14](docs/reverse-engineering/03-engine.md#314-verification),
[`tests/golden_report.json`](tests/golden_report.json)).

## How it was made

Everything in this repository (the reverse engineering of the executable and data files, the
documentation, the Python tools and tests, the remake) was produced by **Claude**, Anthropic's AI model,
working in Claude Code under the supervision of a human (the repository owner), following the
approach of the sister project
[lazarus-revibed](https://github.com/mbialkowski/lazarus-revibed).

## Regenerating

```bash
pip install -r tools/requirements.txt
python3 tools/extract_assets.py original/ assets/                  # all assets
python3 tools/disasm.py original/HL.EXE -o reference/hl.asm         # disassembly
python3 tests/test_sim.py                                           # simulator unit tests
cd original && dosbox -conf dosbox.conf                              # play the original
# golden check against the original (needs DOSBox, Xvfb, xdotool):
Xvfb :99 & DISPLAY=:99 python3 tools/golden_check.py original/ --levels 1-70 \
    --script tests/golden_scenarios.json --out tests/golden_report.json
```

## License

* **Code and documentation written for this project are MIT licensed** (see [`LICENSE`](LICENSE)):
  `tools/`, `tests/`, `docs/` (text), `reference/README.md` and the remake's code (`remake/` except `remake/data/`).
* **The game and everything derived from it are licensed under Creative Commons
  Attribution-ShareAlike 2.5** ([`original/README.TXT`](original/README.TXT),
  <https://creativecommons.org/licenses/by-sa/2.5/>): the original files in `original/`, the
  converted assets in `assets/` and `remake/data/`, the disassembly `reference/hl.asm`, and the screenshots in
  `docs/images/`. Heartlight PC was created by Janusz Pelc (programming, graphics, music) with
  Maciej Miąsik, Paweł Wyrzycki and Marek Kubowicz; levels by Janusz Pelc, Marek Kubowicz,
  Maciej Janiec, Maciej Mach, Marek Kubas and Jacek Aleksandrow; originally published in 1994 by
  Epic MegaGames and Xland; Creative Commons release 2006 by Maciej Miąsik. Epic Games has no
  part in this project or in the 2006 release.
