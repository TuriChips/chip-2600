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
echo "unmutated mbgfx model: $(one mbgfx $D/mbgfx.v)" | tee -a $L
echo "unmutated prio model: $(one prio $D/prio.v)" | tee -a $L
echo "unmutated pgfx model: $(one pgfx "$D/pgfx.v $D/regs.v")" | tee -a $L
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
mutp() { n=$1; sed "$2" $D/pgfx.v > $M/pgfx.v; cmp -s $D/pgfx.v $M/pgfx.v && { echo "mutant $n: SED NO-OP" | tee -a $L; rc=1; return; }
  r=$(one pgfx "$M/pgfx.v $D/regs.v"); echo "mutant $n: $r" | tee -a $L; case "$r" in FAIL:*) ;; *) rc=1;; esac; }
mutp "pgfx ignores vdel (always new)" 's/vdel ? grp_old : grp_new/grp_new/'
mutp "pgfx vdel inverted" 's/vdel ? grp_old : grp_new/vdel ? grp_new : grp_old/'
mutp "pgfx always old" 's/vdel ? grp_old : grp_new/grp_old/'
mutp "pgfx refp ignored (D7 first)" 's/refp ? g\[i\] : g\[7-i\]/g[7-i]/'
mutp "pgfx refp ignored (D0 first)" 's/refp ? g\[i\] : g\[7-i\]/g[i]/'
mutp "pgfx refp inverted" 's/refp ? g\[i\] : g\[7-i\]/refp ? g[7-i] : g[i]/'
mutp "pgfx 101 is 1 clk" 's/nusiz==3.b101 ? 2.d1/nusiz==3\x27b101 ? 2\x27d0/'
mutp "pgfx 101 is 4 clk" 's/nusiz==3.b101 ? 2.d1/nusiz==3\x27b101 ? 2\x27d3/'
mutp "pgfx 111 is 2 clk" 's/nusiz==3.b111 ? 2.d3/nusiz==3\x27b111 ? 2\x27d1/'
mutp "pgfx 111 is 1 clk" 's/nusiz==3.b111 ? 2.d3/nusiz==3\x27b111 ? 2\x27d0/'
mutp "pgfx 110 is 2 clk" 's/nusiz==3.b111 ? 2.d3 : 2.d0/nusiz==3\x27b111 ? 2\x27d3 : nusiz==3\x27b110 ? 2\x27d1 : 2\x27d0/'
mutp "pgfx 100 is 2 clk" 's/nusiz==3.b111 ? 2.d3 : 2.d0/nusiz==3\x27b111 ? 2\x27d3 : nusiz==3\x27b100 ? 2\x27d1 : 2\x27d0/'
mutp "pgfx 001 is 2 clk" 's/nusiz==3.b111 ? 2.d3 : 2.d0/nusiz==3\x27b111 ? 2\x27d3 : nusiz==3\x27b001 ? 2\x27d1 : 2\x27d0/'
mutp "pgfx 011 is 4 clk" 's/nusiz==3.b111 ? 2.d3 : 2.d0/nusiz==3\x27b111 ? 2\x27d3 : nusiz==3\x27b011 ? 2\x27d3 : 2\x27d0/'
mutp "pgfx 010 is 2 clk" 's/nusiz==3.b111 ? 2.d3 : 2.d0/nusiz==3\x27b111 ? 2\x27d3 : nusiz==3\x27b010 ? 2\x27d1 : 2\x27d0/'
mutp "pgfx draws without start" 's/reg act;/reg act = 1;/; s/if (rst) begin act<=0;/if (rst) begin act<=1;/'
mutp "pgfx scan loops after bit 7" 's/if (i==7) act<=0; else i<=i+1;/i<=i+1;/'
mutp "pgfx stops after bit 6" 's/if (i==7) act<=0;/if (i==6) act<=0;/'
mutp "pgfx start ignored while drawing" 's/else if (start) begin/else if (start \&\& !act) begin/'
mutp "pgfx restart keeps the bit index" 's/else if (start) begin act<=1; i<=0; c<=0; end/else if (start) begin act<=1; c<=0; end/'
mutp "pgfx restart keeps the clock count" 's/else if (start) begin act<=1; i<=0; c<=0; end/else if (start) begin act<=1; i<=0; end/'
mutp "pgfx rst ignored" 's/if (rst) begin act<=0; i<=0; c<=0; end/if (rst) begin i<=0; c<=0; end/'
mutp "pgfx advances without step" 's/else if (step \&\& act)/else if (act)/'
mutp "pgfx output not gated by act" 's/assign pgfx = act \&/assign pgfx = /'
mutr() { n=$1; sed "$2" $D/regs.v > $M/regs.v; cmp -s $D/regs.v $M/regs.v && { echo "mutant $n: SED NO-OP" | tee -a $L; rc=1; return; }
  r=$(one pgfx "$D/pgfx.v $M/regs.v"); echo "mutant $n: $r" | tee -a $L; case "$r" in FAIL:*) ;; *) rc=1;; esac; }
mutr "pgfx e2e: GRP0 write forgets P1 old" 's/27: begin grp0_new<=d; grp1_old<=grp1_new; end/27: grp0_new<=d;/'
mutr "pgfx e2e: GRP1 write forgets P0 old" 's/grp0_old<=grp0_new; enabl_old/enabl_old/'
mutr "pgfx e2e: GRP0 write copies P0 new to old" 's/27: begin grp0_new<=d; grp1_old<=grp1_new; end/27: begin grp0_new<=d; grp1_old<=grp1_new; grp0_old<=grp0_new; end/'
mutr "pgfx e2e: NUSIZ stores D5-D4 in the width bits" 's/4: nusiz0<={d\[5\],d\[4\],d\[2:0\]};/4: nusiz0<={d[2:0],d[5],d[4]};/'
mutm() { n=$1; sed "$2" $D/mbgfx.v > $M/mbgfx.v; cmp -s $D/mbgfx.v $M/mbgfx.v && { echo "mutant $n: SED NO-OP" | tee -a $L; rc=1; return; }
  r=$(one mbgfx $M/mbgfx.v); echo "mutant $n: $r" | tee -a $L; case "$r" in FAIL:*) ;; *) rc=1;; esac; }
mutm "mbgfx width 1,1,2,4" 's/n+1 >= w/n+1 >= (w>>1 | 1)/'
mutm "mbgfx restart keeps the step count" 's/else if (start) begin act<=1; n<=0; end/else if (start) begin act<=1; end/'
mutm "mbgfx en ignored" 's/assign gfx = act \& en/assign gfx = act/'
mutm "mbgfx step wins over start" 's/else if (start) begin/else if (start \&\& !step) begin/'
mutm "mbgfx counts clocks, not steps" 's/else if (step \&\& act)/else if (act)/'
mutm "mbgfx 8-wide loses first clock" 's/assign gfx = act \& en/assign gfx = act \& en \& ~(n==0 \&\& size==3)/'
mutm "mbgfx rst ignored" 's/if (rst) begin act<=0; n<=0; end/if (rst) begin n<=0; end/'
mutm "mbgfx width latched at start" "s/wire \[3:0\] w = 4'd1 << size;/reg [3:0] w; always @(posedge clk) if (start) w <= 4'd1<<size;/"
mutm "mbgfx en latched at start" 's/assign gfx = act \& en/reg el; always @(posedge clk) if (start) el<=en; assign gfx = act \& el/'
mutq() { n=$1; sed "$2" $D/prio.v > $M/prio.v; cmp -s $D/prio.v $M/prio.v && { echo "mutant $n: SED NO-OP" | tee -a $L; rc=1; return; }
  r=$(one prio $M/prio.v); echo "mutant $n: $r" | tee -a $L; case "$r" in FAIL:*) ;; *) rc=1;; esac; }
mutq "prio P1 above P0" 's/o0 ? colup0 : o1 ? colup1 : ob ? pfc : colubk/o1 ? colup1 : o0 ? colup0 : ob ? pfc : colubk/'
mutq "prio PF above players when PFP = 0" 's/: (o0 ? colup0 : o1 ? colup1 : ob ? pfc : colubk)/: (ob ? pfc : o0 ? colup0 : o1 ? colup1 : colubk)/'
mutq "prio PFP ignored" 's/wire \[6:0\] c = pfp ?/wire [6:0] c = 1\x27b0 ?/'
mutq "prio PFP: P1 above P0" 's/ob ? pfc : o0 ? colup0 : o1 ? colup1 : colubk)/ob ? pfc : o1 ? colup1 : o0 ? colup0 : colubk)/'
mutq "prio PFP: PF above only BL (ball stays below players)" 's/(ob ? pfc : o0 ? colup0/(pf ? pfc : o0 ? colup0/'
mutq "prio missile colour from COLUP1 (M0)" 's/o0 = p0|m0/o0 = p0/; s/o1 = p1|m1/o1 = p1|m1|m0/'
mutq "prio M1 uses COLUP0" 's/o0 = p0|m0, o1 = p1|m1/o0 = p0|m0|m1, o1 = p1/'
mutq "prio BL ignored" 's/ob = pf|bl/ob = pf/'
mutq "prio PF ignored" 's/ob = pf|bl/ob = bl/'
mutq "prio SCORE ignored" 's/(score \&\& !pfp/(1\x27b0 \&\& !pfp/'
mutq "prio SCORE halves swapped" 's/right ? colup1 : colup0/right ? colup0 : colup1/'
mutq "prio SCORE takes COLUP0 on both halves" 's/right ? colup1 : colup0/colup0/'
# Not mutants: SCORE with BL = 1 or with PFP = 1 are the open [check] cases, deliberately unasserted, so changes there are invisible to the bench.
mutq "prio blk ignored" 's/assign {col, lum} = blk ? 7\x27d0 : c/assign {col, lum} = c/'
mutq "prio blk zeroes lum only" 's/blk ? 7\x27d0 : c/blk ? {c[6:3],3\x27d0} : c/'
mutq "prio blk zeroes col only" 's/blk ? 7\x27d0 : c/blk ? {4\x27d0,c[2:0]} : c/'
mutq "prio blk shows BK instead of 0" 's/blk ? 7\x27d0 : c/blk ? colubk : c/'
mutq "prio lum and col swapped" 's/assign {col, lum} = /assign {lum, col} = /'
mutq "prio lum from D4-D2" 's/assign {col, lum} = blk ? 7\x27d0 : c;/assign {col, lum} = blk ? 7\x27d0 : {c[6:3], c[3:1]};/'
mutq "prio BK colour from COLUPF" 's/ob ? pfc : colubk)/ob ? pfc : colupf)/'
rm -rf $M; exit $rc
