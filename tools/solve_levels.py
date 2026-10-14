#!/usr/bin/env python3
"""Finds a solution for every level and records it in tests/solutions.json.

The search runs in C (tools/solver/hlsolve.c: the rules of tools/hl_sim.py ported to C, and a
beam search over ticks). Before searching, the C rules are checked against every golden trace
(remake/data/golden_traces.json, made from hl_sim.py); every solution found is then replayed with
hl_sim.py itself and kept only if it ends the level there.

A solution is one character per tick from the start of the level: '.' nothing, 'L' 'R' 'U' 'D' a
held direction. The level starts with tick_count 0 (pushing works on odd ticks).

    python3 tools/solve_levels.py original/LEVELS.HL tests/solutions.json [--levels 1-70]
"""
import argparse
import ctypes
import json
import os
import subprocess
import sys
import tempfile
from concurrent.futures import ProcessPoolExecutor

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from hl_levels import load  # noqa: E402
from hl_sim import Sim, BorlandRand, PLAYING, NEXT_LEVEL  # noqa: E402

DIRS = {'.': 0, 'L': Sim.LEFT, 'R': Sim.RIGHT, 'U': Sim.UP, 'D': Sim.DOWN, 'E': 0}
LIB = None


def lib():
    global LIB
    if LIB is None:
        so = os.path.join(tempfile.gettempdir(), 'hlsolve.so')
        src = os.path.join(HERE, 'solver', 'hlsolve.c')
        if not os.path.exists(so) or os.path.getmtime(so) < os.path.getmtime(src):
            subprocess.check_call(['cc', '-O2', '-shared', '-fPIC', '-o', so, src])
        LIB = ctypes.CDLL(so)
        LIB.sim_hash.restype = ctypes.c_uint32
        LIB.solve.restype = ctypes.c_int
    return LIB


def grid(rows):
    return ''.join((rows[y] if y < len(rows) else '').ljust(20)[:20] for y in range(12)).encode('latin-1')


def verify_port(traces_path, levels):
    """the C rules against every golden trace: the state hash after every tick"""
    traces = json.load(open(traces_path))['traces']
    c = lib()
    for t in traces:
        lv = levels[t['level'] - 1]
        c.sim_new(grid(lv.rows), lv.index, t['seed'], t['parity'])
        for i, ch in enumerate(t['inputs']):
            r = c.sim_step(DIRS[ch], ch == 'E')
            want = t['hashes'][i]
            if isinstance(want, list):
                if c.sim_hash() != want[0]:
                    return f"{t['name']}: tick {i} (before the restart)"
                c.sim_restart()
                want = want[1]
            if c.sim_hash() != want:
                return f"{t['name']}: tick {i}"
            if r == 2:
                break
    return None


def check(lv, inputs):
    """replays a solution with hl_sim.py: True when the level ends with the dwarf in the door"""
    s = Sim(lv.rows, lv.index, BorlandRand(1), tick_count=0)
    for ch in inputs:
        s.tick(DIRS[ch], False)
        if not s.level_running():
            return s.game_state == NEXT_LEVEL
    return False


def solve_one(args):
    path, n, beams, max_ticks = args
    lv = load(path)[n - 1]
    c = lib()
    out = ctypes.create_string_buffer(8192)
    for beam in beams:
        for seed in (33, 1, 2):   # 33: no diversity cap; 1, 2: capped buckets, other brick costs
            k = c.solve(grid(lv.rows), lv.index, beam, max_ticks, 0, seed, out)
            if k > 0:
                sol = out.value.decode()
                if check(lv, sol):
                    return n, sol, beam
    return n, None, None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('levels_hl')
    ap.add_argument('out')
    ap.add_argument('--levels', default='1-70')
    ap.add_argument('--beams', default='5000,50000')
    ap.add_argument('--max-ticks', type=int, default=3000)
    ap.add_argument('--jobs', type=int, default=os.cpu_count())
    ap.add_argument('--traces', default=os.path.join(HERE, '..', 'remake', 'data', 'golden_traces.json'))
    a = ap.parse_args()
    levels = load(a.levels_hl)
    err = verify_port(a.traces, levels)
    if err:
        sys.exit('the C rules differ from hl_sim.py: ' + err)
    print('C rules match all golden traces', flush=True)
    lo, hi = (int(v) for v in a.levels.split('-')) if '-' in a.levels else (int(a.levels),) * 2
    beams = [int(b) for b in a.beams.split(',')]
    result = json.load(open(a.out)) if os.path.exists(a.out) else {'note': __doc__.split('\n\n')[2], 'levels': {}}
    todo = [n for n in range(lo, hi + 1) if str(n) not in result['levels']]
    with ProcessPoolExecutor(a.jobs) as ex:
        for n, sol, beam in ex.map(solve_one, [(a.levels_hl, n, beams, a.max_ticks) for n in todo]):
            if sol:
                result['levels'][str(n)] = {'inputs': sol, 'ticks': len(sol)}
                print(f'level {n:2d}: solved in {len(sol)} ticks (beam {beam})', flush=True)
                result['levels'] = dict(sorted(result['levels'].items(), key=lambda kv: int(kv[0])))
                json.dump(result, open(a.out, 'w'), indent=1)
            else:
                print(f'level {n:2d}: no solution found', flush=True)
    print(f"{len(result['levels'])} / 70 levels solved")


if __name__ == '__main__':
    main()
