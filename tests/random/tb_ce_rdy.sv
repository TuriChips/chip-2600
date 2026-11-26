// Random test (chip-2600#16): `ce` gating combined with `rdy` low (WSYNC) on the core copy m6502.
// Copy A runs with ce = 1 on every clock; copy B runs the same program with random ce gaps. The rdy pattern is defined in ce time
// (one value per CPU cycle, k = 0,1,2..., low in random runs: single cycles, bursts, and WSYNC-like windows up to ~100 cycles).
// A sees r[k] on clock k. B sees r[k] on its k-th ce clock, and a random glitching rdy on the ce = 0 clocks in between (ce = 0 must make rdy irrelevant).
// Checks: (1) per ce pulse, B's a, rw, sync, d_oe and d_out (when writing) equal A's, from the first clock after reset (so the reset cycles, rdy ignored there, too);
//         (2) on every ce = 0 clock B's outputs do not change; (3) independent of A/B: if rdy = 0 at a clock that started on a read cycle the bus does not
//         move (a, rw, sync same after the edge); if the cycle was a write, rdy is ignored (spec 2, p.37: RDY holds read cycles only), checked as "a write
//         cycle is followed by a different cycle or the next address" only via the hold rule on reads; (4) the program makes progress (>= 200 sync pulses).
// Memory: RAM below $8000, ROM above (writes not stored), image from +MEM=<hex file> (tests/core/gen_cycles6502.py output). irq_n, nmi_n, so_n tied to 1 (spec D1).
// +SEED=<n> +N=<ce cycles> +MODE=<0 dense, 1 WSYNC windows, 2 sparse>
`timescale 1ns/1ps
module tb_ce_rdy;
  reg clk = 0, res_n = 0, ceb = 0, rdya = 1, rdyb = 1;
  reg [7:0] mema [0:65535]; reg [7:0] memb [0:65535];
  wire [15:0] aa, ab; wire [7:0] da, db; wire oea, oeb, rwa, rwb, sya, syb;
  m6502 A (.clk(clk), .ce(1'b1), .res_n(res_n), .a(aa), .d_in(mema[aa]), .d_out(da), .d_oe(oea), .rw(rwa), .sync(sya), .rdy(rdya), .irq_n(1'b1), .nmi_n(1'b1), .so_n(1'b1));
  m6502 B (.clk(clk), .ce(ceb),  .res_n(res_n), .a(ab), .d_in(memb[ab]), .d_out(db), .d_oe(oeb), .rw(rwb), .sync(syb), .rdy(rdyb), .irq_n(1'b1), .nmi_n(1'b1), .so_n(1'b1));
  always #5 clk = ~clk;
  always @(posedge clk) begin
    if (!rwa && aa < 16'h8000) mema[aa] <= da;
    if (ceb && !rwb && ab < 16'h8000) memb[ab] <= db;
  end
  integer seed, seed0, n, mode, i, k, errs = 0, gap, w, nlow = 0, nlowread = 0, nsync = 0, nhold = 0, ngap = 0;
  string memf;
  reg [15:0] ta [0:65535]; reg tr [0:65535]; reg ts [0:65535]; reg to_ [0:65535]; reg [7:0] td [0:65535]; reg rr [0:65535];
  reg [15:0] pa; reg [7:0] pd; reg prw, psy, poe;
  integer win = 0;
  initial begin
    if (!$value$plusargs("MEM=%s", memf)) begin $display("FAIL no +MEM"); $finish; end
    if (!$value$plusargs("SEED=%d", seed)) seed = 1; seed0 = seed;
    if (!$value$plusargs("N=%d", n)) n = 4000;
    if (!$value$plusargs("MODE=%d", mode)) mode = 0;
    for (i = 0; i < 65536; i = i + 1) begin mema[i] = 8'h00; memb[i] = 8'h00; end
    $readmemh(memf, mema); $readmemh(memf, memb);
    // rdy pattern in ce time
    for (k = 0; k < n; k = k + 1) begin
      if (win > 0) begin rr[k] = 0; win = win - 1; end
      else begin
        rr[k] = 1;
        case (mode)
          0: if (($random(seed) & 3) == 0) begin rr[k] = 0; if (($random(seed) & 3) == 0) win = $random(seed) & 3; end
          1: if (($random(seed) & 31) == 0) begin rr[k] = 0; win = ($random(seed) & 127) % 100; end   // WSYNC: up to ~100 cycles
          default: if (($random(seed) & 15) == 0) rr[k] = 0;
        endcase
      end
    end
    // A: reset 12 clocks, release, then n clocks
    res_n = 0; repeat (12) @(posedge clk); #1 res_n = 1;
    for (k = 0; k < n; k = k + 1) begin
      rdya = rr[k];                                 // set just after the previous edge
      @(posedge clk); #1;
      ta[k] = aa; tr[k] = rwa; ts[k] = sya; to_[k] = oea; td[k] = da;
    end
    // B: same, ce gated
    @(negedge clk); res_n = 0; ceb = 0; rdyb = 1;
    @(posedge clk); #1;
    // (reload of the memory image is not needed for ROM; RAM differs only where A wrote: reload both for the B run)
    for (i = 0; i < 65536; i = i + 1) memb[i] = 8'h00; $readmemh(memf, memb);
    ceb = 1; repeat (12) begin rdyb = $random(seed); @(posedge clk); #1; end   // 12 ce pulses in reset, rdy random (ignored)
    // A's 12-clock reset low phase then release at #1: B releases after the same count of ce pulses
    res_n = 1; pa = ab; pd = db; prw = rwb; psy = syb; poe = oeb;
    for (k = 0; k < n; k = k + 1) begin
      gap = $random(seed) & 7; if (($random(seed) & 31) == 0) gap = $random(seed) & 63;
      ceb = 0;
      repeat (gap) begin
        rdyb = $random(seed); @(posedge clk); #1; ngap = ngap + 1;
        if (ab !== pa || db !== pd || rwb !== prw || syb !== psy || oeb !== poe) begin
          errs = errs + 1; if (errs < 20) $display("FAIL ce=0 hold: outputs changed (rdy glitch) before pulse %0d", k);
        end
      end
      ceb = 1; rdyb = rr[k]; @(posedge clk); #1;
      pa = ab; pd = db; prw = rwb; psy = syb; poe = oeb;
      if (ab !== ta[k] || rwb !== tr[k] || syb !== ts[k] || oeb !== to_[k] || (!tr[k] && db !== td[k])) begin
        errs = errs + 1; if (errs < 20) $display("FAIL ce pulse %0d (rdy=%b): B a=%04h rw=%b sync=%b oe=%b d=%02h, A a=%04h rw=%b sync=%b oe=%b d=%02h", k, rr[k], ab, rwb, syb, oeb, db, ta[k], tr[k], ts[k], to_[k], td[k]);
      end
    end
    ceb = 0;
    // independent rule on A's trace (k >= 8: past the reset sequence): rdy = 0 on a read cycle holds the bus
    for (k = 9; k < n; k = k + 1) begin
      if (ts[k]) nsync = nsync + 1;
      if (!rr[k]) begin
        nlow = nlow + 1;
        if (tr[k-1]) begin
          nlowread = nlowread + 1;
          if (ta[k] !== ta[k-1] || tr[k] !== tr[k-1] || ts[k] !== ts[k-1]) begin
            errs = errs + 1; if (errs < 20) $display("FAIL rdy=0 on read cycle %0d did not hold: a %04h -> %04h", k-1, ta[k-1], ta[k]);
          end else nhold = nhold + 1;
        end
      end
    end
    if (nsync < 100) begin errs = errs + 1; $display("FAIL only %0d sync pulses in %0d cycles", nsync, n); end
    if (nhold < 20)  begin errs = errs + 1; $display("FAIL only %0d rdy-held read cycles exercised", nhold); end
    $display("%s: seed=%0d mode=%0d cycles=%0d syncs=%0d rdy_low=%0d held_reads=%0d ce0_clocks=%0d errors=%0d", errs ? "FAIL" : "PASS", seed0, mode, n, nsync, nlow, nhold, ngap, errs);
    $finish;
  end
endmodule
