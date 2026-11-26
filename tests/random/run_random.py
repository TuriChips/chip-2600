#!/usr/bin/env python3
"""Random RIOT harness: random register traffic + pin changes, compared pulse by
pulse between the reference model (ref/m6532.py) and a DUT, plus an independent
closed-form timer oracle (spec 7.2 formula, no shared code with the model).

DUT choices:  --dut ref          a second instance of the model (ref vs ref, until the RTL exists)
              --dut mutant       model with the v0.1 timer (underflow one pulse early): must be CAUGHT
              --dut trace:FILE   (not wired yet) RTL outputs for the stimulus --emit wrote
Power-on timer value, divide, prescaler phase, RAM and flags are random per seed (D7).
"""
import argparse, os, random, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "ref"))
from m6532 import M6532, DIV

FIELDS = ("d_out", "d_oe", "irq_n", "pa_out", "pa_ddr", "pb_out", "pb_ddr")


class Mutant(M6532):
    """v0.1 timer, known wrong (spec 7.2): reads N - floor(k/D) - 1, underflow at N*D."""
    def _write_io(self, a, d):
        super()._write_io(a, d)
        if (a >> 2) & 1 and (a >> 4) & 1:
            self.val = (d - 1) & 0xFF
            self.left = self.div


def gen_stim(rng, n, reset_prob):
    stim = []
    pa, pb = rng.randrange(256), rng.randrange(256)
    timer_biased = rng.random() < 0.5
    for _ in range(n):
        s = dict(ce=1, res_n=1, cs1=1, cs2_n=0, rs_n=1, rw=1, a=0, d_in=rng.randrange(256))
        r = rng.random()
        if r < 0.03: s["ce"] = 0
        if reset_prob and rng.random() < reset_prob: s["res_n"] = 0
        k = rng.random()
        if k < 0.35:
            s["cs1"] = 0 if rng.random() < 0.05 else 1   # idle: usually unselected
            if s["cs1"]: s["cs2_n"] = 1
            if k < 0.30: s["cs1"] = 0
        else:
            if rng.random() < 0.04: s["cs2_n"] = 1
            if rng.random() < 0.03: s["cs1"] = 0
            s["rw"] = 1 if rng.random() < 0.55 else 0
            c = rng.random()
            if c < 0.2:
                s["rs_n"] = 0; s["a"] = rng.randrange(128)
            elif c < 0.5:
                s["a"] = rng.randrange(4) | (rng.randrange(16) << 3) & 0x78   # ports/DDRs (A2=0)
                s["a"] &= ~4
            else:
                s["a"] = 4 | rng.randrange(4) | (rng.randrange(2) << 3) | (rng.randrange(2) << 4) | (rng.randrange(4) << 5)
                if not s["rw"] and (s["a"] >> 4) & 1:
                    if timer_biased:
                        s["d_in"] = rng.choice((0, 1, 2, 3, 5, 9, 17, 0xFF, rng.randrange(8)))
        if rng.random() < 0.15:
            pa = pa ^ (1 << (7 if rng.random() < 0.5 else rng.randrange(8)))
            pb = pb ^ (1 << rng.randrange(8))
        s["pa_in"], s["pb_in"] = pa, pb
        stim.append(s)
    return stim


class Oracle:
    """Closed-form timer prediction from spec 7.2, independent of M6532."""
    def __init__(self):
        self.on = False
    def observe(self, s, d_out):
        sel = s["cs1"] == 1 and s["cs2_n"] == 0 and s["res_n"] and s["ce"]
        if not s["res_n"] or not s["ce"]:
            return None
        if self.on:
            self.k += 1
        if not (sel and s["rs_n"] == 1):
            return None
        a = s["a"]
        if not s["rw"] and (a >> 2) & 1 and (a >> 4) & 1:
            self.on, self.k = True, 0
            self.N, self.D = s["d_in"], DIV[a & 3]
            return None
        if not self.on or not s["rw"] or not (a >> 2) & 1:
            return None
        under = self.N * self.D + 1
        k = self.k
        if a & 1:                                   # flags register
            exp = 0x80 if k >= under else 0
            return ("flag", exp, d_out & 0x80)
        exp = (self.N - (k - 1) // self.D - 1) if k < under else (0xFF - (k - under)) & 0xFF
        if k > under:
            self.on = False                          # clearing read: resume rule is [check]
        return ("intim", exp, d_out)


def run_seed(seed, n, dut_kind, reset_prob):
    rng = random.Random(seed)
    ref = M6532(); ref.power_on(rng)
    dut = {"ref": M6532, "mutant": Mutant}.get(dut_kind, M6532)()
    dut.__dict__.update({k: (list(v) if isinstance(v, list) else v) for k, v in ref.__dict__.items()})
    stim = gen_stim(rng, n, reset_prob)
    orc = Oracle()
    diffs, oracle_fail = [], []
    for i, s in enumerate(stim):
        ro = ref.step(**s)
        do = dut.step(**s)
        for f in FIELDS:
            if f == "d_out" and not ro["d_oe"]:
                continue
            if ro[f] != do[f]:
                diffs.append((i, f, ro[f], do[f]))
        o = orc.observe(s, ro["d_out"])
        if o and o[1] != o[2]:
            oracle_fail.append((i, o))
    return stim, diffs, oracle_fail


def oracle_on_dut(seed, n, dut_kind, reset_prob):
    """Oracle checked against the DUT's own read data (what catches a wrong DUT)."""
    rng = random.Random(seed)
    ref = M6532(); ref.power_on(rng)
    dut = {"ref": M6532, "mutant": Mutant}[dut_kind]()
    dut.__dict__.update({k: (list(v) if isinstance(v, list) else v) for k, v in ref.__dict__.items()})
    stim = gen_stim(rng, n, reset_prob)
    orc, bad = Oracle(), []
    for i, s in enumerate(stim):
        d = dut.step(**s)
        o = orc.observe(s, d["d_out"])
        if o and o[1] != o[2]:
            bad.append((i, o))
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=200)
    ap.add_argument("--seed0", type=int, default=1)
    ap.add_argument("--pulses", type=int, default=20000)
    ap.add_argument("--dut", default="ref")
    ap.add_argument("--reset-prob", type=float, default=0.0)
    ap.add_argument("--emit", help="directory: write stimulus + expected trace per seed")
    a = ap.parse_args()
    tot_d = tot_o = 0
    reads = 0
    for sd in range(a.seed0, a.seed0 + a.seeds):
        if a.dut.startswith("trace:"):
            sys.exit("trace compare attaches once the RTL testbench exists (see README)")
        stim, diffs, _ = run_seed(sd, a.pulses, a.dut, a.reset_prob)
        bad = oracle_on_dut(sd, a.pulses, "mutant" if a.dut == "mutant" else "ref", a.reset_prob)
        tot_d += len(diffs); tot_o += len(bad)
        if a.emit:
            os.makedirs(a.emit, exist_ok=True)
            rng = random.Random(sd); m = M6532(); m.power_on(rng)
            with open(os.path.join(a.emit, f"seed{sd}.stim"), "w") as f:
                f.write("# power-on: " + repr(m.snapshot()) + "\n")
                for s in stim:
                    f.write(" ".join(f"{k}={v}" for k, v in s.items()) + "\n")
        if diffs or bad:
            print(f"seed {sd}: {len(diffs)} model/DUT diffs, {len(bad)} oracle failures; first: {diffs[:1]} {bad[:1]}")
    print(f"dut={a.dut} seeds={a.seeds} pulses/seed={a.pulses} total_pulses={a.seeds*a.pulses} "
          f"diffs={tot_d} oracle_failures={tot_o}")
    sys.exit(1 if (tot_d or tot_o) else 0)


if __name__ == "__main__":
    main()
