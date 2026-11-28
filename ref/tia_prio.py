"""tia_prio reference model (chip-2600#73), written from spec 6.9, 6.4 (SCORE, PFP), 6.2 (blank). Not derived from the RTL.

prio(p0,m0,p1,m1,pf,bl,score,pfp,right,blk,colup0,colup1,colupf,colubk) -> (lum, col)
  colour registers are 7 bits (D7-D1); lum = D3-D1 = low 3 bits, col = D7-D4 = high 4 bits.
  Normal: P0/M0 > P1/M1 > PF/BL > BK.  PFP: PF/BL > P0/M0 > P1/M1 > BK.
  SCORE: PF takes COLUP0 on the left half, COLUP1 on the right (6.4).  blk -> lum = col = 0.
unsettled(...) is True for SCORE=1 with BL=1 or PFP=1 (6.9 [check], turichips#48): the model does not claim a colour there
(it returns the placeholder: SCORE colour only for PFP=0, BL=0, PF=1), and the harness does not compare those vectors.
"""

def unsettled(score, pfp, bl):
    return bool(score and (bl or pfp))

def prio(p0, m0, p1, m1, pf, bl, score, pfp, right, blk, colup0, colup1, colupf, colubk):
    g0, g1, gf = p0 or m0, p1 or m1, pf or bl
    pfcol = colupf
    if score and not bl and not pfp and pf:   # settled SCORE case (PF only, normal priority)
        pfcol = colup1 if right else colup0
    if pfp:
        order = ((gf, pfcol), (g0, colup0), (g1, colup1))
    else:
        order = ((g0, colup0), (g1, colup1), (gf, pfcol))
    sel = colubk
    for g, c in order:
        if g:
            sel = c; break
    if blk:
        return 0, 0
    return sel & 7, (sel >> 3) & 15
