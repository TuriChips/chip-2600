module tia_poly6(input clk, input step, input rst, output reg [5:0] q);
  always @(posedge clk) if (rst) q <= 0; else if (step) q <= {q[4:0], ~(q[4]^q[5])};
endmodule
module tia_objdec(input [5:0] q, output err, wrap, c3, c7, c15);
  function [5:0] S(input [5:0] s); S = {s[0],s[1],s[2],s[3],s[4],s[5]}; endfunction
  assign err = q==S(6'b111111), wrap = q==S(6'b101101), c3 = q==S(6'b111000), c7 = q==S(6'b101111), c15 = q==S(6'b111001);
endmodule
module tia_hdec(input [5:0] q, output shs,rhs,rcb,rhb,lrhb,cnt,end_,err);
  function [5:0] S(input [5:0] s); S = {s[0],s[1],s[2],s[3],s[4],s[5]}; endfunction
  assign shs=q==S(6'b111100), rhs=q==S(6'b110111), rcb=q==S(6'b001111), rhb=q==S(6'b011100), lrhb=q==S(6'b010111), cnt=q==S(6'b101100), end_=q==S(6'b010100), err=q==S(6'b111111);
endmodule
