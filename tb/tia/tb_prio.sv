// Testbench T9 (priority and colour): tia_prio. Spec: docs/spec.md 6.9, 6.4 (SCORE, PFP), 6.2 (blk).
// Port contract (chip-2600#61): p0 m0 p1 m1 pf bl score pfp right blk colup0 colup1 colupf colubk[6:0] -> lum[2:0] col[3:0]. Combinational.
// colupN = register D7-D1, so col = colupN[6:3] (D7-D4) and lum = colupN[2:0] (D3-D1).
// Expected values come from the spec priority lists only (written below as an explicit if-chain, never from the RTL):
//   normal: P0/M0 > P1/M1 > PF/BL > BK.  PFP = 1: PF/BL > P0/M0 > P1/M1 > BK.
//   SCORE = 1, PFP = 0, PF = 1, BL = 0: PF takes COLUP0 (left half) or COLUP1 (right half). blk = 1: lum = col = 0.
// OPEN (spec 6.9 [check], turichips#48): SCORE = 1 with BL = 1, and SCORE = 1 with PFP = 1 when PF or BL is set.
//   Those are NOT asserted: every such input is printed as a REPORT line with the DUT's colour source.
`timescale 1ns/1ps
module tb_prio;
  logic p0, m0, p1, m1, pf, bl, score, pfp, right, blk;
  logic [6:0] c0, c1, cf, cb;
  wire [2:0] lum; wire [3:0] col;
  tia_prio dut (.p0(p0), .m0(m0), .p1(p1), .m1(m1), .pf(pf), .bl(bl), .score(score), .pfp(pfp), .right(right), .blk(blk),
                .colup0(c0), .colup1(c1), .colupf(cf), .colubk(cb), .lum(lum), .col(col));
  int errs = 0, nchk = 0, nrep = 0;
  // which register an input selects: 0 P0, 1 P1, 2 PF colour (COLUPF), 3 BK
  function automatic int src(input logic p0_, m0_, p1_, m1_, pf_, bl_, pfp_);
    logic o0, o1, ob; o0 = p0_ | m0_; o1 = p1_ | m1_; ob = pf_ | bl_;
    if (pfp_) begin if (ob) return 2; if (o0) return 0; if (o1) return 1; return 3; end
    else      begin if (o0) return 0; if (o1) return 1; if (ob) return 2; return 3; end
  endfunction
  function automatic logic [6:0] regv(input int s);
    case (s) 0: return c0; 1: return c1; 2: return cf; default: return cb; endcase
  endfunction
  task automatic apply(input logic [5:0] o, input logic sc, pp, rt, bk);
    {p0, m0, p1, m1, pf, bl} = o; score = sc; pfp = pp; right = rt; blk = bk; #1;
  endtask
  task automatic chk(input string name, input logic [6:0] exp);
    nchk++;
    if ({col, lum} !== (exp & 7'h7f) || ^{col, lum} === 1'bx) begin
      errs++; $display("FAIL %s: got col=%h lum=%0d expected col=%h lum=%0d", name, col, lum, exp[6:3], exp[2:0]);
    end
  endtask
  // which register the DUT shows (-1 if none of the four matches uniquely)
  function automatic int shown();
    for (int s = 0; s < 4; s++) if ({col, lum} === regv(s)) return s;
    return -1;
  endfunction
  function automatic string sname(input int s);
    case (s) 0: return "COLUP0"; 1: return "COLUP1"; 2: return "COLUPF"; 3: return "COLUBK"; default: return "none"; endcase
  endfunction

  // one register set: all four values differ in col and in lum, and every field is distinct from the other fields' bit patterns
  task automatic sweep(input string tag, input logic [6:0] v0, v1, vf, vb);
    c0 = v0; c1 = v1; cf = vf; cb = vb;
    for (int pp = 0; pp < 2; pp++) for (int sc = 0; sc < 2; sc++) for (int rt = 0; rt < 2; rt++) for (int o = 0; o < 64; o++) begin
      logic [5:0] ob; int s; ob = o[5:0];
      apply(ob, sc[0], pp[0], rt[0], 0);
      // open: SCORE with BL, SCORE with PFP and PF/BL set
      if (sc && (ob[0] || (pp && (ob[1] || ob[0])))) begin
        nrep++;
        if (tag == "A") $display("REPORT open objs=%b(p0 m0 p1 m1 pf bl) score=1 pfp=%0d right=%0d: shows %s", ob, pp, rt, sname(shown()));
      end else begin
        s = src(ob[5], ob[4], ob[3], ob[2], ob[1], ob[0], pp[0]);
        // SCORE (PFP = 0, PF = 1, BL = 0): the playfield level takes COLUP0 left / COLUP1 right
        if (sc && !pp && ob[1] && !ob[0] && s == 2) s = rt ? 1 : 0;
        chk($sformatf("T9 %s objs=%b score=%0d pfp=%0d right=%0d", tag, ob, sc, pp, rt), regv(s));
      end
      // blk forces both fields to 0, always (also in the open cases)
      apply(ob, sc[0], pp[0], rt[0], 1);
      chk($sformatf("T9 %s blk objs=%b score=%0d pfp=%0d right=%0d", tag, ob, sc, pp, rt), 7'h00);
    end
  endtask

  initial begin
    // register set A: every register has a distinct colour code and distinct luminance; no value is 0 in either field
    sweep("A", {4'h3, 3'd5}, {4'h9, 3'd2}, {4'hC, 3'd7}, {4'h6, 3'd1});
    // set B: other values, and fields swapped relative to A (a lum/col swap, or a COLUP mix-up, shows in one of the two)
    sweep("B", {4'hA, 3'd1}, {4'h5, 3'd6}, {4'h1, 3'd3}, {4'hE, 3'd4});
    // lum = D3-D1 and col = D7-D4 for single set bits of the selected register (background only, every bit; then each register alone)
    begin
      logic [5:0] none; none = 0;
      for (int b = 0; b < 7; b++) begin
        c0 = ~7'h0; c1 = 7'h0; cf = 7'h0; cb = 7'h1 << b;
        apply(none, 0, 0, 0, 0);
        chk($sformatf("T9 BK bit %0d: lum=D%0d.. col=D%0d..", b, (b < 3) ? b + 1 : -1, (b >= 3) ? b + 1 : -1), cb);
        if (b < 3) begin if (lum !== (3'd1 << b) || col !== 4'd0) begin errs++; $display("FAIL T9 BK bit %0d: lum=%0d col=%h", b, lum, col); end end
        else       begin if (col !== (4'd1 << (b-3)) || lum !== 3'd0) begin errs++; $display("FAIL T9 BK bit %0d: lum=%0d col=%h", b, lum, col); end end
        nchk++;
      end
    end
    // each register is routed through its own object (P0 alone, M0 alone, P1 alone, M1 alone, PF alone, BL alone) with all others 0
    c0 = 7'h5A; c1 = 7'h25; cf = 7'h7E; cb = 7'h0B;
    apply(6'b100000, 0, 0, 0, 0); chk("T9 P0 alone", c0);
    apply(6'b010000, 0, 0, 0, 0); chk("T9 M0 alone", c0);
    apply(6'b001000, 0, 0, 0, 0); chk("T9 P1 alone", c1);
    apply(6'b000100, 0, 0, 0, 0); chk("T9 M1 alone", c1);
    apply(6'b000010, 0, 0, 0, 0); chk("T9 PF alone", cf);
    apply(6'b000001, 0, 0, 0, 0); chk("T9 BL alone", cf);
    apply(6'b000000, 0, 0, 0, 0); chk("T9 none", cb);
    // blk with an all-ones register set still gives 0 (not just "0 register")
    c0 = 7'h7f; c1 = 7'h7f; cf = 7'h7f; cb = 7'h7f; apply(6'b000000, 0, 0, 0, 1); chk("T9 blk, BK all ones", 7'h00);
    apply(6'b111111, 1, 1, 1, 1); chk("T9 blk, everything on", 7'h00);
    // blk 1 -> 0 releases to the colour in the same evaluation (combinational, no memory)
    apply(6'b000010, 0, 0, 0, 1); chk("T9 blk before release", 7'h00);
    blk = 0; #1; chk("T9 blk released", cf);
    $display("INFO %0d open-case inputs reported (not asserted), %0d checks", nrep, nchk);
    if (errs == 0) $display("PASS: %0d checks", nchk); else $display("FAIL: %0d of %0d checks", errs, nchk);
    $finish;
  end
endmodule
