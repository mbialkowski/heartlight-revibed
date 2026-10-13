#!/usr/bin/env python3
"""Golden traces for the remake: tools/hl_sim.py (verified against the original, 70/70 levels)
run on fixed inputs; the remake must reproduce every tick.

    python3 tools/make_golden_traces.py original/LEVELS.HL tests/golden_scenarios.json \\
        remake/data/golden_traces.json

Per level four traces: 'idle' (no input), 'scenario0'/'scenario1' (the DOSBox scenario moves at
fixed ticks, tick parity 0/1), 'random' (seeded random held directions and an Esc now and then).
Each trace stores the input of every tick ('.', L R U D, E = Esc), and per tick a checksum of the
state (state_hash), the sounds started and, every 50 ticks, the full type grid. A level that ends
with the dwarf dead restarts as in the original; a level change ends the trace.
"""
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hl_levels import load  # noqa: E402
from hl_sim import Sim, BorlandRand, PLAYING  # noqa: E402

DIRS = {'.': 0, 'L': Sim.LEFT, 'R': Sim.RIGHT, 'U': Sim.UP, 'D': Sim.DOWN, 'E': 0}


def state_hash(s):
    """FNV-1a 32 over type, state, frame (308 bytes each) and the counters; sim.gd has the same"""
    h = 0x811C9DC5
    data = (list(s.type) + list(s.state) + list(s.frame) +
            [s.hearts_left & 0xFF, s.death_timer & 0xFF, s.exit_timer & 0xFF, s.game_state & 0xFF,
             s.idle & 0xFF, s.activity & 0xFF, s.tick_count & 0xFF])
    for b in data:
        h ^= b & 0xFF
        h = (h * 0x01000193) & 0xFFFFFFFF
    return h


def run(lv, inputs, parity, seed):
    s = Sim(lv.rows, lv.index, BorlandRand(seed), tick_count=parity)
    hashes, sounds, grids = [], {}, {}
    played = ''
    for t, c in enumerate(inputs):
        s.tick(DIRS[c], c == 'E')
        played += c
        hashes.append(state_hash(s))
        if s.sounds:
            sounds[str(t)] = list(s.sounds)
        if t % 50 == 49:
            grids[str(t)] = list(s.type)
        if not s.level_running():
            if s.game_state != PLAYING:
                break
            s.restart_if_over()
            hashes[-1] = [hashes[-1], state_hash(s)]   # [before, after the restart]
    return dict(level=lv.index + 1, parity=parity, seed=seed, inputs=played,
                hashes=hashes, sounds=sounds, grids=grids, end_state=s.game_state)


def scenario_inputs(moves, length=300):
    out = ['.'] * length
    for i, m in enumerate(moves):
        t = 6 + 9 * i
        if t < length:
            out[t] = m
    return ''.join(out)


def random_inputs(rnd, length=400):
    out = []
    while len(out) < length:
        c = rnd.choice('LRUD.....')
        if rnd.random() < 0.01:
            c = 'E'
        out += [c] * (1 if c == 'E' else rnd.randint(1, 4))
    return ''.join(out[:length])


def main():
    levels = load(sys.argv[1])
    scen = json.load(open(sys.argv[2]))
    rnd = random.Random(70)
    traces = []
    for lv in levels:
        n = lv.index + 1
        traces.append(dict(name=f'{n}/idle', **run(lv, '.' * 300, 0, n)))
        for p in (0, 1):
            traces.append(dict(name=f'{n}/scenario{p}', **run(lv, scenario_inputs(scen[str(n)]), p, n)))
        traces.append(dict(name=f'{n}/random', **run(lv, random_inputs(rnd), 1, n + 1000)))
    json.dump(dict(note='tools/make_golden_traces.py; see its docstring', traces=traces),
              open(sys.argv[3], 'w'), separators=(',', ':'))
    print(len(traces), 'traces,', sum(len(t['hashes']) for t in traces), 'ticks')


if __name__ == '__main__':
    main()
