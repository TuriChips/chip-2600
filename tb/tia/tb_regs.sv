// Testbench T3, T4, T5: tia_regs. Spec: docs/spec.md 6.1 (write map), 6.5 (vertical delay), 6.6 (HMCLR), 5 (reset).
// Expected values come from the spec only. The spec leaves the packing of multi-field ports to the RTL header, so
// the checks that depend on packing are written to not need it: bit count, "all ones on $FF", injectivity over the
// walking-1 data, and port-to-port copies. Exact packing is checked only where the spec or the issue fixes it
// (8-bit registers = d, COLUPx = d[7:1], NUSIZx = {d5,d4,d2,d1,d0}, 1-bit registers = the listed bit).
// A failed check prints "FAIL ..."; the run ends with "PASS" or "FAIL: <n> of <m> checks".
`timescale 1ns/1ps
module tb_regs;
  logic clk = 0, rst = 0, wr = 0;
  logic [5:0] a = 0;
  logic [7:0] d = 0;
  wire        vsync, refp0, refp1, enam0, enam1, enabl_new, enabl_old, vdelp0, vdelp1, vdelbl, resmp0, resmp1;
  wire [2:0]  vblank;
  wire [4:0]  nusiz0, nusiz1, ctrlpf, audf0, audf1;
  wire [6:0]  colup0, colup1, colupf, colubk;
  wire [3:0]  pf0, audc0, audc1, audv0, audv1, hmp0, hmp1, hmm0, hmm1, hmbl;
  wire [7:0]  pf1, pf2, grp0_new, grp0_old, grp1_new, grp1_old;
  wire wsync_s, rsync_s, resp0_s, resp1_s, resm0_s, resm1_s, resbl_s, hmove_s, hmclr_s, cxclr_s;

  tia_regs dut (.clk(clk), .rst(rst), .wr(wr), .a(a), .d(d),
    .vsync(vsync), .vblank(vblank), .nusiz0(nusiz0), .nusiz1(nusiz1),
    .colup0(colup0), .colup1(colup1), .colupf(colupf), .colubk(colubk), .ctrlpf(ctrlpf),
    .refp0(refp0), .refp1(refp1), .pf0(pf0), .pf1(pf1), .pf2(pf2),
    .audc0(audc0), .audc1(audc1), .audf0(audf0), .audf1(audf1), .audv0(audv0), .audv1(audv1),
    .grp0_new(grp0_new), .grp0_old(grp0_old), .grp1_new(grp1_new), .grp1_old(grp1_old),
    .enam0(enam0), .enam1(enam1), .enabl_new(enabl_new), .enabl_old(enabl_old),
    .hmp0(hmp0), .hmp1(hmp1), .hmm0(hmm0), .hmm1(hmm1), .hmbl(hmbl),
    .vdelp0(vdelp0), .vdelp1(vdelp1), .vdelbl(vdelbl), .resmp0(resmp0), .resmp1(resmp1),
    .wsync_s(wsync_s), .rsync_s(rsync_s), .resp0_s(resp0_s), .resp1_s(resp1_s), .resm0_s(resm0_s),
    .resm1_s(resm1_s), .resbl_s(resbl_s), .hmove_s(hmove_s), .hmclr_s(hmclr_s), .cxclr_s(cxclr_s));

  // ---- stored ports, flattened to one array (value zero-extended to 8 bits). Index = row of the table below.
  localparam int NP = 38;
  logic [7:0] pv [0:NP-1];
  always_comb begin
    pv[0]=vsync; pv[1]=vblank; pv[2]=nusiz0; pv[3]=nusiz1; pv[4]=colup0; pv[5]=colup1; pv[6]=colupf; pv[7]=colubk;
    pv[8]=ctrlpf; pv[9]=refp0; pv[10]=refp1; pv[11]=pf0; pv[12]=pf1; pv[13]=pf2; pv[14]=audc0; pv[15]=audc1;
    pv[16]=audf0; pv[17]=audf1; pv[18]=audv0; pv[19]=audv1; pv[20]=grp0_new; pv[21]=grp0_old; pv[22]=grp1_new;
    pv[23]=grp1_old; pv[24]=enam0; pv[25]=enam1; pv[26]=enabl_new; pv[27]=enabl_old; pv[28]=hmp0; pv[29]=hmp1;
    pv[30]=hmm0; pv[31]=hmm1; pv[32]=hmbl; pv[33]=vdelp0; pv[34]=vdelp1; pv[35]=vdelbl; pv[36]=resmp0; pv[37]=resmp1;
  end
  int W [0:NP-1];
  function automatic void build_w(); int t[$]; t = '{1,3,5,5,7,7,7,7, 5,1,1,4,8,8,4,4, 5,5,4,4,8,8,8,8, 1,1,1,1,4,4, 4,4,4,1,1,1,1,1}; for (int i=0;i<NP;i++) W[i]=t[i]; endfunction
  wire [9:0] strobes = {wsync_s, rsync_s, resp0_s, resp1_s, resm0_s, resm1_s, resbl_s, hmove_s, hmclr_s, cxclr_s};

  // ---- the write map of spec 6.1: address -> (port index, bit mask of D). port -1 = strobe, -2 = no register.
  int         own  [0:63];
  logic [7:0] mask [0:63];
  int         sidx [0:63];  // strobe bit position in `strobes` for strobe addresses
  function automatic void setm(input int ad, input int p, input logic [7:0] m);
    own[ad] = p; mask[ad] = m;
  endfunction
  function automatic void build_map();
    for (int i = 0; i < 64; i++) begin own[i] = -2; mask[i] = 0; sidx[i] = -1; end
    setm(8'h00, 0, 8'h02); setm(8'h01, 1, 8'hC2); setm(8'h04, 2, 8'h37); setm(8'h05, 3, 8'h37);
    setm(8'h06, 4, 8'hFE); setm(8'h07, 5, 8'hFE); setm(8'h08, 6, 8'hFE); setm(8'h09, 7, 8'hFE);
    setm(8'h0A, 8, 8'h37); setm(8'h0B, 9, 8'h08); setm(8'h0C, 10, 8'h08); setm(8'h0D, 11, 8'hF0);
    setm(8'h0E, 12, 8'hFF); setm(8'h0F, 13, 8'hFF); setm(8'h15, 14, 8'h0F); setm(8'h16, 15, 8'h0F);
    setm(8'h17, 16, 8'h1F); setm(8'h18, 17, 8'h1F); setm(8'h19, 18, 8'h0F); setm(8'h1A, 19, 8'h0F);
    setm(8'h1B, 20, 8'hFF); setm(8'h1C, 22, 8'hFF); setm(8'h1D, 24, 8'h02); setm(8'h1E, 25, 8'h02);
    setm(8'h1F, 26, 8'h02); setm(8'h20, 28, 8'hF0); setm(8'h21, 29, 8'hF0); setm(8'h22, 30, 8'hF0);
    setm(8'h23, 31, 8'hF0); setm(8'h24, 32, 8'hF0); setm(8'h25, 33, 8'h01); setm(8'h26, 34, 8'h01);
    setm(8'h27, 35, 8'h01); setm(8'h28, 36, 8'h02); setm(8'h29, 37, 8'h02);
    // strobes: bit position in `strobes` = 9 for wsync ... 0 for cxclr (concatenation order above)
    own[8'h02] = -1; sidx[8'h02] = 9; own[8'h03] = -1; sidx[8'h03] = 8; own[8'h10] = -1; sidx[8'h10] = 7;
    own[8'h11] = -1; sidx[8'h11] = 6; own[8'h12] = -1; sidx[8'h12] = 5; own[8'h13] = -1; sidx[8'h13] = 4;
    own[8'h14] = -1; sidx[8'h14] = 3; own[8'h2A] = -1; sidx[8'h2A] = 2; own[8'h2B] = -1; sidx[8'h2B] = 1;
    own[8'h2C] = -1; sidx[8'h2C] = 0;
  endfunction

  int errs = 0, nchk = 0;
  task automatic chk(input string name, input logic [31:0] got, input logic [31:0] exp);
    nchk++;
    if (got !== exp) begin errs++; $display("FAIL %s: got 0x%0h expected 0x%0h", name, got, exp); end
  endtask

  always #5 clk = ~clk;

  // Drive one write pulse: wr for exactly one clk. Returns the number of clk cycles (in a 4-cycle window from the
  // write cycle) in which each strobe was seen high, sampled just before each rising edge.
  int sc [0:9];
  task automatic write(input logic [5:0] ad, input logic [7:0] dd);
    @(negedge clk); wr = 1; a = ad; d = dd;
    for (int i = 0; i < 10; i++) sc[i] = 0;
    for (int c = 0; c < 4; c++) begin
      #4;                                                    // just before the rising edge
      for (int i = 0; i < 10; i++) if (strobes[i]) sc[i]++;
      @(posedge clk); #1;
      if (c == 0) begin wr = 0; a = 6'h3F ^ ad; d = ~dd; end  // wr drops after one clk, a/d change under it
      @(negedge clk);
    end
  endtask
  task automatic reset(); @(negedge clk); rst = 1; @(posedge clk); #1; @(negedge clk); rst = 0; endtask
  logic [7:0] s0 [0:NP-1], s1 [0:NP-1];
  task automatic snap0(); for (int i = 0; i < NP; i++) s0[i] = pv[i]; endtask
  task automatic snap1(); for (int i = 0; i < NP; i++) s1[i] = pv[i]; endtask
  function automatic int pop(input logic [7:0] x); int n = 0; for (int i = 0; i < 8; i++) n += x[i]; return n; endfunction
  task automatic fill(); // every address $00-$2C that is not a strobe or HMCLR, with $FF; then clean strobes out of the way
    for (int ad = 0; ad < 8'h2D; ad++) if (own[ad] >= 0) write(ad[5:0], 8'hFF);
  endtask

  logic [7:0] wk [0:7];
  logic [7:0] dd;
  int nown, ok, bg;
  logic [7:0] fullm;

  // one write from the state in s0; checks of T3
  task automatic check_write(input int ad, input logic [7:0] dv, input string tag);
    string nm = $sformatf("%s $%02h data %02h", tag, ad, dv);
    snap0(); write(ad[5:0], dv); snap1();
    if (own[ad] >= 0) begin
      nown = own[ad];
      fullm = (W[nown] == 8) ? 8'hFF : (8'h01 << W[nown]) - 1;
      chk({nm, ": strobes quiet"}, strobes, 0);                 // sampled after the window: also nothing stuck
      for (int i = 0; i < 10; i++) chk($sformatf("%s: strobe %0d count", nm, i), sc[i], 0);
      chk({nm, ": stored bit count"}, pop(s1[nown]), pop(dv & mask[ad]));
      if (dv == 8'hFF) chk({nm, ": all ones"}, s1[nown], fullm);
      if (dv == 8'h00) chk({nm, ": zero"}, s1[nown], 0);
      if (W[nown] == 8) chk({nm, ": 8-bit register = d"}, s1[nown], dv);
      if (nown >= 4 && nown <= 7) chk({nm, ": COLUP = d[7:1]"}, s1[nown], dv[7:1]);
      if (nown == 2 || nown == 3) chk({nm, ": NUSIZ = {d5,d4,d2,d1,d0}"}, s1[nown], {dv[5], dv[4], dv[2], dv[1], dv[0]});
      if (W[nown] == 1) chk({nm, ": 1-bit register = its bit"}, s1[nown], |(dv & mask[ad]));
      // every other port unchanged, except the vertical-delay copies
      for (int i = 0; i < NP; i++) begin
        ok = (i == nown);
        if (ad == 8'h1B && i == 23) ok = 1;                      // GRP1 old <- GRP1 new
        if (ad == 8'h1C && (i == 21 || i == 27)) ok = 1;         // GRP0 old, ENABL old <- new
        if (!ok) chk($sformatf("%s: port %0d unchanged", nm, i), s1[i], s0[i]);
      end
      if (ad == 8'h1B) chk({nm, ": GRP1 old = old GRP1 new"}, s1[23], s0[22]);
      if (ad == 8'h1C) begin chk({nm, ": GRP0 old = old GRP0 new"}, s1[21], s0[20]);
                             chk({nm, ": ENABL old = old ENABL new"}, s1[27], s0[26]); end
    end else if (own[ad] == -1) begin
      for (int i = 0; i < 10; i++) chk($sformatf("%s: strobe %0d count", nm, i), sc[i], (i == sidx[ad]));
      chk({nm, ": strobes quiet after"}, strobes, 0);
      for (int i = 0; i < NP; i++)
        if (!(ad == 8'h2B && i >= 28 && i <= 32)) chk($sformatf("%s: port %0d unchanged by strobe", nm, i), s1[i], s0[i]);
      if (ad == 8'h2B) for (int i = 28; i <= 32; i++) chk($sformatf("%s: HM port %0d cleared", nm, i), s1[i], 0);
    end else begin
      for (int i = 0; i < 10; i++) chk($sformatf("%s: strobe %0d count", nm, i), sc[i], 0);
      for (int i = 0; i < NP; i++) chk($sformatf("%s: port %0d unchanged", nm, i), s1[i], s0[i]);
    end
  endtask

  // vertical delay model (spec 6.5), 8-bit GRP = d, ENABL = d1
  logic [7:0] m_g0n, m_g0o, m_g1n, m_g1o; logic m_en, m_eo;
  int r;

  initial begin
    build_map(); build_w();
    // ---------- T5 reset (power-on has no defined state before the first rst, so start with one)
    reset();
    for (int i = 0; i < NP; i++) chk($sformatf("T5 after first rst port %0d = 0", i), pv[i], 0);
    chk("T5 after first rst strobes = 0", strobes, 0);
    fill(); write(6'h1B, 8'hA5); write(6'h1C, 8'h5A); write(6'h1F, 8'h02); write(6'h1C, 8'hFF);
    snap0(); ok = 0; for (int i = 0; i < NP; i++) ok += (s0[i] != 0);
    chk("T5 precondition: registers loaded", ok > 20, 1);
    reset();
    for (int i = 0; i < NP; i++) chk($sformatf("T5 after rst of loaded state port %0d = 0", i), pv[i], 0);
    chk("T5 after rst of loaded state strobes = 0", strobes, 0);
    @(negedge clk); chk("T5 outputs stay 0 after rst without writes", {pv[0], pv[1], pv[12], pv[20], pv[23]}, 0);
    // a strobe write, then rst, strobes 0
    write(6'h2B, 8'hFF); reset(); chk("T5 strobes 0 after rst", strobes, 0);

    // ---------- T3 write map: every address, from the reset state and from the all-FF state
    for (bg = 0; bg < 2; bg++) begin
      for (int ad = 0; ad < 64; ad++) begin
        dd = 0;
        for (int v = 0; v < 18; v++) begin
          if (v == 0) dd = 8'h00; else if (v == 1) dd = 8'hFF;
          else if (v < 10) dd = 8'h01 << (v - 2); else dd = ~(8'h01 << (v - 10));
          reset(); if (bg) fill();
          check_write(ad, dd, bg ? "T3 (all-FF background)" : "T3 (reset background)");
        end
      end
    end
    // injectivity of walking-1 data: different stored bits give different port values, unlisted bits give zero
    for (int ad = 0; ad < 8'h2D; ad++) if (own[ad] >= 0) begin
      for (int b = 0; b < 8; b++) begin reset(); write(ad[5:0], 8'h01 << b); wk[b] = pv[own[ad]]; end
      for (int b = 0; b < 8; b++) begin
        if (!mask[ad][b]) chk($sformatf("T3 $%02h walking-1 bit %0d (not stored) = 0", ad, b), wk[b], 0);
        else begin
          chk($sformatf("T3 $%02h walking-1 bit %0d stored, one bit set", ad, b), pop(wk[b]), 1);
          for (int c = b + 1; c < 8; c++) if (mask[ad][c]) chk($sformatf("T3 $%02h bits %0d and %0d land apart", ad, b, c), wk[b] != wk[c], 1);
        end
      end
    end
    // wr = 0: no effect at any address (a and d wiggling)
    reset(); fill(); snap0();
    for (int ad = 0; ad < 64; ad++) begin
      @(negedge clk); wr = 0; a = ad[5:0]; d = 8'h00; @(posedge clk); #1;
      chk($sformatf("T3 wr=0 at $%02h strobes", ad), strobes, 0);
    end
    snap1(); for (int i = 0; i < NP; i++) chk($sformatf("T3 wr=0 port %0d unchanged", i), s1[i], s0[i]);

    // ---------- T4 vertical delay (6.5)
    reset();
    write(6'h1F, 8'h02);                                   // ENABL new = 1
    chk("T4 ENABL write leaves old at 0", enabl_old, 0); chk("T4 ENABL new = 1", enabl_new, 1);
    write(6'h1B, 8'h77);                                   // GRP0 write: must not touch ENABL old, GRP0 old
    chk("T4 GRP0 write: ENABL old unchanged (0)", enabl_old, 0);
    chk("T4 GRP0 write: GRP0 old unchanged (0)", grp0_old, 0);
    chk("T4 GRP0 write: GRP0 new", grp0_new, 8'h77);
    chk("T4 GRP0 write: GRP1 old <- GRP1 new (0)", grp1_old, 0);
    write(6'h1C, 8'h33);                                   // GRP1 write: GRP0 old <- GRP0 new, ENABL old <- ENABL new
    chk("T4 GRP1 write: GRP1 new", grp1_new, 8'h33);
    chk("T4 GRP1 write: GRP0 old <- GRP0 new", grp0_old, 8'h77);
    chk("T4 GRP1 write: ENABL old <- ENABL new", enabl_old, 1);
    chk("T4 GRP1 write: GRP1 old unchanged (0)", grp1_old, 0);
    write(6'h1B, 8'h11);                                   // GRP0 write: GRP1 old <- GRP1 new (0x33)
    chk("T4 GRP0 write: GRP1 old <- 33", grp1_old, 8'h33);
    chk("T4 GRP0 write: GRP0 old stays 77", grp0_old, 8'h77);
    chk("T4 GRP0 write: ENABL old stays 1", enabl_old, 1);
    write(6'h1F, 8'h00);                                   // ENABL new = 0, old stays
    chk("T4 ENABL new 0", enabl_new, 0); chk("T4 ENABL write: old stays 1", enabl_old, 1);
    write(6'h1B, 8'hFF);                                   // GRP0 again: ENABL old still 1
    chk("T4 second GRP0 write: ENABL old still 1", enabl_old, 1);
    write(6'h1C, 8'h00);
    chk("T4 GRP1 write: ENABL old <- 0", enabl_old, 0);
    chk("T4 GRP1 write: GRP0 old <- FF", grp0_old, 8'hFF);
    // random sequence against the model
    reset(); {m_g0n, m_g0o, m_g1n, m_g1o, m_en, m_eo} = '0;
    for (int n = 0; n < 3000; n++) begin
      r = $urandom_range(0, 2); dd = $urandom;
      case (r)
        0: begin write(6'h1B, dd); m_g0n = dd; m_g1o = m_g1n; end
        1: begin write(6'h1C, dd); m_g1n = dd; m_g0o = m_g0n; m_eo = m_en; end
        2: begin write(6'h1F, dd); m_en = dd[1]; end
      endcase
      if (grp0_new !== m_g0n || grp0_old !== m_g0o || grp1_new !== m_g1n || grp1_old !== m_g1o || enabl_new !== m_en || enabl_old !== m_eo) begin
        errs++; $display("FAIL T4 random step %0d (write %0d %02h): g0 %02h/%02h g1 %02h/%02h en %b/%b model g0 %02h/%02h g1 %02h/%02h en %b/%b",
          n, r, dd, grp0_new, grp0_old, grp1_new, grp1_old, enabl_new, enabl_old, m_g0n, m_g0o, m_g1n, m_g1o, m_en, m_eo);
      end
      nchk++;
    end
    // HMCLR: clears all five HM registers and nothing else
    reset(); fill(); write(6'h1B, 8'h5A); write(6'h1C, 8'hC3);
    snap0(); write(6'h2B, 8'h00); snap1();
    for (int i = 28; i <= 32; i++) begin chk($sformatf("T4 HMCLR cleared port %0d", i), s1[i], 0); chk($sformatf("T4 precondition port %0d loaded", i), s0[i] != 0, 1); end
    for (int i = 0; i < NP; i++) if (i < 28 || i > 32) chk($sformatf("T4 HMCLR left port %0d", i), s1[i], s0[i]);
    // HMxx write after HMCLR works, and writes one HM leave the others
    write(6'h20, 8'hA0); chk("T4 HMP0 after HMCLR loads", hmp0 != 0, 1);
    chk("T4 HMP1 stays 0", hmp1, 0); chk("T4 HMM0 stays 0", hmm0, 0); chk("T4 HMM1 stays 0", hmm1, 0); chk("T4 HMBL stays 0", hmbl, 0);
    write(6'h2B, 8'hFF); chk("T4 HMCLR clears HMP0 again", hmp0, 0);

    if (errs == 0) $display("PASS (%0d checks)", nchk); else $display("FAIL: %0d of %0d checks", errs, nchk);
    $finish;
  end
  initial begin #200000000; $display("FAIL: timeout"); $finish; end
endmodule
