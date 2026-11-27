// Scratch model of tia_pgfx from the spec 6.5 (not the RTL). Used only by selfcheck/run.sh.
module tia_pgfx(input clk, rst, step, start, input [7:0] grp_new, grp_old, input vdel, refp, input [2:0] nusiz, output pgfx);
 reg act; reg [2:0] i; reg [1:0] c;
 wire [1:0] w = nusiz==3'b101 ? 2'd1 : nusiz==3'b111 ? 2'd3 : 2'd0;
 always @(posedge clk) if (rst) begin act<=0; i<=0; c<=0; end
  else if (start) begin act<=1; i<=0; c<=0; end
  else if (step && act) begin if (c>=w) begin c<=0; if (i==7) act<=0; else i<=i+1; end else c<=c+1; end
 wire [7:0] g = vdel ? grp_old : grp_new;
 assign pgfx = act & (refp ? g[i] : g[7-i]);
endmodule
