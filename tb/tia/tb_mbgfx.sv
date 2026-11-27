// Testbench T5 (missile and ball graphics): tia_mbgfx. Spec: docs/spec.md 6.5 (width NUSIZ D5-D4 / CTRLPF D5-D4 = 1, 2, 4, 8 colour clocks; enables ENAMx D1, ENABL D1).
// Port contract (chip-2600#51 gives behaviour, names from its text): clk rst step start size[1:0] en -> gfx.
//   size 00/01/10/11 = 1/2/4/8 colour clocks. en is the final enable (the caller does ENAMx D1 & ~RESMPx D1, or the VDELBL select).
// Timing convention (same as tb_pgfx): after a clk edge with start=1 the output is 1 (if en=1); it stays 1 for `w` clk edges
// with step=1 (the run counts steps, not clocks); the w-th step ends it; it stays 0 until the next start.
// Issue #51: `start` wins over `step` in the same clock (the run restarts, that step is not counted); size and en are read live
// (gfx = drawing & en, so en toggled mid-run hides/shows the run without stopping its count).
// Expected values come from the spec and issue text only, never from the RTL.
`timescale 1ns/1ps
module tb_mbgfx;
  logic clk = 0, rst = 0, step = 0, start = 0, en = 1; logic [1:0] size = 0;
  wire g;
  tia_mbgfx dut (.clk(clk), .rst(rst), .step(step), .start(start), .size(size), .en(en), .gfx(g));
  always #5 clk = ~clk;
  int errs = 0, nchk = 0;
  task automatic chk(input string name, input logic got, input logic exp);
    nchk++;
    if (got !== exp) begin errs++; $display("FAIL %s: got %0b expected %0b", name, got, exp); end
  endtask
  task automatic tick(input logic s, input logic st, input logic rs);
    @(negedge clk); step = s; start = st; rst = rs; @(posedge clk); #1; step = 0; start = 0; rst = 0;
  endtask
  function automatic int width(input logic [1:0] s); return 1 << s; endfunction

  // run with a given number of idle (step=0) clocks inserted before every step; checks level after start, after each step, and that it stays 0
  task automatic run(input string tag, input logic [1:0] s, input int gap);
    int w; w = width(s); size = s; en = 1;
    tick(0, 1, 0);
    for (int k = 0; k < w; k++) begin
      chk($sformatf("T5 %s size=%0d gap=%0d step %0d drawing", tag, s, gap, k), g, 1);
      repeat (gap) begin tick(0, 0, 0); chk($sformatf("T5 %s size=%0d gap=%0d held at step %0d", tag, s, gap, k), g, 1); end
      tick(1, 0, 0);
    end
    chk($sformatf("T5 %s size=%0d gap=%0d ends after %0d steps", tag, s, gap, w), g, 0);
    repeat (3) begin tick(1, 0, 0); chk($sformatf("T5 %s size=%0d stays 0", tag, s), g, 0); end
    repeat (3) begin tick(0, 0, 0); chk($sformatf("T5 %s size=%0d stays 0 without step", tag, s), g, 0); end
  endtask

  initial begin
    tick(0, 0, 1);
    size = 3; en = 1;
    chk("T5 0 after rst", g, 0);
    repeat (12) tick(1, 0, 0); chk("T5 0 with steps but no start", g, 0);
    // all four widths, step held 1 (gap 0) and with step gaps
    for (int s = 0; s < 4; s++) for (int gp = 0; gp < 4; gp++) run("run", s[1:0], gp);
    // en = 0: gfx stays 0 for the whole run, every width
    for (int s = 0; s < 4; s++) begin
      size = s; en = 0; tick(0, 1, 0);
      for (int k = 0; k < width(s) + 3; k++) begin chk($sformatf("T5 en=0 size=%0d step %0d", s, k), g, 0); tick(1, 0, 0); end
    end
    // en toggled mid-run: the count keeps going while hidden, the output follows en
    for (int s = 1; s < 4; s++) begin
      int w; w = width(s); size = s; en = 1; tick(0, 1, 0);
      chk($sformatf("T5 entog size=%0d start", s), g, 1);
      tick(1, 0, 0); chk($sformatf("T5 entog size=%0d step 1 drawing", s), g, 1);
      en = 0; #1; chk($sformatf("T5 entog size=%0d en falls mid-run -> 0", s), g, 0);
      en = 1; #1; chk($sformatf("T5 entog size=%0d en back -> 1 (run not lost)", s), g, 1);
      en = 0; #1;
      // run still has w-1 steps left after step 1: stay hidden through the end, then raise en: must be 0 (run over)
      repeat (w - 1) begin tick(1, 0, 0); chk($sformatf("T5 entog size=%0d hidden", s), g, 0); end
      en = 1; #1; chk($sformatf("T5 entog size=%0d en raised after the run ended -> 0", s), g, 0);
    end
    // en low during the run, raised before the run ends: output returns for the remaining steps (size 8: 3 steps hidden, then 2 show)
    size = 3; en = 0; tick(0, 1, 0); repeat (3) tick(1, 0, 0); en = 1; #1;
    chk("T5 entog size=8: en raised at step 3 shows the rest of the run", g, 1);
    tick(1, 0, 0); chk("T5 entog size=8 step 4 still drawing", g, 1);
    repeat (3) tick(1, 0, 0); chk("T5 entog size=8 still drawing at step 7", g, 1); tick(1, 0, 0); chk("T5 entog size=8 ends at step 8", g, 0);
    // start with en = 0 then en = 1 later in the same run, vs start with en = 1: same run length
    size = 2; en = 0; tick(0, 1, 0); en = 1; #1; chk("T5 start with en=0, en=1 next: drawing", g, 1);
    repeat (3) tick(1, 0, 0); chk("T5 that run is 4 steps long", g, 1); tick(1, 0, 0); chk("T5 that run ends at step 4", g, 0);
    // start while drawing restarts the run (each width, restart at each step position)
    for (int s = 0; s < 4; s++) for (int p = 0; p < width(s); p++) begin
      size = s; en = 1; tick(0, 1, 0); repeat (p) tick(1, 0, 0);
      chk($sformatf("T5 restart size=%0d at step %0d: still drawing before", s, p), g, 1);
      tick(0, 1, 0); chk($sformatf("T5 restart size=%0d at step %0d: drawing", s, p), g, 1);
      repeat (width(s) - 1) tick(1, 0, 0);
      chk($sformatf("T5 restart size=%0d at step %0d: full width after restart", s, p), g, 1);
      tick(1, 0, 0); chk($sformatf("T5 restart size=%0d at step %0d: ends width steps after restart", s, p), g, 0);
    end
    // start after the end draws again
    size = 0; tick(0, 1, 0); tick(1, 0, 0); chk("T5 w1 ended", g, 0); tick(0, 1, 0); chk("T5 start after the end draws again", g, 1);
    // start and step in the same clock: start wins, the step is not counted (width 2: 2 more steps needed)
    for (int s = 1; s < 4; s++) begin
      size = s; en = 1; tick(0, 1, 0); tick(1, 0, 0);       // 1 step into the run (size 2: one left)
      tick(1, 1, 0); chk($sformatf("T5 start+step size=%0d: drawing", s), g, 1);
      repeat (width(s) - 1) tick(1, 0, 0);
      chk($sformatf("T5 start+step size=%0d: step in the start clock not counted (last step still to come)", s), g, 1);
      tick(1, 0, 0); chk($sformatf("T5 start+step size=%0d: ends after width steps", s), g, 0);
    end
    // start+step from idle also draws and counts from the next clock only
    size = 1; tick(1, 1, 0); chk("T5 start+step from idle draws", g, 1); tick(1, 0, 0); chk("T5 start+step from idle: 1 step left", g, 1); tick(1, 0, 0); chk("T5 start+step from idle ends", g, 0);
    // width changed mid-run is read live: the run ends when steps reach the new width
    // (narrowing below the steps already done is not in the spec, not tested)
    size = 0; en = 1; tick(0, 1, 0); size = 3;                       // widen before the first step
    repeat (7) tick(1, 0, 0); chk("T5 live width: widened to 8 before step 1: still drawing after 7 steps", g, 1);
    tick(1, 0, 0); chk("T5 live width: ends at 8 steps", g, 0);
    size = 1; tick(0, 1, 0); tick(1, 0, 0); chk("T5 live width: 2-wide, 1 step done", g, 1); size = 2;
    tick(1, 0, 0); tick(1, 0, 0); chk("T5 live width: widened to 4 at step 1: 3 steps done still drawing", g, 1);
    tick(1, 0, 0); chk("T5 live width: ends at 4", g, 0);
    // size does not change the output when idle
    for (int s = 0; s < 4; s++) begin size = s; #1; chk("T5 idle output 0 for any size", g, 0); end
    // rst stops a run and clears; step after rst does not draw; start after rst works
    size = 3; en = 1; tick(0, 1, 0); tick(1, 0, 0); chk("T5 pre-rst drawing", g, 1);
    tick(0, 0, 1); chk("T5 rst stops the run", g, 0);
    repeat (3) tick(1, 0, 0); chk("T5 steps after rst do not draw", g, 0);
    tick(0, 1, 0); chk("T5 start after rst draws", g, 1);
    repeat (7) tick(1, 0, 0); chk("T5 after rst a full 8-wide run: still drawing after 7 steps", g, 1);
    tick(1, 0, 0); chk("T5 after rst a full 8-wide run ends", g, 0);
    // rst wins over start in the same clock
    tick(0, 1, 1); chk("T5 rst+start: idle", g, 0);
    if (errs == 0) $display("PASS (%0d checks)", nchk); else $display("FAIL: %0d of %0d checks", errs, nchk);
    $finish;
  end
endmodule
