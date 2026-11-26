// Directed tests for the chip-2600 core copy (spec D3, D6): opcode $04 (NOP zp, 3 cycles, nothing changes),
// opcode $AB with operand $00 (A = X = 0, N = 0, Z = 1, 2 cycles), and ce = 0 hold.
// Expected values come from spec D3/D6, not from the RTL.
// Two copies run the same program: A with ce = 1 on every clock, B with ce gated. Per ce pulse B must show exactly A's
// outputs; on every ce = 0 clock B's outputs must not change.
`timescale 1ns/1ps
module tb_d6;
  reg clk = 0, res_n = 0, ceb = 0;
  reg [7:0] mema [0:65535]; reg [7:0] memb [0:65535];
  wire [15:0] aa, ab; wire [7:0] da, db; wire oea, oeb, rwa, rwb, sya, syb;
  m6502 A (.clk(clk), .ce(1'b1), .res_n(res_n), .a(aa), .d_in(mema[aa]), .d_out(da), .d_oe(oea), .rw(rwa), .sync(sya), .rdy(1'b1), .irq_n(1'b1), .nmi_n(1'b1), .so_n(1'b1));
  m6502 B (.clk(clk), .ce(ceb),  .res_n(res_n), .a(ab), .d_in(memb[ab]), .d_out(db), .d_oe(oeb), .rw(rwb), .sync(syb), .rdy(1'b1), .irq_n(1'b1), .nmi_n(1'b1), .so_n(1'b1));
  always #5 clk = ~clk;
  always @(posedge clk) begin
    if (!rwa) mema[aa] <= da;
    if (ceb && !rwb) memb[ab] <= db;
  end
  // trace of A, one entry per clock after reset release
  reg [15:0] ta [0:4095]; reg tr [0:4095]; reg ts [0:4095]; reg [7:0] td [0:4095];
  integer na = 0, nb = 0, errs = 0, i, k;
  integer sync_a [0:255]; integer nsync = 0;
  // program (A and B share it)
  task load(input [15:0] at, input [7:0] v); begin mema[at] = v; memb[at] = v; end endtask
  integer p;
  task emit(input [7:0] v); begin load(p[15:0], v); p = p + 1; end endtask
  task chk(input string name, input integer got, input integer exp);
    if (got !== exp) begin errs = errs + 1; $display("FAIL %0s: got %0h expected %0h", name, got, exp); end
    else $display("ok   %0s = %0h", name, got);
  endtask
  reg [15:0] pa_prev; reg [7:0] pd_prev; reg prw, psy, poe;
  integer seed = 7, gap;
  initial begin
    for (i = 0; i < 65536; i = i + 1) begin mema[i] = 8'h00; memb[i] = 8'h00; end
    load(16'hFFFC, 8'h00); load(16'hFFFD, 8'h02);
    p = 16'h0200;
    // --- $04 block: N=1 (LDA #$80), X=$77, Y=$33, C=1, then NOP zp
    emit(8'hA2); emit(8'h77); emit(8'hA0); emit(8'h33); emit(8'h38); emit(8'hA9); emit(8'h80);
    load(16'h0210, 8'h5A);
    emit(8'h04); emit(8'h10);                       // $04 $10, at $0207
    emit(8'h8D); emit(8'h00); emit(8'h03);          // STA $0300
    emit(8'h8E); emit(8'h01); emit(8'h03);          // STX $0301
    emit(8'h8C); emit(8'h02); emit(8'h03);          // STY $0302
    emit(8'h08); emit(8'h68); emit(8'h8D); emit(8'h03); emit(8'h03); // PHP PLA STA $0303
    // --- $AB #0 block: A=$FF (N=1), X=$FF, Y=$44, C=1
    emit(8'hA2); emit(8'hFF); emit(8'hA0); emit(8'h44); emit(8'h38); emit(8'hA9); emit(8'hFF);
    emit(8'hAB); emit(8'h00);                       // LXA #0
    emit(8'h8D); emit(8'h10); emit(8'h03);          // STA $0310
    emit(8'h8E); emit(8'h11); emit(8'h03);          // STX $0311
    emit(8'h8C); emit(8'h12); emit(8'h03);          // STY $0312
    emit(8'h08); emit(8'h68); emit(8'h8D); emit(8'h13); emit(8'h03); // PHP PLA STA $0313
    emit(8'h4C); emit(p[7:0]); emit(p[15:8]);       // JMP * (done)
    // --- run A, ce = 1 every clock: reset 12 cycles, then 150 cycles
    res_n = 0; repeat (12) @(posedge clk); #1 res_n = 1;
    // A and B are released together; B needs 12 ce pulses in reset first, so both are held for the same count of ce pulses
    // (B's ce is off during this phase and gated below)
    // trace A
    for (k = 0; k < 150; k = k + 1) begin @(posedge clk); #1; ta[k] = aa; tr[k] = rwa; ts[k] = sya; td[k] = da; end
    // A results
    chk("A $04: STA $0300 (A unchanged = $80)", mema[16'h0300], 8'h80);
    chk("A $04: STX $0301 (X unchanged = $77)", mema[16'h0301], 8'h77);
    chk("A $04: STY $0302 (Y unchanged = $33)", mema[16'h0302], 8'h33);
    chk("A $04: P unchanged (N=1,I=1,C=1,bit5,B from PHP = $B5)", mema[16'h0303], 8'hB5);
    chk("A $AB #0: A = 0", mema[16'h0310], 8'h00);
    chk("A $AB #0: X = 0", mema[16'h0311], 8'h00);
    chk("A $AB #0: Y unchanged = $44", mema[16'h0312], 8'h44);
    chk("A $AB #0: P: N=0, Z=1, I=1, C=1 (PHP = $37)", mema[16'h0313], 8'h37);
    // cycle counts: sync pulses (opcode fetches) from the trace; $04 at $0207 -> next fetch at $0209 three clocks later;
    // $AB at its address -> next fetch two clocks later
    begin : cyc
      integer t04, t8d, tab, t8e;
      t04 = -1; t8d = -1; tab = -1; t8e = -1;
      for (k = 0; k < 150; k = k + 1) if (ts[k] && tr[k]) begin
        if (ta[k] == 16'h0207) t04 = k;
        if (ta[k] == 16'h0209 && t04 >= 0 && t8d < 0) t8d = k;
        if (ta[k] == 16'h0222 - 16'h0000 + 16'h0000 && 0) tab = k;
      end
      chk("$04 takes 3 cycles (next opcode fetch 3 clocks after its fetch)", t8d - t04, 3);
      begin : rd
        integer seen; seen = 0;
        for (k = t04; k < t8d; k = k + 1) if (ta[k] == 16'h0010 && tr[k]) seen = seen + 1;
        chk("$04 reads its zero-page address ($0010) once", seen, 1);
      end
    end
    begin : cab
      integer tab, tnext, kk, ab_addr;
      ab_addr = 16'h0200 + 7 + 2 + 3 + 3 + 3 + 1 + 1 + 3 + 7;   // address of $AB
      tab = -1; tnext = -1;
      for (kk = 0; kk < 150; kk = kk + 1) if (ts[kk] && tr[kk]) begin
        if (ta[kk] == ab_addr) tab = kk;
        if (ta[kk] == ab_addr + 2 && tab >= 0 && tnext < 0) tnext = kk;
      end
      chk("$AB #0 takes 2 cycles", tnext - tab, 2);
    end
    // --- B: reset for 12 ce pulses, then run with irregular ce gaps; compare with A's trace per ce pulse
    @(negedge clk); res_n = 0; ceb = 0;
    @(posedge clk); #1;
    // restore B's memory (same image, A's writes irrelevant): B memory starts from its own copy of the program
    repeat (3) @(posedge clk);
    nb = 0; ceb = 1; repeat (12) @(posedge clk); #1 res_n = 1;
    pa_prev = ab; pd_prev = db; prw = rwb; psy = syb; poe = oeb;
    for (k = 0; k < 150; k = k + 1) begin
      gap = ($random(seed) & 7);   // 0..7 idle clocks before each ce pulse (0 = back to back)
      ceb = 0;
      repeat (gap) begin
        @(posedge clk); #1;
        if (ab !== pa_prev || db !== pd_prev || rwb !== prw || syb !== psy || oeb !== poe) begin
          errs = errs + 1; if (errs < 20) $display("FAIL ce=0 hold: outputs changed at pulse %0d", k);
        end
      end
      ceb = 1; @(posedge clk); #1;
      pa_prev = ab; pd_prev = db; prw = rwb; psy = syb; poe = oeb;
      if (ab !== ta[k] || rwb !== tr[k] || syb !== ts[k] || (!tr[k] && db !== td[k])) begin
        errs = errs + 1; if (errs < 20) $display("FAIL ce pulse %0d: B a=%04h rw=%b sync=%b d=%02h, A a=%04h rw=%b sync=%b d=%02h", k, ab, rwb, syb, db, ta[k], tr[k], ts[k], td[k]);
      end
    end
    ceb = 0;
    // extra long hold: 300 clocks with ce = 0, nothing may change
    begin : longhold
      integer x0;
      x0 = errs;
      repeat (300) begin @(posedge clk); #1; if (ab !== pa_prev || db !== pd_prev || rwb !== prw || syb !== psy) errs = errs + 1; end
      chk("ce=0 for 300 clocks leaves all bus outputs unchanged", errs - x0, 0);
    end
    chk("B (ce gated) STA $0300", memb[16'h0300], 8'h80);
    chk("B (ce gated) $04 P unchanged", memb[16'h0303], 8'hB5);
    chk("B (ce gated) $AB A = 0", memb[16'h0310], 8'h00);
    chk("B (ce gated) $AB P = $37", memb[16'h0313], 8'h37);
    $display("errors: %0d", errs);
    if (errs == 0) $display("PASS"); else $display("FAIL: %0d errors", errs);
    $finish;
  end
endmodule
