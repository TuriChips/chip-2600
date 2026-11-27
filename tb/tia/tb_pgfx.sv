// Testbench T5 (player graphics): tia_pgfx plus the tia_regs vertical-delay copy. Spec: docs/spec.md 6.5 (Players, Vertical delay).
// Port contract (chip-2600#37 gives behaviour, not names; names as in Beru's tests/random/tb_tia_pgfx.sv, #39):
//   clk rst step start grp_new[7:0] grp_old[7:0] vdel refl nusiz[2:0] -> gfx (names per tia_pgfx header).  nusiz = NUSIZ D2-D0.
// Timing convention (same as tb_pf): after a clk edge with start=1 the output shows bit 0 (D7, or D0 when refp=1);
// a bit lasts `w` clk edges with step=1 (w = 2 for 101, 4 for 111, else 1); the step after the last clock of bit 7 gives 0.
// Not tested (spec [check], turichips#48): when a copy starts, the stretched-mode +1 delay, start+step on the same edge,
// what a mid-scan change of GRP/VDEL/REFP/NUSIZ does.
// Expected values come from the spec only. The end-to-end part writes GRP0/GRP1/VDELPx/NUSIZx/REFPx through tia_regs
// and checks the scanned bits against a model of the spec's copy rule kept here, not the regs outputs.
`timescale 1ns/1ps
module tb_pgfx;
  logic clk = 0, rst = 0, step = 0, start = 0, vdel = 0, refp = 0;
  logic [7:0] gn = 0, go = 0; logic [2:0] nz = 0;
  wire pg;
  tia_pgfx dut (.clk(clk), .rst(rst), .step(step), .start(start), .grp_new(gn), .grp_old(go), .vdel(vdel), .refl(refp), .nusiz(nz), .gfx(pg));
  // second pair for the end-to-end part: P0 and P1 fed from tia_regs
  logic wr = 0, rrst = 0; logic [5:0] a = 0; logic [7:0] d = 0;
  wire [4:0] nusiz0, nusiz1; wire refp0, refp1, vdelp0, vdelp1;
  wire [7:0] g0n, g0o, g1n, g1o;
  tia_regs regs (.clk(clk), .rst(rrst), .wr(wr), .a(a), .d(d), .nusiz0(nusiz0), .nusiz1(nusiz1), .refp0(refp0), .refp1(refp1),
    .grp0_new(g0n), .grp0_old(g0o), .grp1_new(g1n), .grp1_old(g1o), .vdelp0(vdelp0), .vdelp1(vdelp1),
    .vsync(), .vblank(), .colup0(), .colup1(), .colupf(), .colubk(), .ctrlpf(), .pf0(), .pf1(), .pf2(), .audc0(), .audc1(),
    .audf0(), .audf1(), .audv0(), .audv1(), .enam0(), .enam1(), .enabl_new(), .enabl_old(), .hmp0(), .hmp1(), .hmm0(), .hmm1(),
    .hmbl(), .vdelbl(), .resmp0(), .resmp1(), .wsync_s(), .rsync_s(), .resp0_s(), .resp1_s(), .resm0_s(), .resm1_s(),
    .resbl_s(), .hmove_s(), .hmclr_s(), .cxclr_s());
  logic step_e = 0, start_e = 0; wire pe0, pe1;
  tia_pgfx p0 (.clk(clk), .rst(rrst), .step(step_e), .start(start_e), .grp_new(g0n), .grp_old(g0o), .vdel(vdelp0), .refl(refp0), .nusiz(nusiz0[2:0]), .gfx(pe0));
  tia_pgfx p1 (.clk(clk), .rst(rrst), .step(step_e), .start(start_e), .grp_new(g1n), .grp_old(g1o), .vdel(vdelp1), .refl(refp1), .nusiz(nusiz1[2:0]), .gfx(pe1));
  always #5 clk = ~clk;
  int errs = 0, nchk = 0;
  task automatic chk(input string name, input logic [31:0] got, input logic [31:0] exp);
    nchk++;
    if (got !== exp) begin errs++; $display("FAIL %s: got 0x%0h expected 0x%0h", name, got, exp); end
  endtask
  task automatic tick(input logic s, input logic st, input logic rs);
    @(negedge clk); step = s; start = st; rst = rs; @(posedge clk); #1; step = 0; start = 0; rst = 0;
  endtask
  function automatic int width(input logic [2:0] n); return n == 3'b101 ? 2 : n == 3'b111 ? 4 : 1; endfunction
  function automatic logic ebit(input logic [7:0] g, input logic r, input int k); return r ? g[k] : g[7-k]; endfunction
  // one full scan: start, then 8*w clocks compared, then the step after the end must give 0 and stay 0
  task automatic scan(input string tag, input logic [2:0] n, input logic r, input logic v, input logic [7:0] g_new, input logic [7:0] g_old);
    int w; logic [7:0] g;
    w = width(n); nz = n; refp = r; vdel = v; gn = g_new; go = g_old; g = v ? g_old : g_new;
    tick(0, 1, 0);
    for (int c = 0; c < 8 * w; c++) begin
      chk($sformatf("T5 %s nusiz=%0b refp=%0d vdel=%0d clk %0d (bit %0d)", tag, n, r, v, c, c / w), pg, ebit(g, r, c / w));
      tick(1, 0, 0);
    end
    chk($sformatf("T5 %s nusiz=%0b refp=%0d vdel=%0d output 0 after the 8th bit", tag, n, r, v), pg, 0);
    repeat (3) tick(1, 0, 0);
    chk($sformatf("T5 %s nusiz=%0b output stays 0 after the scan", tag, n), pg, 0);
  endtask

  // ---- end-to-end helpers
  task automatic wrreg(input logic [5:0] ad, input logic [7:0] dat);
    @(negedge clk); wr = 1; a = ad; d = dat; @(posedge clk); #1; wr = 0;
  endtask
  // scan both regs-fed players at once; expected graphics given by the caller
  task automatic scan2(input string tag, input logic [7:0] e0, input logic [7:0] e1, input logic [2:0] n0, input logic [2:0] n1, input logic r0, input logic r1);
    int w0, w1, c;
    w0 = width(n0); w1 = width(n1);
    @(negedge clk); start_e = 1; @(posedge clk); #1; start_e = 0;
    for (c = 0; c < 8 * 4; c++) begin
      if (c < 8 * w0) chk($sformatf("T5 e2e %s P0 clk %0d", tag, c), pe0, ebit(e0, r0, c / w0));
      if (c < 8 * w1) chk($sformatf("T5 e2e %s P1 clk %0d", tag, c), pe1, ebit(e1, r1, c / w1));
      @(negedge clk); step_e = 1; @(posedge clk); #1; step_e = 0;
    end
    chk($sformatf("T5 e2e %s P0 ends at 0", tag), pe0, 0);
    chk($sformatf("T5 e2e %s P1 ends at 0", tag), pe1, 0);
  endtask

  logic [7:0] ra, rb;
  logic [7:0] m_g0n, m_g0o, m_g1n, m_g1o;   // model of the spec's copy rule
  initial begin
    tick(0, 0, 1);
    // output 0 outside a scan: after reset, before any start, with graphics all ones
    nz = 0; refp = 0; vdel = 0; gn = 8'hff; go = 8'hff;
    chk("T5 output 0 after rst", pg, 0);
    repeat (5) tick(1, 0, 0);
    chk("T5 output 0 with steps but no start (GRP = $FF)", pg, 0);
    // every NUSIZ code (1/2/4 clocks per bit), both bit orders, new register: each bit alone, all ones, all zeros
    for (int n = 0; n < 8; n++) for (int r = 0; r < 2; r++) begin
      for (int b = 0; b < 8; b++) scan($sformatf("bit %0d", b), n[2:0], r[0], 0, 8'h01 << b, ~(8'h01 << b));
      scan("all ones", n[2:0], r[0], 0, 8'hff, 8'h00);
      scan("all zeros", n[2:0], r[0], 0, 8'h00, 8'hff);
    end
    // VDEL: old register when vdel=1, new when 0, with different patterns
    for (int n = 0; n < 8; n++) for (int r = 0; r < 2; r++) for (int v = 0; v < 2; v++)
      for (int b = 0; b < 8; b++) scan($sformatf("vdel walking %0d", b), n[2:0], r[0], v[0], 8'h01 << b, 8'h80 >> b);
    for (int n = 0; n < 200; n++) scan($sformatf("random %0d", n), $urandom % 8, $urandom % 2, $urandom % 2, $urandom, $urandom);
    // step = 0 holds
    nz = 3'b000; refp = 0; vdel = 0; gn = 8'h80; go = 0;
    tick(0, 1, 0); chk("T5 hold: bit 0 = D7", pg, 1);
    repeat (7) tick(0, 0, 0); chk("T5 hold: 7 clk without step stay on bit 0", pg, 1);
    tick(1, 0, 0); chk("T5 hold: one step leaves bit 0", pg, 0);
    nz = 3'b111; gn = 8'hc0; tick(0, 1, 0);
    chk("T5 hold x4: bit 0", pg, 1); repeat (3) tick(1, 0, 0); chk("T5 hold x4: clk 3 still bit 0", pg, 1);
    repeat (3) tick(0, 0, 0); chk("T5 hold x4: no step, still bit 0", pg, 1);
    tick(1, 0, 0); chk("T5 hold x4: 4th step moves to bit 1 (D6 = 1)", pg, 1);
    repeat (3) tick(1, 0, 0); chk("T5 hold x4: clk 7 still bit 1", pg, 1);
    tick(1, 0, 0); chk("T5 hold x4: bit 2 (D5 = 0)", pg, 0);
    // restart on a new start, mid-bit and mid-scan, each width
    for (int n = 0; n < 3; n++) begin
      logic [2:0] c; c = (n == 0) ? 3'b000 : (n == 1) ? 3'b101 : 3'b111;
      nz = c; refp = 0; vdel = 0; gn = 8'h81; go = 0;
      tick(0, 1, 0); repeat (3 * width(c) + 1) tick(1, 0, 0);   // inside bit 3 (D4 = 0), mid-bit for wide modes
      chk($sformatf("T5 restart nusiz=%0b: inside bit 3 reads 0", c), pg, 0);
      tick(0, 1, 0); chk($sformatf("T5 restart nusiz=%0b: start returns to bit 0", c), pg, 1);
      repeat (width(c) - 1) tick(1, 0, 0); chk($sformatf("T5 restart nusiz=%0b: bit 0 lasts a full width after the restart", c), pg, 1);
      tick(1, 0, 0); chk($sformatf("T5 restart nusiz=%0b: next bit (D6 = 0)", c), pg, 0);
      repeat (7 * width(c) - 1) tick(1, 0, 0); chk($sformatf("T5 restart nusiz=%0b: last clock of bit 7 (D0 = 1)", c), pg, 1);
      tick(1, 0, 0); chk($sformatf("T5 restart nusiz=%0b: scan ends", c), pg, 0);
      tick(0, 1, 0); chk($sformatf("T5 restart nusiz=%0b: start after the end draws again", c), pg, 1);
    end
    // start in the middle of the last bit
    nz = 0; gn = 8'h01; tick(0, 1, 0); repeat (7) tick(1, 0, 0); chk("T5 restart: bit 7 reads D0 = 1", pg, 1);
    tick(0, 1, 0); chk("T5 restart from the last bit: back to bit 0 (D7 = 0)", pg, 0);
    repeat (7) tick(1, 0, 0); chk("T5 restart from the last bit: scan reaches bit 7 again", pg, 1);
    // rst stops a scan
    nz = 0; gn = 8'hff; tick(0, 1, 0); repeat (2) tick(1, 0, 0); chk("T5 pre-rst: drawing", pg, 1);
    tick(0, 0, 1); chk("T5 rst stops the scan", pg, 0);
    tick(1, 0, 0); chk("T5 step after rst does not draw", pg, 0);

    // ---- end to end through tia_regs: GRP0/GRP1 write order and the vertical-delay copy
    rrst = 1; @(posedge clk); #1; rrst = 0;
    m_g0n = 0; m_g0o = 0; m_g1n = 0; m_g1o = 0;
    // spec 6.5: writing GRP0 copies P1 new to P1 old; writing GRP1 copies P0 new to P0 old
    // (sequence chosen so that new and old differ for both players at the end)
    wrreg(6'h1C, 8'h3c); m_g0o = m_g0n; m_g1n = 8'h3c;                    // GRP1 = $3C
    wrreg(6'h1B, 8'ha5); m_g1o = m_g1n; m_g0n = 8'ha5;                    // GRP0 = $A5
    wrreg(6'h1C, 8'h0f); m_g0o = m_g0n; m_g1n = 8'h0f;                    // GRP1 = $0F
    wrreg(6'h1B, 8'h96); m_g1o = m_g1n; m_g0n = 8'h96;                    // GRP0 = $96
    // now P0 new=$96 old=$A5, P1 new=$0F old=$0F. One more GRP1 write makes P1 new differ from old.
    wrreg(6'h1C, 8'hd2); m_g0o = m_g0n; m_g1n = 8'hd2;                    // GRP1 = $D2: P0 old = $96, P1 new=$D2, old=$0F
    for (int v0 = 0; v0 < 2; v0++) for (int v1 = 0; v1 < 2; v1++) begin
      wrreg(6'h25, {7'b0, v0[0]}); wrreg(6'h26, {7'b0, v1[0]});
      scan2($sformatf("VDELP0=%0d VDELP1=%0d", v0, v1), v0 ? m_g0o : m_g0n, v1 ? m_g1o : m_g1n, 0, 0, 0, 0);
    end
    // VDELBL must not change the players
    wrreg(6'h25, 8'h00); wrreg(6'h26, 8'h00); wrreg(6'h27, 8'h01);
    scan2("VDELBL=1 leaves players on new", m_g0n, m_g1n, 0, 0, 0, 0);
    wrreg(6'h27, 8'h00);
    // a GRP0 write alone does not touch P0 old
    wrreg(6'h25, 8'h01); wrreg(6'h1B, 8'h18); wrreg(6'h1B, 8'h24); m_g1o = m_g1n; m_g0n = 8'h24;   // two GRP0 writes: P1 old := P1 new ($D2), P0 old stays $96
    wrreg(6'h26, 8'h01);
    scan2("after GRP0 alone: P0 old unchanged, P1 old = P1 new", m_g0o, m_g1o, 0, 0, 0, 0);
    // REFP and NUSIZ come through tia_regs: D3 of REFPx, D2-D0 of NUSIZx (D5-D4 must not change the player width)
    wrreg(6'h25, 8'h00); wrreg(6'h26, 8'h00);
    wrreg(6'h0B, 8'h08); wrreg(6'h0C, 8'h00); wrreg(6'h04, 8'h35); wrreg(6'h05, 8'h37);   // P0 refp=1, 101 (+D5,D4=11), P1 111 (+D5,D4=11)
    scan2("REFP0=1 NUSIZ0=$35 NUSIZ1=$37", m_g0n, m_g1n, 3'b101, 3'b111, 1, 0);
    wrreg(6'h0B, 8'h00); wrreg(6'h0C, 8'h08); wrreg(6'h04, 8'h30); wrreg(6'h05, 8'h02);
    scan2("REFP1=1 NUSIZ0=$30 (D2-D0=0, D5-D4 set) NUSIZ1=$02", m_g0n, m_g1n, 3'b000, 3'b010, 0, 1);
    wrreg(6'h0B, 8'hf7); wrreg(6'h0C, 8'hf7);   // D3 = 0: refp off even with other bits set
    scan2("REFP bits other than D3 ignored", m_g0n, m_g1n, 3'b010, 3'b010, 0, 0);
    if (errs == 0) $display("PASS (%0d checks)", nchk); else $display("FAIL: %0d of %0d checks", errs, nchk);
    $finish;
  end
endmodule
