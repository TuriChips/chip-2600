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
