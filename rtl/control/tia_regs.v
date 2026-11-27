// tia_regs: TIA write-address decode and write registers.  Owner: Zura.
// Spec: docs/spec.md 6.1 (write map), 6.5 (vertical delay), 6.6 (HMCLR), 5 (reset).
//
// `wr` is a one-clk write pulse made by the top level.  On a clk edge with wr = 1,
// `a` selects one of the 45 write addresses $00-$2C; $2D-$3F do nothing.
// rst = 1 (synchronous) clears every register, latch and strobe.
//
// Output packing: stored bits concatenated high to low, in the order the 6.1 map lists them.
//   vsync   1 = D1                 vblank  3 = {D7,D6,D1}
//   nusiz0/1 5 = {D5,D4,D2,D1,D0} ctrlpf 5 = {D5,D4,D2,D1,D0}
//   colup0/1, colupf, colubk 7 = D7..D1
//   refp0/1 1 = D3                 pf0 4 = D7..D4   pf1, pf2 8 = D7..D0
//   audc0/1 4 = D3..D0   audf0/1 5 = D4..D0   audv0/1 4 = D3..D0
//   grp0_new/old, grp1_new/old 8 = D7..D0   enam0, enam1, enabl_new/old 1 = D1
//   hmp0, hmp1, hmm0, hmm1, hmbl 4 = D7..D4
//   vdelp0, vdelp1, vdelbl 1 = D0   resmp0, resmp1 1 = D1
// Strobes (wsync_s rsync_s resp0_s resp1_s resm0_s resm1_s resbl_s hmove_s hmclr_s cxclr_s):
//   REGISTERED one-clk pulses: 1 for the clk after the edge that saw wr = 1 and the address.
//   Data is ignored.
// Vertical delay (6.5): GRP0 write: grp0_new <= D, grp1_old <= grp1_new (pre-edge value).
//   GRP1 write: grp1_new <= D, grp0_old <= grp0_new and enabl_old <= enabl_new.
//   ENABL write only stores enabl_new.  VDEL selection belongs to the object blocks.
// HMCLR (6.6) clears hmp0, hmp1, hmm0, hmm1, hmbl on the same edge as hmclr_s rises.
module tia_regs (
    input  wire       clk,
    input  wire       rst,
    input  wire       wr,
    input  wire [5:0] a,
    input  wire [7:0] d,
    output reg        vsync,
    output reg  [2:0] vblank,
    output reg  [4:0] nusiz0,
    output reg  [4:0] nusiz1,
    output reg  [6:0] colup0,
    output reg  [6:0] colup1,
    output reg  [6:0] colupf,
    output reg  [6:0] colubk,
    output reg  [4:0] ctrlpf,
    output reg        refp0,
    output reg        refp1,
    output reg  [3:0] pf0,
    output reg  [7:0] pf1,
    output reg  [7:0] pf2,
    output reg  [3:0] audc0,
    output reg  [3:0] audc1,
    output reg  [4:0] audf0,
    output reg  [4:0] audf1,
    output reg  [3:0] audv0,
    output reg  [3:0] audv1,
    output reg  [7:0] grp0_new,
    output reg  [7:0] grp0_old,
    output reg  [7:0] grp1_new,
    output reg  [7:0] grp1_old,
    output reg        enam0,
    output reg        enam1,
    output reg        enabl_new,
    output reg        enabl_old,
    output reg  [3:0] hmp0,
    output reg  [3:0] hmp1,
    output reg  [3:0] hmm0,
    output reg  [3:0] hmm1,
    output reg  [3:0] hmbl,
    output reg        vdelp0,
    output reg        vdelp1,
    output reg        vdelbl,
    output reg        resmp0,
    output reg        resmp1,
    output reg        wsync_s,
    output reg        rsync_s,
    output reg        resp0_s,
    output reg        resp1_s,
    output reg        resm0_s,
    output reg        resm1_s,
    output reg        resbl_s,
    output reg        hmove_s,
    output reg        hmclr_s,
    output reg        cxclr_s
);
    always @(posedge clk) begin
        if (rst) begin
            vsync <= 1'b0;      vblank <= 3'd0;
            nusiz0 <= 5'd0;     nusiz1 <= 5'd0;
            colup0 <= 7'd0;     colup1 <= 7'd0;   colupf <= 7'd0;  colubk <= 7'd0;
            ctrlpf <= 5'd0;     refp0 <= 1'b0;    refp1 <= 1'b0;
            pf0 <= 4'd0;        pf1 <= 8'd0;      pf2 <= 8'd0;
            audc0 <= 4'd0;      audc1 <= 4'd0;    audf0 <= 5'd0;   audf1 <= 5'd0;
            audv0 <= 4'd0;      audv1 <= 4'd0;
            grp0_new <= 8'd0;   grp0_old <= 8'd0; grp1_new <= 8'd0; grp1_old <= 8'd0;
            enam0 <= 1'b0;      enam1 <= 1'b0;    enabl_new <= 1'b0; enabl_old <= 1'b0;
            hmp0 <= 4'd0;       hmp1 <= 4'd0;     hmm0 <= 4'd0;    hmm1 <= 4'd0;  hmbl <= 4'd0;
            vdelp0 <= 1'b0;     vdelp1 <= 1'b0;   vdelbl <= 1'b0;
            resmp0 <= 1'b0;     resmp1 <= 1'b0;
            wsync_s <= 1'b0;    rsync_s <= 1'b0;  resp0_s <= 1'b0; resp1_s <= 1'b0;
            resm0_s <= 1'b0;    resm1_s <= 1'b0;  resbl_s <= 1'b0;
            hmove_s <= 1'b0;    hmclr_s <= 1'b0;  cxclr_s <= 1'b0;
        end else begin
            wsync_s <= 1'b0;    rsync_s <= 1'b0;  resp0_s <= 1'b0; resp1_s <= 1'b0;
            resm0_s <= 1'b0;    resm1_s <= 1'b0;  resbl_s <= 1'b0;
            hmove_s <= 1'b0;    hmclr_s <= 1'b0;  cxclr_s <= 1'b0;
            if (wr) begin
                case (a)
                    6'h00: vsync  <= d[1];
                    6'h01: vblank <= {d[7], d[6], d[1]};
                    6'h02: wsync_s <= 1'b1;
                    6'h03: rsync_s <= 1'b1;
                    6'h04: nusiz0 <= {d[5], d[4], d[2], d[1], d[0]};
                    6'h05: nusiz1 <= {d[5], d[4], d[2], d[1], d[0]};
                    6'h06: colup0 <= d[7:1];
                    6'h07: colup1 <= d[7:1];
                    6'h08: colupf <= d[7:1];
                    6'h09: colubk <= d[7:1];
                    6'h0A: ctrlpf <= {d[5], d[4], d[2], d[1], d[0]};
                    6'h0B: refp0  <= d[3];
                    6'h0C: refp1  <= d[3];
                    6'h0D: pf0    <= d[7:4];
                    6'h0E: pf1    <= d;
                    6'h0F: pf2    <= d;
                    6'h10: resp0_s <= 1'b1;
                    6'h11: resp1_s <= 1'b1;
                    6'h12: resm0_s <= 1'b1;
                    6'h13: resm1_s <= 1'b1;
                    6'h14: resbl_s <= 1'b1;
                    6'h15: audc0  <= d[3:0];
                    6'h16: audc1  <= d[3:0];
                    6'h17: audf0  <= d[4:0];
                    6'h18: audf1  <= d[4:0];
                    6'h19: audv0  <= d[3:0];
                    6'h1A: audv1  <= d[3:0];
                    6'h1B: begin grp0_new <= d; grp1_old <= grp1_new; end
                    6'h1C: begin grp1_new <= d; grp0_old <= grp0_new; enabl_old <= enabl_new; end
                    6'h1D: enam0     <= d[1];
                    6'h1E: enam1     <= d[1];
                    6'h1F: enabl_new <= d[1];
                    6'h20: hmp0 <= d[7:4];
                    6'h21: hmp1 <= d[7:4];
                    6'h22: hmm0 <= d[7:4];
                    6'h23: hmm1 <= d[7:4];
                    6'h24: hmbl <= d[7:4];
                    6'h25: vdelp0 <= d[0];
                    6'h26: vdelp1 <= d[0];
                    6'h27: vdelbl <= d[0];
                    6'h28: resmp0 <= d[1];
                    6'h29: resmp1 <= d[1];
                    6'h2A: hmove_s <= 1'b1;
                    6'h2B: begin
                        hmclr_s <= 1'b1;
                        hmp0 <= 4'd0; hmp1 <= 4'd0; hmm0 <= 4'd0; hmm1 <= 4'd0; hmbl <= 4'd0;
                    end
                    6'h2C: cxclr_s <= 1'b1;
                    default: ;
                endcase
            end
        end
    end
endmodule
