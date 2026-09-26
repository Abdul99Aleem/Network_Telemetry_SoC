#!/usr/bin/env python3
"""UART end-to-end program generator (RV32I mini-assembler).

Emits uart_prog.hex (Verilog $readmemh format) for IMEM at 0x0000_0000.

The program exercises the full documented path:

    VeeR EL2 -> AHB-Lite fabric -> ahb_to_axi_bridge -> uart_axi_slave
             -> axi_uart_top -> uart_transmitter -> uart_tx_o

  * unrolled putc() of "UART\\n" through THR @ 0x1000_0000 (LSR-THRE polled)
  * wait for LSR.TEMT so every byte has fully left the shifter
  * read LSR back over the same path and park it in DMEM[4..7]
  * write the 0xFF DMEM terminator the TB watches for (Phase-2 convention)

Usage:  python3 scripts/p3_uart_prog_gen.py <out.hex>
"""
import sys

X0, T0, T1, T2, S0, S1, A0 = 0, 5, 6, 7, 8, 9, 10

UART_BASE_HI = 0x10000   # lui -> 0x1000_0000
DMEM_BASE_HI = 0x10      # lui -> 0x0001_0000
OFF_THR, OFF_LSR = 0x00, 0x14
LSR_THRE, LSR_TEMT = 0x20, 0x40
PAYLOAD = [ord(c) for c in "UART"] + [0x0A]

# VeeR memory-region control.  MRAC packs {side_effect, cacheable} pairs;
# csr_idx = {addr[31:28], 1'b1}, so the UART region (0x1xxx_xxxx) is MRAC[3].
# side_effect=1 forces every LSU load of LSR to reach the bus instead of
# being forwarded from the load buffer (el2_lsu_bus_buffer obuf_nosend).
MRAC = 0x7C0
MRAC_UART_SIDE_EFFECT = 1 << 3   # 0x0000_0008


# ------------------------------- encoders ----------------------------------
def lui(rd, imm20):
    assert 0 <= imm20 < (1 << 20)
    return ((imm20 << 12) | (rd << 7) | 0x37)


def itype(imm12, rs1, funct3, rd, opcode):
    assert -(1 << 11) <= imm12 < (1 << 12)
    return (((imm12 & 0xFFF) << 20) | (rs1 << 15) | (funct3 << 12) |
            (rd << 7) | opcode)


def addi(rd, rs1, imm12):
    return itype(imm12, rs1, 0b000, rd, 0x13)


def andi(rd, rs1, imm12):
    return itype(imm12, rs1, 0b111, rd, 0x13)


def csrw(csr, rs1):
    """csrw csr, rs1  ==  csrrw x0, csr, rs1."""
    assert 0 <= csr < (1 << 12)
    return itype(csr, rs1, 0b001, 0, 0x73)


def stype(imm12, rs2, rs1, funct3, opcode):
    assert 0 <= imm12 < (1 << 12)
    return ((((imm12 >> 5) & 0x7F) << 25) | ((rs2 & 0x1F) << 20) |
            ((rs1 & 0x1F) << 15) | (funct3 << 12) |
            ((imm12 & 0x1F) << 7) | opcode)


def sb(rs2, imm12, rs1):
    return stype(imm12, rs2, rs1, 0b000, 0x23)


def sw(rs2, imm12, rs1):
    return stype(imm12, rs2, rs1, 0b010, 0x23)


def lw(rd, imm12, rs1):
    return itype(imm12, rs1, 0b010, rd, 0x03)


def branch(imm, rs1, rs2, funct3):
    assert imm % 2 == 0 and -(1 << 12) <= imm < (1 << 12)
    b12, b11 = (imm >> 12) & 1, (imm >> 11) & 1
    b10_5, b4_1 = (imm >> 5) & 0x3F, (imm >> 1) & 0xF
    return ((b12 << 31) | (b10_5 << 25) | ((rs2 & 0x1F) << 20) |
            ((rs1 & 0x1F) << 15) | (funct3 << 12) | (b4_1 << 8) |
            (b11 << 7) | 0x63)


def beq(rs1, rs2, imm):
    return branch(imm, rs1, rs2, 0b000)


def bne(rs1, rs2, imm):
    return branch(imm, rs1, rs2, 0b001)


def jal(rd, imm):
    assert imm % 2 == 0 and -(1 << 20) <= imm < (1 << 20)
    b20, b19_12 = (imm >> 20) & 1, (imm >> 12) & 0xFF
    b11, b10_1 = (imm >> 11) & 1, (imm >> 1) & 0x3FF
    return ((b20 << 31) | (b10_1 << 21) | (b11 << 20) |
            (b19_12 << 12) | ((rd & 0x1F) << 7) | 0x6F)


# ------------------------------ program ------------------------------------
prog = [
    lui(S0, UART_BASE_HI),        # s0 = 0x1000_0000 UART
    lui(S1, DMEM_BASE_HI),        # s1 = 0x0001_0000 DMEM
    # MRAC has no hardware reset; write it explicitly and mark the UART
    # region side-effect so LSR polls are never load-buffer forwarded.
    addi(T0, X0, MRAC_UART_SIDE_EFFECT),
    csrw(MRAC, T0),
]
loop_heads = []


def putc(ch):
    """a0 = ch; THR = ch; spin until LSR.THRE.  5 words, loop back -8."""
    loop_heads.append(len(prog) + 2)
    prog.extend([
        addi(A0, X0, ch),          # a0 = byte
        sw(A0, OFF_THR, S0),       # UART.THR = byte
        lw(T0, OFF_LSR, S0),       # t0 = UART.LSR   <- loop head
        andi(T0, T0, LSR_THRE),    # t0 &= THRE
        beq(T0, X0, -8),           # while (!THRE) goto loop head
    ])


for c in PAYLOAD:
    putc(c)

loop_heads.append(len(prog))
prog.extend([
    # spin until LSR.TEMT -> every byte has left the shifter
    lw(T1, OFF_LSR, S0),           # t1 = UART.LSR   <- loop head
    andi(T1, T1, LSR_TEMT),        # t1 &= TEMT
    beq(T1, X0, -8),               # while (!TEMT) goto loop head

    lw(T1, OFF_LSR, S0),           # t1 = final LSR (expect 0x00000060)
    sw(T1, 4, S1),                 # DMEM[4..7] = LSR

    addi(T2, X0, 0xFF),
    sb(T2, 2, S1),                 # DMEM[2] = 0xFF -> TB PASS gate

    jal(X0, 0),                    # park
])

# self-check: every spin loop really branches back to its own head
assert len(loop_heads) == len(PAYLOAD) + 1
for head in loop_heads:
    assert prog[head + 2] in (beq(T0, X0, -8), beq(T1, X0, -8))

out = sys.argv[1] if len(sys.argv) > 1 else "uart_prog.hex"
with open(out, "w") as f:
    f.write("@00000000\n")
    n = 0
    for w in prog:
        for b in (w & 0xFF, (w >> 8) & 0xFF, (w >> 16) & 0xFF, (w >> 24) & 0xFF):
            f.write("%02X " % b)
            n += 1
            if n % 16 == 0:
                f.write("\n")
    f.write("\n")
print("wrote %s (%d words = %d bytes)" % (out, len(prog), len(prog) * 4))
print("payload: %s" % "".join(chr(c) if 32 <= c < 127 else "\\n" for c in PAYLOAD))
