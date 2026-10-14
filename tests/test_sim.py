#!/usr/bin/env python3
"""Fast checks of tools/hl_sim.py on tiny hand-made levels (no emulator needed).

Each case pins one rule of docs/reverse-engineering/03-engine.md, as observed in the original.
Run: python3 -m pytest tests  or  python3 tests/test_sim.py
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'tools'))
from hl_sim import (Sim, BorlandRand, EMPTY, EXPLOSION, BRICK, ROCK, HEART, BOMB, DWARF,  # noqa
                    DOOR, BALLOON, TUNNEL_R, NEXT_LEVEL)
from hl_levels import load  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..')


def level(*rows):
    rows = list(rows) + [''] * (12 - len(rows))
    return rows


def sim(rows, parity=1):
    return Sim(level(*rows), level_index=0, rand=BorlandRand(1), tick_count=parity)


def t(s, x, y):
    return s.cell(x, y)[0]


def test_falls_one_cell_per_tick_starting_at_once():
    s = sim(['@', '', '', '', '#*!'])
    s.tick()
    assert t(s, 0, 1) == ROCK and t(s, 0, 0) == EMPTY
    s.tick()
    assert t(s, 0, 2) == ROCK


def test_rolls_off_brick_left_first_not_off_metal_or_grass():
    s = sim([' @ ', ' # ', '', '', '*!'])
    s.tick()
    assert t(s, 0, 0) == ROCK            # rolled left (and falls next tick)
    s = sim([' @ ', ' % ', '', '', '*!'])
    s.tick()
    assert t(s, 1, 0) == ROCK            # metal: stays
    s = sim([' @ ', ' . ', '', '', '*!'])
    s.tick()
    assert t(s, 1, 0) == ROCK            # grass: stays


def test_rock_kills_dwarf():
    s = sim(['@', '', '*', '%', '', '!'])
    s.tick()
    s.tick()
    assert t(s, 0, 2) == EXPLOSION and 'expl' in s.sounds


def test_push_only_on_odd_ticks():
    s = sim(['*@ ', '%%%', '!'], parity=0)
    s.tick(Sim.RIGHT)                    # even tick: turns only
    assert s.hero_pos() == (0, 0) and t(s, 1, 0) == ROCK
    s.tick(Sim.RIGHT)                    # odd tick: pushes
    assert s.hero_pos() == (1, 0) and t(s, 2, 0) == ROCK


def test_collect_and_door_opens_in_four_ticks():
    s = sim(['*$!', '%%%'])
    s.tick(Sim.RIGHT)
    assert s.hearts_left == 0 and 'colect' in s.sounds
    assert s.cell(2, 0)[2] == 1          # the door, scanned after the dwarf, starts at once
    for _ in range(2):
        s.tick()
    assert s.cell(2, 0)[1:] == (5, 3)    # frame 3, still closed
    s.tick()
    assert s.cell(2, 0)[1] == 6          # open
    s.tick(Sim.RIGHT)
    assert 'door' in s.sounds and s.exit_timer == 15   # set to 16, counted down at tick end
    while s.level_running():
        s.tick()
    assert s.game_state == NEXT_LEVEL and s.solved


def test_bomb_lands_lights_and_explodes():
    s = sim(['&', '', '#', '', '', '*!'])
    s.tick()                             # falls to row 1, lands on brick
    s.tick()
    assert s.cell(0, 1)[1] == 8          # lit
    s.tick()
    assert s.cell(0, 1)[2] == 1          # lit frame
    s.tick()
    assert t(s, 0, 1) == EXPLOSION and t(s, 0, 2) == EXPLOSION   # brick destroyed


def test_bomb_on_grass_does_not_explode():
    s = sim(['&', '', '.', '', '', '*!'])
    for _ in range(5):
        s.tick()
    assert t(s, 0, 1) == BOMB and s.cell(0, 1)[1] == 2


def test_balloon_lifts_dwarf():
    s = sim(['', '', '*', '0', '%', '!'])
    s.tick()
    assert s.hero_pos() == (0, 1) and t(s, 0, 2) == BALLOON


def test_tunnel_one_cell_per_tick():
    s = sim(['*>> ', '%%%%', '!'])
    s.tick(Sim.RIGHT)
    assert s.hero_pos() is None and s.cell(1, 0)[1] == 1
    s.tick()
    s.tick()
    s.tick()
    assert s.hero_pos() == (3, 0)


def test_esc_dies_after_seven_ticks():
    s = sim(['*!'])
    s.tick(escape=True)                  # 7 ticks blinking (frames 4/5) ...
    for _ in range(6):
        assert t(s, 0, 0) == DWARF and s.cell(0, 0)[2] in (4, 5)
        s.tick()
    assert t(s, 0, 0) == DWARF
    s.tick()                             # ... then the explosion
    assert t(s, 0, 0) == EXPLOSION


def test_idle_dwarf_survives_except_level_30():
    killed = []
    for lv in load(os.path.join(ROOT, 'original', 'LEVELS.HL')):
        s = Sim(lv.rows, lv.index, BorlandRand(1))
        for tick in range(200):
            s.tick()
            if s.hero_pos() is None:
                killed.append((lv.index + 1, tick))
                break
    # level 30: the rocks on top of the pyramid roll down onto the dwarf (as in the original)
    assert killed == [(30, 23)]


if __name__ == '__main__':
    n = 0
    for name, fn in list(globals().items()):
        if name.startswith('test_'):
            fn()
            n += 1
    print(n, 'tests passed')
