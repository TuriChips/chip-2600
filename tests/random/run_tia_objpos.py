#!/usr/bin/env python3
"""Random position-counter harness (chip-2600#63): tia_objpos vs ref/tia_objpos.py, (q, start_main, start_copy) every clk.

  --dut ref | --dut mutant:NAME | --dut rtl   (rtl: iverilog tb_tia_objpos.sv + rtl/datapath/{tia_objpos,tia_poly6,tia_objdec}.v)
Random step / res / nusiz (nusiz changes at any time, incl. mid-period; res often on the same clk as step), rare rst.
Also checks, independently of the model code path: from 000000 with step only, q returns to 000000 every 40 steps and
the sequence hits 111000 / 101111 / 111001 at counts 3 / 7 / 15 (and wrap 101101 at 39), never 111111.
ERR (111111) is not reachable from reset; the stimulus cannot force it, so ERR is covered by the model self-check only
(mutants include ERR variants that the RTL run cannot reach). Stimulus line (hex): rst step res nusiz.
"""
import argparse, os, random, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(ROOT, "ref"))
import tia_objpos as M

MUTANTS = ["period_41", "res_loses_to_step", "res_ignored", "rst_ignored", "no_wrap_reset",
           "xor_not_xnor", "tap_q4_q6", "c3_enabled_for_100", "c7_missing_110", "c15_enabled_101", "c3_missing_011",
           "copy_ignores_nusiz", "nusiz_latched_on_res", "main_gated_by_nusiz", "c7_wrong_state", "step_without_step"]


class Mut(M.TiaObjpos):
    kind = None; lat = 0
    def step(self, rst, step, res, nusiz):
        k = self.kind; S = M.TiaObjpos
        if k == "res_ignored": res = 0
        if k == "rst_ignored": rst = 0
        if k == "res_loses_to_step" and res and step and not rst:
            res = 0
        if k == "period_41" and step and not (rst or res) and self.q == M.WRAP:
            self.q = M.bits("010101"); return self.outputs(nusiz)
        if k == "no_wrap_reset" and step and not (rst or res) and self.q == M.WRAP:
            self.q = M.lfsr(self.q); return self.outputs(nusiz)
        if k == "xor_not_xnor" and step and not (rst or res) and self.q != M.WRAP and self.q != M.ERR:
            q = self.q; self.q = ((q << 1) & 0x3F) | (((q >> 4) ^ (q >> 5)) & 1); return self.outputs(nusiz)
        if k == "tap_q4_q6" and step and not (rst or res) and self.q != M.WRAP and self.q != M.ERR:
            q = self.q; self.q = ((q << 1) & 0x3F) | (1 - (((q >> 3) ^ (q >> 5)) & 1)); return self.outputs(nusiz)
        if k == "step_without_step" and not (rst or res) and not step and self.q == M.C15:
            step = 1
        if k == "nusiz_latched_on_res":
            if res and not rst: self.lat = nusiz
            nusiz = self.lat
        r = S.step(self, rst, step, res, nusiz)
        q, main, copy = r
        if k == "c3_enabled_for_100" and q == M.C3 and nusiz == 4: copy = 1
        if k == "c7_missing_110" and q == M.C7 and nusiz == 6: copy = 0
        if k == "c15_enabled_101" and q == M.C15 and nusiz == 5: copy = 1
        if k == "c3_missing_011" and q == M.C3 and nusiz == 3: copy = 0
        if k == "copy_ignores_nusiz": copy = int(q in (M.C3, M.C7, M.C15))
        if k == "main_gated_by_nusiz" and nusiz == 7: main = 0
        if k == "c7_wrong_state": copy = int((q == M.bits("101110") and nusiz in M.EN7) or (q == M.C3 and nusiz in M.EN3) or (q == M.C15 and nusiz in M.EN15))
        return q, main, copy


def gen_stim(rng, n):
    st_p = rng.choice((0.3, 0.7, 1.0)); rs_p = rng.choice((0.0, 0.01, 0.05)); sr_p = rng.choice((0.0, 0.5, 1.0))
    nz_p = rng.choice((0.0, 0.05, 0.3)); rst_p = rng.choice((0.0, 0.002)); nz = rng.randrange(8); stim = []
    for _ in range(n):
        if rng.random() < nz_p: nz = rng.randrange(8)
        s = int(rng.random() < st_p); r = int(rng.random() < rs_p)
        if s and rng.random() < sr_p * 0.2: r = int(rng.random() < 0.5) | r   # extra res-with-step
        stim.append([int(rng.random() < rst_p), s, r, nz])
    return stim


def trace(stim, kind):
    m = Mut(); m.kind = kind
    return [m.step(*r) for r in stim]


def run_rtl(seed, stim):
    bd = os.path.join(ROOT, "build"); os.makedirs(bd, exist_ok=True)
    sf, of, vvp = (os.path.join(bd, f"objpos_s{seed}.{e}") for e in ("stim", "out", "vvp"))
    with open(sf, "w") as f:
        for r in stim: f.write(" ".join("%x" % x for x in r) + "\n")
    d = os.path.join(ROOT, "rtl", "datapath")
    subprocess.run(["iverilog", "-g2005", "-o", vvp, os.path.join(HERE, "tb_tia_objpos.sv")] +
                   [os.path.join(d, x) for x in ("tia_objpos.v", "tia_poly6.v", "tia_objdec.v")], check=True)
    subprocess.run(["vvp", "-n", vvp, f"+STIM={sf}", f"+OUT={of}", f"+N={len(stim)}"], check=True, stdout=subprocess.DEVNULL)
    with open(of) as f:
        return [tuple(int(x, 16) for x in line.split()) for line in f]


def structural(dut_trace_fn):
    """From reset with step only: period 40, copy decodes at counts 3/7/15, wrap at 39, no ERR."""
    stim = [[1, 0, 0, 0]] + [[0, 1, 0, 0]] * 120
    out = dut_trace_fn(stim)
    seq = [o[0] for o in out]          # seq[0] is state 0 (after reset)
    bad = []
    for i, q in enumerate(seq):
        if q == M.ERR: bad.append(f"ERR reached at step {i}")
        if (q == 0) != (i % 40 == 0): bad.append(f"zero/period mismatch at step {i}")
    for c, s in ((3, "111000"), (7, "101111"), (15, "111001"), (39, "101101")):
        if seq[c] != M.bits(s): bad.append(f"count {c} is {seq[c]:06b} not {s}")
    # copy outputs with each nusiz at counts 3/7/15
    for nz in range(8):
        stim = [[1, 0, 0, nz]] + [[0, 1, 0, nz]] * 40
        o = dut_trace_fn(stim)
        got = [i for i, x in enumerate(o) if x[2]]
        want = sorted(c for c, en in ((3, M.EN3), (7, M.EN7), (15, M.EN15)) if nz in en)
        if got != want: bad.append(f"nusiz {nz}: copy at counts {got}, want {want}")
        if [i for i, x in enumerate(o) if x[1]] != [39]: bad.append(f"nusiz {nz}: start_main not only at 39")
    return bad


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=200); ap.add_argument("--seed0", type=int, default=1)
    ap.add_argument("--clks", type=int, default=5000); ap.add_argument("--dut", default="ref")
    a = ap.parse_args()
    kind = None if a.dut in ("ref", "rtl") else a.dut.split(":", 1)[1]
    tot = bad = 0; seen = set(); res_step = nz_mid = wraps = 0; cp = {3: 0, 7: 0, 15: 0}
    if a.dut == "rtl": fn = lambda st: run_rtl("struct", st)
    else: fn = lambda st: trace(st, kind)
    sb = structural(fn)
    for b in sb: print("structural:", b)
    for sd in range(a.seed0, a.seed0 + a.seeds):
        stim = gen_stim(random.Random(sd), a.clks)
        ref = trace(stim, None)
        dut = run_rtl(sd, stim) if a.dut == "rtl" else trace(stim, kind)
        m = M.TiaObjpos(); prev_nz = None
        for r in stim:
            res_step += bool(r[1] and r[2] and not r[0]); nz_mid += (prev_nz is not None and prev_nz != r[3])
            prev_nz = r[3]; q, mn, c = m.step(*r); seen.add(q); wraps += mn
            if c: cp[{M.C3: 3, M.C7: 7, M.C15: 15}[q]] += 1
        diffs = [i for i in range(len(ref)) if ref[i] != dut[i]]
        tot += len(diffs)
        if diffs:
            bad += 1; i = diffs[0]
            print(f"seed {sd}: {len(diffs)} diffs; first at clk {i}: ref={ref[i]} dut={dut[i]}; stim={stim[i]}")
    print(f"dut={a.dut} seeds={a.seeds} seed0={a.seed0} clks/seed={a.clks} total_clks={a.seeds*a.clks} states_seen={len(seen)}/63 "
          f"(ERR reachable={int(M.ERR in seen)}) res_with_step={res_step} nusiz_changes={nz_mid} start_main_clks={wraps} "
          f"copy_clks_3/7/15={cp[3]}/{cp[7]}/{cp[15]} structural_fails={len(sb)} seeds_with_diffs={bad} diffs={tot}")
    sys.exit(1 if tot or sb else 0)

if __name__ == "__main__":
    main()
