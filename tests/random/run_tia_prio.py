#!/usr/bin/env python3
"""Random priority/colour harness (chip-2600#73): tia_prio vs ref/tia_prio.py, (lum, col) every vector.

  --dut ref | --dut mutant:NAME | --dut rtl   (rtl: iverilog tb_tia_prio.sv + rtl/control/tia_prio.v)
Random p0 m0 p1 m1 pf bl score pfp right blk (per-seed bias) and four colour registers (often with duplicates/zeros).
Vectors with SCORE=1 and (BL=1 or PFP=1) are UNSETTLED (spec 6.9 [check], turichips#48): run through the DUT but not compared; counted.
Colour registers are drawn so the four values differ most of the time, so a wrong source register shows as a diff.
"""
import argparse, os, random, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(ROOT, "ref"))
import tia_prio as M

MUTANTS = ["pfp_ignored", "pfp_inverted", "p1_above_p0", "pf_above_p1", "bk_above_pf", "m0_not_p0", "m1_not_p1", "bl_not_pf",
           "score_ignored", "score_swapped_halves", "score_always_colup0", "score_on_bl_pf_normal", "blk_ignored", "blk_lum_only",
           "blk_col_only", "lum_col_swapped_bits", "bk_uses_colupf", "score_when_pf_off", "score_beats_player"]


def mut(kind, v):
    p0, m0, p1, m1, pf, bl, score, pfp, right, blk, c0, c1, cf, cb = v
    k = kind
    if k == "pfp_ignored": pfp = 0
    if k == "pfp_inverted": pfp = 1 - pfp
    if k == "m0_not_p0": m0 = 0
    if k == "m1_not_p1": m1 = 0
    if k == "bl_not_pf": bl = 0
    if k == "score_ignored": score = 0
    if k == "score_swapped_halves": right = 1 - right
    if k == "blk_ignored": blk = 0
    if k == "score_always_colup0": right = 0
    lum, col = M.prio(p0, m0, p1, m1, pf, bl, score, pfp, right, blk, c0, c1, cf, cb)
    g0, g1, gf = p0 or m0, p1 or m1, pf or bl
    if k == "p1_above_p0" and not pfp and g0 and g1 and not blk: lum, col = c1 & 7, c1 >> 3
    if k == "pf_above_p1" and not pfp and g1 and not g0 and gf and not blk:
        s = M.prio(0, 0, 0, 0, pf, bl, score, pfp, right, 0, c0, c1, cf, cb)[0:2]; lum, col = s
    if k == "bk_above_pf" and not pfp and gf and not g0 and not g1 and not blk: lum, col = cb & 7, cb >> 3
    if k == "bk_uses_colupf" and not (g0 or g1 or gf) and not blk: lum, col = cf & 7, cf >> 3
    if k == "score_on_bl_pf_normal" and score and not pfp and bl and pf and not g0 and not g1 and not blk:
        c = c1 if right else c0; lum, col = c & 7, c >> 3
    if k == "score_when_pf_off" and score and not pfp and not pf and not bl and not g0 and not g1 and not blk:
        c = c1 if right else c0; lum, col = c & 7, c >> 3
    if k == "score_beats_player" and score and not pfp and pf and not bl and (g0 or g1) and not blk:
        c = c1 if right else c0; lum, col = c & 7, c >> 3
    if k == "blk_lum_only" and blk:
        s = M.prio(p0, m0, p1, m1, pf, bl, score, pfp, right, 0, c0, c1, cf, cb); lum, col = 0, s[1]
    if k == "blk_col_only" and blk:
        s = M.prio(p0, m0, p1, m1, pf, bl, score, pfp, right, 0, c0, c1, cf, cb); lum, col = s[0], 0
    if k == "lum_col_swapped_bits":
        lum, col = (lum & 3) | ((lum & 4) >> 0), col
        lum = ((lum >> 1) & 3) | ((lum & 1) << 2)
    return lum, col


def gen(rng, n):
    pb = [rng.choice((0.1, 0.3, 0.5, 0.8)) for _ in range(6)]
    sp = rng.choice((0.2, 0.5, 0.8)); fp = rng.choice((0.2, 0.5, 0.8)); bp = rng.choice((0.0, 0.02, 0.1))
    out = []
    for _ in range(n):
        o = [int(rng.random() < p) for p in pb]
        sc, pp, rt = int(rng.random() < sp), int(rng.random() < fp), rng.randrange(2)
        bk = int(rng.random() < bp)
        if rng.random() < 0.7: cols = rng.sample(range(128), 4)
        else: cols = [rng.choice((0, 0x7f, rng.randrange(128))) for _ in range(4)]
        out.append(o + [sc, pp, rt, bk] + cols)
    return out


def run_rtl(seed, stim):
    bd = os.path.join(ROOT, "build"); os.makedirs(bd, exist_ok=True)
    sf, of, vvp = (os.path.join(bd, f"prio_s{seed}.{e}") for e in ("stim", "out", "vvp"))
    with open(sf, "w") as f:
        for r in stim: f.write(" ".join("%x" % x for x in r) + "\n")
    subprocess.run(["iverilog", "-g2005", "-o", vvp, os.path.join(HERE, "tb_tia_prio.sv"), os.path.join(ROOT, "rtl", "control", "tia_prio.v")], check=True)
    subprocess.run(["vvp", "-n", vvp, f"+STIM={sf}", f"+OUT={of}", f"+N={len(stim)}"], check=True, stdout=subprocess.DEVNULL)
    with open(of) as f:
        return [tuple(int(x, 16) for x in line.split()) for line in f]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=200); ap.add_argument("--seed0", type=int, default=1)
    ap.add_argument("--vecs", type=int, default=5000); ap.add_argument("--dut", default="ref")
    a = ap.parse_args()
    kind = None if a.dut in ("ref", "rtl") else a.dut.split(":", 1)[1]
    tot = bad = cmp_n = unset = 0; blk_n = sc_n = pfp_n = 0; unset_diff = 0
    for sd in range(a.seed0, a.seed0 + a.seeds):
        stim = gen(random.Random(sd), a.vecs)
        ref = [M.prio(*v) for v in stim]
        dut = run_rtl(sd, stim) if a.dut == "rtl" else [mut(kind, v) for v in stim]
        d = []
        for i, v in enumerate(stim):
            sc, pfp, bl = v[6], v[7], v[5]
            blk_n += v[9]; sc_n += sc; pfp_n += pfp
            if M.unsettled(sc, pfp, bl):
                unset += 1; unset_diff += ref[i] != dut[i]; continue
            cmp_n += 1
            if ref[i] != dut[i]: d.append(i)
        tot += len(d)
        if d:
            bad += 1; i = d[0]
            print(f"seed {sd}: {len(d)} diffs; first at vec {i}: ref={ref[i]} dut={dut[i]}; stim={stim[i]}")
    print(f"dut={a.dut} seeds={a.seeds} seed0={a.seed0} vecs/seed={a.vecs} total_vecs={a.seeds*a.vecs} compared={cmp_n} "
          f"unsettled_excluded={unset} (SCORE=1 with BL=1 or PFP=1; of these placeholder-vs-DUT differences={unset_diff}, not counted) "
          f"score_vecs={sc_n} pfp_vecs={pfp_n} blk_vecs={blk_n} seeds_with_diffs={bad} diffs={tot}")
    sys.exit(1 if tot else 0)

if __name__ == "__main__":
    main()
