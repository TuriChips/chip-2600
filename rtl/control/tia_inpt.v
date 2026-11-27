// tia_inpt: TIA input ports I0-I5.  Owner: Zura.  Spec: docs/spec.md 6.8, 6.2 (VBLANK bits), 5.
//
// vblank 3 = {D7, D6, D1} as tia_regs.  inpt 6: bit n = INPTn D7 value.
// I0-I3: inpt[n] = pin, forced to 0 while VBLANK D7 = 1 (dump).
// I4-I5: VBLANK D6 = 0: inpt[n] = pin and the latch is held at 1.
//        D6 = 1: latch, cleared by a 0 on the pin (sampled on clk), stays 0 until D6 = 0.
// rst = 1 (synchronous) sets the latches to 1.
module tia_inpt (
    input  wire       clk,
    input  wire       rst,
    input  wire [5:0] inpt_pin,
    input  wire [2:0] vblank,
    output wire [5:0] inpt
);
    wire d7 = vblank[2];
    wire d6 = vblank[1];
    wire unused_d1 = &{1'b0, vblank[0]};   // D1 (blank) is not used here

    reg [1:0] latch;   // bit 0 = I4, bit 1 = I5; 1 = not cleared

    always @(posedge clk) begin
        if (rst || !d6) latch <= 2'b11;
        else            latch <= latch & inpt_pin[5:4];
    end

    assign inpt[3:0] = d7 ? 4'b0000 : inpt_pin[3:0];
    assign inpt[5:4] = d6 ? latch : inpt_pin[5:4];
endmodule
