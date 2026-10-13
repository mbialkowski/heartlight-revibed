#!/usr/bin/env python3
"""Checks tools/hl_sim.py against the original game running in DOSBox.

The original is driven with xdotool (an X server such as Xvfb is needed) and captured with
DOSBox's own screenshot key (Ctrl+F5, exact 320x200 palette images). Every capture is read back
into a (type, frame) grid with tools/screen_reader.py and must appear, in order, in the
simulator's trajectory for the same level and inputs. Animation frames that depend on
rand() (hearts, balloons) are ignored; all other frames, including the plasma and tunnel
animations that count ticks from the level start, must match.

A key press lands on exactly one tick (the original latches presses between polls), but which
tick is unknown, and the push rule depends on tick parity: the checker therefore keeps every
simulator candidate (press on any of the next few ticks, either parity) that agrees with all
captures so far. A level passes when at least one candidate explains every capture.

    Xvfb :99 &  python3 tools/golden_check.py original/ --levels 1-70 --display :99 \\
        --script tests/golden_scenarios.json --out tests/golden_report.json

Each level is reached with Space+Right/Left (the current level is recognised from its walls),
restarted with Esc, captured at rest, then played. Scenario files (--script) give per level the
moves: "L","R","U","D" (one key tap each, about half a second apart), "E" (Esc).
"""
import argparse
import copy
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from hl_levels import load as load_levels  # noqa: E402
from hl_sim import Sim, HEART, BALLOON, PLASMA, TUNNEL_L, TUNNEL_R, BorlandRand  # noqa: E402
from hl_volume import Volume  # noqa: E402
from screen_reader import ScreenReader  # noqa: E402

RANDOM_FRAMES = (HEART, BALLOON)       # initial frame comes from rand()
KEYS = {'L': 'Left', 'R': 'Right', 'U': 'Up', 'D': 'Down', 'E': 'Escape'}
DIRS = {'L': Sim.LEFT, 'R': Sim.RIGHT, 'U': Sim.UP, 'D': Sim.DOWN}


ALIAS = {}
RECORD = []


def norm_sim(sim):
    out = []
    for y in range(12):
        row = []
        for x in range(20):
            t, s, f = sim.cell(x, y)
            if t in RANDOM_FRAMES:
                f = None
            row.append(ALIAS.get((t, f), (t, f)))
        out.append(tuple(row))
    return tuple(out)


def norm_screen(grid):
    out = []
    for row in grid:
        r = []
        for c in row:
            if c is None:
                r.append(None)
                continue
            t, f = c
            if t in RANDOM_FRAMES:
                f = None
            r.append((t, f))
        out.append(tuple(r))
    return tuple(out)


def same(screen, sim):
    for rs, rm in zip(screen, sim):
        for a, b in zip(rs, rm):
            if a is not None and a != b:
                return False
    return True


class DOSBox:
    def __init__(self, game_dir, display=':99'):
        self.env = dict(os.environ, DISPLAY=display, SDL_AUDIODRIVER='dummy')
        self.tmp = tempfile.mkdtemp(prefix='hlgold')
        self.run = os.path.join(self.tmp, 'run')
        self.cap = os.path.join(self.tmp, 'cap')
        os.makedirs(self.cap)
        shutil.copytree(game_dir, self.run, ignore=shutil.ignore_patterns('*.stt', '*.conf', '*.md'))
        conf = os.path.join(self.tmp, 'dosbox.conf')
        open(conf, 'w').write(f"""[sdl]
output=surface
[dosbox]
captures={self.cap}
[render]
scaler=none
[cpu]
cycles=20000
[autoexec]
mount c {self.run}
c:
hl
""")
        self.proc = subprocess.Popen(['dosbox', '-conf', conf], env=self.env,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(3)
        self.win = self._xdo('search', '--pid', str(self.proc.pid)).split()[-1]
        self.shots = 0

    def _xdo(self, *args):
        return subprocess.run(['xdotool', *args], env=self.env, capture_output=True,
                              text=True).stdout

    def key(self, name, hold=0.03):
        self._xdo('keydown', '--window', self.win, name)
        time.sleep(hold)
        self._xdo('keyup', '--window', self.win, name)

    def combo(self, mod, name):
        self._xdo('keydown', '--window', self.win, mod)
        time.sleep(0.05)
        self.key(name)
        time.sleep(0.05)
        self._xdo('keyup', '--window', self.win, mod)

    def shot(self):
        from PIL import Image
        before = set(os.listdir(self.cap))
        self._xdo('key', '--window', self.win, 'ctrl+F5')
        for _ in range(50):
            time.sleep(0.02)
            new = set(os.listdir(self.cap)) - before
            if new:
                f = os.path.join(self.cap, new.pop())
                time.sleep(0.05)
                img = Image.open(f)
                img.load()
                return img
        raise RuntimeError('no capture')

    def close(self):
        self.proc.kill()
        shutil.rmtree(self.tmp, ignore_errors=True)


def key_of(sim):
    return (norm_sim(sim), sim.tick_count & 1, sim.death_timer, sim.exit_timer, sim.hearts_left,
            tuple(sim.state))


def advance_to(cands, cap, max_ticks=80, limit=300):
    """advance each candidate with no input; keep every state within the window that shows
    `cap` (the same picture can hide different tick parities or fuse states)"""
    out = {}
    for sim in cands:
        s = copy.deepcopy(sim)
        for _ in range(max_ticks):
            if same(cap, norm_sim(s)):
                k = key_of(s)
                if k not in out:
                    out[k] = copy.deepcopy(s)
            if not s.level_running() and not s.restart_if_over():
                break
            s.tick()
            if len(out) >= limit:
                break
    return list(out.values())


def apply_move(cands, m, max_wait=12):
    """the key press lands on one of the next few ticks"""
    out = {}
    for sim in cands:
        s = copy.deepcopy(sim)
        for _ in range(max_wait):
            s.restart_if_over()
            t = copy.deepcopy(s)
            t.tick(DIRS.get(m, 0), m == 'E')
            out.setdefault(key_of(t), t)
            s.tick()
    return list(out.values())


def check_level(box, reader, levels, n, moves, shots_per_phase=5):
    """the game must already show level n (1-based); returns (ok, detail)"""
    lv = levels[n - 1]
    cands = [Sim(lv.rows, level_index=n - 1, rand=BorlandRand(1), tick_count=p) for p in (0, 1)]

    def phase(k):
        nonlocal cands
        for _ in range(k):
            cap = norm_screen(reader.read(box.shot()))
            RECORD.append(('cap', cap))
            new = advance_to(cands, cap)
            if not new:
                return cap
            cands = new
            time.sleep(0.1)
        return None

    bad = phase(shots_per_phase)
    for i, m in enumerate(moves):
        if bad is not None:
            break
        box.key(KEYS[m])
        RECORD.append(('key', m))
        cands = apply_move(cands, m)
        time.sleep(0.3)
        bad = phase(2)
    if bad is None:
        time.sleep(1.0)
        bad = phase(2)
    if bad is None:
        return True, dict(candidates=len(cands))
    # closest candidate state within the next ticks, for the report
    best, diff = None, None
    for sim in cands:
        s = copy.deepcopy(sim)
        for _ in range(40):
            st = norm_sim(s)
            d = [(x, y, bad[y][x], st[y][x]) for y in range(12) for x in range(20)
                 if bad[y][x] is not None and bad[y][x] != st[y][x]]
            if diff is None or len(d) < len(diff):
                best, diff = s.dump(), d
            s.tick()
    return False, dict(screen=ScreenReader.text(
        [[None if c is None else (c[0], c[1] or 0) for c in row] for row in bad]),
        expected=best, diff=[f'({x},{y}) original {a} sim {b}' for x, y, a, b in diff])


STATIC = (2, 3, 7, 9, 11, 12, 13)    # brick, metal, grass, door, plasma, tunnels


def which_level(cap, statics):
    """index of the level whose static cells (walls, grass, door...) best match the capture"""
    best, score = None, -1
    for i, st in enumerate(statics):
        s = 0
        for y in range(12):
            for x in range(20):
                c = cap[y][x]
                if c is not None and (c[0] in STATIC) == (st[y][x] is not None):
                    s += 1 if st[y][x] is None or c[0] == st[y][x] else 0
        if s > score:
            best, score = i, s
    return best


def goto_level(box, reader, statics, n, cur):
    for _ in range(80):
        cap = norm_screen(reader.read(box.shot()))
        cur = which_level(cap, statics) + 1
        if cur == n:
            return cur
        if cur < n:
            box.combo('space', 'Right')
        else:
            box.combo('space', 'Left')
        time.sleep(2.5)
    raise RuntimeError(f'cannot reach level {n}')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('game_dir')
    ap.add_argument('--levels', default='1-70')
    ap.add_argument('--script', help='JSON {level: "RRDL..."}')
    ap.add_argument('--out')
    ap.add_argument('--display', default=os.environ.get('DISPLAY', ':99'))
    a = ap.parse_args()
    lo, hi = (int(v) for v in a.levels.split('-')) if '-' in a.levels else (int(a.levels),) * 2
    levels = load_levels(os.path.join(a.game_dir, 'LEVELS.HL'))
    reader = ScreenReader(Volume(os.path.join(a.game_dir, 'HL.EXE')).read('hl.ggs'))
    ALIAS.update(reader.alias)
    script = json.load(open(a.script)) if a.script else {}
    box = DOSBox(a.game_dir, display=a.display)
    report = {}
    try:
        time.sleep(4)
        box.key('space')                      # title -> level 1
        time.sleep(3)
        statics = []
        for lv in levels:
            sim = Sim(lv.rows, lv.index, BorlandRand(1))
            statics.append([[sim.cell(x, y)[0] if sim.cell(x, y)[0] in STATIC else None
                             for x in range(20)] for y in range(12)])
        cur = 1
        for n in range(lo, hi + 1):
            cur = goto_level(box, reader, statics, n, cur)
            box.key('Escape')                 # restart it: a clean start for the check
            time.sleep(3.5)
            moves = script.get(str(n), '')
            ok, detail = check_level(box, reader, levels, n, moves)
            report[n] = dict(ok=ok, moves=moves, detail=detail)
            print(f'level {n:2d} {"OK " if ok else "FAIL"} {moves}', flush=True)
            if not ok:
                print(detail['screen'])
                print('-- simulator --')
                print(detail['expected'])
                print('differences:', '; '.join(detail['diff']))
    finally:
        box.close()
    if a.out:
        json.dump(report, open(a.out, 'w'), indent=1)
    print(sum(r['ok'] for r in report.values()), '/', len(report), 'levels match')


if __name__ == '__main__':
    main()
