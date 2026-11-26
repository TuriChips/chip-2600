// Testbench for m6532 (MOS 6532 RIOT). Spec: docs/spec.md sections 2.2, 7, 8.2 R1-R3.
// Expected values come from the spec only, never from the RTL or from ref/.
// Pulse numbering (spec 7.2): the timer write cycle is pulse 0; a read k cycles later is pulse k.
// d_out is sampled during the cycle (before the Phi2 edge); irq_n and ports are sampled after it.
// "REPORT" lines record what the RTL does for spec [check] items. Nothing is asserted on them.
// A failed check prints "FAIL ..."; the run ends with "PASS" or "FAIL: <n> of <m> checks".
`timescale 1ns/1ps
module tb;
  logic        clk = 0, ce = 1, res_n = 1;
  logic        cs1 = 0, cs2_n = 1, rs_n = 1, rw = 1;
  logic [6:0]  a = 0;
  logic [7:0]  d_in = 0;
  wire  [7:0]  d_out;
  wire         d_oe;
  logic [7:0]  pa_ext = 8'hFF, pb_ext = 8'hFF;   // outside-world levels on input pins
  bit          pa_force_en = 0, pb_force_en = 0; // an outside driver that overpowers an output pin
  logic [7:0]  pa_force = 0, pb_force = 0;
  wire  [7:0]  pa_out, pa_ddr, pb_out, pb_ddr;
  wire         irq_n;
  // the testbench resolves pin levels (spec 2.2, 7.3)
  wire  [7:0]  pa_in = pa_force_en ? pa_force : ((pa_out & pa_ddr) | (pa_ext & ~pa_ddr));
  wire  [7:0]  pb_in = pb_force_en ? pb_force : ((pb_out & pb_ddr) | (pb_ext & ~pb_ddr));

  m6532 dut (.clk(clk), .ce(ce), .res_n(res_n), .cs1(cs1), .cs2_n(cs2_n), .rs_n(rs_n),
             .rw(rw), .a(a), .d_in(d_in), .d_out(d_out), .d_oe(d_oe),
             .pa_in(pa_in), .pa_out(pa_out), .pa_ddr(pa_ddr),
             .pb_in(pb_in), .pb_out(pb_out), .pb_ddr(pb_ddr), .irq_n(irq_n));

  int          errs = 0, nchk = 0, cycles = 0, pulse = 0;
  bit          verbose = 1;
  logic [7:0]  rd;      // d_out sampled in the last bus cycle
  logic        oe;      // d_oe sampled in the last bus cycle
  logic        irq;     // irq_n sampled after the last cycle

  task automatic chk(input string name, input int got, input int exp);
    nchk++;
    if (got !== exp) begin
      errs++;
      $display("FAIL %s: got 0x%0h expected 0x%0h (cycle %0d, pulse %0d)", name, got, exp, cycles, pulse);
    end else if (verbose) $display("ok   %s = 0x%0h", name, got);
  endtask

  // ------------------------------------------------------------ one Phi2 cycle, general
  task automatic cyc4(input logic c1, input logic c2n, input logic rsn, input logic rwi,
                      input logic [6:0] ad, input logic [7:0] dd);
    cs1 = c1; cs2_n = c2n; rs_n = rsn; rw = rwi; a = ad; d_in = dd; ce = 1;
    #1;
    rd = d_out; oe = d_oe;
    if (verbose) $display("cyc %0d p%0d cs1=%b cs2_n=%b rs_n=%b rw=%b a=%02h din=%02h | dout=%02h oe=%b irq_n=%b pa=%02h/%02h pb=%02h/%02h",
                          cycles, pulse, c1, c2n, rsn, rwi, ad, dd, d_out, d_oe, irq_n, pa_out, pa_ddr, pb_out, pb_ddr);
    clk = 1; #1; clk = 0; #1;
    irq = irq_n;
    cycles++; pulse++;
  endtask
  task automatic wr(input logic rsn, input logic [6:0] ad, input logic [7:0] dd); cyc4(1, 0, rsn, 0, ad, dd); endtask
  task automatic rdb(input logic rsn, input logic [6:0] ad); cyc4(1, 0, rsn, 1, ad, 8'h00); endtask
  task automatic nop(); cyc4(0, 0, 1, 1, 7'h00, 8'h00); endtask   // deselected; the timer still sees the pulse
  task automatic idle(input int n);
    bit v;
    v = verbose;
    if (n > 0) begin
      if (v) $display("idle %0d cycles (pulses %0d..%0d)", n, pulse, pulse + n - 1);
      verbose = 0; repeat (n) nop(); verbose = v;
    end
  endtask
  task automatic goto_pulse(input int k); if (k > pulse) idle(k - pulse); endtask   // next cycle is pulse k

  // ------------------------------------------------------------ register helpers (spec 7.1)
  localparam logic [6:0] A_ORA = 7'h00, A_DDRA = 7'h01, A_ORB = 7'h02, A_DDRB = 7'h03,
                         A_INTIM = 7'h04, A_FLAGS = 7'h05;
  task automatic wio(input logic [6:0] ad, input logic [7:0] dd); wr(1, ad, dd); endtask
  task automatic rio(input logic [6:0] ad); rdb(1, ad); endtask
  function automatic logic [6:0] a_timer(input int sel, input bit ien);
    logic [1:0] s;
    s = sel[1:0];
    return {2'b00, 1'b1, ien, 1'b1, s};   // A4=1, A3=irq enable, A2=1, A1A0=divide select
  endfunction
  function automatic int divisor(input int sel);
    return (sel == 0) ? 1 : (sel == 1) ? 8 : (sel == 2) ? 64 : 1024;
  endfunction
  task automatic tim_write(input int n, input int sel, input bit ien);   // this cycle is pulse 0
    pulse = 0; wio(a_timer(sel, ien), n[7:0]);
  endtask
  task automatic pa7_ctl(input bit en, input bit pos);   // A4=0, A2=1, A1=IRQ enable, A0=edge (0 = negative)
    wio({4'b0000, 1'b1, en, pos}, 8'h00);
  endtask
  // expected INTIM at pulse k >= 1 (spec 7.2)
  function automatic int intim_exp(input int n, input int d, input int k);
    if (k <= n * d) return n - ((k - 1) / d) - 1;
    return (8'hFF - (k - n * d - 1)) & 8'hFF;
  endfunction
  task automatic hw_reset();
    bit v;
    v = verbose; verbose = 0;
    res_n = 0; repeat (3) nop(); res_n = 1; repeat (2) nop(); verbose = v;
  endtask
  // the spec leaves timer and flags unreset (2.2): put them in a known quiet state (timer IRQ off, flag clear)
  task automatic quiet_timer(); bit v; v = verbose; verbose = 0; tim_write(255, 3, 0); verbose = v; endtask
  logic irq_s;   // irq_n as it stood at the end of the last settle(), before any flag-register read
  task automatic settle(); bit v; v = verbose; verbose = 0; repeat (3) nop(); verbose = v; irq_s = irq; endtask

  // ------------------------------------------------------------ R1: RAM
  function automatic logic [7:0] rpat(input int pat, input int i);
    logic [7:0] b;
    b = 8'(i * 3 + 8'h5A);
    case (pat) 0: return b; 1: return ~b; default: return 8'(i); endcase
  endfunction
  task automatic r1_ram();
    $display("== R1 RAM");
    verbose = 0;
    for (int pat = 0; pat < 3; pat++) begin
      for (int i = 0; i < 128; i++) wr(0, 7'(i), rpat(pat, i));
      for (int i = 0; i < 128; i++) begin
        rdb(0, 7'(i));
        chk($sformatf("R1 ram[%0d] pattern %0d", i, pat), rd, rpat(pat, i));
        chk($sformatf("R1 ram[%0d] d_oe on read", i), oe, 1);
      end
    end
    // aliasing: set one cell to FF in a zeroed RAM, every cell must read back 0 except that one
    for (int i = 0; i < 128; i++) wr(0, 7'(i), 8'h00);
    for (int i = 0; i < 128; i += 9) begin
      wr(0, 7'(i), 8'hFF);
      for (int j = 0; j < 128; j++) begin
        rdb(0, 7'(j));
        chk($sformatf("R1 ram alias: [%0d]=FF, read [%0d]", i, j), rd, (i == j) ? 8'hFF : 8'h00);
      end
      wr(0, 7'(i), 8'h00);
    end
    // not selected: writes ignored, bus not driven (spec 2.2: selected when CS1=1 and CS2=0)
    wr(0, 7'h11, 8'hA1);
    cyc4(0, 0, 0, 0, 7'h11, 8'h22);
    cyc4(1, 1, 0, 0, 7'h11, 8'h33);
    cyc4(0, 1, 0, 0, 7'h11, 8'h44);
    rdb(0, 7'h11); chk("R1 ram unselected writes ignored", rd, 8'hA1);
    cyc4(0, 0, 0, 1, 7'h11, 8'h00); chk("R1 d_oe=0 with CS1=0", oe, 0);
    cyc4(1, 1, 0, 1, 7'h11, 8'h00); chk("R1 d_oe=0 with CS2_n=1", oe, 0);
    wr(0, 7'h11, 8'h00); chk("R1 d_oe=0 on a write", oe, 0);
    verbose = 1;
  endtask

  // ------------------------------------------------------------ R1: ports and DDRs
  localparam logic [7:0] PATS [4] = '{8'h00, 8'hFF, 8'h5A, 8'hA5};
  localparam logic [6:0] MIR  [3] = '{7'h08, 7'h10, 7'h18};
  task automatic r1_ports();
    $display("== R1 ports, DDRs, port B read rule");
    hw_reset();
    for (int i = 0; i < 4; i++) begin
      wio(A_DDRA, PATS[i]); rio(A_DDRA); chk("R1 DDRA read-back", rd, PATS[i]); chk("R1 pa_ddr pins", pa_ddr, PATS[i]);
      wio(A_DDRB, ~PATS[i]); rio(A_DDRB); chk("R1 DDRB read-back", rd, ~PATS[i] & 8'hFF); chk("R1 pb_ddr pins", pb_ddr, ~PATS[i] & 8'hFF);
    end
    // ORA/ORB store all 8 bits whatever the direction (spec 7.3), seen when the pins are turned to outputs
    wio(A_DDRA, 8'h00); wio(A_DDRB, 8'h00);
    wio(A_ORA, 8'hC3); wio(A_ORB, 8'h3C);
    wio(A_DDRA, 8'hFF); wio(A_DDRB, 8'hFF);
    chk("R1 ORA stored while DDRA=0 (pa_out)", pa_out, 8'hC3);
    chk("R1 ORB stored while DDRB=0 (pb_out)", pb_out, 8'h3C);
    for (int i = 0; i < 4; i++) begin
      wio(A_ORA, PATS[i]); chk("R1 pa_out follows ORA write", pa_out, PATS[i]);
      wio(A_ORB, PATS[i]); chk("R1 pb_out follows ORB write", pb_out, PATS[i]);
    end
    // Port A read returns the PIN (spec 7.3), also on output bits
    wio(A_DDRA, 8'hFF); wio(A_ORA, 8'hAA);
    rio(A_ORA); chk("R1 port A read, all outputs, pin = OR", rd, 8'hAA);
    pa_force_en = 1; pa_force = 8'h55;
    rio(A_ORA); chk("R1 port A read returns pin (55), not OR (AA), on output bits", rd, 8'h55);
    pa_force_en = 0;
    wio(A_DDRA, 8'h0F); wio(A_ORA, 8'h0A); pa_ext = 8'hB6;
    rio(A_ORA); chk("R1 port A mixed: inputs B_, outputs _A", rd, 8'hBA);
    // Port B read returns ORB on output bits even when the pin disagrees, pins on input bits
    wio(A_DDRB, 8'hF0); wio(A_ORB, 8'hA5); pb_ext = 8'h69;
    pb_force_en = 1; pb_force = 8'h5A;
    rio(A_ORB); chk("R1 port B read: output bits from ORB (A), input bits from pins (A)", rd, 8'hAA);
    pb_force_en = 0;
    rio(A_ORB); chk("R1 port B read, no conflict", rd, 8'hA9);
    wio(A_DDRB, 8'h00); pb_ext = 8'h96; rio(A_ORB); chk("R1 port B read, all inputs", rd, 8'h96);
    wio(A_DDRB, 8'hFF); pb_force_en = 1; pb_force = 8'h00; rio(A_ORB);
    chk("R1 port B read, all outputs, pins forced to 00: still ORB", rd, 8'hA5);
    pb_force_en = 0;
    // A4/A3 are don't-care for the port registers (spec 7.1 table)
    for (int i = 0; i < 3; i++) begin
      wio(A_DDRB, 8'h00);
      wio(A_DDRB | MIR[i], 8'hFF); rio(A_DDRB); chk($sformatf("R1 DDRB written via +%02h", MIR[i]), rd, 8'hFF);
      wio(A_ORB | MIR[i], 8'hE1);  rio(A_ORB | MIR[i]); chk($sformatf("R1 ORB written/read via +%02h", MIR[i]), rd, 8'hE1);
      rio(A_DDRB | MIR[i]); chk($sformatf("R1 DDRB read via +%02h", MIR[i]), rd, 8'hFF);
      wio(A_DDRA | MIR[i], 8'h3C); rio(A_DDRA); chk($sformatf("R1 DDRA via +%02h", MIR[i]), rd, 8'h3C);
    end
    // write to one register leaves the others alone
    wio(A_DDRA, 8'hFF); wio(A_DDRB, 8'hFF); wio(A_ORA, 8'h12); wio(A_ORB, 8'h34);
    wio(A_ORA, 8'h56);
    chk("R1 ORA write leaves ORB", pb_out, 8'h34); chk("R1 ORA write leaves DDRA", pa_ddr, 8'hFF);
  endtask

  // ------------------------------------------------------------ R1: res_n (spec 2.2)
  task automatic r1_reset();
    $display("== R1 res_n");
    // state to be zeroed
    wio(A_DDRA, 8'hFF); wio(A_DDRB, 8'hFF); wio(A_ORA, 8'h5A); wio(A_ORB, 8'hA5);
    wr(0, 7'h20, 8'hC7);                // RAM, must survive
    pa7_ctl(1, 1);                      // positive edge, enabled: reset must select negative, disabled
    tim_write(200, 2, 1);               // timer, must keep counting
    res_n = 0; cyc4(0, 0, 1, 1, 7'h00, 8'h00);
    chk("R1 res_n=0: d_oe floats", d_oe, 0);
    cyc4(1, 0, 1, 1, A_ORA, 8'h00); chk("R1 res_n=0 held, read of ORA: d_oe still 0", oe, 0);
    nop(); res_n = 1; nop();
    chk("R1 reset: pa_ddr = 0", pa_ddr, 0);
    chk("R1 reset: pb_ddr = 0", pb_ddr, 0);
    rio(A_DDRA); chk("R1 reset: DDRA reads 0", rd, 0);
    rio(A_DDRB); chk("R1 reset: DDRB reads 0", rd, 0);
    wio(A_DDRA, 8'hFF); wio(A_DDRB, 8'hFF);
    chk("R1 reset: ORA = 0 (pa_out)", pa_out, 0);
    chk("R1 reset: ORB = 0 (pb_out)", pb_out, 0);
    rdb(0, 7'h20); chk("R1 reset leaves RAM (spec Decision)", rd, 8'hC7);
    // timer not reset: the count continues from the write at pulse 0 (200, /64).
    // pulses so far since the write: use `pulse`
    begin
      int k;
      k = pulse;                       // the next cycle is pulse k
      rio(A_INTIM);
      chk("R1 reset leaves timer running (INTIM follows the write)", rd, intim_exp(200, 64, k));
    end
    // PA7: negative edge and interrupt disabled after reset
    pa_ext = 8'hFF; wio(A_DDRA, 8'h00); settle();
    rio(A_FLAGS);                       // clear any PA7 flag
    pa_ext = 8'h7F; settle(); rio(A_FLAGS);
    chk("R1 reset: PA7 falling edge sets the flag (negative edge selected)", rd[6], 1);
    chk("R1 reset: PA7 interrupt disabled, irq_n stays high", irq, 1);
    rio(A_FLAGS);
    pa_ext = 8'hFF; settle(); rio(A_FLAGS);
    chk("R1 reset: PA7 rising edge does not set the flag", rd[6], 0);
  endtask

  // ------------------------------------------------------------ R2: timer
  // Flag helper: read the flag register (does not touch the timer flag, spec 7.2), return D7
  task automatic read_flags(output int tf, output int pf);
    rio(A_FLAGS); tf = rd[7]; pf = rd[6];
    chk("R2 flag register D5-D0 read 0", rd & 8'h3F, 0);
  endtask

  task automatic r2_values(input int n, input int sel);
    int d, nd, ks[12];
    d = divisor(sel); nd = n * d;
    // INTIM reads at ascending pulses <= N*D+1 in one run (a read at or before N*D+1 does not disturb the timer)
    ks = '{1, 2, d, d + 1, d + 2, nd / 2 + 1, nd - 1, nd, nd + 1, 0, 0, 0};
    $display("== R2 values N=%0d /%0d (N*D=%0d)", n, d, nd);
    hw_reset(); wio(A_DDRA, 8'h00);
    verbose = 0;
    tim_write(n, sel, 0);
    for (int i = 0; i < 9; i++) begin
      // reads past N*D+1 are left out: the read at N*D+2 ends the free-run (spec 7.2), and it has its own check below
      if (ks[i] >= pulse && ks[i] >= 1 && ks[i] <= nd + 1 && (i == 0 || ks[i] > ks[i-1])) begin
        goto_pulse(ks[i]);
        rio(A_INTIM);
        chk($sformatf("R2 N=%0d /%0d INTIM at pulse %0d", n, d, ks[i]), rd, intim_exp(n, d, ks[i]));
      end
    end
    verbose = 1;
    // pulse N*D+1: reads $FF and the flag stays set (spec 7.2 hardware evidence); then flag still set
    hw_reset(); verbose = 0;
    tim_write(n, sel, 0); goto_pulse(nd + 1); rio(A_INTIM);
    chk($sformatf("R2 N=%0d /%0d read on underflow pulse %0d returns FF", n, d, nd + 1), rd, 8'hFF);
    begin int tf, pf; read_flags(tf, pf);
      chk($sformatf("R2 N=%0d /%0d flag still set after read at underflow pulse", n, d), tf, 1); end
    // pulse N*D+2: value FE, read clears the flag
    hw_reset();
    tim_write(n, sel, 0); goto_pulse(nd + 2); rio(A_INTIM);
    chk($sformatf("R2 N=%0d /%0d read at N*D+2 returns FE", n, d), rd, 8'hFE);
    begin int tf, pf; read_flags(tf, pf);
      chk($sformatf("R2 N=%0d /%0d flag cleared by read at N*D+2", n, d), tf, 0); end
    // flag before and at underflow (flag register read, non-destructive)
    hw_reset();
    tim_write(n, sel, 0); goto_pulse(nd);
    begin int tf, pf; read_flags(tf, pf);
      chk($sformatf("R2 N=%0d /%0d flag clear at pulse N*D (%0d)", n, d, nd), tf, (nd == 0) ? 1 : 0); end
    begin int tf, pf; read_flags(tf, pf);
      chk($sformatf("R2 N=%0d /%0d flag set at pulse N*D+1", n, d), tf, 1); end
    verbose = 1;
  endtask

  task automatic r2_flag_clear();
    int tf, pf, k;
    $display("== R2 flag clear on write and on read, ce hold");
    hw_reset(); wio(A_DDRA, 8'h00);
    tim_write(5, 1, 0);                 // N=5, /8: underflow at pulse 41
    goto_pulse(60); read_flags(tf, pf); chk("R2 flag set after underflow", tf, 1);
    tim_write(100, 1, 0);               // write clears the flag
    read_flags(tf, pf); chk("R2 flag cleared by a timer write", tf, 0);
    goto_pulse(801); rio(A_INTIM); chk("R2 N=100 /8 at pulse 801 = FF", rd, 8'hFF);
    goto_pulse(810); rio(A_INTIM); chk("R2 N=100 /8 at pulse 810 (post-underflow, free-run)", rd, intim_exp(100, 8, 810));
    read_flags(tf, pf); chk("R2 flag cleared by INTIM read after underflow", tf, 0);
    idle(30); read_flags(tf, pf); chk("R2 flag stays cleared (no second underflow)", tf, 0);
    // timer write with A3 set or clear: both load the timer
    foreach (MIR[i]) begin
      tim_write(40, 1, MIR[i][3]); goto_pulse(10); rio(A_INTIM);
      chk($sformatf("R2 timer write via %02h loads N", a_timer(1, MIR[i][3])), rd, intim_exp(40, 8, 10));
    end
    // ce = 0 holds the timer: pulses count only when ce = 1
    tim_write(50, 0, 0); idle(10);
    ce = 0; repeat (200) begin #1; clk = 1; #1; clk = 0; #1; end
    k = pulse; rio(A_INTIM);
    chk("R2 ce=0 for 200 clocks does not advance the timer (/1, N=50)", rd, intim_exp(50, 1, k));
  endtask

  // Spec [check] items: report what the RTL does (turichips#48). Asserted only where spec 7.2 is settled.
  task automatic r2_checks();
    int j, d, n, js[8], v;
    $display("== R2 [check] items: report only");
    // /1 running past underflow: settled for the first 200 pulses, reported beyond
    js = '{0, 1, 100, 200, 255, 256, 257, 310};
    for (int i = 0; i < 8; i++) begin
      j = js[i]; n = 5;
      hw_reset(); verbose = 0;
      tim_write(n, 0, 0); goto_pulse(n + 1 + j); rio(A_INTIM); v = rd;
      begin int tf, pf; read_flags(tf, pf);
        $display("REPORT /1 N=5 pulse %0d (%0d past underflow): INTIM=0x%02h expected-by-5-formula=0x%02h flag=%0d",
                 n + 1 + j, j, v, (8'hFF - j) & 8'hFF, tf);
        if (j <= 200) chk($sformatf("R2 /1 free-run, %0d past underflow", j), v, (8'hFF - j) & 8'hFF);
      end
      verbose = 1;
    end
    // 300+ pulses past underflow with no read in between, reported as the flag register sees it
    for (int i = 0; i < 4; i++) begin
      int t[4];
      t = '{300, 311, 400, 520};
      hw_reset(); verbose = 0;
      tim_write(5, 0, 0); goto_pulse(6 + t[i]); rio(A_INTIM); v = rd;
      $display("REPORT /1 N=5 %0d past underflow: INTIM=0x%02h", t[i], v);
      verbose = 1;
    end
    // /D resumes after a post-underflow read: N=2, one read at N*D+2, then one more read j pulses later
    for (int si = 1; si <= 2; si++) begin
      d = divisor(si); n = 2;
      for (j = 1; j <= (si == 1 ? 20 : 70); j += (si == 1 ? 1 : 3)) begin
        hw_reset(); verbose = 0;
        tim_write(n, si, 0); goto_pulse(n * d + 2); rio(A_INTIM);
        chk("R2 resume setup: read at N*D+2 = FE", rd, 8'hFE);
        goto_pulse(n * d + 2 + j); rio(A_INTIM);
        $display("REPORT resume /%0d N=%0d: read at N*D+2 then at +%0d pulses: INTIM=0x%02h  (free-run would give 0x%02h)",
                 d, n, j, rd, (8'hFE - j) & 8'hFF);
        verbose = 1;
      end
    end
    // timer read at A3=1: does it change the timer IRQ enable? (spec 7.2 [check]); observe irq_n
    hw_reset(); verbose = 0;
    tim_write(3, 0, 1); goto_pulse(10);
    $display("REPORT irq_n after underflow with enable written via A3=1 write: %0b (expected 0)", irq);
    rio(A_INTIM | 7'h08);
    $display("REPORT after INTIM read via A3=1 address: flag cleared, irq_n=%0b", irq);
    // probes that tell the answers apart: the timer read happens BEFORE the underflow, so the read itself cannot
    // clear the flag later; irq_n after the underflow shows which A3 the enable came from
    hw_reset(); verbose = 0;
    tim_write(3, 0, 0); goto_pulse(2); rio(A_INTIM | 7'h08); goto_pulse(10);
    $display("REPORT irq_n after underflow: write A3=0, INTIM read at A3=1 before underflow: %0b (0 = the read set the enable)", irq);
    hw_reset();
    tim_write(3, 0, 1); goto_pulse(2); rio(A_INTIM); goto_pulse(10);
    $display("REPORT irq_n after underflow: write A3=1, INTIM read at A3=0 before underflow: %0b (1 = the read cleared the enable)", irq);
    hw_reset();
    tim_write(3, 0, 1); goto_pulse(2); rio(A_INTIM | 7'h08); goto_pulse(10);
    $display("REPORT irq_n after underflow: write A3=1, INTIM read at A3=1 before underflow: %0b (expected 0)", irq);
    verbose = 1;
  endtask


  // ------------------------------------------------------------ R1/R2: bus drive and address mirrors (spec 7.1)
  task automatic pa7_ctl_a(input bit a3, input bit en, input bit pos, input logic [7:0] dd);   // A4=0, A3 free
    wio({3'b000, a3, 1'b1, en, pos}, dd);
  endtask
  task automatic r1_bus_mirrors();
    int tf, pf;
    logic [6:0] ad;
    $display("== R1/R2 d_oe on I/O reads, A4 on writes, A1/A3/A4 mirrors on reads");
    hw_reset(); quiet_timer(); wio(A_DDRA, 8'h00);
    // d_oe: 1 on every selected read, 0 on every write
    rio(A_ORA);   chk("R1 d_oe=1 on ORA read", oe, 1);
    rio(A_DDRA);  chk("R1 d_oe=1 on DDRA read", oe, 1);
    rio(A_ORB);   chk("R1 d_oe=1 on ORB read", oe, 1);
    rio(A_DDRB);  chk("R1 d_oe=1 on DDRB read", oe, 1);
    rio(A_INTIM); chk("R2 d_oe=1 on INTIM read", oe, 1);
    rio(A_FLAGS); chk("R2 d_oe=1 on flag register read", oe, 1);
    rio(A_INTIM | 7'h18); chk("R2 d_oe=1 on INTIM read via A4,A3", oe, 1);
    wio(A_ORA, 8'h00);   chk("R1 d_oe=0 on ORA write", oe, 0);
    wio(A_DDRB, 8'h00);  chk("R1 d_oe=0 on DDRB write", oe, 0);
    tim_write(100, 1, 0); chk("R2 d_oe=0 on timer write", oe, 0);
    pa7_ctl(0, 0);       chk("R3 d_oe=0 on edge-control write", oe, 0);
    // A4=0 selects edge control, never the timer, whatever A3 and the data: INTIM keeps following the timer write
    for (int a3 = 0; a3 < 2; a3++) for (int dv = 0; dv < 2; dv++) for (int en = 0; en < 2; en++) for (int pos = 0; pos < 2; pos++) begin
      verbose = 0;
      tim_write(200, 3, 0); idle(3);
      pa7_ctl_a(a3[0], en[0], pos[0], dv ? 8'hFF : 8'h00);
      idle(2);
      pa7_ctl(0, 0);   // leave the edge control quiet for the next round
      rio(A_INTIM);
      chk($sformatf("R2 edge-control write (A3=%0d A1=%0d A0=%0d data=%0d) does not load the timer", a3, en, pos, dv),
          rd, intim_exp(200, 1024, pulse - 1));
      verbose = 1;
    end
    // timer reads: A1 and A4 (and A3) are don't-care (spec 7.1), same value, same side effect (flag cleared)
    for (int m = 0; m < 8; m++) begin
      ad = A_INTIM | {2'b00, m[2], m[1], 1'b0, m[0], 1'b0};   // m2 = A4, m1 = A3, m0 = A1
      verbose = 0;
      tim_write(3, 1, 0); goto_pulse(40);                      // underflow at pulse 25, flag set
      rio(A_FLAGS); tf = rd[7];
      chk($sformatf("R2 mirror setup %02h: timer flag set", ad), tf, 1);
      begin int k; k = pulse; rio(ad);
        chk($sformatf("R2 INTIM read via %02h value", ad), rd, intim_exp(3, 8, k));
        chk($sformatf("R2 INTIM read via %02h d_oe", ad), oe, 1); end
      read_flags(tf, pf);
      chk($sformatf("R2 INTIM read via %02h clears the timer flag", ad), tf, 0);
      verbose = 1;
    end
    // flag register reads: A1, A3, A4 are don't-care. Read returns both flags, clears the PA7 flag only.
    for (int m = 0; m < 8; m++) begin
      ad = A_FLAGS | {2'b00, m[2], m[1], 1'b0, m[0], 1'b0};
      verbose = 0;
      hw_reset(); wio(A_DDRA, 8'h00); pa_ext = 8'hFF; settle();
      pa7_ctl(0, 0); tim_write(3, 0, 0);
      pa_ext = 8'h7F; goto_pulse(20); settle();
      rio(ad);
      chk($sformatf("R2/R3 flag read via %02h: D7 timer, D6 PA7 both set", ad), rd, 8'hC0);
      chk($sformatf("R2/R3 flag read via %02h d_oe", ad), oe, 1);
      rio(A_FLAGS);
      chk($sformatf("R3 flag read via %02h cleared PA7 flag, kept timer flag", ad), rd, 8'h80);
      pa_ext = 8'hFF; settle();
      verbose = 1;
    end
  endtask

  // ------------------------------------------------------------ R3: PA7 and irq_n
  task automatic r3_pa7_input(input bit en, input bit pos);
    int tf, pf;
    $display("== R3 PA7 as input, enable=%0d edge=%s", en, pos ? "positive" : "negative");
    hw_reset(); quiet_timer(); wio(A_DDRA, 8'h00);
    pa_ext = pos ? 8'h7F : 8'hFF; settle();            // idle level = opposite of the active edge
    pa7_ctl(en, pos); settle(); rio(A_FLAGS);          // clears whatever the setup did
    read_flags(tf, pf);
    chk("R3 PA7 flag clear before the edge", pf, 0);
    chk("R3 irq_n high before the edge", irq, 1);
    // inactive edge first: must not set
    pa_ext = pos ? 8'hFF : 8'h7F; settle(); // that is the opposite of the idle level: it IS the active edge
    read_flags(tf, pf);
    chk("R3 PA7 active edge sets the flag", pf, 1);
    chk("R3 irq_n follows enable on active edge", irq_s, en ? 0 : 1);
    read_flags(tf, pf);
    chk("R3 flag register read clears the PA7 flag", pf, 0);
    chk("R3 irq_n high after the flag read", irq, 1);
    // inactive edge: back to idle level
    pa_ext = pos ? 8'h7F : 8'hFF; settle(); read_flags(tf, pf);
    chk("R3 PA7 inactive edge does not set the flag", pf, 0);
    chk("R3 irq_n high after inactive edge", irq, 1);
    // another active edge after clear sets again
    pa_ext = pos ? 8'hFF : 8'h7F; settle(); read_flags(tf, pf);
    chk("R3 second active edge sets the flag again", pf, 1);
    // other port A pins moving do not set it
    read_flags(tf, pf);
    pa_ext = pos ? 8'h7F : 8'hFF; settle(); read_flags(tf, pf);          // back to idle, flag cleared by the read
    pa_ext = pos ? 8'h3F : 8'hBF; settle(); pa_ext = pos ? 8'h40 : 8'hC0; settle();
    pa_ext = pos ? 8'h7F : 8'hFF; settle(); read_flags(tf, pf);   // PA6..PA0 moved, PA7 stayed at idle
    chk("R3 other pins toggling (PA7 at idle) leave the flag clear", pf, 0);
  endtask

  task automatic r3_pa7_output(input bit pos);
    int tf, pf;
    $display("== R3 PA7 as output, edge=%s", pos ? "positive" : "negative");
    hw_reset(); quiet_timer();
    wio(A_ORA, pos ? 8'h00 : 8'h80); wio(A_DDRA, 8'h80);     // PA7 is an output at its idle level
    pa7_ctl(1, pos); settle(); rio(A_FLAGS);
    read_flags(tf, pf); chk("R3 PA7 output: flag clear before toggle", pf, 0);
    wio(A_ORA, pos ? 8'h80 : 8'h00); settle();
    read_flags(tf, pf); chk("R3 PA7 output: active edge from ORA write sets the flag", pf, 1);
    chk("R3 PA7 output: irq_n low (enabled)", irq_s, 0);
    read_flags(tf, pf);
    wio(A_ORA, pos ? 8'h00 : 8'h80); settle();
    read_flags(tf, pf); chk("R3 PA7 output: inactive edge does not set the flag", pf, 0);
  endtask

  task automatic r3_polarity();
    int tf, pf;
    $display("== R3 polarity change does not set the flag (ruled 2026-11-26, MVT riot/pa7-polarity)");
    for (int lvl = 0; lvl < 2; lvl++) for (int en = 0; en < 2; en++) begin
      hw_reset(); quiet_timer(); wio(A_DDRA, 8'h00);
      pa_ext = lvl ? 8'hFF : 8'h7F; settle();
      pa7_ctl(en[0], 0); settle(); rio(A_FLAGS);
      pa7_ctl(en[0], 1); settle(); read_flags(tf, pf);
      chk($sformatf("R3 neg->pos change, pin=%0d en=%0d: flag stays clear", lvl, en), pf, 0);
      chk($sformatf("R3 neg->pos change, pin=%0d en=%0d: irq_n high", lvl, en), irq, 1);
      pa7_ctl(en[0], 0); settle(); read_flags(tf, pf);
      chk($sformatf("R3 pos->neg change, pin=%0d en=%0d: flag stays clear", lvl, en), pf, 0);
      chk($sformatf("R3 pos->neg change, pin=%0d en=%0d: irq_n high", lvl, en), irq, 1);
    end
  endtask

  task automatic r3_irq();
    int tf, pf;
    $display("== R3 irq_n for each source");
    // timer only, enabled
    hw_reset(); wio(A_DDRA, 8'h00); pa_ext = 8'hFF; settle();
    pa7_ctl(0, 0);
    tim_write(10, 0, 1); goto_pulse(5); chk("R3 timer irq: high before underflow", irq, 1);
    goto_pulse(20); settle(); chk("R3 timer irq: low after underflow (enabled via A3)", irq, 0);
    read_flags(tf, pf); chk("R3 timer flag set", tf, 1); chk("R3 irq_n still low after flag-register read (timer flag not cleared)", irq, 0);
    rio(A_INTIM); read_flags(tf, pf);
    chk("R3 timer flag cleared by INTIM read", tf, 0); chk("R3 irq_n high after INTIM read", irq, 1);
    // timer only, disabled: flag sets, irq_n stays high
    tim_write(10, 0, 0); goto_pulse(20); settle();
    read_flags(tf, pf); chk("R3 timer disabled: flag set", tf, 1); chk("R3 timer disabled: irq_n high", irq, 1);
    // write clears and re-arms with enable
    tim_write(100, 1, 1); read_flags(tf, pf); chk("R3 timer write clears flag", tf, 0); chk("R3 irq_n high after write", irq, 1);
    // both sources: PA7 enabled and timer enabled
    hw_reset(); wio(A_DDRA, 8'h00); pa_ext = 8'hFF; settle();
    pa7_ctl(1, 0); tim_write(10, 0, 1); goto_pulse(20);
    pa_ext = 8'h7F; settle();
    read_flags(tf, pf); chk("R3 both: timer flag", tf, 1); chk("R3 both: PA7 flag", pf, 1); chk("R3 both: irq_n low", irq, 0);
    read_flags(tf, pf); chk("R3 flag read cleared PA7 only: timer flag still 1", tf, 1); chk("R3 flag read cleared PA7 only: PA7 flag now 0", pf, 0);
    chk("R3 irq_n still low from the timer", irq, 0);
    rio(A_INTIM); settle();
    chk("R3 irq_n high once both sources are cleared", irq, 1);
    // PA7 only, timer enabled but no underflow yet
    hw_reset(); wio(A_DDRA, 8'h00); pa_ext = 8'hFF; settle();
    pa7_ctl(1, 0); tim_write(255, 3, 1);
    pa_ext = 8'h7F; settle(); chk("R3 PA7 irq with timer enabled but not expired: low", irq, 0);
    read_flags(tf, pf); chk("R3 PA7 flag was set", pf, 1);
    read_flags(tf, pf); chk("R3 PA7 flag cleared by flag read", pf, 0); chk("R3 irq_n high again", irq, 1);
    // PA7 enabled, timer flag set but timer irq disabled -> only PA7 matters
    hw_reset(); wio(A_DDRA, 8'h00); pa_ext = 8'hFF; settle();
    pa7_ctl(1, 0); tim_write(4, 0, 0); goto_pulse(12);
    chk("R3 timer expired, timer irq disabled, PA7 quiet: irq_n high", irq, 1);
    pa_ext = 8'h7F; settle(); chk("R3 PA7 edge with timer flag set and timer irq disabled: low", irq, 0);
    read_flags(tf, pf); chk("R3 irq_n high after PA7 flag cleared (timer irq disabled)", irq, 1);
    // PA7 disabled, timer enabled: PA7 edge does not raise irq_n
    hw_reset(); wio(A_DDRA, 8'h00); pa_ext = 8'hFF; settle();
    pa7_ctl(0, 0); tim_write(100, 3, 1);
    pa_ext = 8'h7F; settle(); chk("R3 PA7 edge, PA7 irq disabled, timer not expired: irq_n high", irq, 1);
  endtask

  // ------------------------------------------------------------ main
  initial begin
    $display("m6532 testbench: spec docs/spec.md 2.2, 7, 8.2 R1-R3");
    res_n = 0; repeat (2) nop(); res_n = 1; nop();
    r1_ram();
    r1_ports();
    r1_reset();
    for (int s = 0; s < 4; s++) begin
      r2_values(0, s); r2_values(1, s); r2_values(37, s); r2_values(255, s);
    end
    r2_flag_clear();
    r1_bus_mirrors();
    r2_checks();
    for (int en = 0; en < 2; en++) for (int pos = 0; pos < 2; pos++) r3_pa7_input(en[0], pos[0]);
    r3_pa7_output(0); r3_pa7_output(1);
    r3_polarity();
    r3_irq();
    verbose = 1;
    $display("checks: %0d, errors: %0d, cycles: %0d", nchk, errs, cycles);
    if (errs == 0) $display("PASS"); else $display("FAIL: %0d of %0d checks", errs, nchk);
    $finish;
  end
endmodule
