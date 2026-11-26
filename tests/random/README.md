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
