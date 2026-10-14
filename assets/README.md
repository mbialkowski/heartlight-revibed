# Converted assets

Everything here was produced from [`original/`](../original/README.md) by
`python3 tools/extract_assets.py original/ assets/`. It is derived from Heartlight PC and therefore
licensed, like the game, under **Creative Commons Attribution-ShareAlike 2.5** (credits in the
main README). Formats and meaning are documented in
[02-file-formats.md](../docs/reverse-engineering/02-file-formats.md).

| folder | contents |
|---|---|
| `volume/` | the 40 files of the resource volume inside `HL.EXE`, decrypted and unpacked (`volume.json`: directory with original dates) |
| `palette/` | the game palette and the "VGA mono" palette: `.pal` (768 bytes, 6-bit VGA), `.gpl` (GIMP), `.png` swatch |
| `sprites/` | `hl/NN_type_frame.png`: the 63 game sprites, 16×16 RGBA (transparent where the original is), and `_mini.png` 8×8 overview versions; `hl_sheet.png` (8 per row, slot order), `hl_sheet_mini.png`, `hl_cells_24x24.png` (the raw cells), `hl_sheet_x3.png` (preview); `hl.json`: slot → type, frame; `heartlight.tsj`: Tiled tileset |
| `font/` | the 16×8 font: `font_sheet.png` (all three colours), `font_yellow/green/blue.png`, `font.json` (character → glyph, Polish letters) |
| `pictures/` | `logo.png` (192×120, title), `chaos.png` (192×192, start-up) |
| `sounds/` | the 13 effects and the title tune, WAV 8-bit unsigned mono at 8 523 Hz; `sounds.json` says when each plays |
| `music/` | `blocks/a.wav`…`t.wav`: the 20 two-second music blocks; `ingame.wav`: the whole in-game tune (197 blocks, 6:32, loops); `music.json`: the sequence |
| `levels/` | `levels.json` (rows, author, object counts), `png/level_NN.png` (320×192 renders), `tiled/level_NN.tmj` (Tiled maps using `sprites/heartlight.tsj`), `levels_overview.png` |
| `text/` | `loading_ted.txt/json` (the text-mode loading window), `strings.json` (all strings of the data segment) |
| `gamedata/` | `game_data.json`: object types (chars, initial states, sprite bases, frame counts), grid, timing, timers, keys, sound triggers |

Notes for using them in a remake:

* Sprite = `sprite_base[type] + frame` (see `hl.json` / `game_data.json`). Hearts, balloons and
  plasma animate every tick; the explosion plays frames 0–6 (images 0 1 2 3 2 1 0).
* Level renders use frame 0 for hearts and balloons (the original picks a random start frame).
* The WAVs keep the original 8-bit samples; resample with care (the original plays them at
  8 522.7 Hz with no filtering).
