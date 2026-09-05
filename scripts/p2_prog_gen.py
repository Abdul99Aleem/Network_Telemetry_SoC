#!/usr/bin/env python3
"""Phase-2 VeeR program generator (RV32I mini-assembler).

Emits p2_prog.hex (Verilog $readmemh format) for IMEM at 0x0000_0000.
The program writes 'P','2' to DMEM, reads the word back, stores it,
then writes the 0xFF terminator that the TB watches for PASS.

Usage:  python3 scripts/p2_prog_gen.py <out.hex>
"""
import sys

ZERO, GP, A0, A1 = 0, 3, 10, 11


def lui(rd, imm20):
    assert 0 <= imm20 < (1 << 20)
    return ((imm20 << 12) | (rd << 7) | 0x37) & 0xFFFFFFFF


def addi(rd, rs1, imm12):
    assert -(1 << 11) <= imm12 < (1 << 12)
    return (((imm12 & 0xFFF) << 20) | (rs1 << 15) | (0 << 12) | (rd << 7) | 0x13)


def sb(rs2, imm12, rs1):
    assert 0 <= imm12 < (1 << 12)
    return ((((imm12 >> 5) & 0x7F) << 25) | ((rs2 & 0x1F) << 20) |
            ((rs1 & 0x1F) << 15) | (0 << 12) | ((imm12 & 0x1F) << 7) | 0x23)


def lw(rd, imm12, rs1):
    assert 0 <= imm12 < (1 << 12)
    return (((imm12 & 0xFFF) << 20) | ((rs1 & 0x1F) << 15) |
            (2 << 12) | ((rd & 0x1F) << 7) | 0x03)


def sw(rs2, imm12, rs1):
    assert 0 <= imm12 < (1 << 12)
    return ((((imm12 >> 5) & 0x7F) << 25) | ((rs2 & 0x1F) << 20) |
            ((rs1 & 0x1F) << 15) | (2 << 12) | ((imm12 & 0x1F) << 7) | 0x23)


def jal(rd, off):
    assert off == 0  # parked loop only
    return 0x0000006F


# Self-check against Phase-1 exec.log evidence
assert lui(3, 0xD0580) == 0xD05801B7, hex(lui(3, 0xD0580))
assert sb(10, 0, 3) == 0x00A18023, hex(sb(10, 0, 3))

prog = [
    lui(GP, 0x10),        # 0x00: gp = DMEM base 0x00010000
    addi(A0, ZERO, 0x50),  # 0x04: a0 = 'P'
    sb(A0, 0, GP),        # 0x08: DMEM[0] = 'P'
    addi(A0, ZERO, 0x32),  # 0x0C: a0 = '2'
    sb(A0, 1, GP),        # 0x10: DMEM[1] = '2'
    lw(A1, 0, GP),        # 0x14: a1 = DMEM word (expect 0x00003250)
    sw(A1, 4, GP),        # 0x18: DMEM[4..7] = a1
    addi(A0, ZERO, 0xFF),  # 0x1C: terminator
    sb(A0, 2, GP),        # 0x20: DMEM[2] = 0xFF -> TB PASS
    jal(0, 0),            # 0x24: park
]

out = sys.argv[1] if len(sys.argv) > 1 else "p2_prog.hex"
with open(out, "w") as f:
    f.write("@00000000\n")
    # Byte-per-token, address order (little-endian), like the VeeR canned hex.
    n = 0
    for w in prog:
        for b in (w & 0xFF, (w >> 8) & 0xFF, (w >> 16) & 0xFF, (w >> 24) & 0xFF):
            f.write("%02X " % b)
            n += 1
            if n % 16 == 0:
                f.write("\n")
    f.write("\n")
print("wrote %s (%d words)" % (out, len(prog)))
print("expected DMEM[0..7] = 50 32 FF 00 50 32 00 00")
