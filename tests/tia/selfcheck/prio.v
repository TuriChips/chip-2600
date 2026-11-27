// Scratch model of tia_prio written from spec 6.9 / 6.4 and issue #61 (not the RTL). Open cases: SCORE with BL, SCORE with PFP: taken as plain PF/BL colour.
module tia_prio(input p0,m0,p1,m1,pf,bl,score,pfp,right,blk, input [6:0] colup0,colup1,colupf,colubk, output [2:0] lum, output [3:0] col);
  wire o0 = p0|m0, o1 = p1|m1, ob = pf|bl;
  wire [6:0] pfc = (score && !pfp && pf && !bl) ? (right ? colup1 : colup0) : colupf;
  wire [6:0] c = pfp ? (ob ? pfc : o0 ? colup0 : o1 ? colup1 : colubk)
                     : (o0 ? colup0 : o1 ? colup1 : ob ? pfc : colubk);
  assign {col, lum} = blk ? 7'd0 : c;
endmodule
