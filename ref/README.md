# ref/: reference models (Beru)

`m6532.py`: cycle-level 6532 RIOT, one `step()` per Φ2 pulse, written from RIOT DS and
`docs/spec.md` §7 only. Independent of the RTL. Outputs per pulse: `d_out`, `d_oe`, `irq_n`,
`pa_out/pa_ddr`, `pb_out/pb_ddr`.

Timer (spec §7.2): write on pulse 0, decrement on pulses 1, 1+D, …; underflow on pulse N·D+1
(reads `$FF`, flag set, then once-per-pulse free-run); a read ON the underflow pulse keeps the
flag; any other INTIM read clears it and ends free-run. A timer write clears the flag.
PA7: edge on the resolved pin (output or input), arming writes set nothing (ruled 2026-11-26).

Open items, as class attributes so a ruling is one line:
- `READ_A3_SETS_EN` (default False): spec §7.2 [check], does a timer read's A3 change the IRQ enable?
- `PRESCALER_KEEPS_PHASE` (default True): spec §7.2 [check], where ÷D resumes after the read that ends free-run.
- `res_n` leaves timer, RAM and the two flags alone (spec §2.2 decision; flags unspecified in DS p.10). Power-on randomises them (D7).
- ÷1 second wrap (`$00` → `$FF` again, 256 pulses after underflow) re-sets the flag; spec §7.2 [check].

The TIA model is not started: it waits for the §4.2 RSYNC/Φ2 check on turichips#48.

`tia_regs.py` (chip-2600#22): TIA write side, one `step(rst, wr, a, d)` per `clk`. Write map §6.1, vertical delay §6.5
(GRP0 write: GRP1 new → old; GRP1 write: GRP0 new → old and ENABL new → old), HMCLR §6.6, reset §5. Packing and the
registered-strobe assumption are in the file header. The rest of the TIA model still waits on §4.2.

`tia_mbgfx.py` (chip-2600#53): missile / ball graphics run, `step(rst, step, start, size, en)`: a run of 1/2/4/8 colour clocks
(`size` 00..11), `start` wins over `step` and restarts, `gfx = drawing & en`. Harness: `tests/random/run_tia_mbgfx.py`.
