// TIA object decode matrix, combinational (spec 6.5 rows 1-5).
// q[0]=Q1 .. q[5]=Q6. No NUSIZ gating here.
`default_nettype none
module tia_objdec (
    input  wire [5:0] q,
    output wire       err,   // Q1..Q6 = 111111
    output wire       wrap,  // 101101 (count 39)
    output wire       c3,    // 111000
    output wire       c7,    // 101111
    output wire       c15    // 111001
);
    // Patterns written Q1..Q6 left to right; q[0] is Q1, so reverse bits.
    localparam [5:0] P_ERR  = 6'b111111;
    localparam [5:0] P_WRAP = 6'b101101;
    localparam [5:0] P_C3   = 6'b111000;
    localparam [5:0] P_C7   = 6'b101111;
    localparam [5:0] P_C15  = 6'b111001;

    wire [5:0] qs = {q[0], q[1], q[2], q[3], q[4], q[5]}; // Q1 is MSB

    assign err  = (qs == P_ERR);
    assign wrap = (qs == P_WRAP);
    assign c3   = (qs == P_C3);
    assign c7   = (qs == P_C7);
    assign c15  = (qs == P_C15);
endmodule
`default_nettype wire
