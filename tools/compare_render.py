#!/usr/bin/env python3
"""Compares a screen rendered by the remake (red channel = palette index, from
remake/tests/render_dump.gd) with a screenshot of the original (compared in RGB through the
game palette).

    python3 tools/compare_render.py rendered.png original.png [--ignore x,y,w,h ...]

Prints the number of differing pixels and their bounding boxes per 16x16 cell.
"""
import argparse
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hl_gfx import vga_palette  # noqa: E402

PAL, _ = vga_palette(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'original', 'HL.EXE'))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('rendered')
    ap.add_argument('original')
    ap.add_argument('--ignore', action='append', default=[], help='x,y,w,h rectangle to skip')
    ap.add_argument('--ignore-hearts', type=int, metavar='LEVEL',
                    help='skip the cells of the hearts of this level (random start frames)')
    a = ap.parse_args()
    r = Image.open(a.rendered).convert('RGBA').load()
    o = Image.open(a.original).convert('RGB')
    assert o.size == (320, 200), 'need a 320x200 capture'
    o = o.load()
    ignore = [tuple(int(v) for v in s.split(',')) for s in a.ignore]
    if a.ignore_hearts:
        from hl_levels import load
        rows = load(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'original',
                                 'LEVELS.HL'))[a.ignore_hearts - 1].rows
        ignore += [(x * 16, y * 16, 16, 16) for y in range(12) for x in range(20) if rows[y][x] == '$']
    cells = {}
    n = 0
    for y in range(200):
        for x in range(320):
            if any(ix <= x < ix + iw and iy <= y < iy + ih for ix, iy, iw, ih in ignore):
                continue
            i = r[x, y][0]
            if tuple(PAL[3 * i:3 * i + 3]) != o[x, y]:
                n += 1
                cells.setdefault((x // 16, y // 16 if y < 192 else 'status'), []).append((x, y))
    print(f'{n} differing pixels')
    for k, v in sorted(cells.items(), key=lambda kv: str(kv[0])):
        print('cell', k, len(v), 'e.g.', v[:3])
    return 1 if n else 0


if __name__ == '__main__':
    sys.exit(main())
