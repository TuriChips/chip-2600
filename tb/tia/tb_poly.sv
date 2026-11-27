// Testbench T1, T2: tia_poly6, tia_hdec, tia_objdec. Spec: docs/spec.md 4.1 (counter rule, decode table), 6.5 (decode matrix).
// Expected values come from the spec only (the XNOR rule and the two tables), never from the RTL.
// State strings are in the spec's Q1...Q6 order; q[0] = Q1 ... q[5] = Q6.
// A failed check prints "FAIL ..."; the run ends with "PASS" or "FAIL: <n> of <m> checks".
`timescale 1ns/1ps
module tb_poly;
  logic clk = 0, rst = 0, step = 0;
  wire [5:0] q;
  tia_poly6 dut (.clk(clk), .step(step), .rst(rst), .q(q));
  // decodes on the live counter
  wire h_shs, h_rhs, h_rcb, h_rhb, h_lrhb, h_cnt, h_end, h_err;
  wire o_err, o_wrap, o_c3, o_c7, o_c15;
  tia_hdec  hd (.q(q), .shs(h_shs), .rhs(h_rhs), .rcb(h_rcb), .rhb(h_rhb), .lrhb(h_lrhb), .cnt(h_cnt), .end_(h_end), .err(h_err));
  tia_objdec od (.q(q), .err(o_err), .wrap(o_wrap), .c3(o_c3), .c7(o_c7), .c15(o_c15));
  // decodes swept over all 64 inputs (T2)
  logic [5:0] sq = 0;
  wire s_shs, s_rhs, s_rcb, s_rhb, s_lrhb, s_cnt, s_end, s_err;
  wire t_err, t_wrap, t_c3, t_c7, t_c15;
  tia_hdec  hs (.q(sq), .shs(s_shs), .rhs(s_rhs), .rcb(s_rcb), .rhb(s_rhb), .lrhb(s_lrhb), .cnt(s_cnt), .end_(s_end), .err(s_err));
  tia_objdec os (.q(sq), .err(t_err), .wrap(t_wrap), .c3(t_c3), .c7(t_c7), .c15(t_c15));

  int errs = 0, nchk = 0;
  task automatic chk(input string name, input logic [31:0] got, input logic [31:0] exp);
    nchk++;
    if (got !== exp) begin errs++; $display("FAIL %s: got 0x%0h expected 0x%0h", name, got, exp); end
  endtask

  // spec Q1...Q6 string -> q vector (Q1 is q[0])
  function automatic logic [5:0] S(input string s);
    logic [5:0] r;
    for (int i = 0; i < 6; i++) r[i] = (s[i] == "1");
    return r;
  endfunction
  // the spec rule: new Q1 = XNOR(Q5, Q6), Qk = old Q(k-1)
  function automatic logic [5:0] nxt(input logic [5:0] x);
    return {x[4:0], ~(x[4] ^ x[5])};
  endfunction

  task automatic tick(input logic r, input logic s);
    @(negedge clk); rst = r; step = s;
    @(posedge clk); #1;
  endtask

  logic [5:0] seq [0:62];
  int seen [0:63];
  int cnt_shs, cnt_rhs, cnt_rcb, cnt_rhb, cnt_lrhb, cnt_cnt, cnt_end, cnt_werr, cnt_wrap, cnt_c3, cnt_c7, cnt_c15, cnt_oerr, cnt_herr;
  logic [5:0] x, held;
  int k;

  always #5 clk = ~clk;

  initial begin
    // ---------- T1: reset, first step
    tick(1, 0); chk("T1 reset gives 000000", q, 6'b0);
    tick(0, 1); chk("T1 000000 -> 100000 (Q1..Q6)", q, S("100000"));
    tick(1, 1); chk("T1 rst over step gives 000000", q, 6'b0);
    tick(1, 0); tick(0, 0); chk("T1 step=0 holds at 000000", q, 6'b0);

    // ---------- T1: the 63-state sequence, with the decodes counted on the way
    tick(1, 0);
    for (int i = 0; i < 64; i++) seen[i] = 0;
    {cnt_shs, cnt_rhs, cnt_rcb, cnt_rhb, cnt_lrhb, cnt_cnt, cnt_end, cnt_werr, cnt_wrap, cnt_c3, cnt_c7, cnt_c15, cnt_oerr, cnt_herr} = '0;
    x = 6'b0;
    for (k = 0; k < 63; k++) begin
      // state k is on q now (count k from 000000)
      chk($sformatf("T1 state %0d follows XNOR rule", k), q, x);
      seen[q]++;
      if (h_shs)  begin cnt_shs  = k; chk("T1 SHS at count",  k, 4);  end
      if (h_rhs)  begin cnt_rhs  = k; chk("T1 RHS at count",  k, 8);  end
      if (h_rcb)  begin cnt_rcb  = k; chk("T1 RCB at count",  k, 12); end
      if (h_rhb)  begin cnt_rhb  = k; chk("T1 RHB at count",  k, 16); end
      if (h_lrhb) begin cnt_lrhb = k; chk("T1 LRHB at count", k, 18); end
      if (h_cnt)  begin cnt_cnt  = k; chk("T1 CNT at count",  k, 36); end
      if (h_end)  begin cnt_end  = k; chk("T1 END at count",  k, 56); end
      if (h_err)  cnt_herr++;
      if (o_err)  cnt_oerr++;
      if (o_wrap) begin cnt_wrap = k; chk("T1 obj wrap at count", k, 39); end
      if (o_c3)   begin cnt_c3   = k; chk("T1 obj c3 at count",   k, 3);  end
      if (o_c7)   begin cnt_c7   = k; chk("T1 obj c7 at count",   k, 7);  end
      if (o_c15)  begin cnt_c15  = k; chk("T1 obj c15 at count",  k, 15); end
      seq[k] = q;
      x = nxt(x);
      tick(0, 1);
    end
    chk("T1 SHS fired", cnt_shs, 4);   chk("T1 RHS fired", cnt_rhs, 8);   chk("T1 RCB fired", cnt_rcb, 12);
    chk("T1 RHB fired", cnt_rhb, 16);  chk("T1 LRHB fired", cnt_lrhb, 18); chk("T1 CNT fired", cnt_cnt, 36);
    chk("T1 END fired", cnt_end, 56);  chk("T1 obj wrap fired", cnt_wrap, 39);
    chk("T1 obj c3 fired", cnt_c3, 3); chk("T1 obj c7 fired", cnt_c7, 7); chk("T1 obj c15 fired", cnt_c15, 15);
    chk("T1 hdec err never in the 63 states", cnt_herr, 0);
    chk("T1 objdec err never in the 63 states", cnt_oerr, 0);
    chk("T1 after 63 steps back at 000000", q, 6'b0);
    for (int i = 0; i < 64; i++) chk($sformatf("T1 state %b visited once", 6'(i)), seen[i], (i == 63) ? 0 : 1);
    // table counts from the spec's decode table, as literal states, against the observed sequence
    chk("T1 seq[4]  = SHS 111100",  seq[4],  S("111100")); chk("T1 seq[8]  = RHS 110111",  seq[8],  S("110111"));
    chk("T1 seq[12] = RCB 001111",  seq[12], S("001111")); chk("T1 seq[16] = RHB 011100",  seq[16], S("011100"));
    chk("T1 seq[18] = LRHB 010111", seq[18], S("010111")); chk("T1 seq[36] = CNT 101100",  seq[36], S("101100"));
    chk("T1 seq[56] = END 010100",  seq[56], S("010100"));
    chk("T1 seq[3]  = c3 111000",   seq[3],  S("111000")); chk("T1 seq[7]  = c7 101111",   seq[7],  S("101111"));
    chk("T1 seq[15] = c15 111001",  seq[15], S("111001")); chk("T1 seq[39] = wrap 101101", seq[39], S("101101"));

    // ---------- T1: hold on step = 0, at several states
    for (int j = 0; j < 63; j += 5) begin
      tick(1, 0);
      for (int i = 0; i < j; i++) tick(0, 1);
      held = q;
      for (int i = 0; i < 4; i++) tick(0, 0);
      chk($sformatf("T1 hold at count %0d", j), q, held);
      tick(1, 1);
      chk($sformatf("T1 rst over step at count %0d", j), q, 6'b0);
    end

    // ---------- T1: forced 111111 (not reachable from 000000)
    tick(1, 0); tick(0, 1); tick(0, 1);
    force dut.q = 6'b111111; #1; release dut.q; #1;
    if (q !== 6'b111111) $display("REPORT T1 forcing dut.q did not hold after release (q=%b); forced-state checks skipped", q);
    else begin
      chk("T1 forced 111111: hdec err", h_err, 1);  chk("T1 forced 111111: objdec err", o_err, 1);
      chk("T1 forced 111111: no other hdec decode", {h_shs, h_rhs, h_rcb, h_rhb, h_lrhb, h_cnt, h_end}, 0);
      chk("T1 forced 111111: no other objdec decode", {o_wrap, o_c3, o_c7, o_c15}, 0);
      tick(0, 0); chk("T1 forced 111111 holds on step=0", q, 6'b111111);
      tick(0, 1); chk("T1 step from 111111 follows XNOR rule", q, nxt(6'b111111));
      tick(1, 0); chk("T1 rst clears 111111", q, 6'b0);
    end

    // ---------- T2: all 64 inputs
    for (int i = 0; i < 64; i++) begin
      sq = i[5:0]; #1;
      chk($sformatf("T2 hdec shs  %b", sq), s_shs,  (sq == S("111100")));
      chk($sformatf("T2 hdec rhs  %b", sq), s_rhs,  (sq == S("110111")));
      chk($sformatf("T2 hdec rcb  %b", sq), s_rcb,  (sq == S("001111")));
      chk($sformatf("T2 hdec rhb  %b", sq), s_rhb,  (sq == S("011100")));
      chk($sformatf("T2 hdec lrhb %b", sq), s_lrhb, (sq == S("010111")));
      chk($sformatf("T2 hdec cnt  %b", sq), s_cnt,  (sq == S("101100")));
      chk($sformatf("T2 hdec end  %b", sq), s_end,  (sq == S("010100")));
      chk($sformatf("T2 hdec err  %b", sq), s_err,  (sq == S("111111")));
      chk($sformatf("T2 objdec err  %b", sq), t_err,  (sq == S("111111")));
      chk($sformatf("T2 objdec wrap %b", sq), t_wrap, (sq == S("101101")));
      chk($sformatf("T2 objdec c3   %b", sq), t_c3,   (sq == S("111000")));
      chk($sformatf("T2 objdec c7   %b", sq), t_c7,   (sq == S("101111")));
      chk($sformatf("T2 objdec c15  %b", sq), t_c15,  (sq == S("111001")));
    end

    if (errs == 0) $display("PASS (%0d checks)", nchk); else $display("FAIL: %0d of %0d checks", errs, nchk);
    $finish;
  end
  initial begin #5000000; $display("FAIL: timeout"); $finish; end
endmodule
