#!/usr/bin/env python3
"""Build the TuriChips 2600 demo: python3 sw/demo/build.py
Steps: expand NAME = value equates in demo.asm, append the generated tables (below), assemble with tests/core/asm6502.py,
write a 4 KB image at $F000 (sw/demo/demo.bin + demo.sha256), a listing (demo.lst) and the kernel cycle report (logs/demo-cycles.log).
Exit status 1 if any kernel path is over 76 cycles, a deadline (@by) is missed, or a timer window is wrong."""
import sys, re, os, hashlib
sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, 'tests', 'core'))
import asm6502 as A

# ---------------------------------------------------------------- generated tables
FONT = {'2': ['111', '001', '111', '100', '111'], '6': ['111', '100', '111', '101', '111'], '0': ['111', '101', '101', '101', '111']}
def pf_bytes(blocks):                    # blocks[0..19] left to right -> PF0, PF1, PF2 (SPG p.38)
    pf0 = sum(1 << (4 + i) for i in range(4) if blocks[i])
    pf1 = sum(1 << (7 - (i - 4)) for i in range(4, 12) if blocks[i])
    pf2 = sum(1 << (i - 12) for i in range(12, 20) if blocks[i])
    return pf0, pf1, pf2
def title_row(r):
    b = []
    for ch in '2600':
        b += [int(FONT[ch][r][c]) for c in range(3)] + [0, 0]
    return b
SOLID, EMPTY = [1] * 20, [0] * 20
BANDS = 24
band_pf = []; band_col = []; band_bk = []
for b in range(BANDS):
    pf = EMPTY; col = 0x0E
    if b in (0, 8): pf, col = SOLID, 0x1E if b == 0 else 0x4C
    elif b == 23: pf, col = SOLID, 0xC6
    elif 2 <= b <= 6: pf, col = title_row(b - 2), [0x2E, 0x3E, 0x4E, 0x5E, 0x6E][b - 2]
    elif 9 <= b <= 19: col = 0x1E          # the ball is drawn in COLUPF
    band_pf.append(pf_bytes(pf)); band_col.append(col); band_bk.append(0x80 | min(14, 2 * (b // 3)))
GLYPH0 = ['00111100', '01111110', '11011011', '11111111', '11111111', '01011010', '01000010', '11000011']
GLYPH1 = ['00011000', '00011000', '00111100', '01111110', '11111111', '11111111', '11100111', '11000011']
SLINES = BANDS * 7
sp0 = [0] * (SLINES + 1); sp1 = [0] * (SLINES + 1); bl = [0] * (SLINES + 1)
for r in range(8):
    for k in range(2):
        n = 80 + 2 * r + k; sp0[SLINES - n] = int(GLYPH0[r], 2); sp1[SLINES - n] = int(GLYPH1[r], 2)
for n in range(124, 132): bl[SLINES - n] = 2          # ENABL D1
NOTES = [29, 23, 19, 14, 19, 23, 29, 39]               # AUDC 4: ~31.4 kHz / (2 (F+1)): C5 E5 G5 C6 G5 E5 C5 G4
def band_table(f):                                      # index Y = 24..1 is band 24-Y
    t = [0] * 32
    for y in range(1, BANDS + 1): t[y] = f(BANDS - y)
    return t
def emit(label, org, data):
    out = [f'        .org ${org:04X}', f'{label}:']
    for i in range(0, len(data), 16): out.append('        .byte ' + ','.join(str(v) for v in data[i:i + 16]))
    return out
TABLES = (emit('sp0', 0xF200, sp0) + emit('sp1', 0xF300, sp1) + emit('bl', 0xF400, bl)
          + emit('pf0tab', 0xF500, band_table(lambda b: band_pf[b][0])) + emit('pf1tab', 0xF520, band_table(lambda b: band_pf[b][1]))
          + emit('pf2tab', 0xF540, band_table(lambda b: band_pf[b][2])) + emit('coltab', 0xF560, band_table(lambda b: band_bk[b]))
          + emit('pfcol', 0xF580, band_table(lambda b: band_col[b])) + emit('notes', 0xF5A0, NOTES)
          + ['        .org $FFFC', '        .word start, start'])

# ---------------------------------------------------------------- source preparation
def expand(text):
    eq = {}; body = []
    for ln in text.splitlines():
        m = re.match(r'([A-Z][A-Z0-9_]*)\s*=\s*(\S+)', ln)
        if m: eq[m.group(1)] = m.group(2); continue
        body.append(ln)
    pat = re.compile(r'\b(' + '|'.join(sorted(eq, key=len, reverse=True)) + r')\b')
    out = []
    for ln in body:
        code, sep, com = ln.partition(';')
        out.append(pat.sub(lambda m: eq[m.group(1)], code) + sep + com)
    return out, eq
src = open(os.path.join(HERE, 'demo.asm')).read()
lines, EQ = expand(src)
lines = lines + TABLES
labels = {}
A.assemble(lines, False, labels)
mem = A.assemble(lines, True, labels)
image = bytes(mem.get(0xF000 + i, 0) for i in range(4096))
if any(a < 0xF000 for a in mem): sys.exit('bytes below $F000')
open(os.path.join(HERE, 'demo.bin'), 'wb').write(image)
sha = hashlib.sha256(image).hexdigest()
open(os.path.join(HERE, 'demo.sha256'), 'w').write(f'{sha}  demo.bin\n')

# ---------------------------------------------------------------- listing: re-walk the source with the final labels
def cycles(m, mode, worst=True):
    if m in A.BRANCH: return 2
    if m in ('PHA', 'PHP'): return 3
    if m in ('PLA', 'PLP'): return 4
    if m == 'JSR' or m == 'RTS' or m == 'RTI': return 6
    if m == 'BRK': return 7
    if m == 'JMP': return 3 if mode == 'abs' else 5
    rmw = m in ('ASL', 'LSR', 'ROL', 'ROR', 'INC', 'DEC')
    store = m in ('STA', 'STX', 'STY')
    if mode in ('imp', 'acc', 'imm'): return 2
    if rmw: return {'zp': 5, 'zpx': 6, 'abs': 6, 'absx': 7}[mode]
    if mode == 'zp': return 3
    if mode in ('zpx', 'zpy', 'abs'): return 4
    if mode in ('absx', 'absy'): return 5 if store else (5 if worst else 4)   # reads: +1 if the index crosses a page; assume it does
    if mode == 'indx': return 6
    if mode == 'indy': return 6 if store else 6          # 5 (+1 on a crossing); assumed crossing
    raise SystemExit(f'no cycle count for {m} {mode}')
entries = []; pc = 0; lab_at = {}
for raw in lines:
    ln = raw.split(';')[0].strip(); com = raw.partition(';')[2]
    while True:
        mm = re.match(r'([A-Za-z_][A-Za-z_0-9]*):(.*)', ln)
        if not mm: break
        lab_at.setdefault(pc, []).append(mm.group(1)); ln = mm.group(2).strip()
    if not ln: continue
    op, _, rest = ln.partition(' '); opu = op.upper()
    if opu == '.ORG': pc = A.val(rest, labels, True); continue
    if opu == '.BYTE': pc += len(rest.split(',')); continue
    if opu == '.WORD': pc += 2 * len(rest.split(',')); continue
    mode, v = A.pick(opu, rest, labels, True)
    e = dict(pc=pc, m=opu, mode=mode, v=v, size=A.SIZE[mode], cyc=cycles(opu, mode), text=ln, com=com, rest=rest.strip())
    by = re.search(r'@by (\d+)', com); e['by'] = int(by.group(1)) if by else None
    entries.append(e); pc += e['size']
byaddr = {e['pc']: e for e in entries}
orig = src.splitlines()
with open(os.path.join(HERE, 'demo.lst'), 'w') as f:
    f.write('addr  bytes     cyc  source (after equate expansion; tables omitted)\n')
    for e in entries:
        if e['pc'] >= 0xF200: break
        b = ' '.join(f'{mem[e["pc"] + i]:02X}' for i in range(e['size']))
        lbl = ','.join(lab_at.get(e['pc'], []))
        f.write(f'{e["pc"]:04X}  {b:<8}  {e["cyc"]:>3}  {(lbl + ":") if lbl else "":<10}{e["text"]}\n')

# ---------------------------------------------------------------- kernel cycle paths
KS, KE = labels['kernel_start'], labels['kernel_end']
log = []; fail = False
def P(s): log.append(s)
def succ(e):
    nxt = e['pc'] + e['size']
    if e['m'] in A.BRANCH:
        cross = 1 if (e['v'] >> 8) != (nxt >> 8) else 0
        return [(nxt, 2), (e['v'], 3 + cross)]
    if e['m'] == 'JMP': return [(e['v'], 3)]
    if e['m'] in ('JSR', 'RTS', 'RTI', 'BRK'): raise SystemExit(f'{e["m"]} inside the kernel')
    return [(nxt, e['cyc'])]
def is_wsync(e): return e['m'] == 'STA' and e['mode'] == 'zp' and e['v'] == int(EQ['WSYNC'].lstrip('$'), 16)
paths = []            # (start_label_or_addr, [addresses], total, ended_by)
def walk(start, addr, trail, total, byworst, ends):
    e = byaddr[addr]
    if addr in [t for t, _ in trail]: raise SystemExit(f'loop inside a line at {addr:#06x}')
    for nxt, c in succ(e):
        t = total + c; tr = trail + [(addr, t)]
        if is_wsync(e): ends.append((tr, 'WSYNC')); return
        if nxt == KE: ends.append((tr, 'exit')); continue
        if nxt > KE or nxt < KS: raise SystemExit(f'path leaves the kernel at {nxt:#06x}')
        walk(start, nxt, tr, t, byworst, ends)
# the WSYNC store has 3 cycles; for it succ() gives (next, 3)
starts = [(e['pc'] + e['size']) for e in entries if KS <= e['pc'] < KE and is_wsync(e)]
P('Kernel line paths: from the instruction after each STA WSYNC to the next STA WSYNC (inclusive), worst-case page crossings assumed.')
P('Limit: 76 cycles per line (228 colour clocks / 3). "write cycle" = cycle count at the end of the STA.\n')
allmax = 0; deadlines = {}; exit_cycles = []
for s in starts:
    ends = []; walk(s, s, [], 0, None, ends)
    P(f'Start {s:04X} ({",".join(lab_at.get(s, [])) or "-"}):')
    for tr, how in ends:
        tot = tr[-1][1]
        if how == 'WSYNC': allmax = max(allmax, tot)
        else: exit_cycles.append(tot)
        names = [(byaddr[a]['text'], c) for a, c in tr]
        P(f'  path {len(names)} instrs, {tot:>2} cycles ({how}), margin {76 - tot if how == "WSYNC" else "-"}')
        if how == 'WSYNC' and tot > 76: fail = True; P('  ** OVER 76 **')
        for a, c in tr:
            e = byaddr[a]
            if e['by'] is not None:
                deadlines.setdefault((a, e['by']), []).append(c)
P('')
for (a, by), cs in sorted(deadlines.items()):
    e = byaddr[a]; ok = max(cs) <= by; fail |= not ok
    P(f'deadline {e["text"]:<18} write cycle max {max(cs):>2} <= {by}: {"ok" if ok else "FAIL"}')
P(f'\nKernel worst case: {allmax} cycles of 76 (every path ends in STA WSYNC at or before that cycle).')
P(f'Kernel exit (last sprite line -> overscan): {sorted(set(exit_cycles))} cycles from line start to kernel_end.')

# ---------------------------------------------------------------- RIOT timer windows
P('\nTimer windows (RIOT TIM64T, 64 cycles per count; the poll loop adds <= 6):')
def straight(frm, to_label):
    a = labels[frm]; t = labels[to_label]; tot = 0
    while True:
        e = byaddr[a]; tot += e['cyc']
        if a == t: return tot, e
        if e['m'] in A.BRANCH or e['m'] in ('JMP', 'JSR'): raise SystemExit('branch in straight-line timer path')
        a += e['size']
def timer(name, frm, lab, lines_n, extra):
    global fail
    c, e = straight(frm, lab); c += extra
    prev = max(x for x in byaddr if x < e['pc']); n = byaddr[prev]['v']
    lo = c + 64 * n; hi = lo + 6; wl, wh = (lines_n - 1) * 76, lines_n * 76
    ok = wl <= lo and hi < wh; fail |= not ok
    P(f'  {name}: TIM64T={n} written at cycle {c}; expires {lo}..{hi}; must fall in line {lines_n} = {wl}..{wh - 1}: {"ok" if ok else "FAIL"}')
timer('VBLANK (37 lines)', 'vb_start', 'vb_t', 37, 0)
timer('overscan (30 lines)', 'kernel_end', 'ov_t', 30, min(exit_cycles))
P(f'\nFrame: 3 + 37 + 192 + 30 = {3 + 37 + 192 + 30} lines; kernel = {BANDS} bands x (1 setup + 7 sprite) = {BANDS * 8} lines.')
P(f'Image: 4096 bytes at $F000, sha256 {sha}')
P(f'Code ends at ${max(e["pc"] + e["size"] for e in entries if e["pc"] < 0xF200):04X} (tables from $F200).')
P('RESULT: ' + ('FAIL' if fail else 'PASS'))
os.makedirs(os.path.join(ROOT, 'logs'), exist_ok=True)
open(os.path.join(ROOT, 'logs', 'demo-cycles.log'), 'w').write('\n'.join(log) + '\n')
print('\n'.join(log))
sys.exit(1 if fail else 0)
