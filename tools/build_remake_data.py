#!/usr/bin/env python3
"""Builds the Godot remake's data bundle (remake/data/) from the original files.

    python3 tools/build_remake_data.py original/ remake/data/

Images are *index images*: the red channel holds the VGA palette index (alpha 0 = transparent),
so the remake can colour them with a palette shader (fades, VGA mono) exactly like the original.

  game.json          object types, sprite bases, timing, sound names, music sequence, credits
  palette.json       256 RGB (8-bit) + the 'VGA mono' variant
  levels.json        the 70 levels of LEVELS.HL (rows, author)
  LEVELS.HL          the original level file (the remake parses it itself)
  sprites.png        hl.ggs: 8 x 8 cells of 16x16 (slot order)
  sprites_mini.png   the 8x8 overview versions, 8 x 8 cells
  font.png           font.ggs: 16 x 4 cells of 16x24 (three colours stacked)
  logo.png chaos.png pictures
  sounds.bin         all samples (effects, title tune, music blocks "!a".."!t"), raw signed
                     8-bit at 8523 Hz; index in game.json "sounds"
"""
import argparse
import json
import os
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image  # noqa: E402

from extract_assets import SAMPLE_RATE, FONT_CHARS, FONT_POLISH, SOUND_USE, MUSIC_SEQ_OFF, DGROUP  # noqa
from hl_gfx import read_ggs, vga_palette, mono_palette  # noqa: E402
from hl_levels import load as load_levels  # noqa: E402
from hl_sim import SPRITE_BASE, TYPE_NAMES  # noqa: E402
from hl_volume import Volume  # noqa: E402
from mz_loader import MZ  # noqa: E402


def index_image(pixels, w, h):
    img = Image.new('RGBA', (w, h))
    img.putdata([(0, 0, 0, 0) if v is None else (v, 0, 0, 255) for v in pixels])
    return img


def sheet(sprites, box, cols, rows):
    x0, y0, w, h = box
    out = Image.new('RGBA', (cols * w, rows * h), (0, 0, 0, 0))
    for i, s in enumerate(sprites[:cols * rows]):
        if s is not None:
            out.paste(index_image(s.crop(x0, y0, w, h), w, h), ((i % cols) * w, (i // cols) * h))
    return out


def picture(sprites, cols, rows):
    out = Image.new('RGBA', (cols * 24, rows * 24), (0, 0, 0, 0))
    for i, s in enumerate(sprites[:cols * rows]):
        if s is not None:
            out.paste(index_image(s.crop(0, 0, 24, 24), 24, 24), ((i % cols) * 24, (i // cols) * 24))
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('game_dir')
    ap.add_argument('out_dir')
    a = ap.parse_args()
    exe = os.path.join(a.game_dir, 'HL.EXE')
    out = a.out_dir
    os.makedirs(out, exist_ok=True)
    vol = Volume(exe)
    mz = MZ(exe)
    pal, pal6 = vga_palette(exe)

    _, spr = read_ggs(vol.read('hl.ggs'))
    sheet(spr, (0, 0, 16, 16), 8, 8).save(os.path.join(out, 'sprites.png'))
    sheet(spr, (16, 16, 8, 8), 8, 8).save(os.path.join(out, 'sprites_mini.png'))
    _, font = read_ggs(vol.read('font.ggs'))
    sheet(font, (0, 0, 16, 24), 16, 4).save(os.path.join(out, 'font.png'))
    _, logo = read_ggs(vol.read('logo.ggs'))
    picture(logo, 8, 5).save(os.path.join(out, 'logo.png'))
    _, chaos = read_ggs(vol.read('chaos.ggs'))
    picture(chaos, 8, 8).save(os.path.join(out, 'chaos.png'))

    json.dump(dict(game=[pal[3 * i:3 * i + 3] for i in range(256)],
                   mono=[mono_palette(pal6)[3 * i:3 * i + 3] for i in range(256)]),
              open(os.path.join(out, 'palette.json'), 'w'))

    # all samples in one raw file as signed 8-bit (the original's unsigned bytes XOR 0x80, the
    # format Godot's AudioStreamWAV wants); game.json "sounds" = name -> [offset, length]
    sounds = {}
    blob = bytearray()
    for e in vol.entries:
        n = e['name']
        if n.endswith('.snd'):
            data = vol.read(n)
            sounds[n[:-4]] = [len(blob), len(data)]
            blob += bytes(b ^ 0x80 for b in data)
    open(os.path.join(out, 'sounds.bin'), 'wb').write(bytes(blob))

    levels = load_levels(os.path.join(a.game_dir, 'LEVELS.HL'))
    json.dump([dict(author=lv.author or '', rows=lv.rows) for lv in levels],
              open(os.path.join(out, 'levels.json'), 'w'), indent=0)
    shutil.copy(os.path.join(a.game_dir, 'LEVELS.HL'), os.path.join(out, 'LEVELS.HL'))

    json.dump(dict(
        types=TYPE_NAMES,
        sprite_base=[SPRITE_BASE[t] for t in range(14)],
        tick_seconds=960 / SAMPLE_RATE,
        sample_rate=SAMPLE_RATE,
        sounds=sounds,
        sound_use=SOUND_USE,
        music_sequence=mz.cstr(DGROUP, MUSIC_SEQ_OFF).decode('ascii'),
        font_chars={c: i for c, i in FONT_CHARS.items()},
        font_polish=FONT_POLISH,
        # title-screen credit lines (DS:0738...): first letter = colour G/Y/B, capitals = Polish
        credits=[mz.cstr(DGROUP, o).decode('latin1')
                 for o in (0x738, 0x744, 0x758, 0x768, 0x772, 0x781, 0x791, 0x7A1, 0x7B3)],
    ), open(os.path.join(out, 'game.json'), 'w'), indent=1, ensure_ascii=False)
    print('remake data written to', out)


if __name__ == '__main__':
    main()
