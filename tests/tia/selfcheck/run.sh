#!/usr/bin/env bash
# Testbench self-check: the T1-T5 benches on a scratch model written from the spec (poly.v, regs.v here, not the RTL),
# then on mutants of it. The unmutated model must PASS, every mutant must FAIL. Log: logs/tia-tb-selfcheck.log.
set -u
cd "$(git rev-parse --show-toplevel)"; D=tests/tia/selfcheck; M=$(mktemp -d); L=logs/tia-tb-selfcheck.log; : > $L; rc=0
one() { t=$1; f=$2; iverilog -g2012 -o $M/m.vvp tb/tia/tb_$t.sv $f 2>>$L && vvp -n $M/m.vvp | grep -E '^(PASS|FAIL:)'; }
echo "unmutated poly model: $(one poly $D/poly.v)" | tee -a $L
echo "unmutated cx model: $(one cx $D/cx.v)" | tee -a $L
echo "unmutated pf model: $(one pf $D/pf.v)" | tee -a $L
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
mut "cx ignores VBLANK D1" cx cx.v 's/en \&\& !vblank/en/'
mut "cx set on en=0" cx cx.v 's/else if (en \&\& !vblank)/else if (!vblank)/'
mut "cx set wins over CXCLR" cx cx.v 's/if (rst||cxclr) cx<=0; else if (en \&\& !vblank) cx<=cx|s;/if (en \&\& !vblank) cx<=cx|s; else if (rst||cxclr) cx<=0;/'
mut "cx pair M1.P0 and M1.P1 swapped" cx cx.v 's/m1\&p0, m1\&p1,/m1\&p1, m1\&p0,/'
mut "cx P1.BL wired as P1.PF" cx cx.v 's/p1\&pf, p1\&bl,/p1\&pf, p1\&pf,/'
mut "cx CXCLR does not clear M0.M1" cx cx.v 's/if (rst||cxclr) cx<=0;/if (rst||cxclr) cx<={cx[14:1],1\x27b0}|(cx\&15\x27h0001\&{15{cxclr}});/'
mut "inpt I3 not forced by D7" cx cx.v 's/vblank\[2\] ? 4.b0 : inpt_pin\[3:0\]/vblank[2] ? {inpt_pin[3],3\x27b0} : inpt_pin[3:0]/'
mut "inpt I4 forced by D7" cx cx.v 's/assign inpt\[5:4\] = vblank\[1\] ? l \& inpt_pin\[5:4\] : inpt_pin\[5:4\];/assign inpt[5:4] = (vblank[1] ? l \& inpt_pin[5:4] : inpt_pin[5:4]) \& {2\x27b1,~vblank[2]};/'
mut "inpt latch not reset by D6=0" cx cx.v 's/if (rst || !vblank\[1\]) l<=2.b11; else/if (rst) l<=2\x27b11; else/'
mut "inpt latch transparent (no hold)" cx cx.v 's/l <= l \& inpt_pin\[5:4\]/l <= inpt_pin[5:4]/'
mut "inpt latch shared between I4 and I5" cx cx.v 's/l <= l \& inpt_pin\[5:4\]/l <= {2{l[0]\&l[1]\&inpt_pin[4]\&inpt_pin[5]}}/'
mut "rd CXBLPF not driven on D7" cx cx.v 's/6: begin d_out={cx\[2\],1.b0}; d_oe=2;/6: begin d_out={cx[2],1\x27b0}; d_oe=0;/'
mut "rd INPT also drives D6" cx cx.v 's/d_out={inpt\[a-8\],1.b0}; d_oe=2;/d_out={inpt[a-8],1\x27b0}; d_oe=3;/'
mut "rd \$E drives" cx cx.v 's/default: ;/14: d_oe=2;\n   default: ;/'
mut "rd CXM1FB D6 reads CXM0FB D6" cx cx.v 's/d_oe=3; end$/d_oe=3; if (a==5) d_out[0]=cx[5]; end/'
mut "rd INPT3 reads INPT2" cx cx.v 's/inpt\[a-8\]/inpt[(a==11)?2:a-8]/'
mut "pf PF0 bit order reversed" pf pf.v 's/pf0\[3\],pf0\[2\],pf0\[1\],pf0\[0\]}/pf0[0],pf0[1],pf0[2],pf0[3]}/'
mut "pf PF1 bit order not reversed" pf pf.v 's/pf1\[0\],pf1\[1\],pf1\[2\],pf1\[3\],pf1\[4\],pf1\[5\],pf1\[6\],pf1\[7\]/pf1[7],pf1[6],pf1[5],pf1[4],pf1[3],pf1[2],pf1[1],pf1[0]/'
mut "pf PF2 bit order reversed" pf pf.v 's/pf2\[7\],pf2\[6\],pf2\[5\],pf2\[4\],pf2\[3\],pf2\[2\],pf2\[1\],pf2\[0\],/pf2[0],pf2[1],pf2[2],pf2[3],pf2[4],pf2[5],pf2[6],pf2[7],/'
mut "pf reflect ignored" pf pf.v 's/right\&\&pf_ref/1\x27b0/'
mut "pf reflect on the left half" pf pf.v 's/right\&\&pf_ref/pf_ref/'
mut "pf reflect on mirror of bits (18-i)" pf pf.v "s/5'd19-i/5'd18-i/"
mut "pf start ignored" pf pf.v 's/if (rst||start) i<=0;/if (rst) i<=0;/'
mut "pf rst ignored" pf pf.v 's/if (rst||start) i<=0;/if (start) i<=0;/'
mut "pf advances without step" pf pf.v 's/else if (step) i/else i/'
mut "pf advances every 2 steps" pf pf.v 's/else if (step) i<=(i==19)?19:i+1;/else if (step) i<=(i>=18)?19:i+2;/'
rm -rf $M; exit $rc
