# 1. The executable (`HL.EXE`)

## 1.1 Identity

| | |
|---|---|
| Title | **Heartlight PC** |
| Original release | 1994, Epic MegaGames (with Xland); this is the 2006 Creative Commons rebuild |
| Author | Janusz Pelc (program, graphics, music); support Maciej Miąsik, Paweł Wyrzycki, Marek Kubowicz |
| Platform | MS-DOS real mode, 80286+, VGA, PC speaker / Sound Blaster / AdLib / LPT DAC |
| Language | Borland C++ 3.x (1991 runtime, large memory model) with assembly drivers |
| Licence | Creative Commons Attribution-ShareAlike 2.5 (see `original/README.TXT`) |

`HL.EXE` is 512 448 bytes: a 101 440-byte MZ program followed by a 411 008-byte resource volume
([2.1](02-file-formats.md#21-the-resource-volume-appended-to-hlexe)). `CONFIG.EXE` (12 048
bytes, packed) is the SETUP program that writes `CONFIG.DTA`. `LEVELS.HL` holds the 70 levels
as editable text.

## 1.2 File layout

```
0x00000  MZ header (0x1200 bytes, 873 relocations), entry CS:IP = 0000:0000, SS:SP = 179C:0080
0x01200  load image (0x17A40 bytes): 29 segments
0x18C40  resource volume (encrypted, LZ-packed)
```

`tools/mz_loader.py` loads the image at segment `1000` and applies the relocations; all
addresses in these documents are `segment:offset` with that load segment. The data segment
(DGROUP, `DS`) is `214D`; `DS:xxxx` addresses refer to it.

| segment | size | contents |
|---|---|---|
| `1000` | 0x3930 | Borland C++ runtime (startup, `printf`, file I/O, `malloc`, long arithmetic) |
| `1393` | 0x22B0 | main module: `main`, `Init`, config, player files, sprite/sound loading, music sequencer |
| `15BE` | 0x0750 | level file loading and the "Analysing file" window, `SetupLevel` |
| `1633` | 0x19C0 | **the game**: object handlers, `GameTick`, drawing, `PlayGame` |
| `17CF` | 0x1450 | title screen, credits pages, player selection and name entry, quit prompt |
| `1914` | 0x09F0 | `LEVELS.HL` parser and in-memory level packer |
| `19B3` | 0x0800 | sound: sample loading, driver selection |
| `1A33`…`1B72` | | sound drivers: LPT DAC, Sound Blaster, AdLib, PC speaker, Sound Blaster fallback, none |
| `1BAC` | 0x0360 | far memory allocation |
| `1BE2` | 0x0A30 | graphics front end: driver table, page set-up, BMP screenshot |
| `1C85` | 0x0640 | palette fades, `LoadGGS`, picture loading |
| `1CE9`…`1E96` | | five graphics drivers (`1CE9` is VGA Mode X with the palette and mono-palette code) |
| `1F10`, `1F41` | | small helpers (not analysed) |
| `1F57` | 0x0E20 | resource volume file system (`Vol_Mount`, `Vol_Open`, `Vol_Read`, …) |
| `2039` | 0x02A0 | volume decryption and LZ unpacking |
| `2063` | 0x0C70 | keyboard (INT 9) and joystick |
| `212A`, `213D` | | small helpers |
| `214D` | | DGROUP: initialised data, then BSS |

## 1.3 Program flow

```
main (1393:21CF)
 ├─ 286 check ("At least 80286 CPU required!")
 ├─ Init (1393:1A37)
 │   ├─ save INT 1/2/3 vectors and point them at F000:FFF0 (reset) - anti-debugging, repeated
 │   │  on every keyboard poll
 │   ├─ save the text screen; hook INT 9
 │   ├─ ReadConfig: CONFIG.DTA + command line (2.10)
 │   ├─ Vol_Mount: DATA\ , VOLUME.VOL, or HL.EXE itself
 │   ├─ text-mode "Analysing file: levels.hl" window while LoadLevels parses LEVELS.HL
 │   ├─ LoadPlayers (PLAYER1-3.STT), memory check ("Sorry, you don't have enough free memory")
 │   ├─ graphics driver + palette, sound driver (19B3:044C)
 │   ├─ fade-in of chaos.ggs (the "Chaos" picture), LoadSprites (hl.ggs), srand(BIOS ticks)
 │   └─ LoadSounds (*.snd, title tune, music chain)
 └─ loop:
      TitleMenu (17CF:1311)      title tune; logo + rotating credit pages; current player name
        Space / joystick button  → play
        Enter                    → PlayerSelect: choose PLAYER1-3, edit the name
        Esc or F10               → "press y to quit" (Y quits)
      PlayGame (1633:1777)       in-game music; level loop (3.3) until F10 → back to the title
 exit: SavePlayers, restore vectors and the text screen, print
       "Heartlight PC Creative Commons BY-SA 2.5 release 2006 / Originally published in 1994 by
        Epic MegaGames and xland", scramble its own code in memory (1393:2245) and quit
```

Alt+X quits to DOS at once (keyboard hook).

## 1.4 Anti-tamper and anti-debugging (irrelevant for a remake)

* INT 1, 2 and 3 are pointed at the BIOS reset vector `F000:FFF0` at start-up and again after
  every keyboard poll, so a debugger breakpoint reboots the machine.
* Every failure to read a resource ends with *"File HL.EXE is damaged! You must reinstall the
  game."*
* On exit `ExitScramble` (`1393:2245`) and similar routines at the end of other segments swap
  and add the words of their own code segment, so a memory dump taken after the game ran is
  useless.

## 1.5 Video

VGA 320×200×256 in unchained mode (Mode X) with two pages for page flipping and off-screen
memory holding the sprite sheet (sprites are blitted VRAM to VRAM with the write mask).
`DrawFrame` redraws the whole play-field each tick. Graphics calls go through a driver table
(`DS:541B`… set by `1BE2:05A2`): put sprite, fill, copy rectangle, flip, fade in/out, load
picture. The VGA mono driver differs only in the palette.

## 1.6 Sound

Seven drivers share one interface (`DS:08B4`…`08D6`: load, play(channel, sample), stop,
timer reset, timer read). All of them reprogram PIT channel 0 to divisor `0x8C`
(8 522.7 Hz) and play one sample per interrupt (the Sound Blaster driver `1A6E` writes each
sample with DSP command `10h`, direct DAC; the others were not analysed in detail), and they all
count 2 per interrupt in the counter that paces the game, so the game speed does not depend on
the sound device. Two channels are mixed by averaging.

## 1.7 Important globals

The full list is in [`tools/symbols.txt`](../../tools/symbols.txt).

| addr | name | meaning |
|---|---|---|
| `DS:0094` | `s_musicSequence` | in-game music block sequence (2.6) |
| `DS:088C` | `s_levelChars` | `" $@.*!&0=#%<>"` |
| `DS:0B00` | `g_palette` | VGA palette, 256 × 6-bit RGB |
| `DS:4C45` | `g_gameState` | 1 play, 3 quit, 4 to title, 6 next level, 7 previous level, 8 abort |
| `DS:4C47` / `4C49` | `g_heartsTotal` / `g_heartsLeft` | |
| `DS:4C4B` | `g_levelCount` | levels in `LEVELS.HL` |
| `DS:4C5B` | `g_spriteBase[14]` | first sprite of each object type |
| `DS:4C69`, `4D9D`, `4ED1`, `5005` | `g_pending`, `g_frame`, `g_state`, `g_type` | the 22×14 grid (3.1) |
| `DS:5139` | `g_player` | far pointer to the current player record (2.11) |
| `DS:60D2` | `g_heroIdle` | ticks the level survives without the dwarf |
| `DS:60D7` / `60D8` | `g_exitTimer` / `g_deathTimer` | |
| `DS:60D9` | `g_activity` | things that moved this tick |
| `DS:60DB` | `g_dir` | input direction −1/+1/−22/+22 |
| `DS:60DD` | `g_tickCount` | push parity |

## 1.8 Reproducing the analysis

```bash
pip install -r tools/requirements.txt
python3 tools/mz_loader.py original/HL.EXE                    # header, segments
python3 tools/hl_volume.py original/HL.EXE -x /tmp/vol         # list / unpack the resources
python3 tools/disasm.py original/HL.EXE -o reference/hl.asm    # annotated disassembly
python3 tools/extract_assets.py original/ assets/              # all assets
```

Ghidra 11 imports the MZ file directly (old-style DOS executable loader), but its decompiler
loses track of Borland's inline switch tables in the game segments, so the reference for this
project is the annotated disassembly in [`reference/`](../../reference/README.md), whose
listings follow the switch tables, plus the simulator `tools/hl_sim.py`, which is the
decompilation of segment `1633` written out by hand.
