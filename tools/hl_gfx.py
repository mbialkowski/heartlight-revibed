#!/usr/bin/env python3
"""Readers for the graphics of Heartlight PC: GGE sprite files (*.ggs) and the VGA palette.

GGS ("GGE file: sprites (ver 1.8)", Janusz Pelc's sprite editor):
  0x00  char  text[32]   " GGE file: sprites (ver 1.8) \\r\\n\\x1a"
  0x20  u8    info[16]   (07 03 03 02 ... for 24x24 cells; font.ggs: 34 09 03 02)
  0x30  64 x { u8 used (0xFF = empty slot; nothing follows)
               u8 pixels[24*24]   0xFF = transparent, else index into remap[]
               u8 remap[64]       local colour -> VGA palette index
               u8 meta[8]         meta[0] = object type + 1 (0 = none), meta[1] bit 7 = group start
               u8 box[4]          editor data (not used by the game)
               u8 stats[36] }     editor data (not used by the game)
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from mz_loader import MZ  # noqa: E402

DGROUP = 0x214D
PALETTE_OFF = 0x0B00
CELL = 24
ENTRY = 688


def vga_palette(exe_path):
    """256 RGB triples (8-bit) from the 6-bit palette at DS:0B00, expanded like DOSBox does."""
    mz = MZ(exe_path)
    pal6 = mz.read(DGROUP, PALETTE_OFF, 768)
    return [((v << 2) | (v >> 4)) for v in pal6], pal6


def mono_palette(pal6):
    """'VGA mono' mode (CONFIG option 'm'): grey = (r + g + b) / 3 (1CE9:004B)."""
    out = []
    for i in range(256):
        g = (pal6[3 * i] + pal6[3 * i + 1] + pal6[3 * i + 2]) // 3
        out += [g, g, g]
    return [((v << 2) | (v >> 4)) for v in out]


class Sprite:
    def __init__(self, slot, raw):
        self.slot = slot
        self.local = raw[:576]
        self.remap = raw[576:640]
        self.meta = raw[640:648]
        self.box = raw[648:652]
        self.stats = raw[652:688]
        # VGA indices, None = transparent
        self.pixels = [None if v == 0xFF else self.remap[v] for v in self.local]

    @property
    def obj_type(self):
        return self.meta[0] - 1 if self.meta[0] else None

    @property
    def group_start(self):
        return bool(self.meta[1] & 0x80)

    def crop(self, x0, y0, w, h):
        return [self.pixels[(y0 + y) * CELL + x0 + x] for y in range(h) for x in range(w)]


def read_ggs(data):
    header = data[:48]
    sprites = []
    p = 48
    for slot in range(64):
        used = data[p]
        p += 1
        if used == 0xFF:
            sprites.append(None)
            continue
        sprites.append(Sprite(slot, data[p:p + ENTRY]))
        p += ENTRY
    assert p == len(data), (p, len(data))
    return header, sprites


def to_image(pixels, w, h, palette, transparent=None):
    from PIL import Image
    if transparent is None:
        img = Image.new('P', (w, h))
        img.putpalette(palette)
        img.putdata([0 if v is None else v for v in pixels])
        return img
    img = Image.new('RGBA', (w, h))
    img.putdata([(0, 0, 0, 0) if v is None else (palette[3 * v], palette[3 * v + 1], palette[3 * v + 2], 255)
                 for v in pixels])
    return img
