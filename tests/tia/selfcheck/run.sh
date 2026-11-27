#!/usr/bin/env bash
# Testbench self-check: the T1-T5 benches on a scratch model written from the spec (poly.v, regs.v here, not the RTL),
# then on mutants of it. The unmutated model must PASS, every mutant must FAIL. Log: logs/tia-tb-selfcheck.log.
set -u
cd "$(git rev-parse --show-toplevel)"; D=tests/tia/selfcheck; M=$(mktemp -d); L=logs/tia-tb-selfcheck.log; : > $L; rc=0
one() { t=$1; f=$2; iverilog -g2012 -o $M/m.vvp tb/tia/tb_$t.sv $f 2>>$L && vvp -n $M/m.vvp | grep -E '^(PASS|FAIL:)'; }
echo "unmutated poly model: $(one poly $D/poly.v)" | tee -a $L
echo "unmutated regs model: $(one regs $D/regs.v)" | tee -a $L
mut() { n=$1; t=$2; f=$3; sed "$4" $D/$f > $M/$f; cmp -s $D/$f $M/$f && { echo "mutant $n: SED NO-OP" | tee -a $L; rc=1; return; }
  r=$(one $t $M/$f); echo "mutant $n: $r" | tee -a $L; case "$r" in FAIL:*) ;; *) rc=1;; esac; }
Q="'"
mut "GRP0 write also copies ENABL new to old" regs regs.v 's/27: begin grp0_new<=d; grp1_old<=grp1_new; end/27: begin grp0_new<=d; grp1_old<=grp1_new; enabl_old<=enabl_new; end/'
mut "GRP1 write forgets GRP0 old" regs regs.v 's/grp0_old<=grp0_new; enabl_old/enabl_old/'
mut "HMCLR leaves HMBL" regs regs.v 's/hmm1<=0;hmbl<=0; end 44/hmm1<=0; end 44/'
mut "\$2D acts as HMOVE" regs regs.v 's/default: ;/45: hmove_s<=1; default: ;/'
mut "COLUBK stores D7-D2 only" regs regs.v "s/9: colubk<=d\[7:1\]/9: colubk<={d[7:2],1${Q}b0}/"
mut "VDELBL stores D1" regs regs.v 's/39: vdelbl<=d\[0\]/39: vdelbl<=d[1]/'
mut "rst does not clear GRP1 old" regs regs.v 's/grp1_new<=0;grp1_old<=0;/grp1_new<=0;/'
mut "RESP0 strobe two clk wide" regs regs.v "s/always @(posedge clk) begin/reg p = 0; initial resp0_s = 0; always @(posedge clk) begin p <= resp0_s \&\& !p;/; s/cxclr_s} <= 0;/cxclr_s} <= 0; resp0_s <= resp0_s \&\& !p;/"
mut "poly taps Q4,Q6" poly poly.v 's/~(q\[4\]^q\[5\])/~(q[3]^q[5])/'
mut "poly rst loses to step" poly poly.v 's/if (rst) q <= 0; else if (step)/if (step) q <= {q[4:0], ~(q[4]^q[5])}; else if (rst)/'
mut "poly ignores step=0" poly poly.v 's/else if (step) q/else q/'
mut "hdec LRHB wrong state" poly poly.v "s/lrhb=q==S(6${Q}b010111)/lrhb=q==S(6${Q}b010110)/"
mut "objdec c7 wrong" poly poly.v "s/c7 = q==S(6${Q}b101111)/c7 = q==S(6${Q}b101110)/"
rm -rf $M; exit $rc
