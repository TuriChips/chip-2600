// Replays the stimulus of run_tia_objpos.py on one tia_objpos. Ports (#60): clk rst step res nusiz[2:0] -> q[5:0] start_main start_copy.
// Stim line (hex): rst step res nusiz inj (inj=1 forces q=111111 before the edge). Output line: q start_main start_copy, sampled 1 ns after each posedge.
`timescale 1ns/1ps
module tb_tia_objpos;
  reg clk=0, rst=0, stp=0, res=0; reg [2:0] nz=0; wire [5:0] q; wire sm, sc;
  tia_objpos u(.clk(clk),.rst(rst),.step(stp),.res(res),.nusiz(nz),.q(q),.start_main(sm),.start_copy(sc));
  integer fi, fo, n, i, rc; reg [1023:0] sf, of; integer r, s, e, z, j;
  initial begin
    if (!$value$plusargs("STIM=%s", sf) || !$value$plusargs("OUT=%s", of) || !$value$plusargs("N=%d", n)) begin $display("need +STIM +OUT +N"); $finish; end
    fi=$fopen(sf,"r"); fo=$fopen(of,"w");
    rst=1; #5 clk=1; #5 clk=0; rst=0;
    for (i=0;i<n;i=i+1) begin
      rc=$fscanf(fi,"%h %h %h %h %h\n", r, s, e, z, j);
      rst=r; stp=s; res=e; nz=z; if (j) u.u_cnt.q = 6'b111111;  // force ERR (hierarchical, RTL only)
      #5 clk=1; #1
      $fwrite(fo, "%0h %0h %0h\n", q, sm, sc);
      #4 clk=0;
    end
    $fclose(fo); $finish;
  end
endmodule
