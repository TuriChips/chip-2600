#!/usr/bin/env python3
"""Reachable-code scan of 2600 ROM images for undocumented 6502 opcodes.

Recursive descent from the reset vector ($FFFC): follows JMP, JSR, branches and the
fall-through of every instruction, never a byte grep. Data bytes that are never reached
are never decoded. Reports every undocumented opcode on a reached path, plus anything
the trace cannot follow (JMP indirect, RTS/RTI with no known return, code outside ROM,
a jump into the middle of an instruction, writes into the ROM window).

Usage: opscan.py ROM.a26 [ROM.a26 ...]   (4 KB images at $F000)
Output, one line per finding:  <rom>: <KIND> $addr op=$xx <detail>
"""
import sys, os

# documented NMOS 6502: mnemonic, mode per opcode
DOC = {}
def add(m, modes):
    for mode, op in modes.items():
        DOC[op] = (m, mode)
ALU = {'ORA':0x01,'AND':0x21,'EOR':0x41,'ADC':0x61,'STA':0x81,'LDA':0xA1,'CMP':0xC1,'SBC':0xE1}
for m, b in ALU.items():
    md = {'izx':b,'zp':b+4,'imm':b+8,'abs':b+0xC,'izy':b+0x10,'zpx':b+0x14,'aby':b+0x18,'abx':b+0x1C}
    if m == 'STA': del md['imm']
    add(m, md)
SH = {'ASL':0x02,'ROL':0x22,'LSR':0x42,'ROR':0x62}
for m, b in SH.items():
    add(m, {'zp':b+4,'acc':b+8,'abs':b+0xC,'zpx':b+0x14,'abx':b+0x1C})
add('STX', {'zp':0x86,'abs':0x8E,'zpy':0x96})
add('LDX', {'imm':0xA2,'zp':0xA6,'abs':0xAE,'zpy':0xB6,'aby':0xBE})
add('DEC', {'zp':0xC6,'abs':0xCE,'zpx':0xD6,'abx':0xDE})
add('INC', {'zp':0xE6,'abs':0xEE,'zpx':0xF6,'abx':0xFE})
add('STY', {'zp':0x84,'abs':0x8C,'zpx':0x94})
add('LDY', {'imm':0xA0,'zp':0xA4,'abs':0xAC,'zpx':0xB4,'abx':0xBC})
add('CPY', {'imm':0xC0,'zp':0xC4,'abs':0xCC})
add('CPX', {'imm':0xE0,'zp':0xE4,'abs':0xEC})
add('BIT', {'zp':0x24,'abs':0x2C})
add('JMP', {'abs':0x4C,'ind':0x6C})
add('JSR', {'abs':0x20})
for m, op in {'BPL':0x10,'BMI':0x30,'BVC':0x50,'BVS':0x70,'BCC':0x90,'BCS':0xB0,'BNE':0xD0,'BEQ':0xF0}.items():
    add(m, {'rel':op})
for m, op in {'BRK':0x00,'PHP':0x08,'CLC':0x18,'PLP':0x28,'SEC':0x38,'RTI':0x40,'PHA':0x48,'CLI':0x58,
              'RTS':0x60,'PLA':0x68,'SEI':0x78,'DEY':0x88,'TXA':0x8A,'TYA':0x98,'TXS':0x9A,'TAY':0xA8,
              'TAX':0xAA,'CLV':0xB8,'TSX':0xBA,'INY':0xC8,'DEX':0xCA,'CLD':0xD8,'INX':0xE8,'NOP':0xEA,
              'SED':0xF8}.items():
    add(m, {'imp':op})
assert len(DOC) == 151, len(DOC)
LEN = {'imp':1,'acc':1,'imm':2,'zp':2,'zpx':2,'zpy':2,'izx':2,'izy':2,'rel':2,'abs':3,'abx':3,'aby':3,'ind':3}
# Length of an undocumented opcode (NMOS column pattern), only so the trace can go on past it.
def undoc_len(op):
    cc, bbb = op & 3, (op >> 2) & 7
    if cc == 0:
        return {0:2,1:2,2:1,3:3,4:2,5:2,6:1,7:3}[bbb]
    if cc == 2:
        return {0:2,1:2,2:1,3:3,4:1,5:2,6:1,7:3}[bbb]
    return {0:2,1:2,2:2,3:3,4:2,5:2,6:3,7:3}[bbb]

ROM_BASE = 0xF000

def scan(path):
    rom = open(path, 'rb').read()
    if len(rom) != 4096:
        return [('SIZE', 0, 0, 'image is %d bytes, not 4096' % len(rom))], {}
    out, seen, starts, work = [], {}, set(), []
    def peek(a):
        return rom[a & 0xFFF]
    def inrom(a):
        return a & 0x1000 != 0           # 6507: A12 selects the cartridge
    def push(a, why):
        a &= 0x1FFF
        if not inrom(a):
            out.append(('NONROM', a, 0, why)); return
        work.append((a, why))
    reset = peek(0xFFC) | peek(0xFFD) << 8
    push(reset, 'reset vector')
    immstore = {}                          # zp address -> immediates stored there (LDx #n ; STx zp)
    jmpind = {}                            # pc of JMP (zp) -> pointer address
    resolved = set()
    sleds = {}                             # pc of JMP (zp) -> length of the NOP run after it
    while True:
      while work:
          pc, why = work.pop()
          prev = None
          while True:
              pc &= 0x1FFF
              if not inrom(pc):
                  out.append(('NONROM', pc, 0, 'falls into non-ROM from ' + why)); break
              if pc in starts: break
              if 'sled entry' not in why and any(pc in seen.get(k, ()) for k in range(max(0, pc - 2), pc)):
                  out.append(('MIDINSN', pc, peek(pc), 'entered inside an instruction, via ' + why))
              op = peek(pc)
              if op in DOC:
                  m, mode = DOC[op]; n = LEN[mode]
              else:
                  m, mode, n = '???', None, undoc_len(op)
                  out.append(('UNDOC', pc, op, 'len %d, reached via %s' % (n, why)))
              starts.add(pc); seen[pc] = range(pc + 1, pc + n)
              b1 = peek(pc + 1) if n > 1 else 0
              b2 = peek(pc + 2) if n > 2 else 0
              nxt = pc + n
              if mode == 'rel':
                  push(nxt + (b1 - 256 if b1 > 127 else b1), 'branch at $%04X' % pc)
              elif m == 'JMP' and mode == 'abs':
                  push(b1 | b2 << 8, 'JMP at $%04X' % pc); break
              elif m == 'JMP':
                  jmpind[pc] = b1 | b2 << 8; break
              elif m == 'JSR':
                  push(b1 | b2 << 8, 'JSR at $%04X' % pc)
              elif m in ('RTS', 'RTI'):
                  break                      # return sites are the instructions after each JSR, already queued
              elif m == 'BRK' or op in (0x02,0x12,0x22,0x32,0x42,0x52,0x62,0x72,0x92,0xB2,0xD2,0xF2):
                  break
              if m in ('STA','STX','STY') and mode == 'zp' and prev and prev[0] == 'L' + m[1:] and prev[1] == 'imm':
                  immstore.setdefault(b1, set()).add(prev[2])
              prev = (m, mode, b1)
              if m in ('STA','STX','STY') and mode in ('abs','abx','aby') and inrom(b1 | b2 << 8):
                  out.append(('ROMWRITE', pc, op, '%s $%04X (cartridge window)' % (m, b1 | b2 << 8)))
              why = 'fall-through of $%04X' % pc
              pc = nxt
      new = False
      for jpc, ptr in jmpind.items():
          los, his = immstore.get(ptr, ()), immstore.get(ptr + 1, ())
          for lo in los:
              for hi in his:
                  t = (hi << 8 | lo) & 0x1FFF
                  if t not in resolved and inrom(t):
                      resolved.add(t); push(t, 'JMP (ptr $%02X) at $%04X' % (ptr, jpc)); new = True
      # JMP (zp) whose pointer is computed (Sled + index): accept it only if a run of NOPs ($EA)
      # follows the JMP, every entry point of which runs on into the code after the run
      for jpc, ptr in jmpind.items():
          if jpc in sleds or (immstore.get(ptr) and immstore.get(ptr + 1)):
              continue
          run = 0
          while peek(jpc + 3 + run) in (0xEA, 0xC9):      # NOP sled, or CMP #imm slide
              run += 1
          if peek(jpc + 3 + run) == 0xC5 and peek(jpc + 4 + run) == 0xEA:
              run += 1                                    # the slide's tail: CMP zp
          if run:
              sleds[jpc] = run
              for k in range(run + 1):                    # every entry offset the pointer could select
                  push(jpc + 3 + k, 'sled entry +%d after JMP ($%02X) at $%04X' % (k, ptr, jpc))
              new = True
      if not new: break
    for jpc, ptr in jmpind.items():
        if jpc not in sleds and not (immstore.get(ptr) and immstore.get(ptr + 1)):
            out.append(('JMPIND', jpc, 0x6C, 'JMP ($%04X): pointer not set by LDx #n / STx in reached code' % ptr))
    return out, {'reset': reset, 'insns': len(starts), 'sleds': sleds}

if __name__ == '__main__':
    bad = 0
    for p in sys.argv[1:]:
        res, info = scan(p)
        name = os.path.basename(os.path.dirname(p)) + '/' + os.path.basename(p)
        print('%s: reset=$%04X reached_insns=%s findings=%d%s' % (name, info.get('reset', 0), info.get('insns'), len(res),
              ''.join(' sled@$%04X+%d' % kv for kv in sorted(info.get('sleds', {}).items()))))
        for kind, a, op, d in sorted(set(res)):
            print('  %s $%04X op=$%02X %s' % (kind, a, op, d)); bad += 1
    sys.exit(1 if bad else 0)
