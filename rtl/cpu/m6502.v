// CHIP-2600 COPY of chip-6502's m6502 (TuriChips/chip-6502 at 5c06fdc, rtl/top.v + rtl/control/ + rtl/datapath/),
// spec D3 and D6 option (a) (docs/spec.md, chip-2600#2). Differences from the chip-6502 source, and only these:
//   D3  new input `ce` on m6502 (after clk) and on m6502_timing, m6502_control, m6502_alu, m6502_regs. Every clocked
//       block's `always @(posedge clk) begin` became `always @(posedge clk) if (ce) begin`, so with ce = 0 every register
//       (reset included) and every bus output holds, and one ce = 1 clock is one CPU cycle. m6502 wires ce to those four.
//       With ce tied to 1 the logic is the same as chip-6502. Port lists otherwise as there.
//       Reset is gated too: res_n low takes effect only on a ce = 1 clock, so hold it across at least one ce pulse.
//   D6  m6502_decode.v: two entries added by hand (the generator gen_decode.py is not copied; this file is no longer
//       generator output): 8'h04 NOP zp (mode ZP read, no register/flag enables: 3 cycles) and 8'hAB LXA #imm (mode IMM,
//       aop 14 as LDA/LDX with a_we, x_we, f_we: A = X = imm, N/Z from imm, so imm = $00 gives A = X = 0, N = 0, Z = 1;
//       other operands are unspecified in the spec). No other undocumented opcode, `ok` is unused.
//   m6502_system.v and m6502_mem.v (test fixtures) are not copied; m6502_plan.v is unchanged.
// m6502: CPU top level. Pins per spec section 2, in that order. Wiring and the data muxes of blocks.md section 2.
// verilator lint_off DECLFILENAME
module m6502 (
    input  wire        clk,
    input  wire        ce,
    input  wire        res_n,
    output wire [15:0] a,
    input  wire [7:0]  d_in,
    output wire [7:0]  d_out,
    output wire        d_oe,
    output wire        rw,
    output wire        sync,
    input  wire        rdy,
    input  wire        irq_n,
    input  wire        nmi_n,
    input  wire        so_n
);
    wire        reset = ~res_n;                      // datapath reset, active high
    wire [2:0]  t;     wire go;  wire [3:0] rs;
    wire        cyc_rd, cyc_last;
    wire [2:0]  addr_sel, vec_sel, alu_b_sel, d_out_sel;
    wire [3:0]  ab_op;
    wire [1:0]  pc_op, s_op, alu_a_sel;
    wire [4:0]  alu_op;
    wire        a_we, f_we, pull_p, push_b, x_we, y_we, regs_din_tmp;
    wire [7:0]  tmp, a_out, p_push, result, x_out, y_out, s_out;
    wire [3:0]  flags;
    wire [15:0] pc;
    wire        ab_carry;

    m6502_timing u_timing (.clk(clk), .ce(ce), .res_n(res_n), .rdy(rdy), .cyc_rd(cyc_rd), .cyc_last(cyc_last),
                           .t(t), .go(go), .rs(rs));

    m6502_control u_control (
        .clk(clk), .ce(ce), .res_n(res_n), .t(t), .go(go), .rs(rs), .d_in(d_in), .flags(flags), .p_i(p_push[2]),
        .ab_carry(ab_carry), .pcl(pc[7:0]), .irq_n(irq_n), .nmi_n(nmi_n), .so_n(so_n),
        .rw(rw), .d_oe(d_oe), .sync(sync), .cyc_rd(cyc_rd), .cyc_last(cyc_last),
        .addr_sel(addr_sel), .vec_sel(vec_sel), .ab_op(ab_op), .pc_op(pc_op), .s_op(s_op),
        .alu_op(alu_op), .alu_a_sel(alu_a_sel), .alu_b_sel(alu_b_sel), .a_we(a_we), .f_we(f_we),
        .pull_p(pull_p), .push_b(push_b), .x_we(x_we), .y_we(y_we), .d_out_sel(d_out_sel),
        .regs_din_tmp(regs_din_tmp), .tmp(tmp)
    );

    // ALU operands (blocks.md section 2): a_in 0 A, 1 X, 2 Y; b 0 d_in, 1 TMP, 2 X, 3 Y, 4 S, 5 A
    wire [7:0] alu_a_in = (alu_a_sel == 2'd1) ? x_out : (alu_a_sel == 2'd2) ? y_out : a_out;
    wire [7:0] alu_b = (alu_b_sel == 3'd1) ? tmp : (alu_b_sel == 3'd2) ? x_out : (alu_b_sel == 3'd3) ? y_out :
                       (alu_b_sel == 3'd4) ? s_out : (alu_b_sel == 3'd5) ? a_out : d_in;

    m6502_alu u_alu (
        .clk(clk), .ce(ce), .reset(reset), .op(alu_op), .a_in(alu_a_in), .b(alu_b), .a_we(a_we), .f_we(f_we),
        .pull_p(pull_p), .push_b(push_b), .a_out(a_out), .p_push(p_push), .flags(flags), .result(result)
    );

    m6502_regs u_regs (
        .clk(clk), .ce(ce), .reset(reset), .d_in(regs_din_tmp ? tmp : d_in), .wdata(result), .x_we(x_we), .y_we(y_we),
        .ab_op(ab_op), .pc_op(pc_op), .s_op(s_op), .addr_sel(addr_sel), .vec_sel(vec_sel),
        .addr(a), .ab_carry(ab_carry), .x_out(x_out), .y_out(y_out), .s_out(s_out), .pc(pc)
    );

    // d_out (blocks.md section 2): 0 A, 1 X, 2 Y, 3 P as pushed, 4 PCH, 5 PCL, 6 TMP, 7 ALU result
    assign d_out = (d_out_sel == 3'd0) ? a_out : (d_out_sel == 3'd1) ? x_out : (d_out_sel == 3'd2) ? y_out :
                   (d_out_sel == 3'd3) ? p_push : (d_out_sel == 3'd4) ? pc[15:8] : (d_out_sel == 3'd5) ? pc[7:0] :
                   (d_out_sel == 3'd6) ? tmp : result;
endmodule
