// TIA object position counter (spec 6.5): one instance per object (P0, P1, M0, M1, BL).
// Ports:
//   clk, rst   in 1  clock; synchronous reset, counter = 000000
//   step       in 1  one counter step (caller derives it from MOTCK/HMOVE; no timing here)
//   res        in 1  RESxx strobe: counter = 000000 this clock (wins over step)
//   nusiz      in 3  NUSIZ D2..D0 (tie to 000 for the ball)
//   q          out 6 counter state, q[0]=Q1 .. q[5]=Q6, as tia_poly6
//   start_main out 1 1 while state is the wrap decode (101101, count 39)
//   start_copy out 1 1 while state is a copy decode enabled by nusiz
// Not here: +4/+5 landing delays, stretched-mode +1, "one count later" start,
// HMOVE, RESMPx (wait on spec 4.2, turichips#48).
`default_nettype none
module tia_objpos (
    input  wire       clk,
    input  wire       rst,
    input  wire       step,
    input  wire       res,
    input  wire [2:0] nusiz,
    output wire [5:0] q,
    output wire       start_main,
    output wire       start_copy
);
    wire err, wrap, c3, c7, c15;

    tia_objdec u_dec (.q(q), .err(err), .wrap(wrap), .c3(c3), .c7(c7), .c15(c15));

    // From wrap or ERR a step goes to 000000; res and rst also clear.
    wire clr = rst | res | (step & (wrap | err));

    tia_poly6 u_cnt (.clk(clk), .step(step), .rst(clr), .q(q));

    // NUSIZ copy enables (spec 6.5 table).
    wire en3  = (nusiz == 3'b001) | (nusiz == 3'b011);
    wire en7  = (nusiz == 3'b010) | (nusiz == 3'b011) | (nusiz == 3'b110);
    wire en15 = (nusiz == 3'b100) | (nusiz == 3'b110);

    assign start_main = wrap;
    assign start_copy = (c3 & en3) | (c7 & en7) | (c15 & en15);
endmodule
`default_nettype wire
