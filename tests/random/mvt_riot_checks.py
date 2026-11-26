"""Directed checks of ref/m6532.py against the four hardware-verified MVT RIOT
headers (commit 891c079): timer-vblank-spin, timer-underflow-read,
timer-divisors, pa7-polarity.  The CPU's cycle timing is replayed by hand from
the instruction cycle counts (one step per Phi2 pulse)."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "ref"))
from m6532 import M6532

TIM1T, TIM8T, TIM64T, T1024T = 0x14, 0x15, 0x16, 0x17
INTIM, TIMINT = 0x04, 0x05


class Bus:
    def __init__(self, riot=None):
        self.r = riot or M6532()
        self.n = 0

    def idle(self, k=1):
        for _ in range(k):
            self.r.step(rw=1, cs1=0)          # not selected
            self.n += 1

    def wr(self, a, d, rs_n=1):
        self.n += 1
        return self.r.step(rs_n=rs_n, rw=0, a=a, d_in=d)

    def rd(self, a, rs_n=1):
        self.n += 1
        return self.r.step(rs_n=rs_n, rw=1, a=a)["d_out"]


def vblank_spin():
    prof = []
    for idx in range(8):
        b = Bus()
        b.wr(TIM64T, 8)                       # pulse 0
        b.idle(28 + 2 * (8 - idx))            # first INTIM read at pulse 29+2(8-idx)
        cnt = 0
        while True:
            cnt += 1
            v = b.rd(INTIM)
            if v == 0:
                break
            b.idle(8)                         # loop is 9 pulses: read + 8
        prof.append(cnt)
    assert prof == [46, 47, 47, 47, 47, 47, 48, 48], prof


def underflow_read():
    got = []
    for v in range(64, 0, -1):
        b = Bus()
        b.wr(TIM1T, v)
        b.idle(15)                            # 6 NOPs + lda: INTIM read lands on pulse 16
        i = b.rd(INTIM)
        assert b.r.pulse == 16, b.r.pulse
        b.idle(6)
        fl = b.rd(TIMINT) & 0x80
        if i == 0xFF:
            got.append((v, fl))
    assert got == [(15, 0x80)], got           # exactly one V hits; flag survives


def divisors():
    b = Bus()
    b.wr(TIM64T, 0xFF)
    b.idle(100)
    a1 = b.rd(INTIM)
    b2 = Bus()
    b2.wr(TIM64T, 0xFF)
    b2.idle(100 + 16 * 76 - 1)
    a2 = b2.rd(INTIM)
    assert a1 - a2 == 19, (a1, a2)
    b = Bus()
    b.wr(TIM64T, 1)
    b.idle(200)
    assert b.rd(TIMINT) & 0x80
    assert b.rd(TIMINT) & 0x80                # TIMINT read must not clear it
    b.rd(INTIM)
    assert b.rd(TIMINT) & 0x80 == 0


def pa7_polarity():
    b = Bus()
    b.wr(0x01, 0x80)                          # DDRA: PA7 output
    S = []

    # A: high, arm pos
    b.wr(0x00, 0x80); b.rd(TIMINT); b.wr(0x05, 0, ); S.append(b.rd(TIMINT) & 0x40)       # $285 pos
    b.rd(TIMINT); b.wr(0x04, 0); S.append(b.rd(TIMINT) & 0x40)                           # B: neg
    b.wr(0x00, 0x00); b.rd(TIMINT); b.wr(0x05, 0); S.append(b.rd(TIMINT) & 0x40)         # C
    b.rd(TIMINT); b.wr(0x04, 0); S.append(b.rd(TIMINT) & 0x40)                           # D
    b.wr(0x05, 0); b.wr(0x00, 0x00); b.rd(TIMINT); b.wr(0x00, 0x80); S.append(b.rd(TIMINT) & 0x40)  # E genuine
    b.rd(TIMINT); b.wr(0x00, 0x00); S.append(b.rd(TIMINT) & 0x40)                        # F wrong dir
    b.wr(0x00, 0x80); b.rd(TIMINT); S.append(b.rd(TIMINT) & 0x40)                        # G
    b.wr(0x04, 0); b.wr(0x00, 0x00); b.rd(TIMINT); b.wr(0x04, 0); S.append(b.rd(TIMINT) & 0x40)  # H
    assert S == [0, 0, 0, 0, 0x40, 0, 0, 0], S   # OBSERVED = $10: only E set


CHECKS = [vblank_spin, underflow_read, divisors, pa7_polarity]

if __name__ == "__main__":
    bad = 0
    for c in CHECKS:
        try:
            c(); print("PASS", c.__name__)
        except AssertionError as e:
            bad += 1; print("FAIL", c.__name__, e)
    sys.exit(1 if bad else 0)
