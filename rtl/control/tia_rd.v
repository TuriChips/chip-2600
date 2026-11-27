// tia_rd: TIA read mux, combinational.  Owner: Zura.  Spec: docs/spec.md 6.1 (read map).
//
// a = A0-A3.  d_out = {D7, D6}, d_oe = one bit per line, 1 = TIA drives it.
//   $0-$7  collision registers (cx packing: see tia_cx.v), D7 and D6 driven.
//          CXBLPF ($6): D7 only.  OPEN POINT 6.1 [check: LD s2 C6]: D6 is driven as 0 with
//          d_oe[0] = 0 (not driven) until the spec settles it.
//   $8-$D  INPT0-INPT5 on D7, D6 not driven.
//   $E,$F  nothing driven.
// clk and rst are in the port list for uniformity (issue #28) and unused: the mux is combinational.
module tia_rd (
    input  wire        clk,
    input  wire        rst,
    input  wire [3:0]  a,
    input  wire [14:0] cx,
    input  wire [5:0]  inpt,
    output reg  [1:0]  d_out,
    output reg  [1:0]  d_oe
);
    wire unused_clk_rst = &{1'b0, clk, rst};

    always @* begin
        d_out = 2'b00;
        d_oe  = 2'b00;
        case (a)
            4'h0: begin d_out = cx[14:13]; d_oe = 2'b11; end
            4'h1: begin d_out = cx[12:11]; d_oe = 2'b11; end
            4'h2: begin d_out = cx[10:9];  d_oe = 2'b11; end
            4'h3: begin d_out = cx[8:7];   d_oe = 2'b11; end
            4'h4: begin d_out = cx[6:5];   d_oe = 2'b11; end
            4'h5: begin d_out = cx[4:3];   d_oe = 2'b11; end
            4'h6: begin d_out = {cx[2], 1'b0}; d_oe = 2'b10; end
            4'h7: begin d_out = cx[1:0];   d_oe = 2'b11; end
            4'h8: begin d_out = {inpt[0], 1'b0}; d_oe = 2'b10; end
            4'h9: begin d_out = {inpt[1], 1'b0}; d_oe = 2'b10; end
            4'hA: begin d_out = {inpt[2], 1'b0}; d_oe = 2'b10; end
            4'hB: begin d_out = {inpt[3], 1'b0}; d_oe = 2'b10; end
            4'hC: begin d_out = {inpt[4], 1'b0}; d_oe = 2'b10; end
            4'hD: begin d_out = {inpt[5], 1'b0}; d_oe = 2'b10; end
            default: ;
        endcase
    end
endmodule
