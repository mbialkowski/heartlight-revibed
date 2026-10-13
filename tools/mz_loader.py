#!/usr/bin/env python3
"""Loader for the real-mode MZ executable HL.EXE (Borland C++ 3.x, 16-bit).

Loads the image at a chosen paragraph (default 0x1000 -> linear 0x10000), applies the
segment relocations, and exposes the overlay (data appended after the load image).
"""
import struct
import sys

LOAD_SEG = 0x1000


class MZ:
    def __init__(self, path, load_seg=LOAD_SEG):
        self.raw = open(path, 'rb').read()
        d = self.raw
        (sig, cblp, cp, crlc, cparhdr, minalloc, maxalloc, ss, sp, csum, ip, cs,
         lfarlc, ovno) = struct.unpack_from('<2s13H', d, 0)
        assert sig == b'MZ'
        self.hdr = dict(cblp=cblp, cp=cp, crlc=crlc, cparhdr=cparhdr, minalloc=minalloc,
                        maxalloc=maxalloc, ss=ss, sp=sp, ip=ip, cs=cs, lfarlc=lfarlc, ovno=ovno)
        self.hdr_size = cparhdr * 16
        self.image_end = (cp - 1) * 512 + cblp if cblp else cp * 512
        self.image = bytearray(d[self.hdr_size:self.image_end])
        self.load_seg = load_seg
        self.relocs = []
        for i in range(crlc):
            off, seg = struct.unpack_from('<HH', d, lfarlc + 4 * i)
            self.relocs.append((seg, off))
            p = seg * 16 + off
            v = struct.unpack_from('<H', self.image, p)[0]
            struct.pack_into('<H', self.image, p, (v + load_seg) & 0xFFFF)
        self.overlay_off = self.image_end
        self.overlay = d[self.image_end:]
        self.entry = (cs + load_seg, ip)
        self.stack = (ss + load_seg, sp)
        # segments referenced by relocations = the program's segments
        segs = set()
        for seg, off in self.relocs:
            segs.add(struct.unpack_from('<H', self.image, seg * 16 + off)[0])
        segs.add(self.entry[0])
        segs.add(self.stack[0])
        self.segments = sorted(segs)

    def lin(self, seg, off):
        """Linear address (seg:off with the load segment applied) -> offset into image."""
        return seg * 16 + off - self.load_seg * 16

    def read(self, seg, off, n):
        p = self.lin(seg, off)
        return bytes(self.image[p:p + n])

    def word(self, seg, off):
        return struct.unpack('<H', self.read(seg, off, 2))[0]

    def cstr(self, seg, off):
        p = self.lin(seg, off)
        e = self.image.index(0, p)
        return bytes(self.image[p:e])


if __name__ == '__main__':
    mz = MZ(sys.argv[1])
    for k, v in mz.hdr.items():
        print(f'{k:9s} {v:#06x}')
    print(f'header {mz.hdr_size:#x} bytes, image {len(mz.image):#x} bytes, overlay at file '
          f'{mz.overlay_off:#x} ({len(mz.overlay)} bytes)')
    print(f'entry {mz.entry[0]:04X}:{mz.entry[1]:04X} stack {mz.stack[0]:04X}:{mz.stack[1]:04X}')
    print('segments:', ' '.join(f'{s:04X}' for s in mz.segments))
