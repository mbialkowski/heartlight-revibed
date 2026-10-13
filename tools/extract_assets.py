#!/usr/bin/env python3
"""Converts every asset of Heartlight PC (HL.EXE + LEVELS.HL) to modern formats.

    python3 tools/extract_assets.py original/ assets/

Writes (see assets/README.md):
  volume/     the 40 files of the resource volume appended to HL.EXE, decrypted and unpacked
  palette/    the VGA palette (DS:0B00) and its 'VGA mono' variant: .pal (6-bit), .gpl, .png
  sprites/    hl.ggs: 63 sprites (16x16 + 8x8 overview version), sheets, Tiled tileset, JSON
  font/       font.ggs: 53 glyphs 16x8 in 3 colours, sheet and char map
  pictures/   logo.ggs (title logo 192x120) and chaos.ggs (192x192 start-up picture)
  sounds/     13 effects + title tune as WAV (8-bit unsigned, 8523 Hz)
  music/      the 20 in-game music blocks as WAV and the full in-game tune assembled from
              the sequence string in HL.EXE
  levels/     LEVELS.HL as JSON, PNG renders, Tiled maps (.tmj), overview sheet
  text/       loading.ted (text-mode window templates), strings of HL.EXE
  gamedata/   object types, sprite bases, sounds, timing, keys (game_data.json)
"""
import argparse
import json
import os
import struct
import sys
import wave

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from PIL import Image, ImageDraw  # noqa: E402

from hl_gfx import read_ggs, vga_palette, mono_palette, to_image  # noqa: E402
from hl_levels import load as load_levels  # noqa: E402
from hl_sim import Sim, BorlandRand, SPRITE_BASE, TYPE_NAMES  # noqa: E402
from hl_volume import Volume  # noqa: E402
from mz_loader import MZ  # noqa: E402

SAMPLE_RATE = 1193182 / 140          # PIT channel 0 divisor 0x8C, one sample per interrupt
DGROUP = 0x214D
MUSIC_SEQ_OFF = 0x0094

# font.ggs: FontIndex (17CF:000B)
FONT_CHARS = {}
for i, c in enumerate('abcdefghijklmnopqrstuvwxyz'):
    FONT_CHARS[c] = i
for c, i in zip('ACELNOSZ', range(26, 34)):        # Polish letters written as capitals
    FONT_CHARS[c] = i
for i, c in enumerate('0123456789'):
    FONT_CHARS[c] = 34 + i
FONT_CHARS.update({':': 44, '.': 45, '&': 46, ' ': 47, '(': 48, ')': 49, '+': 50, '-': 51, 'I': 52})
FONT_POLISH = dict(zip('ACELNOSZ', 'ĄĆĘŁŃÓŚŻ'))
FONT_COLOURS = ['yellow', 'green', 'blue']          # rows 0-7, 8-15, 16-23 of each glyph

SOUND_USE = {
    'rock': 'rock lands (not on grass)',
    'rocgrass': 'rock or bomb lands on grass',
    'heart0': 'heart lands (not on grass), one of four at random',
    'heart1': 'heart lands (not on grass), one of four at random',
    'heart2': 'heart lands (not on grass), one of four at random',
    'heart3': 'heart lands (not on grass), one of four at random',
    'hrtgrass': 'heart lands on grass',
    'colect': 'dwarf collects a heart',
    'colected': 'last heart collected: the door starts to open',
    'door': 'dwarf enters the open door',
    'tunnel': 'dwarf enters a tunnel',
    'expl': 'explosion (bomb, or dwarf killed)',
    'key': 'F6/F7/F8 option toggled',
    'title': 'title-screen tune (looped)',
}


def save_wav(path, data, rate=SAMPLE_RATE):
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(1)
        w.setframerate(int(round(rate)))
        w.writeframes(data)


def write_palette(out, name, pal):
    os.makedirs(out, exist_ok=True)
    open(os.path.join(out, name + '.pal'), 'wb').write(bytes(v >> 2 for v in pal))
    with open(os.path.join(out, name + '.gpl'), 'w') as f:
        f.write(f'GIMP Palette\nName: Heartlight {name}\nColumns: 16\n#\n')
        for i in range(256):
            f.write('%3d %3d %3d\tindex %d\n' % (pal[3 * i], pal[3 * i + 1], pal[3 * i + 2], i))
    img = Image.new('RGB', (16 * 16, 16 * 16))
    d = ImageDraw.Draw(img)
    for i in range(256):
        d.rectangle([(i % 16) * 16, (i // 16) * 16, (i % 16) * 16 + 15, (i // 16) * 16 + 15],
                    fill=tuple(pal[3 * i:3 * i + 3]))
    img.save(os.path.join(out, name + '.png'))


def sprite_sheet(sprites, pal, box, cols=8):
    """box = (x, y, w, h) inside each 24x24 cell; RGBA sheet, slot order"""
    x0, y0, w, h = box
    rows = (len(sprites) + cols - 1) // cols
    sheet = Image.new('RGBA', (cols * w, rows * h), (0, 0, 0, 0))
    for i, s in enumerate(sprites):
        if s is not None:
            sheet.paste(to_image(s.crop(x0, y0, w, h), w, h, pal, transparent=True),
                        ((i % cols) * w, (i // cols) * h))
    return sheet


def extract_sprites(vol, pal, out):
    os.makedirs(os.path.join(out, 'hl'), exist_ok=True)
    _, sprites = read_ggs(vol.read('hl.ggs'))
    info = []
    base = {}
    for s in sprites:
        if s is None:
            continue
        t = s.obj_type
        base.setdefault(t, s.slot)
        frame = s.slot - base[t]
        name = f'{s.slot:02d}_{TYPE_NAMES[t]}_{frame}'
        to_image(s.crop(0, 0, 16, 16), 16, 16, pal, transparent=True).save(
            os.path.join(out, 'hl', name + '.png'))
        to_image(s.crop(16, 16, 8, 8), 8, 8, pal, transparent=True).save(
            os.path.join(out, 'hl', name + '_mini.png'))
        info.append(dict(slot=s.slot, type=t, type_name=TYPE_NAMES[t], frame=frame,
                         group_start=s.group_start, file=f'hl/{name}.png',
                         mini=f'hl/{name}_mini.png',
                         transparent_pixels=sum(v is None for v in s.crop(0, 0, 16, 16))))
    sprite_sheet(sprites, pal, (0, 0, 16, 16)).save(os.path.join(out, 'hl_sheet.png'))
    sprite_sheet(sprites, pal, (16, 16, 8, 8)).save(os.path.join(out, 'hl_sheet_mini.png'))
    sprite_sheet(sprites, pal, (0, 0, 24, 24)).save(os.path.join(out, 'hl_cells_24x24.png'))
    sheet = sprite_sheet(sprites, pal, (0, 0, 16, 16))
    big = sheet.resize((sheet.width * 3, sheet.height * 3), Image.NEAREST)
    bg = Image.new('RGBA', big.size, (40, 0, 40, 255))
    bg.alpha_composite(big)
    bg.convert('RGB').save(os.path.join(out, 'hl_sheet_x3.png'))
    # Tiled tileset (slot order, 8 columns)
    json.dump(dict(type='tileset', version='1.10', name='heartlight', image='hl_sheet.png',
                   imagewidth=sheet.width, imageheight=sheet.height, tilewidth=16, tileheight=16,
                   columns=8, tilecount=64, margin=0, spacing=0,
                   tiles=[dict(id=i['slot'], type=i['type_name'],
                               properties=[dict(name='frame', type='int', value=i['frame'])])
                          for i in info]),
              open(os.path.join(out, 'heartlight.tsj'), 'w'), indent=1)
    json.dump(dict(cell='24x24: 16x16 sprite at (0,0), 8x8 overview version at (16,16)',
                   sprite_base={TYPE_NAMES[t]: b for t, b in sorted(SPRITE_BASE.items())},
                   sprites=info), open(os.path.join(out, 'hl.json'), 'w'), indent=1)
    return sprites


def extract_font(vol, pal, out):
    os.makedirs(out, exist_ok=True)
    _, sprites = read_ggs(vol.read('font.ggs'))
    used = [s for s in sprites if s is not None]
    sprite_sheet(sprites[:len(used)], pal, (0, 0, 16, 24), cols=16).save(
        os.path.join(out, 'font_sheet.png'))
    for ci, colour in enumerate(FONT_COLOURS):
        sprite_sheet(sprites[:len(used)], pal, (0, 8 * ci, 16, 8), cols=16).save(
            os.path.join(out, f'font_{colour}.png'))
    chars = {}
    for c, i in sorted(FONT_CHARS.items(), key=lambda kv: kv[1]):
        chars[c] = dict(index=i, glyph=FONT_POLISH.get(c, c))
    json.dump(dict(glyph_size=[16, 8], colours=FONT_COLOURS, columns=16,
                   note='index = FontIndex(char) (17CF:000B); capitals stand for Polish letters; '
                        '"(" heart icon, ")" solved-level icon, "+"/"-" option on/off, '
                        '"&" copyright sign, "I" text cursor. Other characters are not drawn.',
                   chars=chars), open(os.path.join(out, 'font.json'), 'w'), indent=1,
              ensure_ascii=False)


def extract_pictures(vol, pal, out):
    os.makedirs(out, exist_ok=True)
    for name, cols, rows in (('logo', 8, 5), ('chaos', 8, 8)):
        _, sprites = read_ggs(vol.read(name + '.ggs'))
        img = Image.new('RGBA', (cols * 24, rows * 24), (0, 0, 0, 0))
        for i, s in enumerate(sprites[:cols * rows]):
            if s is not None:
                img.paste(to_image(s.crop(0, 0, 24, 24), 24, 24, pal, transparent=True),
                          ((i % cols) * 24, (i // cols) * 24))
        img.save(os.path.join(out, name + '.png'))


def extract_sounds(vol, out_snd, out_mus, mz):
    os.makedirs(out_snd, exist_ok=True)
    os.makedirs(os.path.join(out_mus, 'blocks'), exist_ok=True)
    info = {}
    for e in vol.entries:
        n = e['name']
        if not n.endswith('.snd'):
            continue
        data = vol.read(n)
        base = n[:-4]
        if base.startswith('!'):
            save_wav(os.path.join(out_mus, 'blocks', base[1:] + '.wav'), data)
        else:
            save_wav(os.path.join(out_snd, base + '.wav'), data)
            info[base] = dict(file=base + '.wav', samples=len(data),
                              seconds=round(len(data) / SAMPLE_RATE, 3), use=SOUND_USE.get(base))
    json.dump(dict(format='8-bit unsigned PCM mono', sample_rate=SAMPLE_RATE, sounds=info),
              open(os.path.join(out_snd, 'sounds.json'), 'w'), indent=1)
    seq = mz.cstr(DGROUP, MUSIC_SEQ_OFF).decode('ascii')
    blocks = {chr(c): vol.read(f'!{chr(c)}.snd') for c in range(ord('a'), ord('t') + 1)}
    tune = b''.join(blocks[c] for c in seq.rstrip('.'))
    save_wav(os.path.join(out_mus, 'ingame.wav'), tune)
    json.dump(dict(sample_rate=SAMPLE_RATE, block_samples=16939, sequence=seq,
                   note='each letter plays music/blocks/<letter>.wav; "." loops to the start; '
                        'ingame.wav is the whole loop. Modifiers understood by the player but '
                        'unused here: "<" first half, ">" second half, "1"-"4" quarter, '
                        '"!" first 1/16 of the previous block.',
                   low_memory_substitutions=dict(b='a', d='e', g='h', k='j', l='j', q='r'),
                   seconds=round(len(tune) / SAMPLE_RATE, 1)),
              open(os.path.join(out_mus, 'music.json'), 'w'), indent=1)


def render_level(sim, sprites, pal, mini=False):
    size = 8 if mini else 16
    img = Image.new('RGB', (20 * size, 12 * size))
    for y in range(12):
        for x in range(20):
            s = sprites[sim.sprite(x, y)]
            box = (16, 16, 8, 8) if mini else (0, 0, 16, 16)
            img.paste(to_image(s.crop(*box), size, size, pal), (x * size, y * size))
    return img


def extract_levels(levels_path, sprites, pal, out):
    os.makedirs(os.path.join(out, 'png'), exist_ok=True)
    os.makedirs(os.path.join(out, 'tiled'), exist_ok=True)
    levels = load_levels(levels_path)
    data = []
    thumbs = []
    for lv in levels:
        sim = Sim(lv.rows, level_index=lv.index, rand=BorlandRand(0))
        # deterministic frames for the renders: hearts and balloons at frame 0
        for i, t in enumerate(sim.type):
            if t in (5, 10):
                sim.frame[i] = 0
        img = render_level(sim, sprites, pal)
        img.save(os.path.join(out, 'png', f'level_{lv.index + 1:02d}.png'))
        thumbs.append(render_level(sim, sprites, pal, mini=True))
        gids = [sim.sprite(x, y) + 1 for y in range(12) for x in range(20)]
        json.dump(dict(type='map', version='1.10', orientation='orthogonal', renderorder='right-down',
                       width=20, height=12, tilewidth=16, tileheight=16, infinite=False,
                       nextlayerid=2, nextobjectid=1,
                       properties=[dict(name='author', type='string', value=lv.author or ''),
                                   dict(name='hearts', type='int', value=lv.count('$')),
                                   dict(name='brick_frame', type='int', value=lv.index % 4)],
                       tilesets=[dict(firstgid=1, source='../../sprites/heartlight.tsj')],
                       layers=[dict(id=1, name='objects', type='tilelayer', width=20, height=12,
                                    x=0, y=0, opacity=1, visible=True, data=gids)]),
                  open(os.path.join(out, 'tiled', f'level_{lv.index + 1:02d}.tmj'), 'w'))
        data.append(dict(level=lv.index + 1, author=lv.author, hearts=lv.count('$'),
                         counts={TYPE_NAMES[t]: sum(1 for i in range(len(sim.type))
                                                    if sim.type[i] == t and 22 < i < 286
                                                    and 0 < i % 22 < 21)
                                 for t in range(14)},
                         rows=lv.rows, comments=lv.comments))
    json.dump(data, open(os.path.join(out, 'levels.json'), 'w'), indent=1)
    cols = 7
    sheet = Image.new('RGB', (cols * 168, ((len(thumbs) + cols - 1) // cols) * 112), (30, 30, 30))
    d = ImageDraw.Draw(sheet)
    for i, t in enumerate(thumbs):
        x, y = (i % cols) * 168 + 4, (i // cols) * 112 + 12
        sheet.paste(t, (x, y))
        d.text((x, y - 11), f'{i + 1}', fill=(255, 255, 255))
    sheet.save(os.path.join(out, 'levels_overview.png'))


def extract_text(vol, mz, out):
    os.makedirs(out, exist_ok=True)
    ted = vol.read('loading.ted')
    lines = []
    for r in range(25):
        lines.append(bytes(ted[r * 160 + 2 * c] for c in range(80)).decode('cp437').rstrip())
    open(os.path.join(out, 'loading_ted.txt'), 'w', encoding='utf-8').write(
        '\n'.join(lines).rstrip() + '\n')
    # attributes too, as JSON rows of [char, attr]
    json.dump([[[ted[r * 160 + 2 * c], ted[r * 160 + 2 * c + 1]] for c in range(80)]
               for r in range(25)], open(os.path.join(out, 'loading_ted.json'), 'w'))
    import re
    base = mz.lin(DGROUP, 0)
    strings = []
    for m in re.finditer(rb'[\x20-\x7e\r\n]{3,}\x00', bytes(mz.image[base:base + 0x1000])):
        strings.append(dict(offset=f'DS:{m.start():04X}', text=m.group()[:-1].decode('latin1')))
    json.dump(strings, open(os.path.join(out, 'strings.json'), 'w'), indent=1)


def extract_gamedata(out):
    os.makedirs(out, exist_ok=True)
    chars = {' ': 0, '$': 5, '@': 4, '.': 7, '*': 8, '!': 9, '&': 6, '0': 10, '=': 11, '#': 2,
             '%': 3, '<': 12, '>': 13}
    init_state = {0: 0, 5: 2, 4: 2, 7: 0, 8: 1, 9: 5, 6: 2, 10: 2, 11: 2, 2: 0, 3: 0, 12: 2, 13: 2}
    frames = {1: 7, 2: 4, 5: 6, 6: 2, 8: 8, 9: 4, 10: 4, 11: 8, 12: 8, 13: 8}
    types = []
    for t, name in enumerate(TYPE_NAMES):
        ch = next((c for c, v in chars.items() if v == t), None)
        types.append(dict(id=t, name=name, char=ch, initial_state=init_state.get(t),
                          sprite_base=SPRITE_BASE[t], frames=frames.get(t, 1)))
    data = dict(
        source='HL.EXE 2006 CC release; see docs/reverse-engineering/03-engine.md',
        grid=dict(width=22, height=14, level_width=20, level_height=12,
                  index='(y + 1) * 22 + (x + 1)', border='metal (type 3)'),
        timing=dict(pit_hz=1193182 / 140, pit_ticks_per_game_tick=960,
                    game_tick_ms=round(960 / (1193182 / 140) * 1000, 3),
                    game_ticks_per_second=round((1193182 / 140) / 960, 3)),
        types=types,
        states={'dwarf': {1: 'alive'}, 'rock/heart/bomb': {2: 'resting', 3: 'falling', 8: 'bomb lit'},
                'door': {5: 'closed', 6: 'open'}, 'balloon': {2: 'resting', 7: 'rising'},
                'tunnel': {1: 'dwarf inside', 2: 'idle', 3: 'dwarf leaving'}},
        dwarf_frames={0: 'left', 1: 'left step', 2: 'right', 3: 'right step', 4: 'dying',
                      5: 'dying', 6: 'leaving', 7: 'leaving'},
        timers=dict(death_ticks=8, exit_ticks=16, hero_idle_ticks=32, explosion_frames=7,
                    door_opening_ticks=4, option_icons_ticks=48),
        input_priority=['right', 'left', 'down', 'up'],
        keys={'arrows': 'move/push', 'space+left/right': 'previous/next level',
              'esc': 'die and restart level', 'F1': 'overview map', 'F6': 'music', 'F7': 'sound',
              'F8': 'joystick', 'F10': 'title screen', 'alt+x': 'quit to DOS',
              'alt+ctrl+F12': 'screenshot PICnn.BMP'},
        sounds=SOUND_USE,
        rolls_off=['explosion', 'brick', 'rock', 'heart', 'plasma', 'bomb (unlit)'],
        explosion_spares=['metal', 'tunnel_left', 'tunnel_right', 'dwarf leaving (frame>=6)'],
    )
    json.dump(data, open(os.path.join(out, 'game_data.json'), 'w'), indent=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('game_dir')
    ap.add_argument('out_dir')
    a = ap.parse_args()
    exe = os.path.join(a.game_dir, 'HL.EXE')
    vol = Volume(exe)
    mz = MZ(exe)
    pal, pal6 = vga_palette(exe)
    out = a.out_dir
    os.makedirs(os.path.join(out, 'volume'), exist_ok=True)
    for e in vol.entries:
        open(os.path.join(out, 'volume', e['name']), 'wb').write(vol.read(e['name']))
    json.dump([dict(e, date=Volume.dos_time(e['dos_datetime'])) for e in vol.entries],
              open(os.path.join(out, 'volume', 'volume.json'), 'w'), indent=1)
    write_palette(os.path.join(out, 'palette'), 'game', pal)
    write_palette(os.path.join(out, 'palette'), 'mono', mono_palette(pal6))
    sprites = extract_sprites(vol, pal, os.path.join(out, 'sprites'))
    extract_font(vol, pal, os.path.join(out, 'font'))
    extract_pictures(vol, pal, os.path.join(out, 'pictures'))
    extract_sounds(vol, os.path.join(out, 'sounds'), os.path.join(out, 'music'), mz)
    extract_levels(os.path.join(a.game_dir, 'LEVELS.HL'), sprites, pal, os.path.join(out, 'levels'))
    extract_text(vol, mz, os.path.join(out, 'text'))
    extract_gamedata(os.path.join(out, 'gamedata'))
    print('done')


if __name__ == '__main__':
    main()
