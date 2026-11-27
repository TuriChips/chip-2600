#!/usr/bin/env python3
"""Random player-graphics harness (chip-2600#39): tia_pgfx vs ref/tia_pgfx.py, serial bit compared every clk.

  --dut ref | --dut mutant:NAME | --dut rtl   (rtl: iverilog tb_tia_pgfx.sv + rtl/datapath/tia_pgfx.v)
Two players (P0, P1) per run, each with its own scan. The GRP/VDEL values come from ref/tia_regs.py driven by
random register writes (GRP0/GRP1 write order and the vertical-delay copy therefore are exercised end to end),
VDELPx/REFPx/NUSIZx are written randomly too. Config writes (NUSIZ, REFP, VDELP, GRP) land only while that
player is idle unless --live (the live-read semantics are a model choice, see ref/tia_pgfx.py).
Stimulus line (hex): rst step0 start0 step1 start1 | per player: grp_new grp_old vdel refp nusiz
RTL ports (rtl/datapath/tia_pgfx.v): clk rst step start grp_new[7:0] grp_old[7:0] vdel refl nusiz[2:0] -> gfx
(stimulus column refp maps to port refl).
"""
import argparse, os, random, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(ROOT, "ref"))
import tia_pgfx as P
import tia_regs as T

MUTANTS = ["vdel_inverted", "refp_ignored", "nusiz_101_x1", "nusiz_111_x2", "nusiz_100_x2", "no_restart",
           "swap_old_new", "start_no_reset_cnt", "output_after_end"]


class Mut(P.TiaPgfx):
    kind = None
    def step(self, rst, step, start, gn, go, vdel, refp, nusiz):
        k = self.kind
        if k == "vdel_inverted": vdel ^= 1
        if k == "swap_old_new": gn, go = go, gn
        if k == "refp_ignored": refp = 0
        if k == "nusiz_101_x1" and nusiz == 5: nusiz = 0
        if k == "nusiz_111_x2" and nusiz == 7: nusiz = 5
        if k == "nusiz_100_x2" and nusiz == 4: nusiz = 5
        if k == "no_restart" and start and self.active: start = 0
        if k == "start_no_reset_cnt" and start and not rst:
            c = self.cnt; r = P.TiaPgfx.step(self, rst, step, start, gn, go, vdel, refp, nusiz); self.cnt = c; return r
        if k == "output_after_end" and not rst and not start and step and self.active and self.idx == 7 \
                and self.cnt + 1 >= P.width(nusiz):
            P.TiaPgfx.step(self, rst, step, start, gn, go, vdel, refp, nusiz)
            self.active = 1; return 0
        return P.TiaPgfx.step(self, rst, step, start, gn, go, vdel, refp, nusiz)


def gen_stim(rng, n, live):
    regs = T.TiaRegs(); regs.step(1, 0, 0, 0)
    pl = [P.TiaPgfx(), P.TiaPgfx()]
    wr_p = rng.choice((0.05, 0.15, 0.4)); st_p = rng.choice((0.01, 0.05, 0.2)); sp_p = rng.choice((0.5, 0.9, 1.0))
    rst_p = rng.choice((0.0, 0.002)); stim = []
    for _ in range(n):
        rst = int(rng.random() < rst_p)
        a = d = 0; wr = 0
        if rng.random() < wr_p:
            a = rng.choice((0x04, 0x05, 0x0B, 0x0C, 0x1B, 0x1C, 0x25, 0x26, 0x1B, 0x1C))
            d = rng.choice((0x00, 0xFF, 0x55, 0xAA, rng.randrange(256), rng.randrange(256)))
            if a in (0x04, 0x05): d = (d & ~7) | rng.randrange(8)
            who = {0x04: 0, 0x05: 1, 0x0B: 0, 0x0C: 1, 0x25: 0, 0x26: 1}.get(a)
            idle0, idle1 = not pl[0].active, not pl[1].active
            # GRP0 write also copies P1's new to P1's old (a visible change on P1), and vice versa
            affected = {0x1B: (0, 1), 0x1C: (1, 0)}.get(a, (who,))
            wr = int(live or all(not pl[p].active for p in affected if p is not None))
        o = regs.step(rst, wr, a, d)
        s = [rst]; cfg = []
        for p in (0, 1):
            s += [int(rng.random() < sp_p), int(rng.random() < st_p)]
            cfg.append((o["grp%d_new" % p], o["grp%d_old" % p], o["vdelp%d" % p], o["refp%d" % p], o["nusiz%d" % p] & 7))
        for p in (0, 1):
            pl[p].step(s[0], s[1 + 2 * p], s[2 + 2 * p], *cfg[p])
        stim.append((s, cfg))
    return stim


def flat(s, cfg):
    return [s[0], s[1], s[2], s[3], s[4]] + list(cfg[0]) + list(cfg[1])


def trace(stim, kind):
    pl = [Mut(), Mut()]
    for m in pl: m.kind = kind
    out = []
    for s, cfg in stim:
        out.append(tuple(pl[p].step(s[0], s[1 + 2 * p], s[2 + 2 * p], *cfg[p]) for p in (0, 1)))
    return out


def run_rtl(seed, stim):
    bd = os.path.join(ROOT, "build"); os.makedirs(bd, exist_ok=True)
    sf, of, vvp = (os.path.join(bd, f"pgfx_s{seed}.{e}") for e in ("stim", "out", "vvp"))
    with open(sf, "w") as f:
        for s, cfg in stim:
            f.write(" ".join("%x" % x for x in flat(s, cfg)) + "\n")
    subprocess.run(["iverilog", "-g2005", "-o", vvp, os.path.join(HERE, "tb_tia_pgfx.sv"),
                    os.path.join(ROOT, "rtl", "datapath", "tia_pgfx.v")], check=True)
    subprocess.run(["vvp", "-n", vvp, f"+STIM={sf}", f"+OUT={of}", f"+N={len(stim)}"], check=True, stdout=subprocess.DEVNULL)
    with open(of) as f:
        return [tuple(int(x, 16) for x in line.split()) for line in f]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=200); ap.add_argument("--seed0", type=int, default=1)
    ap.add_argument("--clks", type=int, default=5000); ap.add_argument("--dut", default="ref")
    ap.add_argument("--live", action="store_true", help="also change config while a scan is running")
    a = ap.parse_args()
    tot = bad = 0; ones = 0; scans = 0; w = {1: 0, 2: 0, 4: 0}; refl = vold = restarts = 0
    for sd in range(a.seed0, a.seed0 + a.seeds):
        stim = gen_stim(random.Random(sd), a.clks, a.live)
        ref = trace(stim, None)
        dut = run_rtl(sd, stim) if a.dut == "rtl" else trace(stim, None if a.dut == "ref" else a.dut.split(":", 1)[1])
        ones += sum(x[0] + x[1] for x in ref)
        pl = [P.TiaPgfx(), P.TiaPgfx()]
        for s, cfg in stim:
            for p in (0, 1):
                st = s[2 + 2 * p]; act = pl[p].active
                if st and act: restarts += 1
                if st and not s[0]:
                    scans += 1; w[P.width(cfg[p][4])] += 1; refl += cfg[p][3]; vold += cfg[p][2]
                pl[p].step(s[0], s[1 + 2 * p], st, *cfg[p])
        diffs = [(i, p, ref[i][p], dut[i][p]) for i in range(len(ref)) for p in (0, 1) if ref[i][p] != dut[i][p]]
        tot += len(diffs)
        if diffs:
            bad += 1; i, p, e, g = diffs[0]
            print(f"seed {sd}: {len(diffs)} diffs; first at clk {i}: player {p} ref={e} dut={g}; stim={stim[i]}")
    print(f"dut={a.dut} live={int(a.live)} seeds={a.seeds} seed0={a.seed0} clks/seed={a.clks} total_clks={a.seeds*a.clks} "
          f"starts={scans} width_1/2/4={w[1]}/{w[2]}/{w[4]} reflected={refl} vdel_old={vold} restarts_while_drawing={restarts} "
          f"one_bits={ones} seeds_with_diffs={bad} diffs={tot}")
    sys.exit(1 if tot else 0)

if __name__ == "__main__":
    main()
