"""Reference model of the TIA read side and playfield scan (spec 6.1 read map, 6.4, 6.7, 6.8, 5 reset).

Written from docs/spec.md only, not from the RTL. Four small models, one step() per `clk` edge,
output = state AFTER the edge (sampled with inputs held). Port names follow chip-2600 #27 / #28.

* TiaCx   : 15 collision latches. Packing of `cx` (bit 14 = first listed .. bit 0), read-map order:
            {CXM0P D7,D6, CXM1P D7,D6, CXP0FB D7,D6, CXP1FB D7,D6, CXM0FB D7,D6, CXM1FB D7,D6,
             CXBLPF D7, CXPPMM D7,D6}. Pairs (D7, D6) are in PAIRS below.
* TiaInpt : I0-I5. I0-I3 = pin & ~VBLANK.D7 (dump). I4-I5: VBLANK.D6=0 -> pin, latch held 1;
            D6=1 -> latch &= pin, output = latch. Output is the state after the edge.
* tia_rd  : combinational read mux (function read_mux).
* TiaPf   : 20-bit scan by index, copy / reflect.
"""
OBJ = ("p0", "p1", "m0", "m1", "bl", "pf")
# (D7 pair, D6 pair) per read address 0..7; None = line not driven by the register (CXBLPF D6, open spec point)
PAIRS = [(("m0", "p1"), ("m0", "p0")), (("m1", "p0"), ("m1", "p1")),
         (("p0", "pf"), ("p0", "bl")), (("p1", "pf"), ("p1", "bl")),
         (("m0", "pf"), ("m0", "bl")), (("m1", "pf"), ("m1", "bl")),
         (("bl", "pf"), None), (("p0", "p1"), ("m0", "m1"))]
# cx bit index for (addr, line): bit 14 first
CXBIT = {}
_i = 14
for _a, (_h, _l) in enumerate(PAIRS):
    CXBIT[(_a, 7)] = _i; _i -= 1
    if _l is not None:
        CXBIT[(_a, 6)] = _i; _i -= 1
assert _i == -1


class TiaCx:
    def __init__(self): self.cx = 0
    def step(self, rst, en, objs, vblank_d1, cxclr):
        """objs: dict name->0/1. cxclr beats a set on the same clk (#28)."""
        if rst or cxclr:
            self.cx = 0
        elif en and not vblank_d1:
            for (a, line), b in CXBIT.items():
                p = PAIRS[a][0 if line == 7 else 1]
                if objs[p[0]] and objs[p[1]]:
                    self.cx |= 1 << b
        return self.cx


class TiaInpt:
    def __init__(self): self.latch = 3          # I4, I5 latches, 1 = not cleared (bit0 = I4)
    def step(self, rst, pin, vblank):
        d7, d6 = (vblank >> 2) & 1, (vblank >> 1) & 1
        if rst or not d6:
            self.latch = 3                       # "Writing D6 = 0 resets the latches to 1"
        else:
            self.latch &= (pin >> 4) & 3
        o = pin & 0xF
        if d7: o = 0
        o |= ((pin >> 4) & 3 if not d6 else self.latch) << 4
        return o


def read_mux(a, cx, inpt):
    """returns (d_out {D7,D6}, d_oe {D7,D6})"""
    if a <= 7:
        d7 = (cx >> CXBIT[(a, 7)]) & 1
        if (a, 6) in CXBIT:
            return (d7 << 1) | ((cx >> CXBIT[(a, 6)]) & 1), 3
        return d7 << 1, 2                        # CXBLPF: D7 only, D6 not driven (open point)
    if a <= 0xD:
        return ((inpt >> (a - 8)) & 1) << 1, 2
    return 0, 0


class TiaPf:
    def __init__(self): self.i = 0
    def step(self, rst, step, start):
        if rst or start: self.i = 0
        elif step: self.i += 1                    # beyond 19: unspecified, stimulus never goes there
        return self.i
    @staticmethod
    def pf_bit(i, right, ref, pf0, pf1, pf2):
        """pf0 4 bits (D7-D4 as value), pf1, pf2 8 bits each; list: PF0 D4..D7, PF1 D7..D0, PF2 D0..D7"""
        bits = [(pf0 >> k) & 1 for k in range(4)]     # pf0 value bit0 = D4 ... bit3 = D7
        bits += [(pf1 >> k) & 1 for k in range(7, -1, -1)]
        bits += [(pf2 >> k) & 1 for k in range(8)]
        return bits[19 - i] if (right and ref) else bits[i]
