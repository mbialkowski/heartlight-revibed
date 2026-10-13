#!/usr/bin/env python3
"""Builds move scenarios for tools/golden_check.py: per level, the random walk (of N single
moves, each followed by a wait until the level is at rest) that triggers the most different
events in the simulator (sounds, pushes, deaths). Deterministic (seeded).

    python3 tools/make_scenarios.py original/LEVELS.HL tests/golden_scenarios.json
"""
import json
import random
import sys
import os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hl_levels import load  # noqa: E402
from hl_sim import Sim, BorlandRand, DWARF  # noqa: E402

DIRS = {'L': Sim.LEFT, 'R': Sim.RIGHT, 'U': Sim.UP, 'D': Sim.DOWN}


def run(lv, moves, parity=1):
    s = Sim(lv.rows, lv.index, BorlandRand(1), tick_count=parity)
    events = set()
    for m in moves:
        for _ in range(2):           # the press lands on an odd tick in one of two ticks
            if s.tick_count & 1 == 1:
                break
            s.tick()
        before = list(s.type)
        s.tick(DIRS[m])
        events.update(s.sounds)
        moved = [i for i in range(len(before)) if before[i] != s.type[i] and before[i] not in (0, 7, 8)]
        if len(moved) >= 1 and DWARF in [s.type[i] for i in moved]:
            events.add('push')
        for _ in range(60):
            prev = (list(s.type), list(s.state))
            s.tick()
            events.update(s.sounds)
            if not s.level_running():
                events.add('end')
                return events
            if (list(s.type), list(s.state)) == prev:
                break
    return events


def main():
    levels = load(sys.argv[1])
    rnd = random.Random(1994)
    out = {}
    for lv in levels:
        best = (-1, '')
        for _ in range(300):
            moves = ''.join(rnd.choice('LRUD') for _ in range(16))
            ev = run(lv, moves)
            score = len(ev)
            if score > best[0]:
                best = (score, moves, sorted(ev))
        out[str(lv.index + 1)] = best[1]
        print(lv.index + 1, best[1], best[2])
    json.dump(out, open(sys.argv[2], 'w'), indent=1)


if __name__ == '__main__':
    main()
