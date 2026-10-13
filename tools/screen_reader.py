#!/usr/bin/env python3
"""Reads the play-field back out of a 320x200 DOSBox screenshot of Heartlight PC.

Each 16x16 cell is matched against the 16x16 sprites of hl.ggs (transparent pixels drawn as
colour 0), giving (type, frame) per cell. Used to compare the original against tools/hl_sim.py.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hl_gfx import read_ggs  # noqa: E402

TYPE_CHAR = {0: ' ', 1: 'x', 2: '#', 3: '%', 4: '@', 5: '$', 6: '&', 7: '.', 8: '*', 9: '!', 10: '0',
             11: '=', 12: '<', 13: '>'}


class ScreenReader:
    def __init__(self, ggs_bytes):
        _, sprites = read_ggs(ggs_bytes)
        self.table = {}
        self.alias = {}      # (type, frame) -> first (type, frame) with an identical image
        base = {}
        for s in sprites:
            if s is None:
                continue
            t = s.obj_type
            base.setdefault(t, s.slot)
            key = bytes(0 if v is None else v for v in s.crop(0, 0, 16, 16))
            self.table.setdefault(key, (t, s.slot - base[t]))
            self.alias[(t, s.slot - base[t])] = self.table[key]

    def read(self, img):
        """img: PIL 'P' image 320x200 (DOSBox capture). Returns 12 rows of 20 (type, frame)
        tuples; None where no sprite matches."""
        px = img.load()
        grid = []
        for y in range(12):
            row = []
            for x in range(20):
                key = bytes(px[x * 16 + i, y * 16 + j] for j in range(16) for i in range(16))
                row.append(self.table.get(key))
            grid.append(row)
        return grid

    @staticmethod
    def text(grid):
        return '\n'.join(''.join('?' if c is None else TYPE_CHAR[c[0]] for c in row) for row in grid)


if __name__ == '__main__':
    from PIL import Image
    from hl_volume import Volume
    r = ScreenReader(Volume(sys.argv[1]).read('hl.ggs'))
    for f in sys.argv[2:]:
        print(f)
        print(ScreenReader.text(r.read(Image.open(f))))
