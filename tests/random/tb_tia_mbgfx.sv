// Replays the stimulus of run_tia_mbgfx.py on three tia_mbgfx instances (M0, M1, BL).
// Ports expected (#51): clk rst step start size[1:0] en -> gfx. Sampled 1 ns after each posedge.
// Stim line (hex): rst | per object: step start size en
`timescale 1ns/1ps
module tb_tia_mbgfx;
  reg clk=0, rst=0; reg [2:0] stp=0, sta=0, en=0; reg [1:0] sz0=0, sz1=0, sz2=0; wire [2:0] g;
  tia_mbgfx u0(.clk(clk),.rst(rst),.step(stp[0]),.start(sta[0]),.size(sz0),.en(en[0]),.gfx(g[0]));
  tia_mbgfx u1(.clk(clk),.rst(rst),.step(stp[1]),.start(sta[1]),.size(sz1),.en(en[1]),.gfx(g[1]));
  tia_mbgfx u2(.clk(clk),.rst(rst),.step(stp[2]),.start(sta[2]),.size(sz2),.en(en[2]),.gfx(g[2]));
  integer fi, fo, n, i, rc; reg [1023:0] sf, of;
  integer r, s0,t0,z0,e0, s1,t1,z1,e1, s2,t2,z2,e2;
  initial begin
    if (!$value$plusargs("STIM=%s", sf) || !$value$plusargs("OUT=%s", of) || !$value$plusargs("N=%d", n)) begin $display("need +STIM +OUT +N"); $finish; end
    fi=$fopen(sf,"r"); fo=$fopen(of,"w");
    rst=1; #5 clk=1; #5 clk=0; rst=0;
    for (i=0;i<n;i=i+1) begin
      rc=$fscanf(fi,"%h %h %h %h %h %h %h %h %h %h %h %h %h\n", r,s0,t0,z0,e0,s1,t1,z1,e1,s2,t2,z2,e2);
      rst=r; stp={s2[0],s1[0],s0[0]}; sta={t2[0],t1[0],t0[0]}; en={e2[0],e1[0],e0[0]}; sz0=z0; sz1=z1; sz2=z2;
      #5 clk=1; #1
      $fwrite(fo, "%0h %0h %0h\n", g[0], g[1], g[2]);
      #4 clk=0;
    end
    $fclose(fo); $finish;
  end
endmodule
