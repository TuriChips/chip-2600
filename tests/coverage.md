# Coverage: spec behaviour -> test (RIOT, `m6532`)

Spec: `docs/spec.md` draft v0.2, §2.2, §7, §8.2 R1–R3. Testbench: `tb/m6532/tb.sv` (run: `make test BLOCK=m6532`, or `.toolchain/scripts/run_tests.sh m6532`). Every expected value is taken from the spec. Run against Ada's RTL (`rtl/datapath/m6532.v`, #9, on main): `logs/m6532-tb-rtl.log`. `logs/m6532-tb-selfcheck.log` shows the testbench catching mutants of that RTL (see the end of this file).

Check names below are the prefixes of the `ok`/`FAIL` lines in the run log.

| Spec | Behaviour | Test (check name prefix) | Status |
|------|-----------|--------------------------|--------|
| §2.2, §7.1 | RAM: 128 bytes, 3 patterns, each byte reads back; `d_oe` = 1 on a read | `R1 ram[i] pattern` , `R1 ram[i] d_oe on read` | written |
| §7.1 | RAM: no aliasing between cells | `R1 ram alias` | written |
| §2.2 | Selected only when CS1 = 1 and CS2 = 0; unselected writes ignored; no drive when unselected or on a write | `R1 ram unselected writes ignored`, `R1 d_oe=0 …` | written |
| §7.1 | DDRA/DDRB read-back and `pa_ddr`/`pb_ddr` | `R1 DDRA read-back`, `R1 DDRB read-back`, `R1 pa_ddr pins`, `R1 pb_ddr pins` | written |
| §7.3 | ORA/ORB store all 8 bits whatever the direction; `pa_out`/`pb_out` follow | `R1 ORA stored while DDRA=0`, `R1 ORB stored while DDRB=0`, `R1 pa_out follows`, `R1 pb_out follows` | written |
| §7.3 | Port A read returns the **pin**, also on output bits | `R1 port A read returns pin (55), not OR (AA)…`, `R1 port A mixed` | written |
| §7.3 | Port B read returns **ORB** on output bits, pins on input bits | `R1 port B read: output bits from ORB…`, `R1 port B read, all outputs, pins forced…` | written |
| §7.1 | A4/A3 are don't-care for ORA/DDRA/ORB/DDRB (table has no A4/A3 entry for A2 = 0) | `R1 DDRB written via +08/+10/+18` and the ORB/DDRA rows | written, derived from the table |
| §2.2 | `res_n`: DDRA/DDRB/ORA/ORB zero; data bus floats; negative edge, PA7 interrupt disabled | `R1 reset: …`, `R1 res_n=0: d_oe floats` | written |
| §2.2 | `res_n` leaves RAM and timer alone (*Decision*) | `R1 reset leaves RAM`, `R1 reset leaves timer running` | written |
| §7.2 | Timer value at pulses 1, 2, D, D+1, D+2, mid, N·D−1, N·D, N·D+1 for D = 1, 8, 64, 1024 and N = 0, 1, 37, 255 (only points ≤ N·D+1 in the one run; a read at N·D+2 ends the free-run, so it is tested on its own) | `R2 N=… /… INTIM at pulse …` | written |
| §7.2 | Read on pulse N·D+1 returns `$FF` and leaves the flag set | `R2 … read on underflow pulse`, `R2 … flag still set after read at underflow pulse` | written |
| §7.2 | Read on pulse N·D+2 returns `$FE` and clears the flag | `R2 … read at N*D+2 returns FE`, `R2 … flag cleared by read at N*D+2` | written |
| §7.2 | Flag clear at pulse N·D, set at N·D+1 (flag-register read) | `R2 … flag clear at pulse N*D`, `R2 … flag set at pulse N*D+1` | written; the N·D+1 row reads the flag on the pulse it sets, derived from the "read leaves the flag set" evidence |
| §7.2 | N = 0: underflow at pulse 1 | `R2 N=0 …` rows | written |
| §7.2 | Flag cleared by a timer write; stays cleared after a read; timer-write A3 variants load N | `R2 flag cleared by a timer write`, `R2 flag cleared by INTIM read…`, `R2 flag stays cleared`, `R2 timer write via …` | written |
| §2.2 | `ce` = 0 holds the timer | `R2 ce=0 for 200 clocks…` | written |
| §7.2 flag reg | D5–D0 of the flag register read 0 | `R2 flag register D5-D0 read 0` | written |
| §7.2 [check] | ÷1 free-run to 200 pulses past underflow (settled) | `R2 /1 free-run, j past underflow` | written |
| §7.2 [check] | ÷1 at 255/256/257/300+ pulses past underflow | `REPORT /1 N=5 …` lines, nothing asserted | **report only**, to file on turichips#48 |
| §7.2 [check] | Pulse on which ÷D resumes after a post-underflow read (÷8: 20 pulses, ÷64: 70 pulses) | `REPORT resume /8`, `REPORT resume /64` lines | **report only**, to file on turichips#48 |
| §7.2 [check] | Does a timer read's A3 change the timer IRQ enable (read before the underflow, both directions) | `REPORT irq_n after underflow: write A3=…, INTIM read at A3=…` (3 lines) | **report only** |
| §2.2, §7.1 | `d_oe` = 1 on every selected read (ORA, DDRA, ORB, DDRB, INTIM, flags), 0 on every write | `R1 d_oe=1 on …`, `R2 d_oe=1 on …`, `R1/R2/R3 d_oe=0 on … write` | written |
| §7.1 | A4 = 0 writes are edge control only, never load the timer (A3, A1, A0, data varied) | `R2 edge-control write (…) does not load the timer` | written |
| §7.1 | INTIM read: A4, A3, A1 don't-care; same value, flag cleared, bus driven | `R2 INTIM read via XX value/d_oe/clears the timer flag` (8 addresses) | written |
| §7.1 | Flag register read: A4, A3, A1 don't-care; D7/D6 correct; clears PA7 flag only | `R2/R3 flag read via XX …`, `R3 flag read via XX cleared PA7 flag…` (8 addresses) | written |
| §7.4 | PA7 active edge sets the flag, enabled and disabled, both polarities | `R3 PA7 active edge sets the flag` (4 configurations) | written |
| §7.4 | PA7 inactive edge does not set the flag; second edge sets again; other pins moving do not | `R3 PA7 inactive edge…`, `R3 second active edge…`, `R3 other pins…` | written |
| §7.4 | PA7 edge counts when PA7 is an output (ORA write) | `R3 PA7 output: …` | written |
| §7.4 (ruled 2026-11-26) | A polarity change does not set the flag, either direction, either pin level, enabled or not | `R3 neg->pos change…`, `R3 pos->neg change…` | written |
| §7.2 flag reg | Flag-register read clears the PA7 flag only | `R3 flag register read clears the PA7 flag`, `R3 flag read cleared PA7 only…` | written |
| §7.2 | `irq_n`: timer source (enabled by A3 of the write, disabled, cleared by read and by write), PA7 source (enabled/disabled), both, each with the other masked or unexpired | `R3 timer irq…`, `R3 both…`, `R3 PA7 irq…`, `R3 PA7 edge, PA7 irq disabled…` | written |

## Not covered, on purpose
- Electrical timing (RIOT DS pp.3–5): out of scope (§1).
- The 1 clock inside a Φ2 cycle at which `irq_n` and the port outputs change: the testbench samples them after the cycle, with a margin of one or more pulses where the spec is silent.
- Pulse-exact `irq_n` at N·D+1: only sampled with margin.
- Timer read's A3 effect on the IRQ enable: observed only (§7.2 [check]).
- A5/A6 on the INTIM and flag reads: not in the table; Beru's random harness covers them.
- A5/A6 on the I/O registers: the §7.1 table has no column for them, so no mirror test.

## Testbench self-check
The testbench passes on Ada's RTL (`logs/m6532-tb-rtl.log`). Mutants of that RTL, run on the unchanged testbench, are in `logs/m6532-tb-selfcheck.log`. The earlier self-check used a scratch model that did not implement "a read after underflow ends the free-run" (Beru's review of #10); it is dropped.

## Core copy (`rtl/cpu`, spec D3, D6)
Run: `heavy tests/core/run_core.sh`. Log: `logs/core-copy-run.log` (ALL PASS).

| Spec | Behaviour | Test | Status |
|------|-----------|------|--------|
| D3 | Block-library rule: chip-6502's cycle-by-cycle suite (16 runs: every instruction/mode, RDY, interrupts, resets) passes on the copy with `ce` = 1 | `tests/core/run_cyc.sh` (`tb/cpu/tb_cyc6502.sv`, chip-6502 tb with `.ce(1'b1)`), generator and model copied from chip-6502 | done, PASS |
| D3 | chip-6502's ALU block vectors (991,232) pass with `ce` = 1 | `tb/cpu/tb_alu.sv` | done, PASS |
| D6 | `$04` NOP zp: 3 cycles, reads its zero-page address, A/X/Y/P unchanged | `tb/cpu/tb_d6.sv` ("A $04 …", "$04 takes 3 cycles", "$04 reads …") | done, PASS |
| D6 | `$AB #$00`: A = X = 0, N = 0, Z = 1, Y and other flags unchanged, 2 cycles | `tb/cpu/tb_d6.sv` ("A $AB #0 …") | done, PASS |
| D3 | `ce` = 0 holds every register and bus output, with `irq_n`/`nmi_n`/`so_n` tied to 1 (D1; interrupt latches not covered, an R-family reuse needs an interrupt-under-`ce` test); a copy with irregular `ce` gaps (0–7 idle clocks) shows exactly the `ce` = 1 copy's bus trace per `ce` pulse; 300-clock hold; final memory equal | `tb/cpu/tb_d6.sv` ("ce=0 hold", "B (ce gated) …") | done, PASS |

Not run on the copy: chip-6502's X/Z system run (`c7`, needs `m6502_system`, not copied), the CPU-level decimal ADC/SBC runs (`FULL=1`), `selftests`, and the SingleStepTests cross-check (§9 item 2). Seeded faults in `tb_d6` (a timing block ignoring `ce`; `$AB` removed) are both caught.

## TIA blocks (`tb/tia/`, spec §4.1, §5, §6.1, §6.5, §6.6)
Run: `tests/tia/run_tia.sh` (Icarus). RTL log: `logs/tia-tb-rtl.log` (written when the RTL is merged; not yet run on it, `tia_poly6`/`tia_objdec` = #19, `tia_regs`/`tia_hdec` = #20). Self-check: `tests/tia/selfcheck/run.sh`, log `logs/tia-tb-selfcheck.log` (the benches pass on a scratch model written from the spec and fail all 13 mutants). The expected values come from the spec only. The spec leaves the packing of multi-field `tia_regs` ports to the RTL header, so those checks use bit count, all-ones on `$FF`, injectivity of walking-1 data and port-to-port copies. Exact packing is asserted only for 8-bit registers (= `d`), COLUPx (= `d[7:1]`), NUSIZx (`{d5,d4,d2,d1,d0}`) and 1-bit registers.

| Spec | Behaviour | Test | Status |
|------|-----------|------|--------|
| §4.1 | `rst` → 000000; 000000 → 100000 (Q1…Q6); the 63 states follow new Q1 = XNOR(Q5,Q6) and each is visited once, 111111 never; back at 000000 after 63 steps | `tb_poly` T1 ("state k follows XNOR rule", "visited once") | written |
| §4.1 | `step` = 0 holds (at 13 different counts); `rst` wins over `step`; forced 111111: both ERR decodes fire and no other, holds on `step`=0, a step follows the XNOR rule (new state 111111) | `tb_poly` T1 ("hold at count", "rst over step", "forced 111111") | written (forced-state checks need `dut.q` to be a forceable reg, else a REPORT line says they were skipped) |
| §4.1 | Decode counts from 000000: SHS 4, RHS 8, RCB 12, RHB 16, LRHB 18, CNT 36, END 56, each fires once; the literal Q1…Q6 states at those counts | `tb_poly` T1 ("… at count", "seq[n] = …") | written |
| §6.5 | Object decode counts: wrap 39, c3 3, c7 7, c15 15, ERR never in the 63 states | `tb_poly` T1 ("obj … at count") | written |
| §4.1, §6.5 | For all 64 inputs exactly the table's decodes fire: `tia_hdec` (8 outputs) and `tia_objdec` (5) | `tb_poly` T2 | written |
| §6.1 | Every address `$00`–`$3F` × data `$00`, `$FF`, 8 walking-1, 8 walking-0, from the reset state and from an all-`$FF` state: only the map's bits stored, the bit count and placement as above, no other port changes (except the vertical-delay copies) | `tb_regs` T3 ("T3 (… background) $aa data dd …") | written |
| §6.1 | `$2D`–`$3F` change nothing and raise no strobe; `wr` = 0 does nothing at any address | `tb_regs` T3 | written |
| §6.1 | Strobes WSYNC, RSYNC, RESP0/1, RESM0/1, RESBL, HMOVE, HMCLR, CXCLR: exactly that one strobe high for exactly one `clk` (counted over a 4-clk window, so a registered or a combinational pulse both pass), data ignored, no stored port changed (except HMCLR) | `tb_regs` T3 ("strobe n count") | written |
| §6.5 | Vertical delay: GRP0 write → GRP1 old = GRP1 new and does not touch GRP0 old or ENABL old; GRP1 write → GRP0 old = GRP0 new and ENABL old = ENABL new; an ENABL write changes no old copy; 3000 random writes against a model | `tb_regs` T4 | written |
| §6.6 | HMCLR clears HMP0, HMP1, HMM0, HMM1, HMBL and nothing else; an HM write after HMCLR loads, one HM write leaves the others | `tb_regs` T4 | written |
| §5 | After `rst`, every stored output and every strobe is 0 (from a fully loaded state, vertical-delay copies included), compared with `!==` so X fails | `tb_regs` T5 | written |

Not covered: the `$00`–`$2C` write-time phase (Φ2 fall alignment, §4.2 [check]); `rst` and `wr` in the same clk (spec silent); `tia_hdec`'s delay boxes and END's reset route (§4.1 [check]); NUSIZ gating of c3/c7/c15 (§6.5 [check]); the strobes' own timing relative to `wr` (registered or not): not in the spec.

## TIA collisions, inputs, read map, static playfield (`tb/tia/tb_cx.sv`, `tb/tia/tb_pf.sv`, spec §6.1, §6.4, §6.7, §6.8)
Run: `tests/tia/run_tia.sh` (Icarus; runs `cx` and `pf` after `poly` and `regs`). RTL log: `logs/tia-tb-rtl.log` (not yet run on the RTL: `tia_cx`/`tia_inpt`/`tia_rd` = #28, `tia_pf` = #27, not merged). Self-check: `tests/tia/selfcheck/run.sh`, log `logs/tia-tb-selfcheck.log`: both benches pass on scratch models written from the spec (`cx.v`, `pf.v`) and fail all 26 new mutants. Expected values come from the spec and the issues' port contracts. `tia_cx` packing as in #28 (pair order of the read map, CXM0P D7 = cx[14] … CXPPMM D6 = cx[0]).
**Port name:** #27 names the input `ref`, a SystemVerilog keyword (Icarus and Verilator reject it). `tb_pf` connects `.pf_ref(...)`; the RTL must use that name, or the bench changes with it.

| Spec | Behaviour | Test | Status |
|------|-----------|------|--------|
| §6.7 | Each of the 15 pairs, alone, sets its own bit and no other; a single object or none sets nothing; all six set all 15; the bit holds after the outputs drop | `tb_cx` T7 ("pair n …", "object n alone") | written |
| §6.7 | `en` = 0 sets nothing | `tb_cx` T7 ("en=0 sets nothing") | written |
| §6.7 | VBLANK D1 = 1 blocks every pair's set (also 2 clocks running) and does not clear set bits; set resumes when D1 = 0. No HBLANK input exists: a 228-clock run with D1 = 0 sets at any clock | `tb_cx` T7 ("blocked by VBLANK D1", "any colour clock") | written |
| §6.7 | CXCLR clears all 15 (with `en` 0 and 1), and wins over a set on the same clk (from clear and from set); sets work after it | `tb_cx` T7 ("CXCLR …") | written |
| §6.7 | 5000 random clocks of objects/`vblank`/`en`/`cxclr` against a model | `tb_cx` T7 ("random") | written |
| §6.8 | I0–I3 follow the pin, read 0 while VBLANK D7 = 1 (with D1 = 1 too), are not affected by D6 or D1, no leak to other inputs | `tb_cx` T8 ("I n …") | written |
| §6.8 | I4–I5: D6 = 0 transparent; D6 = 1 a 0 pulse latches 0 until D6 = 0, then reads the pin again; the latch is reset by D6 = 0 and latches again; D1 does not release it; I4 and I5 latch independently; D7 does not force I4–I5 | `tb_cx` T8 ("I4/I5 …") | written |
| §6.1 | Read map, every address `$0`–`$F`: D7 and D6 per line with a walking 1 over all 15 `cx` bits (only the mapped bit shows), `d_oe` = 11 on `$0`–`$5`, `$7`; `$8`–`$D` D7 = INPTn, `d_oe` = 10, walking 1 and 0 over the 6 inputs; `$E`/`$F` `d_oe` = 00; inputs never reach collision reads and vice versa | `tb_cx` read map ("RD $a …") | written |
| §6.4 | All 20 bits one at a time, left half and right half, `ref` 0 and 1, one bit per `step`; all ones, all zeros, 200 random patterns; right half with `ref` 1 is the left reversed, with `ref` 0 repeats it | `tb_pf` T4 | written |
| §6.4 | `step` = 0 holds the index; `start` restarts at bit 0 mid-scan; `rst` gives index 0 | `tb_pf` T4 ("hold", "restart", "rst") | written |
| §6.4 | A write shows from the next index (PF1 and PF2 changed mid-scan) | `tb_pf` T4 ("written … index") | written |

Not covered: CXBLPF D6 and its `d_oe[0]` (§6.1 [check: LD s2 C6]); the colour clock from which a mid-line PF write is visible, and the RHB/CNT-to-first-bit delay (§6.4 [check], turichips#48); the index after bit 19 without a `start`; `rst` in `tia_inpt` (latch state after reset: spec silent); `tia_rd` `d_out` where `d_oe` = 0; SCORE and PFP (§6.9, priority mux).

## TIA player graphics scanner (`tb/tia/tb_pgfx.sv`, spec §6.5 Players and Vertical delay, chip-2600#38)
Run: `tests/tia/run_tia.sh` (runs `pgfx` once `rtl/datapath/tia_pgfx.v` exists; prints SKIPPED until then). Self-check: `tests/tia/selfcheck/run.sh`, log `logs/tia-tb-selfcheck.log`: the bench passes on the scratch model `pgfx.v` (with `regs.v`) and fails all 28 pgfx mutants. **Not yet run on the RTL**: `tia_pgfx` is #37, not merged. **Port names are assumed** (#37 gives behaviour only): `clk rst step start grp_new[7:0] grp_old[7:0] vdel refp nusiz[2:0] pgfx`, as in Beru's #43 harness. Convention: after the clk edge with `start` the output shows bit 0; a bit lasts 1/2/4 edges with `step`; the step after bit 7 gives 0.

| Spec | Behaviour | Test | Status |
|------|-----------|------|--------|
| §6.5 | All 8 NUSIZ D2-D0 codes: 101 = 2, 111 = 4, the other six = 1 clock per bit; each of the 8 bits alone, all ones, all zeros, both bit orders | `tb_pgfx` T5 "bit n", "all ones/zeros" | written |
| §6.5 | REFPx D3 = 0 scans D7 first, = 1 D0 first | `tb_pgfx` T5 (every scan, `refp` 0/1) | written |
| §6.5 | VDELPx D0 = 1 selects old, 0 new (walking-bit patterns that differ between new and old) | `tb_pgfx` T5 "vdel walking" | written |
| §6.5 | Output 0 outside a scan: after `rst`, with steps but no `start`, after bit 7 and on later steps, `rst` mid-scan | `tb_pgfx` T5 ("output 0 ...", "rst stops the scan") | written |
| §6.5 | `start` restarts mid-bit, mid-scan and from the last bit, at each width; start after the end draws again; `step` = 0 holds | `tb_pgfx` T5 "restart", "hold" | written |
| §6.5 Vertical delay | GRP0/GRP1 write order through `tia_regs`: GRP0 write copies P1 new to old, GRP1 write copies P0 new to old; VDELP0/VDELP1 in all four combinations; VDELBL does not affect players; a lone GRP0 write leaves P0 old | `tb_pgfx` T5 "e2e" | written |
| §6.5 | NUSIZ D2-D0 (not D5-D4) and REFP D3 (not other bits) reach the player through `tia_regs` | `tb_pgfx` T5 "e2e" | written |

Not covered: when a copy starts (position counter, [check] turichips#48), the stretched-mode +1 start delay, `start` and `step` on the same edge, mid-scan changes of GRP/VDEL/REFP/NUSIZ, copies (§6.5 NUSIZ decode, a later block), missiles, RESMP.
