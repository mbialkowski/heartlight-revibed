#!/usr/bin/env python3
"""LEVELS.HL reader with the original parser's rules (HL.EXE 1914:0004 ParseLevelFile).

* Lines are read up to '\\n' (text mode, so CR LF is fine); only the first 20 characters of a
  line count, shorter lines are padded with spaces.
* Everything outside '{' ... '}' blocks is a comment. A block starts with a line whose first
  character is '{' and ends with a line starting with '}'.
* A block must have exactly 12 lines, at least one '*' (dwarf) and one '!' (exit), and only
  the characters " $@.*!&0=#%<>". Up to 199 levels.

    python3 tools/hl_levels.py LEVELS.HL [--json out.json]
"""
import argparse
import json
import re

LEVEL_CHARS = ' $@.*!&0=#%<>'
MAX_LEVELS = 199


class LevelError(Exception):
    pass


class Level:
    def __init__(self, index, rows, comments):
        self.index = index
        self.rows = rows               # 12 strings of exactly 20 characters
        self.comments = comments       # comment lines before the block
        self.author = None
        for c in comments:
            m = re.match(r'\s*author\s*:\s*(.*\S)', c)
            if m:
                self.author = m.group(1)

    def count(self, ch):
        return sum(r.count(ch) for r in self.rows)


def parse(text):
    lines = text.replace('\x1a', '').split('\n')
    levels, comments, block = [], [], None
    for lineno, raw in enumerate(lines, 1):
        line = raw.rstrip('\r')[:20]
        if block is None:
            if line.startswith('{'):
                block = []
            elif raw.strip():
                comments.append(raw.rstrip('\r'))
            continue
        if line.startswith('}'):
            n = len(levels) + 1
            if len(block) < 12:
                raise LevelError(f'Not enough lines in level #{n}! (line {lineno})')
            if not any('*' in r for r in block):
                raise LevelError(f'No hero on level #{n}!')
            if not any('!' in r for r in block):
                raise LevelError(f'No exit on level #{n}!')
            levels.append(Level(len(levels), block, comments))
            if len(levels) >= MAX_LEVELS:
                raise LevelError(f'Too many levels defined (max={MAX_LEVELS})!')
            block, comments = None, []
            continue
        if len(block) == 12:
            raise LevelError(f'Too many lines in level #{len(levels) + 1}! (line {lineno})')
        bad = [c for c in line if c not in LEVEL_CHARS]
        if bad:
            raise LevelError(f'Invalid object on level #{len(levels) + 1}! {bad[0]!r} line {lineno}')
        block.append(line.ljust(20))
    if not levels:
        raise LevelError('No levels in file')
    return levels


def load(path):
    return parse(open(path, 'rb').read().decode('latin1'))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('levels')
    ap.add_argument('--json')
    a = ap.parse_args()
    levels = load(a.levels)
    for lv in levels:
        print(f'level {lv.index + 1:2d}  hearts {lv.count("$"):3d}  rocks {lv.count("@"):3d}  '
              f'bombs {lv.count("&"):2d}  balloons {lv.count("0"):2d}  author {lv.author}')
    if a.json:
        json.dump([dict(level=lv.index + 1, author=lv.author, hearts=lv.count('$'), rows=lv.rows)
                   for lv in levels], open(a.json, 'w'), indent=1)


if __name__ == '__main__':
    main()
