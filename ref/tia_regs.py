"""Reference model of the TIA write side (spec 6.1 write map, 6.5 vertical delay, 6.6 HMCLR, 5 reset).

Written from docs/spec.md only (turichips docs/2600/spec.md @ f8aff66), not from the RTL.
One step() per `clk` edge. Inputs: rst, wr (one-clk write pulse), a (6 bits), d (8 bits).
Output: dict of every register value AFTER that edge, plus the strobe pulses.

Packing: a register's stored bits are concatenated high to low in the order the spec lists them
(NUSIZ = {D5,D4,D2,D1,D0}, VBLANK = {D7,D6,D1}, CTRLPF = {D5,D4,D2,D1,D0}).
Strobes are modelled as REGISTERED pulses: 1 in the cycle after the edge that saw wr=1 and the
address, 0 otherwise. Zura's issue (#20) says "one-clk pulse outputs" without saying registered
or combinational; STROBES_REGISTERED is the one-line switch (open item for #20).
"""

# addr: (name, bits listed high->low)
WRITE_MAP = {
    0x00: ("vsync", (1,)), 0x01: ("vblank", (7, 6, 1)),
    0x04: ("nusiz0", (5, 4, 2, 1, 0)), 0x05: ("nusiz1", (5, 4, 2, 1, 0)),
    0x06: ("colup0", (7, 6, 5, 4, 3, 2, 1)), 0x07: ("colup1", (7, 6, 5, 4, 3, 2, 1)),
    0x08: ("colupf", (7, 6, 5, 4, 3, 2, 1)), 0x09: ("colubk", (7, 6, 5, 4, 3, 2, 1)),
    0x0A: ("ctrlpf", (5, 4, 2, 1, 0)), 0x0B: ("refp0", (3,)), 0x0C: ("refp1", (3,)),
    0x0D: ("pf0", (7, 6, 5, 4)), 0x0E: ("pf1", tuple(range(7, -1, -1))), 0x0F: ("pf2", tuple(range(7, -1, -1))),
    0x15: ("audc0", (3, 2, 1, 0)), 0x16: ("audc1", (3, 2, 1, 0)),
    0x17: ("audf0", (4, 3, 2, 1, 0)), 0x18: ("audf1", (4, 3, 2, 1, 0)),
    0x19: ("audv0", (3, 2, 1, 0)), 0x1A: ("audv1", (3, 2, 1, 0)),
    0x1B: ("grp0", tuple(range(7, -1, -1))), 0x1C: ("grp1", tuple(range(7, -1, -1))),
    0x1D: ("enam0", (1,)), 0x1E: ("enam1", (1,)), 0x1F: ("enabl", (1,)),
    0x20: ("hmp0", (7, 6, 5, 4)), 0x21: ("hmp1", (7, 6, 5, 4)), 0x22: ("hmm0", (7, 6, 5, 4)),
    0x23: ("hmm1", (7, 6, 5, 4)), 0x24: ("hmbl", (7, 6, 5, 4)),
    0x25: ("vdelp0", (0,)), 0x26: ("vdelp1", (0,)), 0x27: ("vdelbl", (0,)),
    0x28: ("resmp0", (1,)), 0x29: ("resmp1", (1,)),
}
STROBES = {0x02: "wsync", 0x03: "rsync", 0x10: "resp0", 0x11: "resp1", 0x12: "resm0", 0x13: "resm1",
           0x14: "resbl", 0x2A: "hmove", 0x2B: "hmclr", 0x2C: "cxclr"}
assert len(WRITE_MAP) + len(STROBES) == 45
HM = ("hmp0", "hmp1", "hmm0", "hmm1", "hmbl")
WIDTH = {n: len(b) for n, b in WRITE_MAP.values()}
# vertical-delay "old" copies (6.5): outputs grp0_old, grp1_old, enabl_old
OLD = ("grp0_old", "grp1_old", "enabl_old")


def pack(bits, d):
    v = 0
    for b in bits:
        v = (v << 1) | ((d >> b) & 1)
    return v


class TiaRegs:
    STROBES_REGISTERED = True

    def __init__(self):
        self.reset()

    def reset(self):
        self.r = {n: 0 for n, _ in WRITE_MAP.values()}
        self.r.update({o: 0 for o in OLD})
        self.s = {n + "_s": 0 for n in STROBES.values()}

    def outputs(self):
        o = dict(self.r)
        o["grp0_new"], o["grp1_new"], o["enabl_new"] = o.pop("grp0"), o.pop("grp1"), o.pop("enabl")
        o.update(self.s)
        return o

    def step(self, rst, wr, a, d):
        if rst:
            self.reset()
            return self.outputs()
        self.s = {k: 0 for k in self.s}
        if wr:
            r = self.r
            if a in WRITE_MAP:
                name, bits = WRITE_MAP[a]
                v = pack(bits, d)
                if a == 0x1B:                       # GRP0: GRP1 new -> GRP1 old (old values taken before the edge)
                    r["grp1_old"] = r["grp1"]
                elif a == 0x1C:                     # GRP1: GRP0 new -> GRP0 old and ENABL new -> ENABL old
                    r["grp0_old"] = r["grp0"]
                    r["enabl_old"] = r["enabl"]
                r[name] = v
            elif a in STROBES:
                self.s[STROBES[a] + "_s"] = 1
                if a == 0x2B:
                    for h in HM:
                        r[h] = 0
            # $2D-$3F: no effect
        return self.outputs()
