"""Reference model of the missile / ball graphics run (spec 6.5 widths, enables; chip-2600 #51 scope text).

Written from docs/spec.md only, not from the RTL. One step() per `clk` edge; the returned bit is the state
AFTER the edge (inputs held), like ref/tia_pgfx.py. One instance per missile / ball.

  start : begins a run of `width` colour clocks (also while drawing: restarts it). Wins over a same-clk step.
  step  : one colour clock. The run ends after `width` steps.
  size  : 00 -> 1, 01 -> 2, 10 -> 4, 11 -> 8 colour clocks (missile NUSIZ D5-D4, ball CTRLPF D5-D4). Read live.
  en    : supplied by the caller (ENAMx & ~RESMPx, or VDELBL ? ENABL old : ENABL new). Read live: gfx = drawing & en.
  Output 0 when not drawing (before the first start, after the run, after rst).
Mid-run changes of size/en are a modelling choice (live read), so the harness only makes them with --live.
"""


def width(size):
    return 1 << (size & 3)


class TiaMbgfx:
    def __init__(self):
        self.active = 0; self.cnt = 0

    def step(self, rst, step, start, size, en):
        if rst:
            self.active = 0; self.cnt = 0
        elif start:
            self.active = 1; self.cnt = 0
        elif step and self.active:
            if self.cnt + 1 >= width(size):
                self.active = 0; self.cnt = 0
            else:
                self.cnt += 1
        return int(self.active and en)
