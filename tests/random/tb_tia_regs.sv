// Generated from ref/tia_regs.py port list (names/widths from #20). Drives tia_regs from a stim file, dumps every output after each clk edge.
// Sampling: 1 time unit after posedge clk (registered strobes show the pulse in the cycle after the write edge).
`timescale 1ns/1ps
module tb_tia_regs;
  reg clk=0, rst=0, wr=0; reg [5:0] a=0; reg [7:0] d=0;
  wire [3:0] audc0;
  wire [3:0] audc1;
  wire [4:0] audf0;
  wire [4:0] audf1;
  wire [3:0] audv0;
  wire [3:0] audv1;
  wire [6:0] colubk;
  wire [6:0] colup0;
  wire [6:0] colup1;
  wire [6:0] colupf;
  wire [4:0] ctrlpf;
  wire [0:0] cxclr_s;
  wire [0:0] enabl_new;
  wire [0:0] enabl_old;
  wire [0:0] enam0;
  wire [0:0] enam1;
  wire [7:0] grp0_new;
  wire [7:0] grp0_old;
  wire [7:0] grp1_new;
  wire [7:0] grp1_old;
  wire [3:0] hmbl;
  wire [0:0] hmclr_s;
  wire [3:0] hmm0;
  wire [3:0] hmm1;
  wire [0:0] hmove_s;
  wire [3:0] hmp0;
  wire [3:0] hmp1;
  wire [4:0] nusiz0;
  wire [4:0] nusiz1;
  wire [3:0] pf0;
  wire [7:0] pf1;
  wire [7:0] pf2;
  wire [0:0] refp0;
  wire [0:0] refp1;
  wire [0:0] resbl_s;
  wire [0:0] resm0_s;
  wire [0:0] resm1_s;
  wire [0:0] resmp0;
  wire [0:0] resmp1;
  wire [0:0] resp0_s;
  wire [0:0] resp1_s;
  wire [0:0] rsync_s;
  wire [2:0] vblank;
  wire [0:0] vdelbl;
  wire [0:0] vdelp0;
  wire [0:0] vdelp1;
  wire [0:0] vsync;
  wire [0:0] wsync_s;
  tia_regs dut(.clk(clk),.rst(rst),.wr(wr),.a(a),.d(d),
    .audc0(audc0),
    .audc1(audc1),
    .audf0(audf0),
    .audf1(audf1),
    .audv0(audv0),
    .audv1(audv1),
    .colubk(colubk),
    .colup0(colup0),
    .colup1(colup1),
    .colupf(colupf),
    .ctrlpf(ctrlpf),
    .cxclr_s(cxclr_s),
    .enabl_new(enabl_new),
    .enabl_old(enabl_old),
    .enam0(enam0),
    .enam1(enam1),
    .grp0_new(grp0_new),
    .grp0_old(grp0_old),
    .grp1_new(grp1_new),
    .grp1_old(grp1_old),
    .hmbl(hmbl),
    .hmclr_s(hmclr_s),
    .hmm0(hmm0),
    .hmm1(hmm1),
    .hmove_s(hmove_s),
    .hmp0(hmp0),
    .hmp1(hmp1),
    .nusiz0(nusiz0),
    .nusiz1(nusiz1),
    .pf0(pf0),
    .pf1(pf1),
    .pf2(pf2),
    .refp0(refp0),
    .refp1(refp1),
    .resbl_s(resbl_s),
    .resm0_s(resm0_s),
    .resm1_s(resm1_s),
    .resmp0(resmp0),
    .resmp1(resmp1),
    .resp0_s(resp0_s),
    .resp1_s(resp1_s),
    .rsync_s(rsync_s),
    .vblank(vblank),
    .vdelbl(vdelbl),
    .vdelp0(vdelp0),
    .vdelp1(vdelp1),
    .vsync(vsync),
    .wsync_s(wsync_s));
  integer fi, fo, n, i, r_, w_, a_, d_; reg [1023:0] sf, of; integer rc;
  initial begin
    if (!$value$plusargs("STIM=%s", sf) || !$value$plusargs("OUT=%s", of) || !$value$plusargs("N=%d", n)) $fatal(1, "need +STIM +OUT +N");
    fi=$fopen(sf,"r"); fo=$fopen(of,"w");
    for (i=0;i<n;i=i+1) begin
      rc=$fscanf(fi,"%d %d %h %h\n", r_, w_, a_, d_);
      rst=r_; wr=w_; a=a_; d=d_;
      #5 clk=1; #1
      $fwrite(fo, "audc0=%0h audc1=%0h audf0=%0h audf1=%0h audv0=%0h audv1=%0h colubk=%0h colup0=%0h colup1=%0h colupf=%0h ctrlpf=%0h cxclr_s=%0h enabl_new=%0h enabl_old=%0h enam0=%0h enam1=%0h grp0_new=%0h grp0_old=%0h grp1_new=%0h grp1_old=%0h hmbl=%0h hmclr_s=%0h hmm0=%0h hmm1=%0h hmove_s=%0h hmp0=%0h hmp1=%0h nusiz0=%0h nusiz1=%0h pf0=%0h pf1=%0h pf2=%0h refp0=%0h refp1=%0h resbl_s=%0h resm0_s=%0h resm1_s=%0h resmp0=%0h resmp1=%0h resp0_s=%0h resp1_s=%0h rsync_s=%0h vblank=%0h vdelbl=%0h vdelp0=%0h vdelp1=%0h vsync=%0h wsync_s=%0h\n",
        audc0, audc1, audf0, audf1, audv0, audv1, colubk, colup0, colup1, colupf, ctrlpf, cxclr_s, enabl_new, enabl_old, enam0, enam1, grp0_new, grp0_old, grp1_new, grp1_old, hmbl, hmclr_s, hmm0, hmm1, hmove_s, hmp0, hmp1, nusiz0, nusiz1, pf0, pf1, pf2, refp0, refp1, resbl_s, resm0_s, resm1_s, resmp0, resmp1, resp0_s, resp1_s, rsync_s, vblank, vdelbl, vdelp0, vdelp1, vsync, wsync_s);
      #4 clk=0;
    end
    $fclose(fo); $finish;
  end
endmodule
