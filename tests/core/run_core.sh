#!/usr/bin/env bash
# Core-copy tests (spec D3, D6): chip-6502's cycle and ALU suites on rtl/cpu with ce = 1, plus the directed
# $04 / $AB #0 / ce = 0 hold test. Usage: heavy tests/core/run_core.sh   (Icarus). Exit 1 on any failure.
set -u
cd "$(git rev-parse --show-toplevel)"; mkdir -p build logs; rc=0
echo "== cycles (chip-6502 gen_cycles6502, 16 runs, ce=1)"; bash tests/core/run_cyc.sh || rc=1
echo "== alu block (chip-6502 vectors, ce=1)"
python3 tests/core/alu/gen_vectors.py build/alu_vectors.hex >/dev/null
iverilog -g2012 -o build/alu.vvp tb/cpu/tb_alu.sv rtl/cpu/m6502_alu.v && \
  vvp -n build/alu.vvp +VEC=build/alu_vectors.hex +N=$(( $(wc -l < build/alu_vectors.hex) / 2 )) | grep -E '^(PASS|FAIL)' || rc=1
echo "== D6 and ce hold (directed)"
iverilog -g2012 -o build/d6.vvp tb/cpu/tb_d6.sv rtl/cpu/*.v && vvp -n build/d6.vvp | grep -vE 'finish' || rc=1
[ $rc -eq 0 ] && echo "core-copy: ALL PASS" || echo "core-copy: FAILURES"
exit $rc
