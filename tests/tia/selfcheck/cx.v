// Scratch model of tia_cx, tia_inpt, tia_rd written from the spec and the port contract (not the RTL). Used only by selfcheck/run.sh.
module tia_cx(input clk, rst, p0,p1,m0,m1,bl,pf, vblank, en, cxclr, output reg [14:0] cx);
 wire [14:0] s = {m0&p1, m0&p0, m1&p0, m1&p1, p0&pf, p0&bl, p1&pf, p1&bl, m0&pf, m0&bl, m1&pf, m1&bl, bl&pf, p0&p1, m0&m1};
 always @(posedge clk) if (rst||cxclr) cx<=0; else if (en && !vblank) cx<=cx|s;
endmodule
module tia_inpt(input clk, rst, input [5:0] inpt_pin, input [2:0] vblank, output [5:0] inpt);
 reg [1:0] l;
 always @(posedge clk) if (rst || !vblank[1]) l<=2'b11; else l <= l & inpt_pin[5:4];
 assign inpt[3:0] = vblank[2] ? 4'b0 : inpt_pin[3:0];
 assign inpt[5:4] = vblank[1] ? l & inpt_pin[5:4] : inpt_pin[5:4];
endmodule
module tia_rd(input clk, rst, input [3:0] a, input [14:0] cx, input [5:0] inpt, output reg [1:0] d_out, d_oe);
 always @* begin d_out=0; d_oe=0;
  case (a)
   0,1,2,3,4,5,7: begin d_out={cx[14-2*a], cx[13-2*a]}; d_oe=3; end
   6: begin d_out={cx[2],1'b0}; d_oe=2; end
   8,9,10,11,12,13: begin d_out={inpt[a-8],1'b0}; d_oe=2; end
   default: ;
  endcase
  if (a==7) d_out={cx[1],cx[0]};
 end
endmodule
