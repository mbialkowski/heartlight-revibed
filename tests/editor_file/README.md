# A level file saved by the remake's editor, played by the original

`LEVELS.HL` was written by the remake's level editor code (`remake/scripts/game/level_set.gd`):
the original 70 levels with level 1 changed (a rock, a bomb, an empty cell) and a new level 2
("author: Editor Test", made from the editor's template with rocks, a heart, a balloon, plasma,
bricks and tunnels). The original `HL.EXE` reads it and plays it exactly as the remake's rules
predict:

```bash
mkdir -p /tmp/edtest && cp original/HL.EXE tests/editor_file/LEVELS.HL /tmp/edtest/
Xvfb :97 &
python3 tools/golden_check.py /tmp/edtest --levels 1-3 --display :97 --script tests/editor_file/moves.json
# level  1 OK  RRDD
# level  2 OK  DRRRRDDLL
# level  3 OK
# 3 / 3 levels match
```
