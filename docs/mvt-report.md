# MVT fetch, build route and undocumented-opcode scan

_Homer · 2026-11-26 · issue chip-2600#6 · spec §9 item 1, caveats (b)–(d), D6_

Everything here was run on 2026-11-26. Commands: `sw/fetch_mvt.sh [--build]`, `sw/opscan.py`, `sw/mvt_ref.py`. Raw scan output: [`mvt-opscan.txt`](mvt-opscan.txt).

## 1. Fetch and pin (rule 9: nothing from MVT is committed)

`sw/fetch_mvt.sh` puts everything in `build/mvt/` (git-ignored) and stops on any hash mismatch.

| What | Source | Pin | Licence |
|------|--------|-----|---------|
| Test sources, headers, **27 reference PNGs** | `ajoneil/missingno-vcs-tests` | commit `891c079976a2f68033ca4af2fe2fd85aaf1906c9` | MIT, © 2026 Andrew O'Neil (`LICENSE` sha256 `01fa4a27…e214`) |
| **81 prebuilt NTSC ROMs**, plus `palette.rs` and the runner | `ajoneil/missingno` | commit `5e5b8d7dad46355e9bf48b53978d7d91d2ec9e23` (2026-11-01) | MIT, © 2025 Andrew O'Neil (`LICENSE` sha256 `cd35f62a…f010`) |

- **The MVT repo holds no ROM binaries**, only sources and PNGs. The prebuilt ROMs exist only in missingno, so spec §9 item 1's single commit pin isn't enough for the ROMs. The missingno commit above is the second pin.
- Hashes: [`sw/mvt-roms.sha256`](../sw/mvt-roms.sha256) (81 ROMs, `<sub>/<test>_ntsc.a26`) and [`sw/mvt-pngs.sha256`](../sw/mvt-pngs.sha256) (27 PNGs). The missingno copies of the 27 PNGs are byte-identical to MVT's (checked with `cmp`).
- In-scope count confirmed: 81 ROMs = harness 2, cpu 7, riot 11, tia-render 15, tia-timing 30, collision 16. 54 self-tests plus 27 screenshots. Matches spec §9.

## 2. Proposal for caveat (b): use the prebuilt ROMs, keep dasm as an optional check

**Proposal: take the prebuilt MIT ROMs from missingno, verified by sha256.** Reasons:
1. I assembled all 81 sources from MVT `891c079` with dasm 2.20.14.1 (Ubuntu noble package; binary sha256 `cfb23732…`) and dasm master headers (`machines/atari2600` at dasm commit `e629d260b92dd8d2b5c2ff11cbbc6265ebb46946`: `macro.h` v1.11 sha256 `5b7a37c2…a4e6`, `vcs.h` v1.07 sha256 `ee9492d0…5b9e`), `-f3 -Iinclude`. **All 81 outputs are byte-identical to the prebuilt ROMs.** So there is one set of hashes, not two, and the prebuilt ROMs are the ones the sources produce. `sw/fetch_mvt.sh --build` redoes this check (needs `dasm` and `DASM_INC`).
2. The prebuilt route needs no GPL tool and no header. dasm is GPL-2.0 (its `LICENSE`), used here only as a build tool and never shipped, which is fine either way. But a fresh clone would also need the right `macro.h`, which is v1.11 (spec D6 cites it) and is **not** what the dasm 2.20.14.1 tag ships (v1.09), nor what Ubuntu's package installs (it installs no headers at all).
3. One fewer moving part in CI.

**Licence text in `vcs.h`/`macro.h` (the [check] in spec §9(b)):** neither file contains a licence text. The headers only say they're "explicitly supported as a dasm-preferred companion file", and the changelog notes "updated license/links" (1.09, 2020), with no licence named. The repo they live in is GPL-2.0. Since we don't copy or ship them, this doesn't block anything; it matters only if Sai ever wants them in a repo. If so, ask upstream.

Caveat on the pin: the prebuilt ROMs are three months newer than the MVT pin, but the rebuild above shows they match its sources. If either commit moves, the hash check fails and someone has to look.

## 3. Undocumented-opcode scan (D6)

Method (`sw/opscan.py`): recursive-descent disassembly from the reset vector, following JMP, JSR, branches and fall-through. Only reached bytes are decoded, so data that looks like opcodes is never counted. Not a byte grep. It checks every reached opcode against the 151 documented NMOS opcodes. Checked on a synthetic image: a reached `$A7` is found, an unreached `$04` is not.

What the trace can't follow by itself, and how it was handled:
- `JMP (zp)`: 21 ROMs jump through a RAM pointer that the code computes (`Sled + index`). In all 21, the JMP is directly followed by a run of `$EA` (NOP) bytes (one, `collision/latency-swallow`, by a run of `$C9` CMP #imm bytes ending in `CMP zp`). The scan accepts the jump only then, and traces from every offset in that run. All entry offsets decode to documented opcodes. The run lengths are in `mvt-opscan.txt` (`sled@`).
- No `JMP (ind)` is left unresolved, no code runs outside the cartridge window, no jump lands inside an instruction (apart from the deliberate sled entries), and no reached store writes into the ROM window.
- Not covered: code in RAM, and `RTS`-address tricks. The tracer treats `RTS` as the end of a path and relies on every `JSR` return site being reached by fall-through, so a ROM that pushes an address and returns to it would escape it. Checked by grep, not by the tracer: `PHA` appears in 6 sources. I read the two `cpu/stack-aliases-*` ones (they point SP into RAM/TIA to test aliasing, and jump back explicitly: "no rts"). I did not read the other four (`tia-render/nusiz`, `missile-copies`, `player-reflect`, `vertical-delay`). No reached jump or branch goes outside the cartridge window, so no ROM jumps to RAM through a `JMP`. **Beru: the RTS trick and the four unread `PHA` users are the part worth a second look.**

**Result: D6's assumption holds.** All 81 ROMs, 23 440 reached instructions in total (sum of the per-ROM counts):

| Opcode | Meaning | Sites | ROMs | Operand |
|--------|---------|-------|------|---------|
| `$AB` | LXA #imm | 73 | 73 (all with `CLEAN_START`) | `$00` at all 73 |
| `$04` | NOP zp | 125 | 38 (`SLEEP n`, n odd) | `$00` at all 125 (`nop VSYNC`) |
| anything else | | **0** | | |

- 4 ROMs reach no undocumented opcode: `collision/blanked-reset`, `copy-adjacency`, `resbl-kill`, `reset-phase`.
- `LXA #0` leaves A = X = 0 whatever the "magic constant" is, so the unspecified part of `$AB` is never exercised. Flags N = 0, Z = 1, as in D6.
- Nothing needs to go on turichips#48. D6 (a) as written is enough.

## 4. Caveat (d): colour code → RGB inverse map, and the frame rule

Read from `crates/systems/vcs/tests/accuracy/common/mod.rs`, `tia/palette.rs` and `console.rs` at the missingno pin.

**Inverse map.**
- The runner turns each TIA pixel byte `b` into RGB through `NTSC_PALETTE[b >> 1]`: a 128-entry table, index = hue(4 bits):luma(3 bits).
- **All 128 RGB values are distinct**, so the inverse map exists and is a plain dictionary. The runner has no tolerance: the compare is pixel-exact.
- `sw/mvt_ref.py` reads the table from the pinned `palette.rs` at run time (nothing copied into our repo) and maps every pixel of every reference PNG back to a 7-bit code. **All 27 PNGs decode with no unknown colour.** The map's code is `colour byte >> 1`, so our `col[3:0]`:`lum[2:0]` output maps to the table as `{col, lum}`, assuming our 4+3 bit packing matches the hue/luma split (Zura/Ada: confirm against §6.9).
- Pixels with no object drawn (blanked by VBLANK D1, or inside the HMOVE comb, or undrawn after RSYNC) are **code 0 = black (0,0,0)**. Our runner must output code 0 there, not the background colour.

**Frame capture rule** (what to put in our runner):
1. A pixel *x* (0–159) is colour clock 68 + *x* of the line. HBLANK pixels aren't in the frame.
2. A scanline is flagged VSYNC if the VSYNC latch is set when the line ends (the HSync wrap). A frame is the run of **non-VSYNC lines** between two VSYNC blocks. It completes when the next VSYNC block starts (the latch rising), not at the falling edge. The lines are the same as with a falling-edge boundary, so §4.1's "the frame boundary is the falling edge" gives the same pixels. Igris may want to say "frame content starts at the falling edge, and is delivered at the next rising edge".
3. The runner steps 8 frames and **keeps the last one** (the 8th complete frame, or the last one it got if later ones exceed a 400-line budget). Frames 1–7 are not compared. Frame 1 is partial: it starts at power-on.
4. Compare: the first `min(frame lines, reference lines)` rows, pixel-exact. **This accepts a frame shorter than the reference.** Our runner should compare height too, and report it separately, rather than copy this leniency. Whether to fail on it is for Beru and Igris.
5. References are 160×259 for 26 of the 27 ROMs. **`tia-timing/midline-resp` is 160×260.** Spec §9 says 259 for all.

**Self-tests:** the runner steps CPU instructions (cap 5 000 000, not frames) and polls RAM `$80..$83` after each instruction. PASS = `$A5`, FAIL = `$5A`. Stops if the CPU jams. 5 M instructions is roughly 15 M CPU cycles, far above need. Our frame budget (spec: "a frame budget the runner states") can be set from the longest self-test; I haven't measured it, because there is no 2600 model yet.

## 5. Open for others
- **Igris:** §9(a)'s one commit pin isn't enough for ROMs (two pins, above); §4.1 frame boundary wording; `midline-resp` is 260 lines, not 259.
- **Beru:** second look at the RTS/RAM-code blind spot in §3. Decide about frame height strictness (§4 rule 4).
- **Tesla:** `sw/fetch_mvt.sh` and `sw/mvt-*.sha256` are the fetch to call from the Makefile. It needs `git` only, `dasm` only with `--build`.
