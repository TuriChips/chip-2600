#!/usr/bin/env python3
"""Random missile/ball graphics harness (chip-2600#53): tia_mbgfx vs ref/tia_mbgfx.py, gfx compared every clk.

  --dut ref | --dut mutant:NAME | --dut rtl   (rtl: iverilog tb_tia_mbgfx.sv + rtl/datapath/tia_mbgfx.v)
Three objects per run (M0, M1, BL), each with its own scan, random step/start/size/en streams. size and en
change only while that object is idle unless --live (live-read is a model choice, see ref/tia_mbgfx.py).
Stimulus line (hex): rst | per object: step start size en
RTL ports expected (rtl/datapath/tia_mbgfx.v, #51): clk rst step start size[1:0] en -> gfx.
"""
import argparse, os, random, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(ROOT, "ref"))
import tia_mbgfx as M

MUTANTS = ["width_x2_at_01", "width_8_as_4", "width_off_by_one", "no_restart", "start_no_reset_cnt",
           "en_ignored", "en_latched_at_start", "step_beats_start", "output_after_end", "rst_ignored",
           "size_latched_at_start"]


class Mut(M.TiaMbgfx):
    kind = None
    lat = None
    def step(self, rst, step, start, size, en):
        k = self.kind; S = M.TiaMbgfx
        if k == "width_x2_at_01" and size == 1: size = 2
        if k == "width_8_as_4" and size == 3: size = 2
        if k == "en_ignored": en = 1
        if k == "rst_ignored": rst = 0
        if k == "no_restart" and start and self.active and not rst: start = 0
        if k == "step_beats_start" and start and step and self.active and not rst: start = 0
        if k == "en_latched_at_start":
            if start and not rst: self.lat = en
            if self.lat is not None: en = self.lat
        if k == "size_latched_at_start":
            if start and not rst: self.lat = size
            if self.lat is not None and not start: size = self.lat
        if k == "width_off_by_one" and not rst and not start and step and self.active and self.cnt + 1 >= M.width(size) and size == 3:
            self.cnt += 1; return int(self.active and en)   # 8 lasts 9
        if k == "start_no_reset_cnt" and start and not rst:
            c = self.cnt; r = S.step(self, rst, step, start, size, en); self.cnt = c; return r
        if k == "output_after_end" and not rst and not start and step and self.active and self.cnt + 1 >= M.width(size):
            S.step(self, rst, step, start, size, en); self.active = 1; self.cnt = M.width(size) - 1; return 0
        return S.step(self, rst, step, start, size, en)


def gen_stim(rng, n, live):
    ob = [M.TiaMbgfx() for _ in range(3)]
    st_p = rng.choice((0.01, 0.05, 0.2)); sp_p = rng.choice((0.5, 0.9, 1.0)); ch_p = rng.choice((0.05, 0.2, 0.5))
    rst_p = rng.choice((0.0, 0.002)); cfg = [[0, 1] for _ in range(3)]; stim = []
    for _ in range(n):
        rst = int(rng.random() < rst_p); row = [rst]
        for p in range(3):
            if rng.random() < ch_p and (live or not ob[p].active):
                cfg[p] = [rng.randrange(4), int(rng.random() < 0.75)]
            s, t = int(rng.random() < sp_p), int(rng.random() < st_p)
            row += [s, t, cfg[p][0], cfg[p][1]]
        for p in range(3):
            ob[p].step(rst, *row[1 + 4 * p:5 + 4 * p])
        stim.append(row)
    return stim


def trace(stim, kind):
    ob = [Mut() for _ in range(3)]
    for m in ob: m.kind = kind
    return [tuple(ob[p].step(r[0], *r[1 + 4 * p:5 + 4 * p]) for p in range(3)) for r in stim]


def run_rtl(seed, stim):
    bd = os.path.join(ROOT, "build"); os.makedirs(bd, exist_ok=True)
    sf, of, vvp = (os.path.join(bd, f"mbgfx_s{seed}.{e}") for e in ("stim", "out", "vvp"))
    with open(sf, "w") as f:
        for r in stim: f.write(" ".join("%x" % x for x in r) + "\n")
    subprocess.run(["iverilog", "-g2005", "-o", vvp, os.path.join(HERE, "tb_tia_mbgfx.sv"),
                    os.path.join(ROOT, "rtl", "datapath", "tia_mbgfx.v")], check=True)
    subprocess.run(["vvp", "-n", vvp, f"+STIM={sf}", f"+OUT={of}", f"+N={len(stim)}"], check=True, stdout=subprocess.DEVNULL)
    with open(of) as f:
        return [tuple(int(x, 16) for x in line.split()) for line in f]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=200); ap.add_argument("--seed0", type=int, default=1)
    ap.add_argument("--clks", type=int, default=5000); ap.add_argument("--dut", default="ref")
    ap.add_argument("--live", action="store_true")
    a = ap.parse_args()
    tot = bad = ones = starts = restarts = off = 0; w = [0] * 4
    for sd in range(a.seed0, a.seed0 + a.seeds):
        stim = gen_stim(random.Random(sd), a.clks, a.live)
        ref = trace(stim, None)
        dut = run_rtl(sd, stim) if a.dut == "rtl" else trace(stim, None if a.dut == "ref" else a.dut.split(":", 1)[1])
        ones += sum(map(sum, ref))
        ob = [M.TiaMbgfx() for _ in range(3)]
        for r in stim:
            for p in range(3):
                s, t, z, e = r[1 + 4 * p:5 + 4 * p]
                if t and not r[0]:
                    starts += 1; w[z] += 1; off += (not e); restarts += ob[p].active
                ob[p].step(r[0], s, t, z, e)
        diffs = [(i, p, ref[i][p], dut[i][p]) for i in range(len(ref)) for p in range(3) if ref[i][p] != dut[i][p]]
        tot += len(diffs)
        if diffs:
            bad += 1; i, p, e, g = diffs[0]
            print(f"seed {sd}: {len(diffs)} diffs; first at clk {i}: obj {p} ref={e} dut={g}; stim={stim[i]}")
    print(f"dut={a.dut} live={int(a.live)} seeds={a.seeds} seed0={a.seed0} clks/seed={a.clks} total_clks={a.seeds*a.clks} "
          f"starts={starts} size_0/1/2/3={'/'.join(map(str, w))} en0_starts={off} restarts_while_drawing={restarts} "
          f"one_bits={ones} seeds_with_diffs={bad} diffs={tot}")
    sys.exit(1 if tot else 0)

if __name__ == "__main__":
    main()
