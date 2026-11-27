// tia_pf: TIA playfield scanner (spec 6.4).
// Scan index 0..19 advances on `step` (once per 4 colour clocks), reset to 0 by `start`.
// Bit list, index 0..19: PF0 D4,D5,D6,D7 ; PF1 D7..D0 ; PF2 D0..D7.
// Left half, or right half with pf_ref=0: index i reads list[i].
// Right half with pf_ref=1: index i reads list[19-i].
// pf0/pf1/pf2 are read live (combinational on the index), so a write shows on the
// next bit reached. The top decides when the write lands and when `start` fires
// (RHB/CNT decodes: timing not settled, spec 4.1/6.4, turichips#48).
// SCORE and PFP are handled in the priority mux (spec 6.9), not here.
// pf0 is the 4-bit value from D7..D4 (pf0[0] = D4).
module tia_pf (
    input  wire       clk,
    input  wire       rst,
    input  wire       step,
    input  wire       start,
    input  wire       right,
    input  wire       pf_ref,
    input  wire [3:0] pf0,
    input  wire [7:0] pf1,
    input  wire [7:0] pf2,
    output wire       pf
);
    reg [4:0] idx;
    always @(posedge clk) begin
        if (rst || start) idx <= 5'd0;
        else if (step)    idx <= (idx == 5'd19) ? 5'd19 : idx + 5'd1;
    end

    wire [4:0] k = (right && pf_ref) ? (5'd19 - idx) : idx;
    wire [19:0] list = {pf2[7:0], pf1[0], pf1[1], pf1[2], pf1[3], pf1[4], pf1[5], pf1[6], pf1[7], pf0[3:0]};
    assign pf = list[k];
endmodule
