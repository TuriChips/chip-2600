// Testbench T4 (static part): tia_pf. Spec: docs/spec.md 6.4; port contract in chip-2600#27.
// Bit list, index 0..19: PF0 D4, D5, D6, D7, PF1 D7..D0, PF2 D0..D7. pf0[3:0] = D7..D4 (as tia_regs), so PF0 D4 = pf0[0].
// Left half, or right half with ref=0: index i reads list[i]. Right half with ref=1: list[19-i].
// Mid-line write timing is [check] (turichips#48): only "a write shows from the next index" is tested.
`timescale 1ns/1ps
module tb_pf;
  logic clk = 0, rst = 0, step = 0, start = 0, right = 0, ref_ = 0;
  logic [3:0] pf0 = 0; logic [7:0] pf1 = 0, pf2 = 0;
  wire pf;
  tia_pf dut (.clk(clk), .rst(rst), .step(step), .start(start), .right(right), .pf_ref(ref_), .pf0(pf0), .pf1(pf1), .pf2(pf2), .pf(pf));
  always #5 clk = ~clk;
  int errs = 0, nchk = 0;
  task automatic chk(input string name, input logic [31:0] got, input logic [31:0] exp);
    nchk++;
    if (got !== exp) begin errs++; $display("FAIL %s: got 0x%0h expected 0x%0h", name, got, exp); end
  endtask
  // list position k -> value from a 20-bit register image {pf2,pf1,pf0}
  function automatic logic lst(input logic [3:0] a, input logic [7:0] b, input logic [7:0] c, input int k);
    if (k < 4) return a[k]; else if (k < 12) return b[11-k]; else return c[k-12];
  endfunction
  function automatic logic expect_bit(input logic [3:0] a, input logic [7:0] b, input logic [7:0] c, input logic r, input logic rf, input int i);
    return lst(a, b, c, (r && rf) ? 19 - i : i);
  endfunction
  task automatic tick(input logic s, input logic st, input logic rs);
    @(negedge clk); step = s; start = st; rst = rs; @(posedge clk); #1; step = 0; start = 0; rst = 0;
  endtask
  // run one scan: start, then 20 indices one step apart; compare every index
  task automatic scan(input string tag, input logic r, input logic rf, input logic [3:0] a, input logic [7:0] b, input logic [7:0] c);
    pf0 = a; pf1 = b; pf2 = c; right = r; ref_ = rf;
    tick(0, 1, 0);
    for (int i = 0; i < 20; i++) begin
      chk($sformatf("T4 %s index %0d", tag, i), pf, expect_bit(a, b, c, r, rf, i));
      if (i < 19) tick(1, 0, 0);
    end
  endtask
  logic [19:0] w;
  initial begin
    tick(0, 0, 1);
    // one bit at a time, 20 bits x both halves x ref 0/1
    for (int k = 0; k < 20; k++) for (int r = 0; r < 2; r++) for (int rf = 0; rf < 2; rf++) begin
      logic [3:0] a; logic [7:0] b, c; a = 0; b = 0; c = 0;
      if (k < 4) a[k] = 1; else if (k < 12) b[11-k] = 1; else c[k-12] = 1;
      scan($sformatf("bit %0d right=%0d ref=%0d", k, r, rf), r, rf, a, b, c);
    end
    // all ones and all zeros
    for (int r = 0; r < 2; r++) for (int rf = 0; rf < 2; rf++) begin
      scan($sformatf("all ones right=%0d ref=%0d", r, rf), r, rf, 4'hf, 8'hff, 8'hff);
      scan($sformatf("all zeros right=%0d ref=%0d", r, rf), r, rf, 4'h0, 8'h00, 8'h00);
    end
    // random patterns
    for (int n = 0; n < 200; n++) scan($sformatf("random %0d", n), $urandom % 2, $urandom % 2, $urandom, $urandom, $urandom);
    // right half reflect is the exact reverse of the left half
    begin
      logic [19:0] left, rr, rev;
      pf0 = 4'hb; pf1 = 8'h5c; pf2 = 8'ha3; ref_ = 1;
      right = 0; tick(0, 1, 0); for (int i = 0; i < 20; i++) begin left[i] = pf; if (i < 19) tick(1, 0, 0); end
      right = 1; tick(0, 1, 0); for (int i = 0; i < 20; i++) begin rr[i] = pf; if (i < 19) tick(1, 0, 0); end
      for (int i = 0; i < 20; i++) rev[i] = left[19-i];
      chk("T4 right half with ref=1 is the left half reversed", rr, rev);
      ref_ = 0; right = 1; tick(0, 1, 0); for (int i = 0; i < 20; i++) begin rr[i] = pf; if (i < 19) tick(1, 0, 0); end
      chk("T4 right half with ref=0 repeats the left half", rr, left);
    end
    // step = 0 holds the index
    pf0 = 4'b0001; pf1 = 8'h00; pf2 = 8'h00; right = 0; ref_ = 0;
    tick(0, 1, 0); chk("T4 hold: index 0 reads PF0 D4", pf, 1);
    repeat (7) tick(0, 0, 0); chk("T4 hold: 7 clk without step stay at index 0", pf, 1);
    tick(1, 0, 0); chk("T4 one step leaves index 0", pf, 0);
    // restart on start, mid-scan
    pf0 = 4'b0001; pf1 = 8'h01; pf2 = 8'h80; right = 0; ref_ = 0;
    tick(0, 1, 0); repeat (9) tick(1, 0, 0);  // index 9 = PF1 D2
    chk("T4 restart: index 9 reads 0", pf, 0);
    tick(0, 1, 0); chk("T4 restart: start returns to index 0", pf, 1);
    tick(1, 0, 0); chk("T4 restart: step after start is index 1", pf, 0);
    repeat (10) tick(1, 0, 0); chk("T4 restart: index 11 = PF1 D0", pf, 1);
    tick(0, 1, 0); chk("T4 restart again to index 0", pf, 1);
    // restart with right/ref changes
    right = 1; ref_ = 1; pf0 = 4'b0000; pf1 = 8'h00; pf2 = 8'h80; tick(0, 1, 0); chk("T4 reflect: index 0 reads PF2 D7", pf, 1);
    // rst: index 0
    right = 0; ref_ = 0; pf0 = 4'b0001; pf1 = 0; pf2 = 0; tick(0, 1, 0); repeat (5) tick(1, 0, 0); chk("T4 pre-rst index 5 reads 0", pf, 0);
    tick(0, 0, 1); chk("T4 rst gives index 0", pf, 1);
    tick(1, 0, 0); chk("T4 step after rst is index 1", pf, 0);
    // write shows from the next index (timing within the line is [check], turichips#48)
    pf0 = 0; pf1 = 0; pf2 = 0; right = 0; ref_ = 0;
    tick(0, 1, 0); repeat (4) tick(1, 0, 0);   // index 4 = PF1 D7
    pf1 = 8'h40; tick(1, 0, 0);                // index 5 = PF1 D6
    chk("T4 PF1 written to $40 at index 4: index 5 shows the new bit", pf, 1);
    pf1 = 8'h00; tick(1, 0, 0); chk("T4 index 6 shows the new PF1 (0)", pf, 0);
    pf2 = 8'h80; repeat (6) tick(1, 0, 0);     // index 12 = PF2 D0
    chk("T4 PF2 written at index 6: index 12 reads PF2 D0 = 0", pf, 0);
    repeat (7) tick(1, 0, 0); chk("T4 index 19 reads the new PF2 D7", pf, 1);
    if (errs == 0) $display("PASS (%0d checks)", nchk); else $display("FAIL: %0d of %0d checks", errs, nchk);
    $finish;
  end
endmodule
