# 2. File formats

All multi-byte values are little-endian. Readers for every format are in [`tools/`](../../tools/);
`tools/extract_assets.py` converts everything to [`assets/`](../../assets/README.md).

| file | format | section |
|---|---|---|
| `HL.EXE` | MZ executable + appended resource volume | [2.1](#21-the-resource-volume-appended-to-hlexe) |
| `*.ggs` (in the volume) | GGE sprite files | [2.3](#23-ggs-sprite-files) |
| `*.snd` (in the volume) | raw 8-bit PCM | [2.5](#25-sounds-snd) |
| music sequence (in the EXE) | string of block letters | [2.6](#26-in-game-music-sequence) |
| `loading.ted` (in the volume) | text-mode screen dump | [2.7](#27-loadingted) |
| `demo.rec` (in the volume) | unused input recording | [2.8](#28-demorec-unused) |
| `LEVELS.HL` | plain text | [2.9](#29-levelshl) |
| `CONFIG.DTA` | two letters | [2.10](#210-configdta) |
| `PLAYER1.STT`…`PLAYER3.STT` | 242-byte records, XOR-ed | [2.11](#211-playerstt) |
| `PICnn.BMP` | hidden screenshot | [2.12](#212-hidden-screenshots-picnnbmp) |

## 2.1 The resource volume appended to `HL.EXE`

The MZ load image ends at file offset `0x18C40`; the remaining 411 008 bytes are a "volume"
(a small archive) with every graphic, sound and the music. At start-up (`Vol_Mount`, `1F57:056F`)
the game tries, in order, a directory `DATA\`, a file `VOLUME.VOL`, and finally `HL.EXE` itself,
so the resources can also be supplied as loose files or as a separate `VOLUME.VOL` — the 2006
release only uses the copy inside the EXE. If none is found it stops with *"File HL.EXE is
damaged! You must reinstall the game."*

Layout (offsets from the end of the file):

```
end - size            archive data (files back to back)
end - 16 - 32*count   directory, count entries of 32 bytes   (XOR-encrypted)
end - 16              trailer, 16 bytes                       (XOR-encrypted)
```

Trailer: `char sig[10]` (`"volume\0"` + 3 bytes), `u16 count` (40), `u32 size` (411 008 = the
whole archive including directory and trailer; the archive starts at `filesize - size`).

Directory entry (32 bytes):

| off | type | field |
|---|---|---|
| 0x00 | `char[13]` | file name, NUL-terminated (8.3) |
| 0x0D | `u8` | 1 = packed |
| 0x0E | `u32` | offset of the data from the archive start |
| 0x12 | `u32` | stored (packed) size |
| 0x16 | `u32` | unpacked size |
| 0x1A | `u32` | DOS date/time of the original file |
| 0x1E | `u8` | DOS attributes (0x20) |
| 0x1F | `u8` | escape byte of the packer (0xFD–0xFF) |

**Encryption** (`XorBlock` `2039:0272`, `Vol_ReadXor` `2039:0015`): each region (trailer,
directory, the data of each file) is XOR-ed with a running key that starts at `0xF2` and grows by
`0x11` after every byte (mod 256).

**Packing** (`Vol_Unpack` `2039:00B3`), applied after decryption — a minimal LZ77:

```
while out < size:
    c = next()
    if c == escape:
        v = next() | next() << 8
        if v == 0:  out += escape                       # literal escape byte
        else:       copy (v >> 10) bytes from out[-(v & 0x3FF) - 1]   # may overlap
    else:
        out += c
```

Contents (dates are the original file dates stored in the directory; `tools/hl_volume.py`
lists and extracts them):

| file | size | date | contents |
|---|---|---|---|
| `loading.ted` | 4 000 | 1999-06-15 | text-mode "Analysing file" window templates |
| `hl.ggs` | 43 456 | 1992-12-20 | the 63 game sprites |
| `chaos.ggs` | 44 144 | 1992-12-20 | 192×192 start-up picture ("Chaos") |
| `font.ggs` | 36 576 | 1993-04-29 | 53 glyphs of the 16×8 three-colour font, HUD icons |
| `logo.ggs` | 27 632 | 1992-12-20 | 192×120 "HEARTLIGHT PC" logo |
| `!a.snd` … `!t.snd` | 16 939 each | 1992-09-30 | the 20 blocks of the in-game music |
| `title.snd` | 16 939 | 1992-11-13 | title-screen tune |
| `colect.snd` … `hrtgrass.snd` | 203–22 763 | 1992-08/10 | the 13 sound effects |
| `demo.rec` | 8 132 | 1992-10-21 | unused input recording |

The 1992 dates predate the 1994 release: the PC engine was built in 1992–93 (see
[06-history.md](06-history.md)). `loading.ted` is dated 1999, from a later rebuild.

## 2.2 Palette

One 256-colour VGA palette for everything, stored in the EXE at `DS:0B00` (file offset
`0x131D0`), 768 bytes of 6-bit RGB. `SetPalette` (`1CE9:0022`) loads it with `INT 10h/1012h`.
The **VGA mono** option of SETUP replaces each colour by grey `(r + g + b) / 3`
(`1CE9:004B`). DOSBox screenshots expand 6-bit values as `v << 2 | v >> 4`; the palettes in
`assets/palette/` use the same expansion and match the original's screenshots exactly.

Fades (`FadePalette` `1C85:0001`) step all 768 components linearly between black and the
palette over `N` vertical retraces.

## 2.3 GGS sprite files

Written by Janusz Pelc's sprite editor "GGE". Read by `LoadGGS` (`1C85:016F`).

```
0x00  char  text[32]      " GGE file: sprites (ver 1.8) \r\n\x1A"
0x20  u8    info[16]      07 03 03 02 00…  (font.ggs: 34 09 03 02 00…); not used by the game
0x30  64 slots:
        u8  used          0xFF = empty slot, nothing follows
        u8  pixels[576]   24×24, row-major; 0xFF = transparent, else index into remap[]
        u8  remap[64]     local colour → VGA palette index
        u8  meta[8]       meta[0] = object type + 1 (0 = none); meta[1] bit 7 = first frame
        u8  box[4]        editor data, copied but never used
        u8  stats[36]     editor data, copied but never used
```

The loader replaces every non-transparent pixel by `remap[pixel]` and converts the cell to the
four Mode X planes. Each 24×24 cell of `hl.ggs` holds the 16×16 sprite at (0,0) and an 8×8
reduced copy at (16,16) used by the overview map (F1). The pictures (`logo.ggs`, `chaos.ggs`)
are cut into 24×24 cells, row by row, 8 cells wide.

**`hl.ggs` slots** (`meta[0]` gives the type; `LoadSprites` `1393:0281` records the first slot of
each type in `g_spriteBase[14]`, `DS:4C5B`; a cell is drawn with sprite `g_spriteBase[type] + frame`):

| slots | type | frames |
|---|---|---|
| 0 | 0 empty | black |
| 1–6 | 5 heart | 6-frame beat |
| 7 | 7 grass | |
| 8 | 4 rock | |
| 9–15 | 1 explosion | 0–6 |
| 16–23 | 8 dwarf | 0/1 walk left, 2/3 walk right, 4/5 dying (blink), 6/7 leaving through the door |
| 24–27 | 9 door | 0 closed … 3 open |
| 28–31 | 10 balloon | 4-frame sway |
| 32–39 | 11 plasma | 8-frame shimmer |
| 40–47 | 12 tunnel `<` | 0–3 idle, 4–7 with the dwarf inside |
| 48–55 | 13 tunnel `>` | same |
| 56–59 | 2 brick | colour = level number mod 4 |
| 60 | 3 metal wall | |
| 61–62 | 6 bomb | 0 idle, 1 lit |

**`font.ggs`**: each glyph is 16×8, drawn three times in the 24-pixel cell: yellow (rows 0–7),
green (8–15), blue (16–23). Character → glyph (`FontIndex` `17CF:000B`): `a`–`z` 0–25; capitals
stand for Polish letters `A`=Ą 26, `C`=Ć 27, `E`=Ę 28, `L`=Ł 29, `N`=Ń 30, `O`=Ó 31, `S`=Ś 32,
`Z`=Ż 33; `0`–`9` 34–43; `:` 44, `.` 45, `&` 46 (©), space 47; HUD icons `(` 48 heart,
`)` 49 solved-level mark, `+` 50 option on, `-` 51 option off; `I` 52 text cursor. Any other
character returns −1 and is not drawn. Strings shown on the title screen start with a colour
letter: `G` green, `Y` yellow, `B` blue (e.g. `"BpaweL wyrzycki"` = Paweł Wyrzycki in blue).

## 2.4 Screen

320×200 VGA in unchained (Mode X) layout with page flipping. The play-field is 20×12 cells of
16×16 = 320×192 at the top, the status line is the bottom 8 pixels (20 glyphs of 16×8).

## 2.5 Sounds (`*.snd`)

Headerless 8-bit unsigned mono PCM. All drivers reprogram PIT channel 0 to divisor `0x8C`
(1 193 182 / 140 = **8 522.7 Hz**) and output one sample per timer interrupt, so that is the
sample rate. Two channels are mixed in software (`(a + b) / 2`): one for music, one for effects.
A sound is a chain of 12-byte records `{far ptr data, u16 offset, …, u16 length, far ptr next}`,
which is how the music loops.

| file | samples | played when |
|---|---|---|
| `rock` | 1 231 | rock lands (not on grass) |
| `rocgrass` | 307 | rock or bomb lands on grass |
| `heart0`–`heart3` | 464–466 | heart lands (not on grass), one of the four at random |
| `hrtgrass` | 203 | heart lands on grass |
| `colect` | 5 582 | the dwarf picks up a heart |
| `colected` | 9 237 | the last heart is taken: the door starts to open |
| `door` | 22 763 | the dwarf walks into the open door |
| `tunnel` | 11 698 | the dwarf enters a tunnel |
| `expl` | 5 505 | a bomb explodes, or the dwarf is killed |
| `key` | 393 | F6/F7/F8 toggled |
| `title` | 16 939 | title screen, looped |

## 2.6 In-game music sequence

The in-game music is built from the 20 blocks `!a.snd`…`!t.snd` (16 939 samples ≈ 1.99 s
each) by `BuildSampleChain` (`1393:0B71`) from the string at `DS:0094`:

```
lllljjjkababdedemnmnghgissssttttaaabeeefopopghghmnmnghghscstscstcacbcdceqrqrhhhhjkjkghgisbsbsbst
aeaendndncncnnnfsbsjsbskstststsiadadbdbfrqrqhghgopophghistscstscabdeabdfotothhhisssjssskstskstsc.
```

Each letter appends block `!<letter>.snd`; `.` links the last block back to the first (an endless
loop of 197 blocks ≈ 6 min 32 s). The builder also understands modifiers that this string does
not use: `<` / `>` keep the first / second half of the previous block, `1`–`4` one quarter,
`!` the first sixteenth; spaces are ignored. When memory is short (`DS:4C19`) the blocks
b, d, g, k, l, q are replaced by a, e, h, j, j, r. The title tune is the single block `title.snd`
looped.

## 2.7 `loading.ted`

4 000 bytes = an 80×25 text screen (character, attribute pairs). It holds the templates of the
"Analysing file" window shown while `LEVELS.HL` is parsed: Polish (`Analiza pliku`) and English
versions, each with a "pressed" variant. The game copies the English window to the text screen
and fills in the file name, a progress bar, the level counter and the free-memory percentage.

## 2.8 `demo.rec` (unused)

8 132 bytes, stored in the volume but never opened by the 2006 executable (no code or string
refers to it). It looks like a keyboard recording: most bytes are arrow scan codes (`48` `4B`
`4D` `50`) separated by `00`, with `FE n` runs; a straightforward per-tick reading does not play
any level of `LEVELS.HL` sensibly, so it probably belongs to an earlier level set or input
format. It is kept in `assets/volume/` for completeness.

## 2.9 `LEVELS.HL`

Plain text (the 2006 file has CR LF line ends and a final `^Z`). Parsed at start-up by
`ParseLevelFile` (`1914:0004`) while the "Analysing file" window shows the progress:

* Lines are read up to `\n`; only the first 20 characters count; shorter lines are padded with
  spaces (empty cells).
* A level is a block from a line starting with `{` to a line starting with `}`; everything
  outside blocks is a comment (the file starts with a legend, each level is preceded by
  `author: …`).
* A block must have exactly 12 lines and contain at least one `*` and one `!`; only the 13
  characters below are allowed. Errors: *Not enough lines / Too many lines / No hero / No exit /
  Invalid object on level #n*, *Too many levels defined (max=199)*, *No levels in file*.
* Several `*` are accepted; the scan order then decides (every dwarf is an independent object
  and all move together).

| char | object | type id | initial state | initial frame |
|---|---|---|---|---|
| space | empty | 0 | 0 | |
| `$` | heart | 5 | 2 | random 0–5 |
| `@` | rock | 4 | 2 | |
| `.` | grass | 7 | 0 | |
| `*` | dwarf | 8 | 1 | 2 (faces right) if x < 10, else 0 |
| `!` | exit door | 9 | 5 | |
| `&` | bomb | 6 | 2 | |
| `0` | balloon | 10 | 2 | random 0–3 |
| `=` | plasma | 11 | 2 | |
| `#` | brick wall | 2 | 0 | level number mod 4 (colour) |
| `%` | metal wall | 3 | 0 | |
| `<` | tunnel to the left | 12 | 2 | |
| `>` | tunnel to the right | 13 | 2 | |

The parser stores each level packed in memory (`PackLevel` `1914:0609`): a 4-bit code per cell
(the index in `" $@.*!&0=#%<>"`), with codes 13–15 introducing back-references, row- or
column-major, whichever is shorter. This is only a memory optimisation.

`assets/levels/` has the 70 levels as JSON, PNG and Tiled maps.

## 2.10 `CONFIG.DTA`

Written by `CONFIG.EXE` (SETUP), read by `ReadConfig` (`1393:016D`). Two letters, the same
letters can be given on the command line (`HL v b`):

| letter | meaning |
|---|---|
| `v` | VGA |
| `m` | VGA mono (grey palette) |
| `s` | PC speaker |
| `b` | Sound Blaster (falls back to no sound if the DSP at 220h does not reset) |
| `a` | AdLib (samples played through the OPL2) |
| `1` / `2` | DAC (Covox) on LPT1 / LPT2 |
| `n` | no sound |

Also accepted (command line): `/n` no sound, `/s` Sound Blaster, `/j` joystick on by default
for new players, `/k` or `k` keyboard, `?` memory report (code/sound/data/free/heap sizes,
written with `info.txt`). Anything else stops with *"Wrong parameter! Please run SETUP."*
The release's file is `vb`. `main` still maps the letters `e`, `c`, `h` to EGA, CGA and
Hercules drivers (segments `1D4F`–`1E96` hold five graphics drivers), but the option parser no
longer accepts them.

## 2.11 `PLAYER?.STT`

Three save slots, 242 bytes each, written when a player's record changed (`SavePlayer`
`1393:0A07`), read at start-up (`LoadPlayer` `1393:0860`).

| off | type | field |
|---|---|---|
| 0x00 | `char[13]` | name (default `player1`…`player3`) |
| 0x0D | u8 | slot |
| 0x0E | u8 | modified |
| 0x10 | u16 ×2 | date and time stamp of `LEVELS.HL` when saved; a different stamp resets the progress |
| 0x14 | u8 | current player |
| 0x16 | u16 | number of sessions |
| 0x18 | u8 [6] | rotated on every save (purpose unknown) |
| 0x1E | u8 | overview map (F1) on |
| 0x1F | u8 | music on (F6) |
| 0x20 | u8 | sound effects on (F7) |
| 0x21 | u8 | joystick on (F8) |
| 0x22 | u8 | ticks the option icons stay visible |
| 0x24 | u16 | current level (0-based) |
| 0x26 | u8 [199] | 1 = level solved |
| 0xEE | u16 | solved count (recomputed on every level start) |
| 0xF0 | u16 | checksum: 1 + sum of bytes 0x00–0xEF (before encryption) |

Bytes 0x00–0xEF are XOR-encrypted: `k = 0; c = 0xF5; for each byte: k = (k + c) & 0xFF;
byte ^= k; c -= 2`. A file with a bad checksum is replaced by a fresh record.

## 2.12 Hidden screenshots `PICnn.BMP`

Holding Alt + Ctrl and pressing F12 (on the title screen, in the game, while loading) saves the
screen as `PIC00.BMP`, `PIC01.BMP`, … (`SaveScreenshot` `1BE2:0210`).
