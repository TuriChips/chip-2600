"""Reference model of the TIA player graphics scan (spec 6.5 Players, Vertical delay).

Written from docs/spec.md only, not from the RTL. One step() per `clk` edge; the returned bit is the
state AFTER the edge (inputs held), like ref/tia_rd.py TiaPf. Port names follow chip-2600 #37's scope text.

  start : restarts the scan at the first bit (also while drawing). Wins over a same-clk step.
  step  : one colour clock. A bit lasts `width` steps (NUSIZ D2-D0: 101 -> 2, 111 -> 4, else 1).
  grp   : VDELPx D0 = 1 selects the OLD register, else the NEW one.
  order : D7 first, or D0 first when REFPx D3 = 1.
  Output 0 when not drawing (before the first start, after the 8th bit, after rst).
GRP / VDEL / REFP are read live on the current bit index (a write shows on the next bit reached),
NUSIZ is read live for the width. Mid-scan changes of these are a modelling choice, so the harness only
makes them when --live is given; the default changes them while idle.
The vertical-delay copy itself is ref/tia_regs.py (GRP1 write copies GRP0 new -> old, ...).
"""


def width(nusiz):
    return {5: 2, 7: 4}.get(nusiz & 7, 1)


class TiaPgfx:
    def __init__(self):
        self.active = 0; self.idx = 0; self.cnt = 0

    def bit(self, grp_new, grp_old, vdel, refp, nusiz):
        if not self.active:
            return 0
        g = grp_old if vdel else grp_new
        return (g >> self.idx) & 1 if refp else (g >> (7 - self.idx)) & 1

    def step(self, rst, step, start, grp_new, grp_old, vdel, refp, nusiz):
        if rst:
            self.active = 0; self.idx = 0; self.cnt = 0
        elif start:
            self.active = 1; self.idx = 0; self.cnt = 0
        elif step and self.active:
            if self.cnt + 1 >= width(nusiz):
                self.cnt = 0
                if self.idx == 7: self.active = 0
                else: self.idx += 1
            else:
                self.cnt += 1
        return self.bit(grp_new, grp_old, vdel, refp, nusiz)
