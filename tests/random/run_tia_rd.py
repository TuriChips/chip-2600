#!/usr/bin/env python3
"""Random TIA read-side / playfield harness (chip-2600#30): collisions (tia_cx), input ports (tia_inpt),
read mux (tia_rd), playfield scan (tia_pf), compared every clk against ref/tia_rd.py.

  --dut ref            second model instance (self-check, 0 diffs by construction)
  --dut mutant:NAME    planted bug, must be CAUGHT (see MUTANTS)
  --dut rtl            iverilog tb_tia_rd.sv + rtl/control/{tia_cx,tia_inpt,tia_rd}.v + rtl/datapath/tia_pf.v
Per clk compared: cx, inpt, d_out, d_oe (tia_rd driven by independent random cx/inpt), pf.
CXBLPF D6 (read addr 6, d_out[0] and d_oe[0]) is masked: open spec point (6.1).
Stimulus line: rst en objs(6) vblank(3) cxclr pin(6) a(4) rcx(15) rinpt(6) step start right ref pf0 pf1 pf2
"""
import argparse, os, random, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(ROOT, "ref"))
import tia_rd as R

KEYS = ("cx", "inpt", "d_out", "d_oe", "pf")


def gen_stim(rng, n):
    st = []; idx = 0
    en_p = rng.choice((0.3, 0.7, 1.0)); obj_p = rng.choice((0.1, 0.3, 0.6, 0.9))
    vb_p = rng.choice((0.0, 0.1, 0.5)); clr_p = rng.choice((0.0, 0.005, 0.05)); rst_p = rng.choice((0.0, 0.002, 0.02))
    vblank = rng.randrange(8); pin = rng.randrange(64); right = 0; ref = 0
    pf0, pf1, pf2 = rng.randrange(16), rng.randrange(256), rng.randrange(256)
    for _ in range(n):
        rst = int(rng.random() < rst_p)
        objs = sum((rng.random() < obj_p) << k for k in range(6))
        if rng.random() < 0.15: vblank = (vblank & 3) | (rng.randrange(2) << 2) | (rng.randrange(2) << 1)  # D7,D6
        if rng.random() < 0.1: vblank = (vblank & 6) | (rng.random() < vb_p)                                # D1
        if rng.random() < 0.3: pin ^= 1 << rng.randrange(6)
        if rng.random() < 0.02: pin = rng.randrange(64)
        # playfield: index kept in 0..19; a start restarts it
        start = int(rng.random() < 0.05 or idx >= 19 and rng.random() < 0.5)
        step = int(not start and idx < 19 and rng.random() < 0.5)
        if rst or start: idx = 0
        elif step: idx += 1
        if rng.random() < 0.05: right = rng.randrange(2)
        if rng.random() < 0.05: ref = rng.randrange(2)
        if rng.random() < 0.05: pf0, pf1, pf2 = rng.randrange(16), rng.choice((0, 255, rng.randrange(256))), rng.choice((0, 255, rng.randrange(256)))
        st.append((rst, int(rng.random() < en_p), objs, vblank, int(rng.random() < clr_p), pin, rng.randrange(16),
                   rng.randrange(1 << 15), rng.randrange(64), step, start, right, ref, pf0, pf1, pf2))
    return st


class Model:
    kind = None
    def __init__(self):
        self.cx = R.TiaCx(); self.inp = R.TiaInpt(); self.pf = R.TiaPf()
    def step(self, s):
        rst, en, objs, vb, clr, pin, a, rcx, rin, step, start, right, ref, p0, p1, p2 = s
        k = self.kind
        o = {n: (objs >> i) & 1 for i, n in enumerate(R.OBJ)}
        d1 = vb & 1
        if k == "gate_on_d7": d1 = (vb >> 2) & 1
        if k == "set_beats_clear" and clr and en and not d1 and o["p0"] and o["p1"]:
            self.cx.step(rst, en, o, d1, 0); cx = self.cx.cx | (1 << R.CXBIT[(7, 7)]); self.cx.cx = cx
        else:
            cx = self.cx.step(rst, en if k != "ignore_en" else 1, o, d1, clr)
        inpt = self.inp.step(rst, pin, vb)
        if k == "dump_d6": inpt = (inpt & ~0xF) | (pin & 0xF if not (vb >> 1) & 1 else 0)
        if k == "i5_no_latch": inpt = (inpt & 0xF) | ((pin >> 4 & 2 | inpt >> 4 & 1) << 4)
        d_out, d_oe = R.read_mux(a, rcx, rin)
        if k == "inpt_drive_d6" and 8 <= a <= 13: d_oe |= 1
        if k == "inpt_off_by_one" and 8 <= a <= 13: d_out = ((rin >> ((a - 7) % 6)) & 1) << 1
        if k == "e_drives" and a == 14: d_oe = 2
        if k == "swap_m0p" and a == 0: d_out = ((d_out & 1) << 1) | (d_out >> 1)
        pfi = self.pf.step(rst, step, start)
        pf = R.TiaPf.pf_bit(pfi, right, ref if k != "reflect_left" else ref, p0, p1, p2)
        if k == "reflect_left": pf = R.TiaPf.pf_bit(pfi, 1, ref, p0, p1, p2) if ref else pf
        if k == "pf0_order": pf = R.TiaPf.pf_bit(pfi, right, ref, int(f"{p0:04b}"[::-1], 2) if pfi < 4 else p0, p1, p2)
        if k == "pf2_msb_first" and pfi >= 12 and not (right and ref): pf = (p2 >> (19 - pfi)) & 1
        if k == "ref_no_right": pf = R.TiaPf.pf_bit(pfi, 1, ref, p0, p1, p2)
        return (cx, inpt, d_out, d_oe, pf)

MUTANTS = ["gate_on_d7", "set_beats_clear", "ignore_en", "dump_d6", "i5_no_latch", "inpt_drive_d6",
           "inpt_off_by_one", "e_drives", "swap_m0p", "reflect_left", "pf0_order", "pf2_msb_first", "ref_no_right"]


def trace(stim, kind):
    m = Model(); m.kind = kind
    return [m.step(s) for s in stim]


def run_rtl(seed, stim):
    bd = os.path.join(ROOT, "build"); os.makedirs(bd, exist_ok=True)
    sf, of, vvp = (os.path.join(bd, f"tiard_s{seed}.{e}") for e in ("stim", "out", "vvp"))
    with open(sf, "w") as f:
        for s in stim:
            f.write(" ".join("%x" % x for x in s) + "\n")
    srcs = [os.path.join(ROOT, "rtl", "control", x) for x in ("tia_cx.v", "tia_inpt.v", "tia_rd.v")] + [os.path.join(ROOT, "rtl", "datapath", "tia_pf.v")]
    subprocess.run(["iverilog", "-g2005", "-o", vvp, os.path.join(HERE, "tb_tia_rd.sv")] + srcs, check=True)
    subprocess.run(["vvp", "-n", vvp, f"+STIM={sf}", f"+OUT={of}", f"+N={len(stim)}"], check=True, stdout=subprocess.DEVNULL)
    with open(of) as f:
        return [tuple(int(x, 16) for x in line.split()) for line in f]


def mask(s, o):
    cx, inpt, d_out, d_oe, pf = o
    if s[6] == 6: d_out &= 2; d_oe &= 2      # CXBLPF D6 open point
    return (cx, inpt, d_out, d_oe, pf)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=200); ap.add_argument("--seed0", type=int, default=1)
    ap.add_argument("--clks", type=int, default=5000); ap.add_argument("--dut", default="ref")
    a = ap.parse_args()
    tot = bad = 0; cov = {"cx_bits": 0, "reads": set(), "latched_clear": 0, "right_ref": 0}
    for sd in range(a.seed0, a.seed0 + a.seeds):
        stim = gen_stim(random.Random(sd), a.clks)
        ref = trace(stim, None)
        dut = run_rtl(sd, stim) if a.dut == "rtl" else trace(stim, None if a.dut == "ref" else a.dut.split(":", 1)[1])
        for r in ref: cov["cx_bits"] |= r[0]
        cov["reads"].update(s[6] for s in stim)
        cov["right_ref"] += sum(1 for s in stim if s[11] and s[12])
        diffs = [(i, KEYS[j], mask(stim[i], ref[i])[j], mask(stim[i], dut[i])[j]) for i in range(len(ref)) for j in range(5)
                 if mask(stim[i], ref[i])[j] != mask(stim[i], dut[i])[j]]
        tot += len(diffs)
        if diffs:
            bad += 1; i, k, e, g = diffs[0]
            print(f"seed {sd}: {len(diffs)} diffs; first at clk {i}: {k} ref={e:#x} dut={g:#x}; stim={stim[i]}")
    print(f"dut={a.dut} seeds={a.seeds} seed0={a.seed0} clks/seed={a.clks} total_clks={a.seeds*a.clks} "
          f"cx_bits_ever_set={bin(cov['cx_bits']).count('1')}/15 read_addrs={len(cov['reads'])}/16 "
          f"right_and_ref_clks={cov['right_ref']} seeds_with_diffs={bad} diffs={tot}")
    sys.exit(1 if tot else 0)

if __name__ == "__main__":
    main()
