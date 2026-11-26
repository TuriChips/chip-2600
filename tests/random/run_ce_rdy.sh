#!/usr/bin/env bash
# chip-2600#16: ce gating x rdy random test on the core copy. Usage: heavy tests/random/run_ce_rdy.sh [RTL_DIR] [N_PROGRAMS]
# Runs tb_ce_rdy over the generated random programs (tests/core/gen_cycles6502.py) x 3 rdy modes. Exit 1 on any failure.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"; mkdir -p build logs
rtl=${1:-rtl/cpu}; np=${2:-4}; bad=0
python3 tests/core/gen_cycles6502.py build/gen/c6502 >/dev/null
iverilog -g2012 -o build/ce_rdy.vvp tests/random/tb_ce_rdy.sv $(find "$rtl" -name '*.v') || exit 1
for s in $(seq 1 "$np"); do for m in 0 1 2; do
  r=$(vvp -n build/ce_rdy.vvp +MEM=build/gen/c6502/cyc_s$s.hex +SEED=$((s*100+m)) +MODE=$m +N=${N:-4000} | grep -E '^(PASS|FAIL)' | head -4)
  echo "prog s$s mode $m: $r"; case "$r" in PASS*) ;; *) bad=$((bad+1));; esac
done; done
echo "ce_rdy: $bad failing"; [ $bad -eq 0 ]
