# tests/random: RIOT random harness (Beru)

- `mvt_riot_checks.py`: replays the four hardware-verified MVT RIOT headers (`timer-vblank-spin`,
  `timer-underflow-read`, `timer-divisors`, `pa7-polarity`) against `ref/m6532.py`.
- `run_random.py`: random register reads/writes (RAM, ports, DDRs, timer ÷1/8/64/1024, flags,
  edge control, unselected accesses, ce gaps) and PA/PB pin changes (PA7 flips often), compared
  per pulse between the model and a DUT, plus a closed-form timer oracle (spec §7.2) that shares
  no code with the model. Random power-on timer/prescaler/RAM/flags per seed (D7).
  - `--dut ref`: ref vs ref (until the RTL exists). `--dut mutant`: v0.1 timer, must fail (harness self-check).
  - `--emit DIR`: writes each seed's stimulus; the RTL testbench replays it and writes its outputs
    (trace compare is not wired until Ada/Titus's testbench exists).
  - `--reset-prob P`: random mid-run `res_n` (off by default: flags after reset are unspecified).

Run: `python3 tests/random/mvt_riot_checks.py && python3 tests/random/run_random.py --seeds 200 --pulses 20000`

Note: ref vs ref is 0 diffs by construction. The only independent check today is the timer oracle (INTIM and the D7 flag). irq_n, the PA7 flag, ports and RAM are checked only once the RTL trace is wired.

## Core copy: `ce` gating × `rdy` (WSYNC), chip-2600#16

- `tb_ce_rdy.sv` + `run_ce_rdy.sh`: the gated `m6502` (random `ce` gaps, 0..7 clocks, sometimes up to 63) against an ungated copy given the same `rdy` pattern in `ce` time (single-cycle lows, bursts, WSYNC-like windows up to ~100 cycles). B's `rdy` glitches randomly on the `ce` = 0 clocks. Per `ce` pulse B's `a`, `rw`, `sync`, `d_oe` and write data must equal A's, from the first clock after reset (reset cycles included); on `ce` = 0 clocks B's outputs must not move. Independent of A/B: `rdy` = 0 on a read cycle holds `a`/`rw`/`sync`.
- Programs: the random images from `tests/core/gen_cycles6502.py` (s1..s4) × 3 rdy modes, 4000 cycles each. `irq_n`/`nmi_n`/`so_n` tied to 1 (D1); not covered here, note for R-family reuse.
- Run: `heavy tests/random/run_ce_rdy.sh [RTL_DIR] [N_PROGRAMS]` (about 11 s for 4 programs). Log: `logs/ce-rdy-random.log`.
- Self-check: mutants of `m6502_timing.v` (rdy sampled on every clock; rdy honoured on writes; t counter clocked by `ce | ~rdy`) all fail; the unmodified copy passes (`logs/ce-rdy-random.log`).

## TIA write side (chip-2600#22)
- `run_tia_regs.py`: random (`rst`, `wr`, `a`, `d`) sequences, all 64 addresses (45%+ of writes on GRP0/GRP1/ENABL/HM*/HMCLR), resets, compared every `clk` on all 48 outputs against `ref/tia_regs.py`. `--dut ref` (self-check), `--dut mutant:NAME` (8 planted bugs, all caught: `logs/tia-regs-random.log`), `--dut rtl` (compiles `tb_tia_regs.sv` + `rtl/control/tia_regs.v`, same compare).
- `tb_tia_regs.sv`: generated from the model's port list (names and widths from #20); samples 1 ns after each posedge. First clk of every run is a reset.
- Status: `tia_regs` RTL is not merged, so `--dut rtl` has only been checked against a throwaway stub written from the same table (plumbing only, not evidence). Run `python3 tests/random/run_tia_regs.py --dut rtl --seeds 200` once Zura's PR lands.
- Open for #20: strobes are modelled as registered pulses (high in the cycle after the write edge); `TiaRegs.STROBES_REGISTERED` documents it.

## TIA read side and playfield (chip-2600#30)
- `ref/tia_rd.py`: `TiaCx` (15 latches, VBLANK D1-only gating, CXCLR beats set), `TiaInpt` (dump, I4/I5 latch), `read_mux` ($0-$F, `d_out`/`d_oe`), `TiaPf` (20-bit scan, copy/reflect). Packings are in the file header.
- `run_tia_rd.py` + `tb_tia_rd.sv`: random per-clk object outputs, VBLANK/CXCLR/pin traffic, random reads (tia_rd gets independent random cx/inpt), random scan start/step with random PF/REF/right. `--dut ref|mutant:NAME|rtl`. 13 planted bugs, all caught. CXBLPF D6 is masked.
- Status: RTL not merged yet; only the self-check has run (`logs/tia-rd-random.log`). Run `python3 tests/random/run_tia_rd.py --dut rtl --seeds 200` when #27/#28 land.
- Model choices the RTL may differ on (will be filed as issues if so): `tia_inpt` output is the latch state after the edge (cleared by a 0 on the pin at that edge); latches reset to 1 on rst or D6=0; scan index beyond 19 and simultaneous step+start are not stimulated.
- `ref` is a SystemVerilog keyword: #27's `tia_pf` port `ref` only compiles as Verilog-2005 (-g2005); the harness uses -g2005. If Ada renames it, the TB instance needs the new name.
