// Scratch model of tia_pf from the spec 6.4 (not the RTL). Used only by selfcheck/run.sh.
module tia_pf(input clk, rst, step, start, right, pf_ref, input [3:0] pf0, input [7:0] pf1, pf2, output pf);
 reg [4:0] i;
 always @(posedge clk) if (rst||start) i<=0; else if (step) i<=(i==19)?19:i+1;
 wire [4:0] k = (right&&pf_ref) ? 5'd19-i : i;
 wire [19:0] l = {pf2[7],pf2[6],pf2[5],pf2[4],pf2[3],pf2[2],pf2[1],pf2[0], pf1[0],pf1[1],pf1[2],pf1[3],pf1[4],pf1[5],pf1[6],pf1[7], pf0[3],pf0[2],pf0[1],pf0[0]};
 assign pf = l[k];
endmodule
