#!/usr/bin/env python3
"""Reference implementation of the Heartlight PC game rules, ported from HL.EXE segment 1633.

Every function names the original routine and follows it branch for branch, including its
quirks (scan order, the "pending" flag, push only on odd ticks, explosion neighbours to the
right/below aging one frame in the same tick...). See docs/reverse-engineering/03-engine.md.

    sim = Sim(levels[0].rows, level_index=0)
    sim.tick(Sim.RIGHT)            # one 112.6 ms game tick with the right arrow held
    print(sim.dump())

The grid is the original 22 x 14 array (a one-cell metal border around the 20 x 12 level);
cell index = (y + 1) * 22 + (x + 1).
"""
import random as _random

W, H = 22, 14
N = W * H

# object types (g_type values)
EMPTY, EXPLOSION, BRICK, METAL, ROCK, HEART, BOMB, GRASS, DWARF, DOOR, BALLOON, PLASMA, \
    TUNNEL_L, TUNNEL_R = range(14)
TYPE_NAMES = ['empty', 'explosion', 'brick', 'metal', 'rock', 'heart', 'bomb', 'grass', 'dwarf',
              'door', 'balloon', 'plasma', 'tunnel_left', 'tunnel_right']
LEVEL_CHARS = ' $@.*!&0=#%<>'

# first sprite of each type in hl.ggs (g_spriteBase, built from the sprite metadata)
SPRITE_BASE = {EMPTY: 0, HEART: 1, GRASS: 7, ROCK: 8, EXPLOSION: 9, DWARF: 16, DOOR: 24,
               BALLOON: 28, PLASMA: 32, TUNNEL_L: 40, TUNNEL_R: 48, BRICK: 56, METAL: 60,
               BOMB: 61}

# sound effect names (record address in DGROUP -> file in the volume)
SND_ROCK, SND_HEART = 'rock', ('heart0', 'heart1', 'heart2', 'heart3')
SND_COLLECT, SND_TUNNEL, SND_DOOR_OPEN, SND_EXPLODE = 'colect', 'tunnel', 'colected', 'expl'
SND_DOOR, SND_KEY, SND_HEART_GRASS, SND_ROCK_GRASS = 'door', 'key', 'hrtgrass', 'rocgrass'

# game state values (g_gameState, DS:4C45)
PLAYING, QUIT, NEXT_LEVEL, PREV_LEVEL = 1, 4, 6, 7


class BorlandRand:
    """Borland C++ rand(): 32-bit LCG, returns bits 16..30."""

    def __init__(self, seed=1):
        self.s = seed & 0xFFFFFFFF

    def __call__(self):
        self.s = (self.s * 0x015A4E35 + 1) & 0xFFFFFFFF
        return (self.s >> 16) & 0x7FFF


class Sim:
    LEFT, RIGHT, UP, DOWN, NONE = -1, 1, -W, W, 0

    def __init__(self, rows, level_index=0, rand=None, tick_count=0):
        """rows: 12 strings of up to 20 level characters (as in LEVELS.HL)."""
        self.rand = rand or BorlandRand(_random.randrange(1 << 16))
        self.level_index = level_index
        self.tick_count = tick_count       # g_tickCount (DS:60DD), not reset between levels
        self.sounds = []                   # sounds started during the last tick
        self.setup(rows)

    # 15BE:04F9 SetupLevel
    def setup(self, rows):
        self.rows = rows
        self.type = [METAL] * N
        self.state = [0] * N
        self.frame = [0] * N
        self.pending = [1] * N
        self.hearts_left = 0
        for x in range(20):
            for y in range(12):
                row = rows[y] if y < len(rows) else ''
                c = row[x] if x < len(row) else ' '
                si = (y + 1) * W + (x + 1)
                t, s, f = METAL, 2, 0      # default case (unreachable: the parser rejects others)
                if c == ' ':
                    t, s = EMPTY, 0
                elif c == '#':
                    t, s, f = BRICK, 0, self.level_index % 4
                elif c == '%':
                    t, s = METAL, 0
                elif c == '@':
                    t, s = ROCK, 2
                elif c == '$':
                    t, s, f = HEART, 2, self.rand() * 6 // 0x8000
                    self.hearts_left += 1
                elif c == '*':
                    t, s, f = DWARF, 1, (2 if x < 10 else 0)
                elif c == '!':
                    t, s = DOOR, 5
                elif c == '&':
                    t, s = BOMB, 2
                elif c == '.':
                    t, s = GRASS, 0
                elif c == '0':
                    t, s, f = BALLOON, 2, self.rand() * 4 // 0x8000
                elif c == '=':
                    t, s = PLASMA, 2
                elif c == '<':
                    t, s = TUNNEL_L, 2
                elif c == '>':
                    t, s = TUNNEL_R, 2
                self.type[si], self.state[si], self.frame[si] = t, s, f
        self.hearts_total = self.hearts_left
        self.game_state = PLAYING
        self.death_timer = 0               # DS:60D8
        self.exit_timer = 0                # DS:60D7
        self.idle = 1                      # DS:60D2
        self.activity = 1                  # DS:60D9
        self.dir = 0                       # DS:60DB
        self.solved = False

    # helpers ---------------------------------------------------------------------------
    def _move(self, src, dst, state=None):
        """copy type/state/frame from src to dst, mark dst processed, clear src"""
        self.type[dst] = self.type[src]
        self.state[dst] = self.state[src] if state is None else state
        self.frame[dst] = self.frame[src]
        self.pending[dst] = 0
        self.type[src] = self.state[src] = self.frame[src] = 0

    def _clear(self, i):
        self.type[i] = self.state[i] = self.frame[i] = 0

    def _sound(self, name):
        self.sounds.append(name)

    # 1633:0C4D GameTick ----------------------------------------------------------------
    def tick(self, direction=0, escape=False):
        """One game tick. direction: one of LEFT/RIGHT/UP/DOWN/NONE (the original gives
        right > left > down > up priority when several arrows are held)."""
        self.sounds = []
        self.activity = 0
        self.dir = direction
        if escape and self.death_timer == 0 and self.exit_timer == 0:
            self.death_timer = 8
        self.pending = [1] * N
        for y in range(1, 13):
            for x in range(1, 21):
                si = y * W + x
                if self.state[si] == 0 or self.pending[si] == 0:
                    continue
                t = self.type[si]
                if t == EXPLOSION:
                    self.explosion_think(si)
                elif t == ROCK:
                    self.rock_think(si)
                elif t == HEART:
                    self.heart_think(si)
                elif t == BOMB:
                    self.bomb_think(si)
                elif t == DWARF:
                    self.hero_think(si)
                elif t == DOOR:
                    self.door_think(si)
                elif t == BALLOON:
                    self.balloon_think(si)
                elif t == PLASMA:
                    self.plasma_think(si)
                elif t in (TUNNEL_L, TUNNEL_R):
                    self.tunnel_think(si)
        self.tick_count = (self.tick_count + 1) & 0xFFFF
        self.idle -= 1
        if self.death_timer:
            self.death_timer -= 1
        if self.exit_timer:
            self.exit_timer -= 1

    def restart_if_over(self):
        """PlayGame restarts the level when it ends without a level change (the dwarf died)"""
        if not self.level_running() and self.game_state == PLAYING:
            self.setup(self.rows)
            return True
        return False

    def level_running(self):
        """the PlayGame loop condition (1633:1956)"""
        return self.game_state == PLAYING and self.activity != 0 and self.idle != 0

    # 1633:00C0 Hero_Think ----------------------------------------------------------------
    def hero_think(self, si):
        self.activity += 1
        self.idle = 0x20
        if self.death_timer:
            if self.death_timer > 1:
                self.frame[si] = 4 | (self.death_timer & 1)
            else:
                self._sound(SND_EXPLODE)
                self.type[si], self.state[si], self.frame[si] = EXPLOSION, 1, 0
            return
        if self.exit_timer:
            if self.exit_timer > 1:
                self.frame[si] = 6 | (self.exit_timer & 1)
            else:
                self.game_state = NEXT_LEVEL
                self.solved = True
            return
        f = self.frame[si]
        d = self.dir
        if d == -1:
            f = (f ^ 1) & 1
        elif d == 1:
            f = (f ^ 1) | 2
        elif d in (-W, W):
            f = (f & 2) | (f ^ 1)
        if d == 0:
            self.frame[si] = f & 2
            return
        di = si + d
        t = self.type[di]
        if t in (EMPTY, GRASS):                                      # 02AB
            self._hero_to(si, di, f)
        elif t in (ROCK, BOMB, BALLOON):                             # 01F9 push
            if (self.type[si + 2 * d] == EMPTY and self.state[di] == 2
                    and self.state[di - W] != 3 and d not in (-W, W)):
                if self.tick_count & 1:
                    j = si + 2 * d
                    self.type[j], self.state[j], self.frame[j] = \
                        self.type[di], self.state[di], self.frame[di]
                    self.pending[j] = 0
                    self._hero_to(si, di, f)
                else:
                    self.frame[si] = f
            else:
                self.frame[si] = f & 2
        elif t == HEART:                                             # 038A
            if self.state[di] == 2:
                self._sound(SND_COLLECT)
                self._hero_to(si, di, f)
                self.hearts_left -= 1
            # a falling heart blocks the hero; his frame is left unchanged
        elif t == DOOR:                                              # 03F7
            if self.state[di] == 6:
                self._sound(SND_DOOR)
                self._hero_to(si, di, f)
                self.exit_timer = 0x10
            else:
                self.frame[si] = f & 2
        elif t in (TUNNEL_L, TUNNEL_R):                              # 02D4
            if (t == TUNNEL_L and d == -1) or (t == TUNNEL_R and d == 1):
                j = di
                while self.type[j] == t:
                    j += d
                if self.type[j] in (EMPTY, GRASS):
                    self._sound(SND_TUNNEL)
                    self.state[di] = 1
                    self.pending[di] = 0
                    self._clear(si)
                    return
            self.frame[si] = f & 2
        else:                                                        # 0471
            self.frame[si] = f & 2

    def _hero_to(self, si, di, f):
        self.type[di], self.state[di], self.frame[di] = DWARF, 1, f
        self.pending[di] = 0
        self._clear(si)

    # 1633:04AB Tunnel_Think --------------------------------------------------------------
    def tunnel_think(self, si):
        st = self.state[si]
        d = -1 if self.type[si] == TUNNEL_L else 1
        if st == 1:                         # the dwarf is inside this cell
            self.activity += 1
            self.idle = 0x20
            self.frame[si] = ((self.frame[si] + 1) & 3) | 4
            self.state[si] = 2
            n = si + d
            t = self.type[n]
            if t in (TUNNEL_L, TUNNEL_R):
                if t == self.type[si]:
                    self.state[n] = 1
                    self.pending[n] = 0
            elif t in (EMPTY, GRASS):
                self.state[si] = 3
        elif st == 2:
            self.frame[si] = (self.frame[si] + 1) & 3
        elif st == 3:                       # the dwarf leaves the tunnel
            self.activity += 1
            self.idle = 0x20
            self.frame[si] = (self.frame[si] + 1) & 3
            self.state[si] = 2
            n = si + d
            if self.type[n] in (GRASS, EMPTY):
                self.type[n], self.state[n] = DWARF, 1
                self.frame[n] = 0 if self.type[si] == TUNNEL_L else 2
                self.pending[n] = 0

    # 1633:05B5 Gravity (rock, heart, bomb) -----------------------------------------------
    def gravity(self, di):
        landed = 0
        if self.state[di] == 2:
            b = self.type[di + W]
            if b == EMPTY:
                self.state[di] = 3
                self.activity += 1
            elif b in (EXPLOSION, BRICK, ROCK, HEART, PLASMA) or \
                    (b == BOMB and self.frame[di + W] == 0):
                if (self.type[di - 1] == EMPTY and self.type[di + W - 1] == EMPTY
                        and self.state[di - W - 1] != 3):
                    self._move(di, di - 1, state=3)
                    self.activity += 1
                elif (self.type[di + 1] == EMPTY and self.type[di + W + 1] == EMPTY
                        and self.state[di - W + 1] != 3):
                    self._move(di, di + 1, state=3)
                    self.activity += 1
            elif b == BALLOON:
                if self.type[di + 2 * W] == EMPTY and self.type[di - W] in (ROCK, HEART, BOMB):
                    self._move(di + W, di + 2 * W)
                    self.state[di] = 3
        if self.state[di] == 3:
            self.activity += 1
            b = self.type[di + W]
            if b == EMPTY:
                self._move(di, di + W)
            elif b == BOMB:
                self.state[di + W] = 8
                self.state[di] = 2
                landed = 1
            elif b == DWARF:
                if self.frame[di + W] < 6:
                    self._sound(SND_EXPLODE)
                    self.type[di + W], self.state[di + W], self.frame[di + W] = EXPLOSION, 1, 0
                    self.pending[di + W] = 0
                self.state[di] = 2
                landed = 1
            else:
                self.state[di] = 2
                landed = 1
        return landed

    # 1633:07A7 Rock_Think
    def rock_think(self, si):
        if self.gravity(si):
            self._sound(SND_ROCK_GRASS if self.type[si + W] == GRASS else SND_ROCK)

    # 1633:0824 Heart_Think
    def heart_think(self, si):
        self.frame[si] = (self.frame[si] + 1) % 6
        if self.gravity(si):
            if self.type[si + W] == GRASS:
                self._sound(SND_HEART_GRASS)
            else:
                self._sound(SND_HEART[self.rand() * 4 // 0x8000])

    # 1633:098D Bomb_Think
    def bomb_think(self, di):
        if self.gravity(di):
            if self.type[di + W] != GRASS:
                self.state[di] = 8
            else:
                self._sound(SND_ROCK_GRASS)
        if self.state[di] != 8:
            return
        if self.frame[di] == 0:             # lit: explodes on its next turn
            self.frame[di] = 1
            b = di + W
            if self.type[b] == DWARF and self.frame[b] >= 6:
                return
            if self.type[b] == BOMB:
                return
            self.pending[b] = 0
            return
        self._sound(SND_EXPLODE)
        self.type[di], self.state[di], self.frame[di] = EXPLOSION, 1, 1
        for d in (-1, 1, -W, W):
            n = di + d
            t = self.type[n]
            if t in (METAL, TUNNEL_L, TUNNEL_R):
                continue
            if t == BOMB:
                self.state[n] = 8
                self.pending[n] = 0
                continue
            if t == DWARF and self.frame[n] >= 6:
                continue
            self.type[n], self.state[n], self.frame[n] = EXPLOSION, 1, 0

    # 1633:0AE5 Balloon_Think
    def balloon_think(self, di):
        self.frame[di] = (self.frame[di] + 1) & 3
        if self.state[di] == 2:
            a = self.type[di - W]
            if a == EMPTY:
                self.state[di] = 7
                self.activity += 1
            elif a in (ROCK, HEART, BOMB, DWARF):
                if self.type[di - 2 * W] == EMPTY:
                    j, k = di - 2 * W, di - W
                    self.type[j], self.state[j], self.frame[j] = \
                        self.type[k], self.state[k], self.frame[k]
                    self._clear(k)
                    self.state[di] = 7
        if self.state[di] == 7:
            self.activity += 1
            if self.type[di - W] == EMPTY:
                self._move(di, di - W)
            else:
                self.state[di] = 2

    # 1633:0BAF Door_Think
    def door_think(self, si):
        if self.frame[si] < 3:
            if self.hearts_left == 0:
                if self.frame[si] == 0:
                    self._sound(SND_DOOR_OPEN)
                self.frame[si] += 1
        else:
            self.state[si] = 6

    # 1633:0C08 Explosion_Think
    def explosion_think(self, si):
        self.activity += 1
        if self.frame[si] < 6:
            self.frame[si] += 1
        else:
            self._clear(si)

    # 1633:0C37 Plasma_Think
    def plasma_think(self, si):
        self.frame[si] = (self.frame[si] + 1) & 7

    # views -------------------------------------------------------------------------------
    def cell(self, x, y):
        si = (y + 1) * W + (x + 1)
        return self.type[si], self.state[si], self.frame[si]

    def sprite(self, x, y):
        t, _, f = self.cell(x, y)
        return SPRITE_BASE[t] + f

    def hero_pos(self):
        for i in range(N):
            if self.type[i] == DWARF:
                return (i % W - 1, i // W - 1)
        return None

    def dump(self):
        rows = []
        for y in range(12):
            rows.append(''.join(LEVEL_CHARS[[EMPTY, HEART, ROCK, GRASS, DWARF, DOOR, BOMB, BALLOON,
                                             PLASMA, BRICK, METAL, TUNNEL_L, TUNNEL_R].index(t)]
                                if t != EXPLOSION else 'x'
                                for t in (self.cell(x, y)[0] for x in range(20))))
        return '\n'.join(rows)
