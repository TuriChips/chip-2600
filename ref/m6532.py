"""Cycle-level reference model of the MOS 6532 RIOT, written from RIOT DS and
docs/spec.md section 7 only (no RTL, no emulator source).

One call to step() is one Phi2 pulse with ce=1.  Pulse 0 of a timer interval is
the write cycle itself.  Items the spec still marks [check] are class
attributes so a ruling flips one line, and are listed in ref/README.md.
"""
import random

DIV = (1, 8, 64, 1024)


class M6532:
    # [check] spec 7.2: does an INTIM/timer read with A3 set also change the timer IRQ enable?
    READ_A3_SETS_EN = False
    # [check] spec 7.2: after a post-underflow read ends free-run, is the prescaler phase kept
    # (True: it kept cycling mod D during free-run) or restarted at D (False)?
    PRESCALER_KEEPS_PHASE = True

    def __init__(self):
        self.ram = [0] * 128
        self.ora = self.ddra = self.orb = self.ddrb = 0
        self.val = 0            # value INTIM reads now
        self.div = 1            # current divide
        self.left = 1           # pulses until the next /D decrement
        self.free = False       # post-underflow once-per-pulse free-run
        self.tflag = 0
        self.pflag = 0
        self.ten = 0            # timer IRQ enable (A3 of last timer write)
        self.pen = 0            # PA7 IRQ enable
        self.pos = 0            # PA7 edge: 0 = negative, 1 = positive
        self.pa_ext = 0xFF      # outside-world levels, as last given
        self.pb_ext = 0xFF
        self.pa7_prev = 1
        self.pulse = 0

    # -- power-on state (D7): RAM, timer, prescaler phase, flags are arbitrary
    def power_on(self, rng):
        self.ram = [rng.randrange(256) for _ in range(128)]
        self.val = rng.randrange(256)
        self.div = rng.choice(DIV)
        self.left = rng.randrange(1, self.div + 1)
        self.free = rng.random() < 0.3
        self.tflag = rng.randrange(2)
        self.pflag = rng.randrange(2)
        self.ten = rng.randrange(2)
        self.ora = self.ddra = self.orb = self.ddrb = 0
        self.pen, self.pos = 0, 0

    # -- helpers
    def pins_a(self):
        return (self.ora & self.ddra) | (self.pa_ext & ~self.ddra & 0xFF)

    def pins_b(self):
        return (self.orb & self.ddrb) | (self.pb_ext & ~self.ddrb & 0xFF)

    def irq_n(self):
        return 0 if ((self.tflag and self.ten) or (self.pflag and self.pen)) else 1

    def _reset(self):
        self.ora = self.ddra = self.orb = self.ddrb = 0
        self.pen, self.pos = 0, 0
        self.pa7_prev = (self.pins_a() >> 7) & 1   # resync, sets nothing

    def _dec(self):
        under = self.val == 0
        if under:
            self.tflag = 1
            self.free = True
        self.val = (self.val - 1) & 0xFF
        return under

    # -- one Phi2 pulse
    def step(self, ce=1, res_n=1, cs1=1, cs2_n=0, rs_n=1, rw=1, a=0, d_in=0,
             pa_in=None, pb_in=None):
        if pa_in is not None:
            self.pa_ext = pa_in & 0xFF
        if pb_in is not None:
            self.pb_ext = pb_in & 0xFF
        d_out, d_oe = 0, 0
        if not res_n:
            self._reset()
            return self._outs(d_out, 0)
        if not ce:
            return self._outs(d_out, 0)
        sel = cs1 == 1 and cs2_n == 0
        is_write_timer = sel and rs_n == 1 and not rw and (a >> 2) & 1 and (a >> 4) & 1
        # timer tick happens on every pulse except the write cycle that (re)starts it
        under_now = False
        if not is_write_timer:
            under_now = self._tick_flagged()
        if sel:
            if rs_n == 0:
                if rw:
                    d_out, d_oe = self.ram[a & 0x7F], 1
                else:
                    self.ram[a & 0x7F] = d_in & 0xFF
            elif rw:
                d_out, d_oe = self._read_io(a, under_now)
            else:
                self._write_io(a, d_in & 0xFF)
        # PA7 edge detection on the resolved pin, end of pulse
        p7 = (self.pins_a() >> 7) & 1
        if p7 != self.pa7_prev:
            if (p7 == 1) == bool(self.pos):
                self.pflag = 1
            self.pa7_prev = p7
        return self._outs(d_out, d_oe)

    def _tick_flagged(self):
        """Timer advance on a pulse after the write; True if it underflowed now.
        The prescaler cycles mod D even during free-run."""
        self.pulse += 1
        self.left -= 1
        edge = self.left == 0
        if edge:
            self.left = self.div
        if self.free or edge:
            return self._dec()
        return False

    def _read_io(self, a, under_now):
        a2 = (a >> 2) & 1
        if not a2:
            r = a & 3
            if r == 0:
                return self.pins_a(), 1
            if r == 1:
                return self.ddra, 1
            if r == 2:
                return (self.orb & self.ddrb) | (self.pb_ext & ~self.ddrb & 0xFF), 1
            return self.ddrb, 1
        if a & 1:                                   # interrupt flags
            v = (self.tflag << 7) | (self.pflag << 6)
            self.pflag = 0
            return v, 1
        v = self.val                                # INTIM
        if self.READ_A3_SETS_EN:
            self.ten = (a >> 3) & 1
        if not under_now:                           # a read ON the underflow pulse keeps the flag
            self.tflag = 0
            if self.free:
                self.free = False
                if not self.PRESCALER_KEEPS_PHASE:
                    self.left = self.div
        return v, 1

    def _write_io(self, a, d):
        a2 = (a >> 2) & 1
        if not a2:
            r = a & 3
            if r == 0:
                self.ora = d
            elif r == 1:
                self.ddra = d
            elif r == 2:
                self.orb = d
            else:
                self.ddrb = d
            return
        if (a >> 4) & 1:                            # timer write
            self.div = DIV[a & 3]
            self.ten = (a >> 3) & 1
            self.val = d
            self.left = 1                           # first decrement on pulse 1
            self.free = False
            self.tflag = 0
            self.pulse = 0
        else:                                       # edge detect control, no flag set (ruled)
            self.pen = (a >> 1) & 1
            self.pos = a & 1

    def _outs(self, d_out, d_oe):
        return {
            "d_out": d_out, "d_oe": d_oe, "irq_n": self.irq_n(),
            "pa_out": self.ora, "pa_ddr": self.ddra,
            "pb_out": self.orb, "pb_ddr": self.ddrb,
        }

    def snapshot(self):
        return (tuple(self.ram), self.ora, self.ddra, self.orb, self.ddrb, self.val,
                self.div, self.left, self.free, self.tflag, self.pflag, self.ten,
                self.pen, self.pos)
