# Disassembly reference

[`hl.asm`](hl.asm) is the annotated disassembly of the code segments of `HL.EXE` (2006 CC
release), produced by [`tools/disasm.py`](../tools/disasm.py) with the names in
[`tools/symbols.txt`](../tools/symbols.txt):

* addresses are `segment:offset` with the program loaded at segment `1000`; DGROUP is `214D`;
* Borland switch tables are decoded (`; switch table, N cases`, `.case_XXXX:` labels);
* string operands show the string, global variables their name, and accesses to the level grid
  are spelled out, e.g. `mov al, byte ptr [di + 0x501b]  ; type[i+22]` (the cell below).

Where to start reading:

| what | routines |
|---|---|
| program flow | `main` `1393:21CF`, `Init` `1393:1A37`, `TitleMenu` `17CF:1311`, `PlayGame` `1633:1777` |
| the game rules | `GameTick` `1633:0C4D` and the handlers `Hero_Think`, `Gravity`, `Rock_Think`, `Heart_Think`, `Bomb_Think`, `Balloon_Think`, `Door_Think`, `Explosion_Think`, `Plasma_Think`, `Tunnel_Think` (segment `1633`) |
| level loading | `ParseLevelFile` `1914:0004`, `ParseLevel` `1914:03CE`, `SetupLevel` `15BE:04F9` |
| resources | `Vol_Mount` `1F57:056F`, `Vol_Unpack` `2039:00B3`, `LoadGGS` `1C85:016F`, `LoadSprites` `1393:0281` |
| input | `PollKeyboard` `2063:0858`, `KeyDown` `2063:05CB`, `KeyPressed` `2063:0584` |

The game rules of segment `1633` are also written out as Python in
[`tools/hl_sim.py`](../tools/hl_sim.py), one function per routine, which is the practical
"decompilation" for porting. A Ghidra decompilation was tried: Ghidra loads the MZ file but its
decompiler cannot follow the inline switch tables of this code, so it is not included.

Regenerate with `python3 tools/disasm.py original/HL.EXE -o reference/hl.asm`; never edit
`hl.asm` by hand.
