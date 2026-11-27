// tia_prio: TIA priority encoder and colour mux (combinational).  Owner: Zura.
// Spec: docs/spec.md 6.9 (priority, colour), 6.4 (SCORE, PFP), 6.2 (blank).
//
// Ports
//   p0 m0 p1 m1 pf bl  in  1  serial outputs of the six objects this colour clock
//   score, pfp         in  1  CTRLPF D1, D2
//   right              in  1  1 in the right half of the visible line (caller derives it from CNT)
//   blk                in  1  6.2 blank
//   colup0 colup1 colupf colubk  in 7 each  register D7-D1
//   lum                out 3  D3-D1 of the selected register
//   col                out 4  D7-D4 of the selected register
//
// Behaviour
//   Normal: P0/M0 (COLUP0) > P1/M1 (COLUP1) > PF/BL (COLUPF) > BK (COLUBK).
//   PFP = 1: PF/BL > P0/M0 > P1/M1 > BK.
//   SCORE = 1, PFP = 0, PF = 1, BL = 0: PF takes COLUP0 (right = 0) or COLUP1 (right = 1).
//   blk = 1: lum = 0, col = 0.
//
// OPEN (spec 6.9 [check], turichips#48, LD s5 "PRIORITY ENCODER"): the colour when SCORE = 1
// with BL = 1, and when SCORE = 1 with PFP = 1, is NOT settled.  The placeholder below
// (score_pf, one expression) takes the SCORE colour only for PFP = 0, PF = 1, BL = 0; every
// other case uses COLUPF.  A ruling changes only that one line.
module tia_prio (
    input  wire       p0,
    input  wire       m0,
    input  wire       p1,
    input  wire       m1,
    input  wire       pf,
    input  wire       bl,
    input  wire       score,
    input  wire       pfp,
    input  wire       right,
    input  wire       blk,
    input  wire [6:0] colup0,
    input  wire [6:0] colup1,
    input  wire [6:0] colupf,
    input  wire [6:0] colubk,
    output wire [2:0] lum,
    output wire [3:0] col
);
    wire g0 = p0 | m0;
    wire g1 = p1 | m1;
    wire gf = pf | bl;

    // OPEN CASES live here (SCORE with BL, SCORE with PFP): one-line change when ruled.
    wire score_pf = score & ~pfp & pf & ~bl;

    wire [6:0] pfcol = score_pf ? (right ? colup1 : colup0) : colupf;

    reg [6:0] sel;
    always @* begin
        if (pfp) begin
            if (gf)      sel = pfcol;
            else if (g0) sel = colup0;
            else if (g1) sel = colup1;
            else         sel = colubk;
        end else begin
            if (g0)      sel = colup0;
            else if (g1) sel = colup1;
            else if (gf) sel = pfcol;
            else         sel = colubk;
        end
    end

    assign lum = blk ? 3'd0 : sel[2:0];
    assign col = blk ? 4'd0 : sel[6:3];
endmodule
