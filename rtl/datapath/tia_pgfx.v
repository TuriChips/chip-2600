// tia_pgfx: TIA player graphics scanner (spec 6.5 Players, Vertical delay).
// Ports:
//   clk, rst         input        clock, synchronous reset (idle, output 0)
//   step             input        one pulse per colour clock while the caller wants the scan to advance
//   start            input        begin (or restart) the scan: bit 0 is shown from the next clock
//   nusiz[2:0]       input        NUSIZ D2..D0: 101 -> 2 clocks/bit, 111 -> 4, others -> 1 (SPG p.22)
//   grp_new[7:0]     input        GRPx new copy
//   grp_old[7:0]     input        GRPx old copy
//   vdel             input        VDELPx D0: 1 selects old, 0 selects new
//   refl             input        REFPx D3: 1 scans D0 first, 0 scans D7 first (SPG p.41)
//   gfx              output       current graphics bit, 0 when not drawing
// `start` wins over `step` in the same clock. GRP and size inputs are read live.
// Which clock `start` fires on (copy decodes, stretched-mode +1 delay) is the position
// counter's job (turichips#48), not decided here.
module tia_pgfx (
    input  wire       clk,
    input  wire       rst,
    input  wire       step,
    input  wire       start,
    input  wire [2:0] nusiz,
    input  wire [7:0] grp_new,
    input  wire [7:0] grp_old,
    input  wire       vdel,
    input  wire       refl,
    output wire       gfx
);
    reg       active;
    reg [2:0] idx;   // bit number scanned so far, 0..7
    reg [1:0] sub;   // clocks spent on the current bit

    wire [1:0] last = (nusiz == 3'b111) ? 2'd3 : (nusiz == 3'b101) ? 2'd1 : 2'd0;

    always @(posedge clk) begin
        if (rst) begin
            active <= 1'b0;
            idx    <= 3'd0;
            sub    <= 2'd0;
        end else if (start) begin
            active <= 1'b1;
            idx    <= 3'd0;
            sub    <= 2'd0;
        end else if (step && active) begin
            if (sub == last) begin
                sub <= 2'd0;
                if (idx == 3'd7) active <= 1'b0;
                idx <= idx + 3'd1;
            end else begin
                sub <= sub + 2'd1;
            end
        end
    end

    wire [7:0] g = vdel ? grp_old : grp_new;
    wire [2:0] k = refl ? idx : ~idx;   // ~idx = 7 - idx
    assign gfx = active & g[k];
endmodule
