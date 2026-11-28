// Replays run_tia_prio.py stimulus on tia_prio (combinational).
// Stim line (hex): p0 m0 p1 m1 pf bl score pfp right blk colup0 colup1 colupf colubk.  Output line: lum col.
`timescale 1ns/1ps
module tb_tia_prio;
  reg p0=0,m0=0,p1=0,m1=0,pf=0,bl=0,sc=0,pp=0,rt=0,bk=0; reg [6:0] c0=0,c1=0,cf=0,cb=0; wire [2:0] lum; wire [3:0] col;
  tia_prio u(.p0(p0),.m0(m0),.p1(p1),.m1(m1),.pf(pf),.bl(bl),.score(sc),.pfp(pp),.right(rt),.blk(bk),
             .colup0(c0),.colup1(c1),.colupf(cf),.colubk(cb),.lum(lum),.col(col));
  integer fi, fo, n, i, rc; reg [1023:0] sf, of;
  integer a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1,b2,b3;
  initial begin
    if (!$value$plusargs("STIM=%s", sf) || !$value$plusargs("OUT=%s", of) || !$value$plusargs("N=%d", n)) begin $display("need +STIM +OUT +N"); $finish; end
    fi=$fopen(sf,"r"); fo=$fopen(of,"w");
    for (i=0;i<n;i=i+1) begin
      rc=$fscanf(fi,"%h %h %h %h %h %h %h %h %h %h %h %h %h %h\n",a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,b0,b1,b2,b3);
      p0=a0;m0=a1;p1=a2;m1=a3;pf=a4;bl=a5;sc=a6;pp=a7;rt=a8;bk=a9;c0=b0;c1=b1;cf=b2;cb=b3;
      #1 $fwrite(fo,"%0h %0h\n",lum,col);
    end
    $fclose(fo); $finish;
  end
endmodule
