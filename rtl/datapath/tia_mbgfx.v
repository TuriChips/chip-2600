// tia_mbgfx: TIA missile / ball graphics (spec 6.5 Missiles and Ball, SPG pp.38-41).
// One instance per missile and one for the ball.
// Ports:
//   clk, rst         input        clock, synchronous reset (idle, output 0)
//   step             input        one pulse per colour clock while the caller wants the run to advance
//   start            input        begin (or restart) a run: drawn from the next clock
//   size[1:0]        input        00 -> 1, 01 -> 2, 10 -> 4, 11 -> 8 colour clocks wide
//                                 (missile: NUSIZx D5..D4; ball: CTRLPF D5..D4)
//   en               input        object enabled. The caller builds it, outside this block:
//                                 missile: ENAMx D1 AND NOT RESMPx D1
//                                 ball:    VDELBL ? ENABL old : ENABL new
//   gfx              output       1 while drawing and en = 1, else 0
// `start` wins over `step` in the same clock. size and en are read live.
// Which clock `start` fires on (position counter, copies) is turichips#48, not decided here.
module tia_mbgfx (
    input  wire       clk,
    input  wire       rst,
    input  wire       step,
    input  wire       start,
    input  wire [1:0] size,
    input  wire       en,
    output wire       gfx
);
    reg       active;
    reg [2:0] cnt;   // clocks drawn so far, 0..7

    wire [2:0] last = (3'd1 << size) - 3'd1;   // width - 1

    always @(posedge clk) begin
        if (rst) begin
            active <= 1'b0;
            cnt    <= 3'd0;
        end else if (start) begin
            active <= 1'b1;
            cnt    <= 3'd0;
        end else if (step && active) begin
            if (cnt == last) active <= 1'b0;
            cnt <= cnt + 3'd1;
        end
    end

    assign gfx = active & en;
endmodule
