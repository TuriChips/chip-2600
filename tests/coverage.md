# Coverage: spec behaviour -> test (RIOT, `m6532`)

Spec: `docs/spec.md` draft v0.2, §2.2, §7, §8.2 R1–R3. Testbench: `tb/m6532/tb.sv` (run: `make test BLOCK=m6532`, or `.toolchain/scripts/run_tests.sh m6532`). Every expected value is taken from the spec. Nothing here is "passing against the RTL" until a log under `logs/` says so: Ada's RTL (`rtl/m6532.v`, #3) is not on main yet. `logs/m6532-tb-selfcheck.log` only shows that the testbench itself runs and catches seeded faults (see the end of this file).

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
| §7.2 | Timer value at pulses 1, 2, D, D+1, D+2, mid, N·D−1, N·D, N·D+1 for D = 1, 8, 64, 1024 and N = 0, 1, 37, 255 | `R2 N=… /… INTIM at pulse …` | written |
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
| §7.2 [check] | Does a timer read with A3 = 1 change the timer IRQ enable | `REPORT after INTIM read via A3=1 address` | **report only** |
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
- Timer read with A3 = 1: observed only (§7.2 [check]).
- A5/A6 on the I/O registers: the §7.1 table has no column for them, so no mirror test.
- Core-copy tests ($04, $AB #0, `ce` = 0 hold, chip-6502 suite with `ce` = 1): waiting on Zura's PR (#2); tracked on issue #4.

## Testbench self-check (no RTL yet)
Titus wrote a throw-away model of §7 (not committed) and ran the testbench on it to check the harness, then seeded faults. Results in `logs/m6532-tb-selfcheck.log`. This is a check of the tests, not evidence about Ada's design.
