#!/usr/bin/env python3
"""Random TIA write-side harness (chip-2600#22): the same random (rst, wr, a, d) sequence drives
ref/tia_regs.py and a DUT; every output is compared every clk.

  --dut ref            second instance of the model (self-check)
  --dut mutant:NAME    model with a planted bug: must be CAUGHT (names: see MUTANTS)
  --dut rtl            iverilog-compile tb_tia_regs.sv + RTL_DIR/*.v, run it on the stimulus, compare traces
                       (--rtl-dir, default rtl/control; only tia_regs.v is pulled in unless --all-rtl)
Stimulus is biased to GRP0/GRP1/ENABL (vertical delay), HM*/HMCLR, resets; all 64 addresses appear.
"""
import argparse, os, random, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.join(HERE, "..", "..")
sys.path.insert(0, os.path.join(ROOT, "ref"))
import tia_regs as T

OUT_ORDER = None  # fixed field order, set from the model


class Mut(T.TiaRegs):
    kind = None
    def step(self, rst, wr, a, d):
        k = self.kind
        pre = dict(self.r)
        if k == "grp1_old_from_old" and wr and not rst and a == 0x1C:
            o = super().step(rst, wr, a, d); self.r["grp0_old"] = pre["grp0_old"]; return self.outputs()
        if k == "no_enabl_old" and wr and not rst and a == 0x1C:
            super().step(rst, wr, a, d); self.r["enabl_old"] = pre["enabl_old"]; return self.outputs()
        if k == "grp0_copies_enabl" and wr and not rst and a == 0x1B:
            super().step(rst, wr, a, d); self.r["enabl_old"] = pre["enabl"]; return self.outputs()
        if k == "hmclr_misses_hmbl" and wr and not rst and a == 0x2B:
            super().step(rst, wr, a, d); self.r["hmbl"] = pre["hmbl"]; return self.outputs()
        if k == "hm_mask_d3" and wr and not rst and a in (0x20, 0x21, 0x22, 0x23, 0x24):
            super().step(rst, wr, a, d); n = T.WRITE_MAP[a][0]; self.r[n] = ((d >> 3) & 0xF); return self.outputs()
        if k == "decode_2d" and wr and not rst and a == 0x2D:
            return super().step(rst, wr, 0x2C, d)       # $2D aliases CXCLR
        if k == "rst_keeps_old" and rst:
            o = super().step(rst, wr, a, d); self.r["grp0_old"] = pre["grp0_old"]; return self.outputs()
        if k == "nusiz_d3" and wr and not rst and a in (0x04, 0x05):
            super().step(rst, wr, a, d); n = T.WRITE_MAP[a][0]
            self.r[n] = ((d >> 5) & 3) << 3 | (d >> 3 & 1) << 2 | (d & 3); return self.outputs()
        return super().step(rst, wr, a, d)

MUTANTS = ["grp1_old_from_old", "no_enabl_old", "grp0_copies_enabl", "hmclr_misses_hmbl", "hm_mask_d3",
           "decode_2d", "rst_keeps_old", "nusiz_d3"]


def gen_stim(rng, n):
    biased = [0x1B, 0x1C, 0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x2B]
    mode = rng.random()
    wr_p = rng.choice((0.3, 0.6, 0.9))
    rst_p = rng.choice((0.0, 0.003, 0.02))
    st = []
    for _ in range(n):
        r = rng.random()
        a = rng.choice(biased) if r < 0.45 else rng.randrange(64)
        d = rng.choice((0x00, 0xFF, 0x0F, 0xF0, 0x55, 0xAA, 1 << rng.randrange(8))) if rng.random() < 0.4 else rng.randrange(256)
        st.append((1 if rng.random() < rst_p else 0, 1 if rng.random() < wr_p else 0, a, d))
    st[0] = (1, st[0][1], st[0][2], st[0][3])   # first clk is a reset: flops are X before it
    return st


def make_model(kind):
    if kind == "ref": return T.TiaRegs()
    m = Mut(); m.kind = kind.split(":", 1)[1]; return m


def model_trace(stim, m):
    keys = None; tr = []
    for s in stim:
        o = m.step(*s)
        if keys is None: keys = sorted(o)
        tr.append(tuple(o[k] for k in keys))
    return keys, tr


def run_rtl(seed, stim, rtl_dir, all_rtl, keys):
    bd = os.path.join(ROOT, "build"); os.makedirs(bd, exist_ok=True)
    sf, of, vvp = (os.path.join(bd, f"tia_s{seed}.{e}") for e in ("stim", "out", "vvp"))
    with open(sf, "w") as f:
        for s in stim: f.write("%d %d %02x %02x\n" % s)
    srcs = sorted(os.path.join(rtl_dir, x) for x in os.listdir(rtl_dir) if x.endswith(".v")) if all_rtl \
        else [os.path.join(rtl_dir, "tia_regs.v")]
    subprocess.run(["iverilog", "-g2012", "-o", vvp, os.path.join(HERE, "tb_tia_regs.sv")] + srcs, check=True)
    subprocess.run(["vvp", "-n", vvp, f"+STIM={sf}", f"+OUT={of}", f"+N={len(stim)}"], check=True, stdout=subprocess.DEVNULL)
    tr = []
    with open(of) as f:
        for line in f:
            h = dict(x.split("=") for x in line.split())
            tr.append(tuple(int(h[k], 16) for k in keys))
    return tr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--seeds", type=int, default=200)
    ap.add_argument("--seed0", type=int, default=1)
    ap.add_argument("--clks", type=int, default=5000)
    ap.add_argument("--dut", default="ref")
    ap.add_argument("--rtl-dir", default=os.path.join(ROOT, "rtl", "control"))
    ap.add_argument("--all-rtl", action="store_true")
    a = ap.parse_args()
    tot = 0; bad_seeds = 0; seen = set()
    for sd in range(a.seed0, a.seed0 + a.seeds):
        stim = gen_stim(random.Random(sd), a.clks)
        seen.update(s[2] for s in stim)
        keys, ref = model_trace(stim, T.TiaRegs())
        if a.dut == "rtl":
            dut = run_rtl(sd, stim, a.rtl_dir, a.all_rtl, keys)
        else:
            _, dut = model_trace(stim, make_model(a.dut))
        diffs = [(i, keys[j], ref[i][j], dut[i][j]) for i in range(len(ref)) for j in range(len(keys)) if ref[i][j] != dut[i][j]]
        tot += len(diffs)
        if diffs:
            bad_seeds += 1
            i, k, e, g = diffs[0]
            print(f"seed {sd}: {len(diffs)} diffs; first at clk {i}: {k} ref={e:#x} dut={g:#x}; input (rst,wr,a,d)={stim[i]}")
    print(f"dut={a.dut} seeds={a.seeds} clks/seed={a.clks} total_clks={a.seeds*a.clks} addresses_seen={len(seen)}/64 "
          f"seeds_with_diffs={bad_seeds} diffs={tot}")
    sys.exit(1 if tot else 0)


if __name__ == "__main__":
    main()
