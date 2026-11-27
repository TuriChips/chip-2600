#!/usr/bin/env bash
# TIA tests T1-T5, T7, T8, read map (spec 4.1, 5, 6.1, 6.4, 6.5, 6.6, 6.7, 6.8) on rtl/datapath/tia_poly6.v, tia_objdec.v, tia_pf.v and rtl/control/tia_hdec.v, tia_regs.v, tia_cx.v, tia_inpt.v, tia_rd.v.
# Usage: tests/tia/run_tia.sh   (Icarus). Log: logs/tia-tb-rtl.log. Exit 1 on any failure.
set -u
cd "$(git rev-parse --show-toplevel)"; mkdir -p build logs; rc=0; L=logs/tia-tb-rtl.log; : > "$L"
run() { # name tb sources...
  n=$1; tb=$2; shift 2
  iverilog -g2012 -o build/$n.vvp "$tb" "$@" >>"$L" 2>&1 || { echo "$n: COMPILE FAIL" | tee -a "$L"; rc=1; return; }
  out=$(vvp -n build/$n.vvp); echo "== $n"; echo "$out" | grep -vE 'finish' >>"$L"
  echo "$n: $(echo "$out" | grep -E '^(PASS|FAIL:)')" | tee -a "$L"; echo "$out" | grep -q '^PASS' || rc=1; }
run poly tb/tia/tb_poly.sv rtl/datapath/tia_poly6.v rtl/datapath/tia_objdec.v rtl/control/tia_hdec.v
run regs tb/tia/tb_regs.sv rtl/control/tia_regs.v
run cx tb/tia/tb_cx.sv rtl/control/tia_cx.v rtl/control/tia_inpt.v rtl/control/tia_rd.v
run pf tb/tia/tb_pf.sv rtl/datapath/tia_pf.v
if [ -f rtl/datapath/tia_pgfx.v ]; then run pgfx tb/tia/tb_pgfx.sv rtl/datapath/tia_pgfx.v rtl/control/tia_regs.v; else echo "pgfx: SKIPPED (rtl/datapath/tia_pgfx.v not merged, chip-2600#37)" | tee -a "$L"; fi
if [ -f rtl/datapath/tia_mbgfx.v ]; then run mbgfx tb/tia/tb_mbgfx.sv rtl/datapath/tia_mbgfx.v; else echo "mbgfx: SKIPPED (rtl/datapath/tia_mbgfx.v not merged, chip-2600#51)" | tee -a "$L"; fi
[ $rc -eq 0 ] && echo "tia: ALL PASS" | tee -a "$L" || echo "tia: FAILURES" | tee -a "$L"
exit $rc
