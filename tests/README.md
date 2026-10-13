# Tests

* `golden_scenarios.json` — per level, the 16 moves played by `tools/golden_check.py`
  (generated with `tools/make_scenarios.py`, seed 1994).
* `golden_report.json` — the result of the last run against the original in DOSBox.
* `test_sim.py` — fast checks of `tools/hl_sim.py` that need no emulator (`python3 -m pytest tests`
  or `python3 tests/test_sim.py`).

Running the golden check (needs DOSBox, Xvfb, xdotool):

```bash
Xvfb :99 -screen 0 1024x768x24 &
DISPLAY=:99 python3 tools/golden_check.py original/ --levels 1-70 \
    --script tests/golden_scenarios.json --out tests/golden_report.json
```
