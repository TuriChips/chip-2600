// tia_cx: TIA collision latches.  Owner: Zura.  Spec: docs/spec.md 6.1 (read map), 6.7, 5 (reset).
//
// 15 latches, one per object pair.  On a clk edge with en = 1 (one-clk pulse per colour clock),
// a latch sets when both of its objects' serial outputs are 1 and vblank = 0.
// Only VBLANK D1 gates (6.7): HBLANK and the HMOVE comb do NOT.
// cxclr (strobe from tia_regs) clears all 15 and wins over a set on the same clk.
// rst = 1 (synchronous) clears all.
//
// Output packing of cx, bit 14 first, in read-map order (6.1):
//   {CXM0P D7,D6, CXM1P D7,D6, CXP0FB D7,D6, CXP1FB D7,D6, CXM0FB D7,D6, CXM1FB D7,D6,
//    CXBLPF D7, CXPPMM D7,D6}
//   cx[14]=M0*P1  [13]=M0*P0  [12]=M1*P0  [11]=M1*P1  [10]=P0*PF  [9]=P0*BL  [8]=P1*PF  [7]=P1*BL
//   cx[6]=M0*PF   [5]=M0*BL   [4]=M1*PF   [3]=M1*BL   [2]=BL*PF  [1]=P0*P1  [0]=M0*M1
// OPEN POINT (6.1 [check: LD s2 C6]): CXBLPF D6 is unknown.  There is no latch for it; tia_rd
// drives it as 0 with d_oe[0] = 0 (D6 not driven) so the open point stays visible.
module tia_cx (
    input  wire        clk,
    input  wire        rst,
    input  wire        p0,
    input  wire        p1,
    input  wire        m0,
    input  wire        m1,
    input  wire        bl,
    input  wire        pf,
    input  wire        vblank,   // VBLANK D1
    input  wire        en,
    input  wire        cxclr,
    output reg  [14:0] cx
);
    wire [14:0] hit = {
        m0 & p1, m0 & p0, m1 & p0, m1 & p1,
        p0 & pf, p0 & bl, p1 & pf, p1 & bl,
        m0 & pf, m0 & bl, m1 & pf, m1 & bl,
        bl & pf, p0 & p1, m0 & m1
    };

    always @(posedge clk) begin
        if (rst || cxclr)
            cx <= 15'd0;
        else if (en && !vblank)
            cx <= cx | hit;
    end
endmodule
