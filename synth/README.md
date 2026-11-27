# synth/: block-level synthesis (Leo)

Flow: `synth/run.sh` (called by `make synth`). Yosys 0.33 → sky130_fd_sc_hd `tt_025C_1v80`, ABC at a 100 ns clock (a stand-in: the spec has no electrical timing), then OpenSTA with ideal wires and clock, no placement. Same flow and cell library as chip-z80. Local run needs the layout tools: `source .toolchain/scripts/eda-env.sh; synth/run.sh`. Without the liberty or OpenROAD (CI today) it prints SKIP and leaves the committed report alone.

Run on chip-2600 main 0a31a1c, toolchain v0.10.2. Full output: `synth/report.txt`; per block `synth/logs/<block>.{yosys.log,stat.txt,sta.log}`.

| Block | Cells | Flops | Latches | Area (µm²) | Worst path (ns, any start to any end) | Source |
|-------|------:|------:|--------:|-----------:|------:|--------|
| m6532 | 3330 | 1085 | 0 | 43047.5 | 6.086 | `logs/m6532.stat.txt`, `logs/m6532.sta.log` |
| tia_regs | 660 | 166 | 0 | 5904.4 | 3.816 | `logs/tia_regs.*` |
| tia_hdec | 15 | 0 | 0 | 86.3 | 0.277 | `logs/tia_hdec.*` |
| tia_poly6 | 19 | 6 | 0 | 209.0 | 0.663 | `logs/tia_poly6.*` |
| tia_objdec | 11 | 0 | 0 | 56.3 | 0.260 | `logs/tia_objdec.*` |
| tia_cx | 46 | 15 | 0 | 566.8 | 0.732 | `logs/tia_cx.*` |
| tia_inpt | 13 | 2 | 0 | 108.9 | 0.542 | `logs/tia_inpt.*` |
| tia_rd | 27 | 0 | 0 | 182.7 | 0.782 | `logs/tia_rd.*` |
| tia_pf | 43 | 5 | 0 | 404.1 | 1.835 | `logs/tia_pf.*` |

Notes:
- All blocks pass `check -assert` (no multiple drivers, no undriven signals) and have 0 latches. Nothing to file for Ada or Zura.
- m6532 flops: 1024 are the 128-byte RAM (as flops, no macro), so area is dominated by RAM. RAM-versus-logic area is not separated.
- tia_hdec, tia_objdec and tia_rd are purely combinational: the path is input to output, against a virtual clock.
- Block paths are not chip speed: they are gates only and exclude wires and the surrounding logic. No speed is claimed.
- Yosys "warnings" in the report are the liberty reader skipping scan-flop cells and an ABC multi-output note; none concern the RTL.
- Not covered yet: the 6507 core (`rtl/cpu/`, no file list entry, not in this issue) and the `tia` / `a2600` tops. They get rows when their RTL is on main.
