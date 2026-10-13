#!/usr/bin/env python3
"""Reader for the resource "volume" appended to HL.EXE (also loadable as VOLUME.VOL).

Layout (see docs/reverse-engineering/02-file-formats.md):
  archive = last <size> bytes of the file
  trailer = last 16 bytes: char sig[10] "volume\\0..", u16 count, u32 archive size
  directory = count * 32 bytes just before the trailer:
      char name[13]; u8 packed; u32 offset; u32 packed_size; u32 size; u32 dos_datetime;
      u8 attr; u8 escape
  trailer and directory are XOR-encrypted: key starts at 0xF2, += 0x11 per byte (restarting
  for each region); each file's data is encrypted the same way, the key restarting at 0xF2.
  packed files use a small LZ77: byte == escape -> u16 v; v == 0 -> literal escape byte,
  else copy (v >> 10) bytes from distance (v & 0x3FF) + 1.

    python3 tools/hl_volume.py HL.EXE            # list
    python3 tools/hl_volume.py HL.EXE -x outdir  # extract (unpacked)
"""
import argparse
import os
import struct

KEY0, KEY_STEP = 0xF2, 0x11


def xor(data, key=KEY0, step=KEY_STEP):
    out = bytearray(len(data))
    for i, c in enumerate(data):
        out[i] = c ^ key
        key = (key + step) & 0xFF
    return bytes(out)


def unlz(data, size, escape):
    out = bytearray()
    i = 0
    while len(out) < size:
        c = data[i]
        i += 1
        if c == escape:
            v = data[i] | data[i + 1] << 8
            i += 2
            if v:
                n, dist = v >> 10, (v & 0x3FF) + 1
                for _ in range(n):
                    out.append(out[-dist])
                continue
        out.append(c)
    return bytes(out)


class Volume:
    def __init__(self, path):
        d = open(path, 'rb').read()
        t = xor(d[-16:])
        self.signature = t[:10]
        count, size = struct.unpack('<HI', t[10:16])
        self.base = len(d) - size
        raw = xor(d[-16 - 32 * count:-16])
        self.entries = []
        for i in range(count):
            e = raw[32 * i:32 * i + 32]
            name = e[:13].split(b'\0')[0].decode('ascii')
            packed = e[13]
            off, psize, usize, dt = struct.unpack_from('<IIII', e, 14)
            self.entries.append(dict(name=name, packed=packed, offset=off, packed_size=psize,
                                     size=usize, dos_datetime=dt, attr=e[30], escape=e[31]))
        self.data = d

    @staticmethod
    def dos_time(dt):
        t, dd = dt & 0xFFFF, dt >> 16
        return '%04d-%02d-%02d %02d:%02d:%02d' % (1980 + (dd >> 9), dd >> 5 & 15, dd & 31,
                                                   t >> 11, t >> 5 & 63, (t & 31) * 2)

    def read(self, name):
        e = next(e for e in self.entries if e['name'].lower() == name.lower())
        start = self.base + e['offset']
        raw = xor(self.data[start:start + e['packed_size']])
        return unlz(raw, e['size'], e['escape']) if e['packed'] else raw[:e['size']]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('exe')
    ap.add_argument('-x', '--extract')
    a = ap.parse_args()
    v = Volume(a.exe)
    print(f'signature {v.signature!r}, {len(v.entries)} files, archive at {v.base:#x}')
    for e in v.entries:
        print(f"{e['name']:13s} {'lz' if e['packed'] else '--'} off {e['offset']:7d} "
              f"packed {e['packed_size']:6d} size {e['size']:6d} {v.dos_time(e['dos_datetime'])}"
              f" esc {e['escape']:02x}")
    if a.extract:
        os.makedirs(a.extract, exist_ok=True)
        for e in v.entries:
            open(os.path.join(a.extract, e['name']), 'wb').write(v.read(e['name']))


if __name__ == '__main__':
    main()
