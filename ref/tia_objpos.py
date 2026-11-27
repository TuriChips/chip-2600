"""Reference model of one TIA object position counter (spec 4.1 LFSR rule, 6.5 decode matrix + NUSIZ table; chip-2600 #60/#63).

Written from docs/spec.md only, not from the RTL. One step() per `clk` edge; outputs are the state AFTER the edge
(inputs held), like the other ref/ models. State q is a 6-bit int, bit0 = Q1 ... bit5 = Q6 (as tia_poly6 `q`).

  rst   : counter = 000000 (wins over everything)
  res   : RESxx strobe, counter = 000000 this clock (wins over step)
  step  : from wrap (101101) or ERR (111111) -> 000000, else Q1' = XNOR(Q5,Q6), Qk' = old Q(k-1)
  nusiz : D2-D0. Copy enables (spec 6.5 table): count 3 for 001/011, count 7 for 010/011/110, count 15 for 100/110;
          none for 000/101/111.
  start_main = state is the wrap decode (Q1..Q6 = 101101, count 39); start_copy = an enabled copy decode.
  nusiz is read live: a change mid-period takes effect on the very next output (combinational gating).
Test-only: the harness forces q=ERR by assigning self.q (RTL: hierarchical write); ERR is unreachable from reset.
Not here: landing delays, stretched-mode +1, HMOVE, RESMPx (spec 6.5/6.6, still [check]).
"""


def bits(s):          # "Q1..Q6" string -> int with bit0 = Q1
    return sum(int(c) << i for i, c in enumerate(s))


WRAP = bits("101101"); ERR = bits("111111")
C3 = bits("111000"); C7 = bits("101111"); C15 = bits("111001")
EN3 = (1, 3); EN7 = (2, 3, 6); EN15 = (4, 6)


def lfsr(q):
    q1, q5, q6 = q & 1, (q >> 4) & 1, (q >> 5) & 1
    return ((q << 1) & 0x3F) | (1 - (q5 ^ q6))


class TiaObjpos:
    def __init__(self):
        self.q = 0

    def outputs(self, nusiz):
        q = self.q
        main = int(q == WRAP)
        copy = int((q == C3 and nusiz in EN3) or (q == C7 and nusiz in EN7) or (q == C15 and nusiz in EN15))
        return self.q, main, copy

    def step(self, rst, step, res, nusiz, inj=0):
        if inj:
            self.q = ERR   # test hook, see header
        if rst or res:
            self.q = 0
        elif step:
            self.q = 0 if self.q in (WRAP, ERR) else lfsr(self.q)
        return self.outputs(nusiz)
