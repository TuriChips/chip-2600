#!/usr/bin/env python3
"""Reference-frame helpers for the MVT screenshot tests (spec section 9, caveat (d)).

  ntsc_palette()      the 128-entry NTSC table, read from the pinned missingno source at run time
                      (build/mvt/src-missingno/.../tia/palette.rs); nothing copied into this repo.
  inverse_map()       RGB -> 7-bit colour code, where code = (colour byte) >> 1 = hue(4):luma(3).
  decode_png(path)    8-bit RGBA PNG -> (width, height, rows of RGB tuples); stdlib only.
  ref_codes(path)     decode_png + inverse_map: rows of 7-bit codes, or raises on a colour not in the table.
Usage: mvt_ref.py [build/mvt]   checks all 27 reference PNGs map to codes, prints sizes.
"""
import re, struct, sys, zlib, os, glob

PALETTE_RS = 'src-missingno/crates/systems/vcs/src/tia/palette.rs'

def ntsc_palette(mvt_dir):
    src = open(os.path.join(mvt_dir, PALETTE_RS)).read()
    i = src.index('const NTSC_PALETTE'); j = src.index('];', i)
    pal = [tuple(map(int, m)) for m in re.findall(r'\((\d+), (\d+), (\d+)\)', src[i:j])]
    assert len(pal) == 128 and len(set(pal)) == 128, 'palette must be 128 distinct colours'
    return pal

def inverse_map(mvt_dir):
    return {rgb: code for code, rgb in enumerate(ntsc_palette(mvt_dir))}

def decode_png(path):
    b = open(path, 'rb').read()
    assert b[:8] == b'\x89PNG\r\n\x1a\n'
    pos, idat = 8, b''
    while pos < len(b):
        n, t = struct.unpack('>I4s', b[pos:pos + 8]); d = b[pos + 8:pos + 8 + n]; pos += 12 + n
        if t == b'IHDR':
            w, h, depth, ctype, _, _, interlace = struct.unpack('>IIBBBBB', d)
            assert (depth, ctype, interlace) == (8, 6, 0), 'expected 8-bit RGBA, not interlaced'
        elif t == b'IDAT':
            idat += d
    raw, bpp, stride = zlib.decompress(idat), 4, 4 * w
    rows, prev = [], bytearray(stride)
    for y in range(h):
        f = raw[y * (stride + 1)]; cur = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for x in range(stride):
            a = cur[x - bpp] if x >= bpp else 0; up = prev[x]; c = prev[x - bpp] if x >= bpp else 0
            if f == 1: cur[x] = (cur[x] + a) & 255
            elif f == 2: cur[x] = (cur[x] + up) & 255
            elif f == 3: cur[x] = (cur[x] + (a + up) // 2) & 255
            elif f == 4:
                p = a + up - c; pa, pb, pc = abs(p - a), abs(p - up), abs(p - c)
                cur[x] = (cur[x] + (a if pa <= pb and pa <= pc else up if pb <= pc else c)) & 255
        rows.append([tuple(cur[4 * i:4 * i + 3]) for i in range(w)]); prev = cur
    return w, h, rows

def ref_codes(path, inv):
    w, h, rows = decode_png(path)
    return w, h, [[inv[p] for p in r] for r in rows]

if __name__ == '__main__':
    d = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), '..', 'build', 'mvt')
    inv = inverse_map(d)
    for p in sorted(glob.glob(os.path.join(d, 'refs', '*', '*_ntsc.png'))):
        w, h, rows = ref_codes(p, inv)
        print('%-40s %dx%d codes=%d' % (os.path.relpath(p, os.path.join(d, 'refs')), w, h, len({c for r in rows for c in r})))
