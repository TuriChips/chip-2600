// TIA 6-bit polynomial counter (spec 4.1, 6.5).
// q[0]=Q1 .. q[5]=Q6. Steps only when told; no timing of its own.
`default_nettype none
module tia_poly6 (
    input  wire       clk,
    input  wire       step,
    input  wire       rst,
    output reg  [5:0] q
);
    // new Q1 = XNOR(Q5, Q6); Qk = old Q(k-1)
    wire fb = ~(q[4] ^ q[5]);

    always @(posedge clk) begin
        if (rst)
            q <= 6'b000000;
        else if (step)
            q <= {q[4:0], fb};
    end
endmodule
`default_nettype wire
