// Replays the stimulus of run_tia_pgfx.py on two tia_pgfx instances (ports as in rtl/datapath/tia_pgfx.v header):
// clk rst step start grp_new grp_old vdel refl nusiz -> gfx. Sampled 1 ns after each posedge.
// Stim line (hex): rst step0 start0 step1 start1 gn0 go0 vd0 rf0 nz0 gn1 go1 vd1 rf1 nz1
`timescale 1ns/1ps
module tb_tia_pgfx;
  reg clk=0, rst=0, step0=0, start0=0, step1=0, start1=0, vd0=0, rf0=0, vd1=0, rf1=0;
  reg [7:0] gn0=0, go0=0, gn1=0, go1=0; reg [2:0] nz0=0, nz1=0;
  wire pgfx0, pgfx1;
  tia_pgfx u0(.clk(clk),.rst(rst),.step(step0),.start(start0),.grp_new(gn0),.grp_old(go0),.vdel(vd0),.refl(rf0),.nusiz(nz0),.gfx(pgfx0));
  tia_pgfx u1(.clk(clk),.rst(rst),.step(step1),.start(start1),.grp_new(gn1),.grp_old(go1),.vdel(vd1),.refl(rf1),.nusiz(nz1),.gfx(pgfx1));
  integer fi, fo, n, i, rc; reg [1023:0] sf, of;
  integer a0,a1,a2,a3,a4,b0,b1,b2,b3,b4,c0,c1,c2,c3,c4;
  initial begin
    if (!$value$plusargs("STIM=%s", sf) || !$value$plusargs("OUT=%s", of) || !$value$plusargs("N=%d", n)) begin $display("need +STIM +OUT +N"); $finish; end
    fi=$fopen(sf,"r"); fo=$fopen(of,"w");
    // priming clock with rst=1 (ref starts idle; the RTL regs have no initial value), not sampled
    rst=1; #5 clk=1; #5 clk=0; rst=0;
    for (i=0;i<n;i=i+1) begin
      rc=$fscanf(fi,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h %h\n", a0,a1,a2,a3,a4,b0,b1,b2,b3,b4,c0,c1,c2,c3,c4);
      rst=a0; step0=a1; start0=a2; step1=a3; start1=a4;
      gn0=b0; go0=b1; vd0=b2; rf0=b3; nz0=b4; gn1=c0; go1=c1; vd1=c2; rf1=c3; nz1=c4;
      #5 clk=1; #1
      $fwrite(fo, "%0h %0h\n", pgfx0, pgfx1);
      #4 clk=0;
    end
    $fclose(fo); $finish;
  end
endmodule
