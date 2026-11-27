module tia_regs(input clk, rst, wr, input [5:0] a, input [7:0] d,
 output reg vsync, output reg [2:0] vblank, output reg [4:0] nusiz0, nusiz1, output reg [6:0] colup0,colup1,colupf,colubk,
 output reg [4:0] ctrlpf, output reg refp0, refp1, output reg [3:0] pf0, output reg [7:0] pf1, pf2,
 output reg [3:0] audc0,audc1, output reg [4:0] audf0,audf1, output reg [3:0] audv0,audv1,
 output reg [7:0] grp0_new,grp0_old,grp1_new,grp1_old, output reg enam0,enam1,enabl_new,enabl_old,
 output reg [3:0] hmp0,hmp1,hmm0,hmm1,hmbl, output reg vdelp0,vdelp1,vdelbl,resmp0,resmp1,
 output reg wsync_s,rsync_s,resp0_s,resp1_s,resm0_s,resm1_s,resbl_s,hmove_s,hmclr_s,cxclr_s);
 always @(posedge clk) begin
  {wsync_s,rsync_s,resp0_s,resp1_s,resm0_s,resm1_s,resbl_s,hmove_s,hmclr_s,cxclr_s} <= 0;
  if (rst) begin vsync<=0;vblank<=0;nusiz0<=0;nusiz1<=0;colup0<=0;colup1<=0;colupf<=0;colubk<=0;ctrlpf<=0;refp0<=0;refp1<=0;pf0<=0;pf1<=0;pf2<=0;
   audc0<=0;audc1<=0;audf0<=0;audf1<=0;audv0<=0;audv1<=0;grp0_new<=0;grp0_old<=0;grp1_new<=0;grp1_old<=0;enam0<=0;enam1<=0;enabl_new<=0;enabl_old<=0;
   hmp0<=0;hmp1<=0;hmm0<=0;hmm1<=0;hmbl<=0;vdelp0<=0;vdelp1<=0;vdelbl<=0;resmp0<=0;resmp1<=0; end
  else if (wr) case (a)
   0: vsync<=d[1]; 1: vblank<={d[7],d[6],d[1]}; 2: wsync_s<=1; 3: rsync_s<=1;
   4: nusiz0<={d[5],d[4],d[2:0]}; 5: nusiz1<={d[5],d[4],d[2:0]};
   6: colup0<=d[7:1]; 7: colup1<=d[7:1]; 8: colupf<=d[7:1]; 9: colubk<=d[7:1];
   10: ctrlpf<={d[5],d[4],d[2:0]}; 11: refp0<=d[3]; 12: refp1<=d[3]; 13: pf0<=d[7:4]; 14: pf1<=d;15: pf2<=d;
   16: resp0_s<=1; 17: resp1_s<=1; 18: resm0_s<=1; 19: resm1_s<=1; 20: resbl_s<=1;
   21: audc0<=d[3:0]; 22: audc1<=d[3:0]; 23: audf0<=d[4:0]; 24: audf1<=d[4:0]; 25: audv0<=d[3:0]; 26: audv1<=d[3:0];
   27: begin grp0_new<=d; grp1_old<=grp1_new; end
   28: begin grp1_new<=d; grp0_old<=grp0_new; enabl_old<=enabl_new; end
   29: enam0<=d[1]; 30: enam1<=d[1]; 31: enabl_new<=d[1];
   32: hmp0<=d[7:4]; 33: hmp1<=d[7:4]; 34: hmm0<=d[7:4]; 35: hmm1<=d[7:4]; 36: hmbl<=d[7:4];
   37: vdelp0<=d[0]; 38: vdelp1<=d[0]; 39: vdelbl<=d[0]; 40: resmp0<=d[1]; 41: resmp1<=d[1];
   42: hmove_s<=1; 43: begin hmclr_s<=1; hmp0<=0;hmp1<=0;hmm0<=0;hmm1<=0;hmbl<=0; end 44: cxclr_s<=1;
   default: ;
  endcase
 end
endmodule
