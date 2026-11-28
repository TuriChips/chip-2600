// Scratch model of tia_objpos from the spec 4.1, 6.5 (not the RTL). Used only by selfcheck/run.sh.
module cnt6(input clk, clr, step, output reg [5:0] q);
 always @(posedge clk) if (clr) q<=0; else if (step) q<={q[4:0], ~(q[4]^q[5])};
endmodule
module tia_objpos(input clk, rst, step, res, input [2:0] nusiz, output [5:0] q, output start_main, start_copy);
 wire err = q==6'b111111, wrap = q==6'b101101, c3 = q==6'b111000, c7 = q==6'b101111, c15 = q==6'b111001; // Q1..Q6 as q[0..5] reversed below
 wire [5:0] r = {q[0],q[1],q[2],q[3],q[4],q[5]};
 wire e = r==6'b111111, w = r==6'b101101, a3 = r==6'b111000, a7 = r==6'b101111, a15 = r==6'b111001;
 cnt6 u_cnt(.clk(clk), .clr(rst|res|(step&(w|e))), .step(step), .q(q));
 assign start_main = w;
 assign start_copy = (a3 & (nusiz==1|nusiz==3)) | (a7 & (nusiz==2|nusiz==3|nusiz==6)) | (a15 & (nusiz==4|nusiz==6));
endmodule
