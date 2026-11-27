// Scratch model of tia_mbgfx from spec 6.5 and chip-2600#51 (not the RTL). Used only by selfcheck/run.sh.
module tia_mbgfx(input clk, rst, step, start, input [1:0] size, input en, output gfx);
 reg act; reg [2:0] n;
 wire [3:0] w = 4'd1 << size;
 always @(posedge clk) begin
  if (rst) begin act<=0; n<=0; end
  else if (start) begin act<=1; n<=0; end
  else if (step && act) begin if (n+1 >= w) act<=0; n<=n+1; end
 end
 assign gfx = act & en;
endmodule
