// m6532: MOS 6532 RIOT (128x8 RAM, two 8-bit ports, interval timer, PA7 edge IRQ).
// Spec: docs/spec.md 2.2 and 7.1-7.4.  Owner: Ada.
//
// Timing: one `ce` = 1 clock is one Phi2 pulse.  A timer write is pulse 0; on
// pulse k a timer read returns the value *after* that pulse's decrement step
// (spec 7.2: N - floor((k-1)/D) - 1).  Everything advances only on ce.
//
// Spec [check] items, my reading (see PR):
//  [check-1] After underflow the prescaler keeps cycling mod D during the
//            once-per-pulse free-run; a read ends the free-run and the next
//            /D step comes when the running prescaler next wraps (phase kept).
//            Same choice as ref/m6532.py PRESCALER_KEEPS_PHASE = True.
//  [check-2] A timer read does NOT change the timer IRQ enable (only a timer
//            write's A3 does).  Same as ref READ_A3_SETS_EN = False.
//  [check-3] /1 past $00: the counter simply wraps $00 -> $FF and keeps
//            counting down.  Every pass through $00 -> $FF sets the flag
//            again (same as ref/m6532.py); Igris to rule in spec 7.2.
//  [pin-levels] pa_in / pb_in are the resolved pin levels (spec 2.2, 7.3).
//            Port A reads pa_in as is; port B reads ORB for output bits and
//            pb_in for input bits.  PA7 edge detect watches pa_in[7].
module m6532 (
    input  wire       clk,
    input  wire       ce,
    input  wire       res_n,
    input  wire       cs1,
    input  wire       cs2_n,
    input  wire       rs_n,
    input  wire       rw,
    input  wire [6:0] a,
    input  wire [7:0] d_in,
    output wire [7:0] d_out,
    output wire       d_oe,
    input  wire [7:0] pa_in,
    output wire [7:0] pa_out,
    output wire [7:0] pa_ddr,
    input  wire [7:0] pb_in,
    output wire [7:0] pb_out,
    output wire [7:0] pb_ddr,
    output wire       irq_n
);

    // ---------------------------------------------------------------- state
    reg [7:0]  ram [0:127];
    reg [7:0]  ora, ddra, orb, ddrb;
    reg [7:0]  tval;        // value INTIM reads
    reg [10:0] tdiv;        // 1, 8, 64 or 1024
    reg [10:0] tleft;       // pulses until the next /D step (1..tdiv)
    reg        tfree;       // post-underflow once-per-pulse free-run
    reg        tflag;       // D7
    reg        pflag;       // D6
    reg        ten;         // timer IRQ enable
    reg        pen;         // PA7 IRQ enable
    reg        ppos;        // PA7 edge: 0 = negative, 1 = positive
    reg        pa7_prev;

    // --------------------------------------------------------------- decode
    wire sel   = ce & res_n & cs1 & ~cs2_n;
    wire ram_s = sel & ~rs_n;
    wire io_s  = sel &  rs_n;
    wire rd    = io_s & rw;
    wire wr    = io_s & ~rw;
    wire a2    = a[2];

    wire t_wr    = wr & a2 & a[4];            // timer write
    wire e_wr    = wr & a2 & ~a[4];           // edge detect control write
    wire t_rd    = rd & a2 & ~a[0];           // INTIM read
    wire f_rd    = rd & a2 &  a[0];           // interrupt flag read

    // ---------------------------------------------------------- timer step
    // Every ce pulse except the timer-write pulse steps the timer.
    wire       tstep     = ce & ~t_wr;
    wire       tedge     = (tleft == 11'd1);   // /D step due this pulse
    wire       dec       = tstep & (tfree | tedge);
    wire       under_now = dec & (tval == 8'h00);
    wire [7:0] tval_n    = dec ? tval - 8'd1 : tval;

    // ------------------------------------------------------------ PA7 edge
    wire p7      = pa_in[7];
    // Compared against the polarity as updated by a same-pulse control write
    // (matches ref/m6532.py: write first, then edge check).
    wire ppos_n  = e_wr ? a[0] : ppos;
    wire p7_edge = ce & (p7 != pa7_prev) & (p7 == ppos_n);

    // ------------------------------------------------------------ read mux
    reg [7:0] rdata;
    always @* begin
        if (ram_s)
            rdata = ram[a];
        else if (!a2)
            case (a[1:0])
                2'd0: rdata = pa_in;
                2'd1: rdata = ddra;
                2'd2: rdata = (orb & ddrb) | (pb_in & ~ddrb);
                default: rdata = ddrb;
            endcase
        else if (a[0])
            rdata = {tflag | under_now, pflag, 6'b0};   // flag set on this pulse is already visible
        else
            rdata = tval_n;
    end

    assign d_out  = rdata;
    assign d_oe   = (ram_s | io_s) & rw;
    assign pa_out = ora;
    assign pa_ddr = ddra;
    assign pb_out = orb;
    assign pb_ddr = ddrb;
    assign irq_n  = ~((tflag & ten) | (pflag & pen));

    // ------------------------------------------------------------- clocked
    always @(posedge clk) begin
        if (!res_n) begin
            // I/O registers cleared, PA7 IRQ off, negative edge.  Timer, RAM,
            // flags and timer enable are not reset (spec 2.2).
            ora <= 8'h00; ddra <= 8'h00; orb <= 8'h00; ddrb <= 8'h00;
            pen <= 1'b0;  ppos <= 1'b0;
            pa7_prev <= pa_in[7];     // resync, sets no flag
        end else if (ce) begin
            if (ram_s & ~rw) ram[a] <= d_in;

            if (wr & ~a2) begin
                case (a[1:0])
                    2'd0: ora  <= d_in;
                    2'd1: ddra <= d_in;
                    2'd2: orb  <= d_in;
                    default: ddrb <= d_in;
                endcase
            end

            // PA7 edge control: no flag set on a polarity change (spec 7.4, ruled)
            if (e_wr) begin
                pen  <= a[1];
                ppos <= a[0];
            end

            pa7_prev <= p7;

            // timer
            if (t_wr) begin
                tdiv  <= (a[1:0] == 2'd0) ? 11'd1 :
                         (a[1:0] == 2'd1) ? 11'd8 :
                         (a[1:0] == 2'd2) ? 11'd64 : 11'd1024;
                ten   <= a[3];
                tval  <= d_in;
                tleft <= 11'd1;           // first step on pulse 1
                tfree <= 1'b0;
                tflag <= 1'b0;
            end else begin
                tval  <= tval_n;
                tleft <= tedge ? tdiv : tleft - 11'd1;   // prescaler keeps cycling
                if (under_now) begin
                    tflag <= 1'b1;
                    tfree <= 1'b1;
                end else if (t_rd) begin
                    // a read on the underflow pulse keeps the flag (spec 7.2)
                    tflag <= 1'b0;
                    tfree <= 1'b0;
                end
            end

            // flags: read clears PA7 flag; an edge this pulse wins
            if (p7_edge)    pflag <= 1'b1;
            else if (f_rd)  pflag <= 1'b0;
        end
    end

endmodule
