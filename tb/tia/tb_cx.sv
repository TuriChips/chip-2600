// Testbench T7, T8, read map: tia_cx, tia_inpt, tia_rd. Spec: docs/spec.md 6.1 (read map), 6.7, 6.8.
// Expected values come from the spec and the issue's port contract (chip-2600#28), never from the RTL.
// cx packing (issue #28): cx[14:0] = {M0P D7, D6, M1P D7, D6, P0FB D7, D6, P1FB D7, D6, M0FB D7, D6, M1FB D7, D6, BLPF D7, PPMM D7, D6}.
// Open spec point: CXBLPF D6 (6.1 [check]): only D7 and d_oe[1] are tested at address 6.
`timescale 1ns/1ps
module tb_cx;
  logic clk = 0, rst = 0;
  always #5 clk = ~clk;
  int errs = 0, nchk = 0;
  task automatic chk(input string name, input logic [31:0] got, input logic [31:0] exp);
    nchk++;
    if (got !== exp) begin errs++; $display("FAIL %s: got 0x%0h expected 0x%0h", name, got, exp); end
  endtask

  // ---------- tia_cx
  logic p0, p1, m0, m1, bl, pf, vblank_d1, en, cxclr;
  wire [14:0] cx;
  tia_cx cxd (.clk(clk), .rst(rst), .p0(p0), .p1(p1), .m0(m0), .m1(m1), .bl(bl), .pf(pf), .vblank(vblank_d1), .en(en), .cxclr(cxclr), .cx(cx));
  // pair table, cx index -> the two objects, in read-map order (6.1): index 14 = CXM0P D7 = M0.P1 ... index 0 = CXPPMM D6 = M0.M1
  // objects: 0 P0, 1 P1, 2 M0, 3 M1, 4 BL, 5 PF
  function automatic int pa(input int i);
    case (i)
      0: return 2;
      1: return 2;
      2: return 3;
      3: return 3;
      4: return 0;
      5: return 0;
      6: return 1;
      7: return 1;
      8: return 2;
      9: return 2;
      10: return 3;
      11: return 3;
      12: return 4;
      13: return 0;
      14: return 2;
    endcase
    return 0;
  endfunction
  function automatic int pb(input int i);
    case (i)
      0: return 1;
      1: return 0;
      2: return 0;
      3: return 1;
      4: return 5;
      5: return 4;
      6: return 5;
      7: return 4;
      8: return 5;
      9: return 4;
      10: return 5;
      11: return 4;
      12: return 5;
      13: return 1;
      14: return 3;
    endcase
    return 0;
  endfunction
  task automatic drive(input logic [5:0] o);   // o[k] = object k
    {pf, bl, m1, m0, p1, p0} = {o[5], o[4], o[3], o[2], o[1], o[0]};
  endtask
  task automatic cxtick(input logic [5:0] o, input logic vb, input logic e, input logic c);
    @(negedge clk); drive(o); vblank_d1 = vb; en = e; cxclr = c;
    @(posedge clk); #1;
  endtask
  task automatic cxclear;
    cxtick(0, 0, 0, 1); cxtick(0, 0, 0, 0);
  endtask
  function automatic logic [14:0] pairmask(input logic [5:0] o);   // all pairs both of whose objects are in o
    logic [14:0] r = 0;
    for (int k = 0; k < 15; k++) r[14-k] = o[pa(k)] & o[pb(k)];
    return r;
  endfunction
  // index i in the list above counts from the left, bit = 14 - i
  function automatic logic [14:0] onepair(input int i);
    logic [14:0] r = 0; r[14-i] = 1; return r;
  endfunction

  // ---------- tia_inpt
  logic [5:0] pin; logic [2:0] vb3;   // {D7, D6, D1}
  wire [5:0] inpt;
  tia_inpt ipd (.clk(clk), .rst(rst), .inpt_pin(pin), .vblank(vb3), .inpt(inpt));
  task automatic itick(input logic [5:0] p, input logic [2:0] v);
    @(negedge clk); pin = p; vb3 = v; @(posedge clk); #1;
  endtask

  // ---------- tia_rd
  logic [3:0] ra; logic [14:0] rcx; logic [5:0] rin;
  wire [1:0] d_out, d_oe;
  tia_rd rdd (.clk(clk), .rst(rst), .a(ra), .cx(rcx), .inpt(rin), .d_out(d_out), .d_oe(d_oe));

  logic [14:0] exp;
  logic [5:0] o;
  int e;
  initial begin
    p0=0;p1=0;m0=0;m1=0;bl=0;pf=0;vblank_d1=0;en=0;cxclr=0; pin=6'h3f; vb3=0; ra=0; rcx=0; rin=0;
    rst = 1; repeat (3) @(posedge clk); #1; rst = 0;
    // ===== T7
    chk("T7 after rst cx = 0", cx, 0);
    for (int i = 0; i < 15; i++) begin   // each pair alone: its own bit, and no other
      o = 0; o[pa(i)] = 1; o[pb(i)] = 1;
      cxclear();
      cxtick(o, 0, 1, 0);
      chk($sformatf("T7 pair %0d (%0d.%0d) sets its own bit only", i, pa(i), pb(i)), cx, onepair(i) | pairmask(o));
      chk($sformatf("T7 pair %0d: exactly the pairs of the objects present", i), cx, pairmask(o));
      cxtick(0, 0, 1, 0); chk($sformatf("T7 pair %0d holds after outputs drop", i), cx, pairmask(o));
    end
    // exactly 2 objects: own bit alone
    for (int i = 0; i < 15; i++) begin
      o = 0; o[pa(i)] = 1; o[pb(i)] = 1; cxclear(); cxtick(o, 0, 1, 0);
      chk($sformatf("T7 pair %0d two objects: only bit %0d", i, 14-i), cx, onepair(i));
    end
    // a single object, or none, sets nothing
    for (int k = 0; k < 6; k++) begin cxclear(); cxtick(6'b1 << k, 0, 1, 0); chk($sformatf("T7 object %0d alone sets nothing", k), cx, 0); end
    cxclear(); cxtick(0, 0, 1, 0); chk("T7 no object sets nothing", cx, 0);
    // all six: all 15
    cxclear(); cxtick(6'h3f, 0, 1, 0); chk("T7 all six objects set all 15", cx, 15'h7fff);
    // en = 0: no set
    cxclear(); cxtick(6'h3f, 0, 0, 0); cxtick(6'h3f, 0, 0, 0); chk("T7 en=0 sets nothing", cx, 0);
    // VBLANK D1 gate
    for (int i = 0; i < 15; i++) begin
      o = 0; o[pa(i)] = 1; o[pb(i)] = 1; cxclear(); cxtick(o, 1, 1, 0);
      chk($sformatf("T7 pair %0d blocked by VBLANK D1=1", i), cx, 0);
    end
    cxclear(); cxtick(6'h3f, 1, 1, 0); cxtick(6'h3f, 1, 1, 0); chk("T7 all six blocked while VBLANK D1=1, 2 clocks", cx, 0);
    cxtick(6'h3f, 0, 1, 0); chk("T7 set again when VBLANK D1 drops", cx, 15'h7fff);
    // the gate does not clear what is already set
    cxtick(0, 1, 1, 0); chk("T7 VBLANK D1=1 does not clear set bits", cx, 15'h7fff);
    // no other gating: many set clocks with VBLANK D1=0 over a long run (no HBLANK input exists; the set depends on vblank and en only)
    cxclear(); for (int c = 0; c < 228; c++) cxtick((c % 7 == 3) ? 6'b110000 : 6'b000000, 0, 1, 0);
    chk("T7 BL.PF set at any colour clock when VBLANK D1=0 (228 clocks)", cx, onepair(12));
    // CXCLR
    cxtick(6'h3f, 0, 1, 0); chk("T7 pre CXCLR all set", cx, 15'h7fff);
    cxtick(0, 0, 0, 1); chk("T7 CXCLR clears all 15", cx, 0);
    cxtick(0, 0, 0, 0); chk("T7 stays clear", cx, 0);
    cxtick(6'h3f, 0, 1, 0); cxtick(0, 0, 1, 1); chk("T7 CXCLR clears with en=1", cx, 0);
    // CXCLR wins over a set on the same clk
    cxclear(); cxtick(6'h3f, 0, 1, 1); chk("T7 CXCLR wins over a set on the same clk (from clear)", cx, 0);
    cxtick(6'h3f, 0, 1, 0); cxtick(6'h3f, 0, 1, 1); chk("T7 CXCLR wins over a set on the same clk (from set)", cx, 0);
    cxtick(6'h3f, 0, 1, 0); chk("T7 set after CXCLR", cx, 15'h7fff);
    // random vs model
    begin
      logic [14:0] m; logic [5:0] r; logic v, ee, cc; m = 0;
      cxclear();
      for (int n = 0; n < 5000; n++) begin
        r = $urandom; v = ($urandom % 4 == 0); ee = ($urandom % 3 != 0); cc = ($urandom % 9 == 0);
        if (cc) m = 0; else if (ee && !v) m |= pairmask(r);
        cxtick(r, v, ee, cc);
        if (cx !== m) begin errs++; nchk++; $display("FAIL T7 random clk %0d: got 0x%0h expected 0x%0h", n, cx, m); n = 5000; end
      end
      nchk++;
    end

    // ===== T8
    // I0-I3: pin, forced to 0 while D7 = 1
    for (int n = 0; n < 4; n++) begin
      itick(6'h3f, 3'b000); chk($sformatf("T8 I%0d follows pin 1", n), inpt[n], 1);
      itick(6'h3f & ~(6'b1 << n), 3'b000); chk($sformatf("T8 I%0d follows pin 0", n), inpt[n], 0);
      chk($sformatf("T8 I%0d: other inputs unaffected by pin %0d", n, n), inpt, 6'h3f & ~(6'b1 << n));
      itick(6'h3f, 3'b100); chk($sformatf("T8 I%0d reads 0 while VBLANK D7=1 (pin 1)", n), inpt[n], 0);
      itick(6'h3f, 3'b101); chk($sformatf("T8 I%0d reads 0 while D7=1, D1=1", n), inpt[n], 0);
      itick(6'h3f, 3'b000); chk($sformatf("T8 I%0d reads pin again after D7=0", n), inpt[n], 1);
      itick(6'h3f, 3'b010); chk($sformatf("T8 I%0d not affected by D6", n), inpt[n], 1);
      itick(6'h3f & ~(6'b1 << n), 3'b010); chk($sformatf("T8 I%0d D6=1 pin 0 reads 0 (transparent)", n), inpt[n], 0);
      itick(6'h3f, 3'b010); chk($sformatf("T8 I%0d D6=1 pin back to 1 reads 1 (no latch)", n), inpt[n], 1);
      itick(6'h3f, 3'b001); chk($sformatf("T8 I%0d not affected by D1", n), inpt[n], 1);
    end
    itick(6'h3f, 3'b100); chk("T8 D7=1: I0-I3 = 0, I4-I5 unaffected by D7", inpt, 6'b110000);
    itick(6'h00, 3'b100); chk("T8 D7=1 pin 0: all 0", inpt, 0);
    // I4-I5 transparent with D6=0
    for (int n = 4; n < 6; n++) begin
      itick(6'h3f, 3'b000); chk($sformatf("T8 I%0d D6=0 pin 1", n), inpt[n], 1);
      itick(6'h3f & ~(6'b1 << n), 3'b000); chk($sformatf("T8 I%0d D6=0 pin 0", n), inpt[n], 0);
      itick(6'h3f, 3'b000); chk($sformatf("T8 I%0d D6=0 pin back to 1", n), inpt[n], 1);
      // latch
      itick(6'h3f, 3'b010); chk($sformatf("T8 I%0d D6=1 pin 1 reads 1", n), inpt[n], 1);
      itick(6'h3f & ~(6'b1 << n), 3'b010); chk($sformatf("T8 I%0d D6=1 pin pulses 0: reads 0", n), inpt[n], 0);
      itick(6'h3f, 3'b010); chk($sformatf("T8 I%0d D6=1 pin back to 1: latched 0", n), inpt[n], 0);
      itick(6'h3f, 3'b010); itick(6'h3f, 3'b010); chk($sformatf("T8 I%0d stays latched 0", n), inpt[n], 0);
      chk($sformatf("T8 I%0d latch does not touch the other I4/I5 (pin 1)", n), inpt[9-n], 1);
      itick(6'h3f, 3'b011); chk($sformatf("T8 I%0d D1 change does not release the latch", n), inpt[n], 0);
      itick(6'h3f, 3'b000); chk($sformatf("T8 I%0d D6=0 reads pin again (1)", n), inpt[n], 1);
      itick(6'h3f, 3'b010); chk($sformatf("T8 I%0d D6=1 again: latch was reset to 1", n), inpt[n], 1);
      itick(6'h3f & ~(6'b1 << n), 3'b010); itick(6'h3f, 3'b010); chk($sformatf("T8 I%0d latches 0 a second time", n), inpt[n], 0);
      itick(6'h3f & ~(6'b1 << n), 3'b000); chk($sformatf("T8 I%0d D6=0 pin 0 reads pin (0)", n), inpt[n], 0);
      itick(6'h3f, 3'b000); chk($sformatf("T8 I%0d D6=0 pin 1 reads 1", n), inpt[n], 1);
    end
    // both latches independent
    itick(6'h3f, 3'b000); itick(6'h3f, 3'b010); itick(6'b101111, 3'b010); itick(6'h3f, 3'b010);
    chk("T8 I4 latched, I5 not", inpt[5:4], 2'b10);
    itick(6'b011111, 3'b010); itick(6'h3f, 3'b010); chk("T8 both latched", inpt[5:4], 2'b00);
    itick(6'h3f, 3'b000); chk("T8 D6=0 releases both", inpt, 6'h3f);
    // D6=1 while D7=1 (both): I0-I3 still 0, I4/I5 latch
    itick(6'h3f, 3'b110); chk("T8 D7=1 D6=1: I0-I3 0, I4-I5 follow pin", inpt, 6'b110000);

    // ===== read map (6.1), tia_rd. d_out lines checked only where d_oe is 1.
    begin
      // read-map table: address -> pair index (list order above, counted from the left in cx[14:0]) for D7 and D6, -1 = not driven / not tested
      int d7i [8]; int d6i [8];
      d7i[0]=0;d7i[1]=2;d7i[2]=4;d7i[3]=6;d7i[4]=8;d7i[5]=10;d7i[6]=12;d7i[7]=13;
      d6i[0]=1;d6i[1]=3;d6i[2]=5;d6i[3]=7;d6i[4]=9;d6i[5]=11;d6i[6]=-1;d6i[7]=14;
      //     // M0.P1, M1.P0, P0.PF, P1.PF, M0.PF, M1.PF, BL.PF, P0.P1
      //     // M0.P0, M1.P1, P0.BL, P1.BL, M0.BL, M1.BL, open, M0.M1
      for (int a = 0; a < 16; a++) begin
        ra = a; rin = 6'b0; rcx = 0; #1;
        if (a < 8) chk($sformatf("RD $%0x d_oe[1] (D7 driven)", a), d_oe[1], 1);
        if (a < 8 && a != 6) chk($sformatf("RD $%0x d_oe[0] (D6 driven)", a), d_oe[0], 1);
        if (a >= 8 && a < 14) begin chk($sformatf("RD $%0x INPT d_oe = D7 only", a), d_oe, 2'b10); end
        if (a >= 14) chk($sformatf("RD $%0x drives nothing", a), d_oe, 2'b00);
        // all zeros: driven lines read 0
        if (a < 8) begin chk($sformatf("RD $%0x D7 = 0 with cx = 0", a), d_out[1], 0); if (a != 6) chk($sformatf("RD $%0x D6 = 0 with cx = 0", a), d_out[0], 0); end
        // walking-1 on cx: only the mapped bit shows
        if (a < 8) for (int i = 0; i < 15; i++) begin
          rcx = 15'b1 << (14 - i); #1;
          chk($sformatf("RD $%0x cx index %0d: D7", a, i), d_out[1], (d7i[a] == i));
          if (a != 6) chk($sformatf("RD $%0x cx index %0d: D6", a, i), d_out[0], (d6i[a] == i));
          chk($sformatf("RD $%0x cx index %0d: d_oe[1]", a, i), d_oe[1], 1);
        end
        // inputs do not leak into collision reads
        if (a < 8) begin rcx = 0; rin = 6'h3f; #1; chk($sformatf("RD $%0x inpt does not reach D7", a), d_out[1], 0); if (a != 6) chk($sformatf("RD $%0x inpt does not reach D6", a), d_out[0], 0); end
        // INPT: D7 = inpt[a-8]
        if (a >= 8 && a < 14) for (int n = 0; n < 6; n++) begin
          rcx = 0; rin = 6'b1 << n; #1; chk($sformatf("RD $%0x walking-1 inpt %0d D7", a, n), d_out[1], (n == a - 8));
          rcx = 15'h7fff; rin = ~(6'b1 << n); #1; chk($sformatf("RD $%0x walking-0 inpt %0d D7 (cx all ones)", a, n), d_out[1], (n != a - 8));
        end
        if (a >= 14) begin rcx = 15'h7fff; rin = 6'h3f; #1; chk($sformatf("RD $%0x drives nothing with everything set", a), d_oe, 2'b00); end
        // d_oe independent of data
        if (a < 8) begin rcx = 15'h7fff; rin = 6'h3f; #1; chk($sformatf("RD $%0x d_oe[1] with data set", a), d_oe[1], 1); end
        if (a >= 8 && a < 14) begin rcx = 15'h7fff; rin = 6'h3f; #1; chk($sformatf("RD $%0x d_oe with data set", a), d_oe, 2'b10); end
      end
    end
    if (errs == 0) $display("PASS (%0d checks)", nchk); else $display("FAIL: %0d of %0d checks", errs, nchk);
    $finish;
  end
endmodule
