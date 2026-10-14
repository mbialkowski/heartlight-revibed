# Original game files — Heartlight PC, Creative Commons release 2006

These are the unmodified files of the 2006 freeware release of Heartlight PC, which its authors
licensed under **Creative Commons Attribution-ShareAlike 2.5** (see [`README.TXT`](README.TXT),
the release's own readme, for credits, controls and the licence). Every tool in `tools/` and
every address in the documentation refers to exactly these files; check them with `sha256sum`.

| file | bytes | contents | sha256 |
|---|---|---|---|
| `HL.EXE` | 512 448 | the game: Borland C++ MZ executable + appended resource volume (graphics, sounds, music) | `843977aef8f27515f91d16b04f1b12cad8e593398d201119951af88b92919be7` |
| `LEVELS.HL` | 20 973 | the 70 levels, plain text (editable) | `fcd415e0d1da011de77df05ef6277cb5d0b1983ca78da5f51f69317674169b76` |
| `CONFIG.EXE` | 12 048 | SETUP: chooses graphics mode and sound device, writes `CONFIG.DTA` | `fa604ea481c1b228eee8bed2a0c9fb884fbca96c86b176e303028b2ac86c7fe2` |
| `CONFIG.DTA` | 2 | `vb` = VGA + Sound Blaster | `88d2f47e5eec541d907a3951ea1586732930d4a84510624b48c5e259c51d139b` |
| `README.TXT` | 4 487 | release notes, controls, credits, licence | `3c7f590c574b9589a818c5f47304c96a4755a229e96e269e9ccb191fa5c28825` |

## Running it

[DOSBox](https://www.dosbox.com/) 0.74 or newer (DOSBox-X / DOSBox Staging also work):

```bash
cd original
dosbox -conf dosbox.conf
```

The game writes `PLAYER1.STT`…`PLAYER3.STT` here (ignored by git). Run `CONFIG` inside DOSBox
to change the sound device.

Controls: arrows move, **Space + ←/→** previous/next level, **Esc** restart the level (the dwarf
explodes), **F1** overview map, **F6** music, **F7** sound, **F8** joystick, **F10** back to the
title, **Alt+X** quit. On the title: **Space** play, **Enter** choose / rename the player.
