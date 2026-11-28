// Testbench T10 (object position counter): tia_objpos. Spec: docs/spec.md 4.1 (counter), 6.5 (decode matrices, NUSIZ table).
// Ports: clk rst step res nusiz[2:0] -> q[5:0] (q[0]=Q1) start_main start_copy.
// Expected values come from the spec only: the counter sequence is generated here from the 4.1 rule (new Q1 = XNOR(Q5,Q6)),
// the decode states from the 6.5 matrix, the copy enables from the 6.5 NUSIZ table (offsets +16/+32/+64 -> counts 3/7/15).
// ERR (111111) is not reachable from 000000 by stepping, so the bench deposits it into dut.u_cnt.q (as tb_tia_objpos does).
// Out of scope (spec 10 [check], turichips#48): +4/+5 landing delay, stretched +1, "one count later" start, HMOVE, RESMP.
`timescale 1ns/1ps
module tb_objpos;
  logic clk = 0, rst = 0, step = 0, res = 0; logic [2:0] nusiz = 0;
  wire [5:0] q; wire sm, sc;
  tia_objpos dut (.clk(clk), .rst(rst), .step(step), .res(res), .nusiz(nusiz), .q(q), .start_main(sm), .start_copy(sc));
  always #5 clk = ~clk;
  int errs = 0, nchk = 0;
  logic [5:0] seq [0:39];
  // spec 6.5 table, written independently of the RTL: offset list per NUSIZ code, as colour clocks
  function automatic logic copy_at(input logic [2:0] n, input int cnt);
    int off; off = 4 * (cnt + 1);              // 6.5: copy at count c starts at 4*(c+1) colour clocks after the main copy
    case (n)
      3'b001: return off == 16;
      3'b010: return off == 32;
      3'b011: return off == 16 || off == 32;
      3'b100: return off == 64;
      3'b110: return off == 32 || off == 64;
      default: return 0;                        // 000, 101, 111: none
    endcase
  endfunction
  task automatic chk(input string name, input logic [5:0] eq, input logic esm, input logic esc);
    nchk++;
    if (q !== eq || sm !== esm || sc !== esc) begin
      errs++; $display("FAIL %s: q=%b sm=%b sc=%b expected q=%b sm=%b sc=%b", name, q, sm, sc, eq, esm, esc);
    end
  endtask
  // one clock with given inputs, sample after the edge
  task automatic tick(input logic r, s, rs);
    rst = r; step = s; res = rs; @(posedge clk); #1; rst = 0; step = 0; res = 0;
  endtask
  task automatic clear(); tick(1, 0, 0); endtask
  task automatic goto_count(input int n); clear(); for (int i = 0; i < n; i++) tick(0, 1, 0); endtask

  initial begin
    // sequence from the 4.1 rule
    seq[0] = 6'b000000;
    for (int i = 1; i < 40; i++) seq[i] = {seq[i-1][4:0], ~(seq[i-1][4] ^ seq[i-1][5])};
    // spec 6.5 decode states, hard-coded as a cross-check of the generated sequence (Q1..Q6 as q[0..5])
    // Q1..Q6 = 101101 -> q = 6'b101101 reversed
    if (seq[3] !== 6'b000111 || seq[7] !== 6'b111101 || seq[15] !== 6'b100111 || seq[39] !== 6'b101101) begin
      $display("FAIL bench-seq: generated states at 3/7/15/39 differ from the 6.5 matrix"); errs++;
    end
    // (the matrix lists Q1..Q6; q[0]=Q1 so the literal is the reverse; verified below by the decode checks on the DUT)
    @(negedge clk); clear();
    chk("after rst", 6'b0, 0, 0);

    // A: full sequence, 3 periods, every NUSIZ code at every count: q, start_main, start_copy
    for (int n = 0; n < 8; n++) begin
      nusiz = n[2:0]; clear();
      for (int p = 0; p < 3; p++) for (int c = 0; c < 40; c++) begin
        chk($sformatf("seq nusiz=%b period=%0d count=%0d", nusiz, p, c), seq[c], c == 39, copy_at(nusiz, c));
        tick(0, 1, 0);
      end
      chk($sformatf("after 120 steps nusiz=%b", nusiz), 6'b0, 0, 0);
    end
    // the matrix rows by label (Q1..Q6 string order): state 101101 at 39, copies at 3/7/15
    nusiz = 3'b011; goto_count(3);  chk("count 3 = Q1..Q6 111000 (+16), nusiz 011", {1'b0,1'b0,1'b0,1'b1,1'b1,1'b1}, 0, 1);
    nusiz = 3'b011; goto_count(7);  chk("count 7 = Q1..Q6 101111 (+32), nusiz 011", {1'b1,1'b1,1'b1,1'b1,1'b0,1'b1}, 0, 1);
    nusiz = 3'b110; goto_count(15); chk("count 15 = Q1..Q6 111001 (+64), nusiz 110", {1'b1,1'b0,1'b0,1'b1,1'b1,1'b1}, 0, 1);
    nusiz = 3'b000; goto_count(39); chk("count 39 = Q1..Q6 101101, nusiz 000", {1'b1,1'b0,1'b1,1'b1,1'b0,1'b1}, 1, 0);

    // B: no start at the neighbours of each decode state is covered by A; period exactly 40 from 000000
    nusiz = 0; clear();
    for (int i = 0; i < 40; i++) begin tick(0, 1, 0); if (i < 39 && q === 6'b0) begin errs++; $display("FAIL period: back at 000000 after %0d steps", i+1); end end
    chk("period 40", 6'b0, 0, 0);

    // C: step = 0 holds, in every state of the period, for 3 clocks, with every nusiz
    for (int c = 0; c < 40; c++) begin
      nusiz = c[2:0]; goto_count(c);
      for (int k = 0; k < 3; k++) begin tick(0, 0, 0); chk($sformatf("hold count=%0d clk=%0d", c, k), seq[c], c == 39, copy_at(nusiz, c)); end
    end

    // D: res clears that clock and wins over step; from every state
    for (int c = 0; c < 40; c++) begin
      nusiz = 3'b011; goto_count(c); tick(0, 0, 1); chk($sformatf("res step=0 count=%0d", c), 6'b0, 0, 0);
      goto_count(c);                 tick(0, 1, 1); chk($sformatf("res step=1 count=%0d", c), 6'b0, 0, 0);
      tick(0, 1, 0); chk($sformatf("step after res count=%0d", c), seq[1], 0, 0);   // counting resumes from 000000
    end

    // E: rst clears, from every state, with and without step
    for (int c = 0; c < 40; c++) begin
      goto_count(c); tick(1, 0, 0); chk($sformatf("rst count=%0d", c), 6'b0, 0, 0);
      goto_count(c); tick(1, 1, 0); chk($sformatf("rst+step count=%0d", c), 6'b0, 0, 0);
      goto_count(c); tick(1, 1, 1); chk($sformatf("rst+step+res count=%0d", c), 6'b0, 0, 0);
    end

    // F: ERR 111111 -> 000000 on the next step; no starts in ERR; step=0 holds ERR; res/rst clear it
    for (int n = 0; n < 8; n++) begin
      nusiz = n[2:0];
      clear(); @(negedge clk); dut.u_cnt.q = 6'b111111; #1;
      chk($sformatf("ERR forced nusiz=%b", nusiz), 6'b111111, 0, 0);
      tick(0, 0, 0); chk($sformatf("ERR holds nusiz=%b", nusiz), 6'b111111, 0, 0);
      tick(0, 1, 0); chk($sformatf("ERR step nusiz=%b", nusiz), 6'b0, 0, 0);
      tick(0, 1, 0); chk($sformatf("ERR then step nusiz=%b", nusiz), seq[1], 0, 0);
    end
    @(negedge clk); dut.u_cnt.q = 6'b111111; #1; tick(0, 0, 1); chk("ERR res", 6'b0, 0, 0);
    @(negedge clk); dut.u_cnt.q = 6'b111111; #1; tick(1, 0, 0); chk("ERR rst", 6'b0, 0, 0);
    @(negedge clk); dut.u_cnt.q = 6'b111111; #1; tick(0, 1, 1); chk("ERR step+res", 6'b0, 0, 0);

    if (errs == 0) $display("PASS tb_objpos (%0d checks)", nchk); else $display("FAIL: %0d of %0d checks", errs, nchk);
    $finish;
  end
endmodule
