// tia_hdec: HSync counter decodes (spec 4.1 decode table).  Owner: Zura.
// Combinational.  q is tia_poly6's q: q[0] = Q1 ... q[5] = Q6.
// Each output is 1 when q equals the Q1..Q6 state listed in the 4.1 table.
// The D1/D2 delay boxes and END's reset route are NOT here ([check: LD s1 C5-C4], turichips#48).
//   shs  111100 (count 4)    rhs  110111 (8)     rcb 001111 (12)   rhb 011100 (16)
//   lrhb 010111 (18)         cnt  101100 (36)    end_ 010100 (56)  err 111111
// (state strings are Q1..Q6, left to right; the literals below are written Q6..Q1.)
module tia_hdec (
    input  wire [5:0] q,
    output wire       shs,
    output wire       rhs,
    output wire       rcb,
    output wire       rhb,
    output wire       lrhb,
    output wire       cnt,
    output wire       end_,
    output wire       err
);
    assign shs  = (q == 6'b001111);
    assign rhs  = (q == 6'b111011);
    assign rcb  = (q == 6'b111100);
    assign rhb  = (q == 6'b001110);
    assign lrhb = (q == 6'b111010);
    assign cnt  = (q == 6'b001101);
    assign end_ = (q == 6'b001010);
    assign err  = (q == 6'b111111);
endmodule
