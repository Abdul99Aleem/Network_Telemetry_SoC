# SW/HW Memory-Image Architecture — First-Principles Analysis and Spec Amendments

**Project:** RISC-V Network Telemetry SoC
**Status:** Review of the draft specification *Embedded Software Build and RTL Simulation Image Architecture Specification*
**Date:** 2026-09-26
**Primary processor:** VeeR EL2 RV32IMC (`core/Cores-VeeR-EL2` @ `06ad26a`, locked submodule)
**Toolchain:** `riscv64-unknown-elf-gcc` 16.1.0 / Binutils 2.47.20260726 (`/opt/riscv`)
**Simulator:** Synopsys VCS U-2023.03 + Verdi U-2023.03-SP1

---

## 0. Purpose

This document does three things:

1. States the underlying problem from first principles, so the frozen specification
   is understood rather than memorised.
2. **Verifies the three corrections** raised against the draft specification, with
   reproducible evidence from this machine and from the VeeR RTL itself.
3. Lists **numbered, concrete amendments** (§H) that must be folded into the
   specification before it is frozen.

Related records:

| Document | Role |
|---|---|
| `RISC_V_GNU_Toolchain_Setup_and_Validation_Record.md` | Toolchain bring-up evidence |
| `Phase1_VeeR_Bringup_Completion_Record.md` | VeeR boots, executes, AHB transaction |
| `Phase2_AHB_Fabric_Completion_Record.md` | Project fabric + VeeR boots from IMEM @ `0x0` |
| `RISC_V_Network_Telemetry_SoC_Architecture_Document_v3.md` | Authoritative SoC architecture (memory map §9) |

---

# PART A — What is currently in flight

opencode records session state in `~/.local/share/opencode/opencode.db`. At the
time of writing there are three `opencode` processes and these sessions:

| Session | Title | State |
|---|---|---|
| `ses_f237e9d18…` | Explore VeeR RTL config (`@explore` subagent) | 40 messages, report delivered |
| `ses_f237fed17…` | SW/HW memory image architecture for VeeR SoC | idle (2 messages) |
| `ses_f2378bb50…` | Understanding VeeR firmware build and memory image flow | this review |

The draft specification was produced by a session that spawned an `@explore`
subagent to research VeeR's RTL *before* freezing the spec. That is the correct
order of operations: it corresponds to checklist item **B (VeeR Configuration)**
in the draft.

The subagent's research report (≈31 KB) established, and this review independently
re-verified, the following:

- VeeR configuration is **generated at build time** by `configs/veer.config`
  (Perl) into `el2_param.vh`, `common_defines.vh`, `defines.h`, `link.ld`.
  No configuration header is checked in, and `/tmp/opencode/veer_p2` (the
  Phase-2 workdir) has been cleaned, so those files must be regenerated.
- **`iccm_enable = 1` and `dccm_enable = 1` by default** — 64 KB each, 4 banks,
  `ram_4096x39`.
- ICCM `0xEE000000–0xEE00FFFF`, DCCM `0xF0040000–0xF004FFFF`
  (address = `256 MB × region + offset`).
- `dccm_addr_xor = 0`, `iccm_addr_xor = 0`, `lockstep_enable = 0`.
- ICCM/DCCM storage is a **single 39-bit array** `reg [38:0] ram_core [4095:0]`
  per bank, with ECC stored **inline at bits [38:32]** — not in a separate array.
- **There is no `sw/`, `firmware/` or `software/` directory in the repository.**
  All software today lives inside the VeeR submodule (`testbench/asm/`,
  `testbench/tests/`).
- `ahb_sram.BASE_ADDR` is a **dead parameter** — declared, never referenced in
  the body.

Uncommitted work also exists in the tree (`.gitignore` rewrite, the toolchain
record, `rtl/uart/`, `tb/tb_uart*`). The repository has work in flight.

---

# PART B — First principles: the problem being solved

A processor does one thing:

> At each clock, read a value at address `A`, interpret it, update state.

In RTL simulation, memory arrays initialise to **`X`** (4-state unknown). If the
CPU fetches `X`, everything downstream is `X` and nothing is checkable.

Therefore the entire problem reduces to:

> **Place specific byte values at specific addresses before the CPU is released
> from reset.**

Two independent machines produce this:

- **Software** (compiler + linker) decides *what bytes, at what addresses*.
- **Hardware** (RTL + testbench) owns *the physical arrays and the reset timing*.

They share exactly one thing — a **contract**: the set of `(address, byte)` pairs.
No compiler knows about VCS. No RTL knows about `main.c`.

Everything in the draft specification is an elaboration of that one sentence.

---

# PART C — The software path from first principles

## C.1 Why a cross-compiler, and what `-march`/`-mabi` really do

The host is x86-64; VeeR executes RISC-V; hence `riscv64-unknown-elf-gcc`.

**The executable name says nothing about the output ISA.** Verified on this
machine:

```console
$ riscv64-unknown-elf-gcc -march=rv32imc_zicsr_zifencei -mabi=ilp32 \
      -O0 -ffreestanding -nostdlib -Wl,-T,demo.ld -o demo.elf demo.c

$ riscv64-unknown-elf-readelf -A demo.elf
Attribute Section: riscv
File Attributes
  Tag_RISCV_stack_align: 16-bytes
  Tag_RISCV_arch: "rv32i2p1_m2p0_c2p0_zicsr2p0_zifencei2p0_zmmul1p0_zca1p0"
```

GCC expands `rv32imc` into `rv32i2p1_m2p0_c2p0` and appends the explicitly named
extensions.

> **`zicsr` and `zifencei` are mandatory in modern binutils.** Without them
> `csrw` and `fence.i` fail to assemble. Startup and interrupt setup need both.

**⇒ Amendment H.8:** the frozen `ARCH := rv32imc` from draft §11 is insufficient.

## C.2 A linker script is an address allocator

The compiler emits *relocatable* `.o` files with no addresses. The linker assigns
them. The location counter `.` is the whole mechanism:

```ld
SECTIONS {
  . = 0x00000000;
  .text   : { *(.text*) }
  .rodata : { *(.rodata*) }
  . = 0x00010000;
  .data   : { *(.data*) }
  .bss    : { *(.bss*) }
}
```

This is the single place where software's view of the memory map is encoded —
which is why draft §4/§5 are correct to call it critical, and why it cannot be
written until the VeeR build configuration is frozen (draft §5).

## C.3 What ELF is, and the `.bss` consequence

ELF is a **container**: a header plus tables saying "these N bytes belong at
address X, with these flags." Real output from this machine:

```console
$ riscv64-unknown-elf-readelf -SW demo.elf
  [ 1] .text    PROGBITS  00000000 001000 00001a 00  AX  0  0  2
  [ 2] .srodata PROGBITS  0000001c 00101c 000006 00   A  0  0  4
  [ 3] .sdata   PROGBITS  00010000 002000 000004 00  WA  0  0  4
  [ 4] .sbss    NOBITS    00010004 002004 000004 00  WA  0  0  4
```

- `PROGBITS` = has bytes in the file. `NOBITS` = **has none**.
- `.srodata` sits at `0x1c`, contiguous with `.text` — the linker merged them
  because nothing forced a gap.

**Why ELF is authoritative (draft §6/§35 correct):** every other artifact is a
lossy projection of this table. Intel HEX drops symbols and debug. `.mem` drops
section names, drops `.bss`, and drops gaps unless `@` records are emitted.

> **The `.bss` rule:** `.sbss` is `NOBITS` — there are literally zero bytes for
> it in the ELF, so **no conversion tool can ever produce them.** Either
> `startup.S` zeros it at boot, or the loader pre-fills the RAM array with zeros.
> Your `rtl/ahb/ahb_sram.sv:47-50` already pre-fills. Both mechanisms are
> harmless together. Draft checklist **G** asks for an "unused memory
> initialization policy" but never answers it. **⇒ Amendment H.9.**

---

# PART D — Correction 1 and 2: `$readmemh` vs `$fread`, Intel HEX vs Verilog hex

## D.1 `$readmemh` vs `$fread`

The draft's correction is right. Precise distinction:

| Task | Argument | Parses |
|---|---|---|
| `$readmemh("f", mem)` | **filename string** | Text: hex tokens, `@<addr>` records, `_` separators |
| `$fread(mem, fd)` | **integer file handle** from `$fopen` | **Raw binary bytes**, packed into memory words |

`$fread` gives you bytes from a binary file; you would have to write your own
parser for anything structured. `$readmemh` is purpose-built for hex memory
images. The draft's usage is correct.

## D.2 Intel HEX vs Verilog hex — real outputs, same ELF

Reproduce with:

```bash
riscv64-unknown-elf-objcopy -O ihex     demo.elf demo.ihex
riscv64-unknown-elf-objcopy -O verilog  demo.elf demo.mem
```

**Intel HEX (`-O ihex`):**

```text
:10000000411106C622C40008C16783A707001387F1
:0A0010001700C16723A0E700C5BF79
:06001C0048454C4C4F006A
:020000021000EC
:040000002A000000D2
:00000001FF
```

Field-by-field for line 1: `:` start-of-record, `10` = 16 bytes follow,
`0000` = address, `00` = record type **data**, then 16 data bytes, `F1` =
checksum. Line 4 `:020000021000EC` is type **02 — extended segment address**,
which relocates everything after it. Line 6 `:00000001FF` is type **01 — EOF**.

`$readmemh` understands **none** of this. It has no concept of record types, no
checksum verification, no length field. Feeding it `:10000000…` would attempt to
parse `:10000000` as a hex token and either error or write garbage.

**Verilog hex (`-O verilog`):**

```text
@00000000
41 11 06 C6 22 C4 00 08 C1 67 83 A7 07 00 13 87
17 00 C1 67 23 A0 E7 00 C5 BF
@0000001C
48 45 4C 4C 4F 00
@00010000
2A 00 00 00
```

That is `$readmemh`'s grammar exactly: `@<hex address>` sets the write pointer,
subsequent tokens fill consecutive locations.

Cross-check against VeeR's own canned image
`core/Cores-VeeR-EL2/testbench/hex/user_mode0/hello_world.hex`:

```text
@80000000
73 10 20 B0 73 10 20 B8 97 00 00 00 93 80 80 11
...
```

Byte-per-token with an `@` record — the same format.

## D.3 The tool is already named inside your own repository

Draft §8.2 hedges ("an appropriate `objcopy` Verilog output mode or a dedicated
conversion utility"). No hedge is needed — VeeR's own build uses it:

```make
# core/Cores-VeeR-EL2/tools/Makefile:297-300
program.hex: picolibc $(OFILES) ${BUILD_DIR}/defines.h
	$(GCC_PREFIX)-gcc ... -o $(TEST).exe
	$(GCC_PREFIX)-objcopy -O verilog  $(TEST).exe program.hex
```

**⇒ Amendment H.1: freeze `$(OBJCOPY) -O verilog`.**

## D.4 The `--verilog-data-width` trap (absent from the draft)

Same ELF, two widths:

```console
$ riscv64-unknown-elf-objcopy -O verilog --verilog-data-width 1 demo.elf w1.mem
@00000000
41 11 06 C6 22 C4 00 08 C1 67 83 A7 07 00 13 87
17 00 C1 67 23 A0 E7 00 C5 BF
@0000001C
48 45 4C 4C 4F 00
@00010000
2A 00 00 00

$ riscv64-unknown-elf-objcopy -O verilog --verilog-data-width 4 demo.elf w4.mem
@00000000
C6061141 0800C422 A78367C1 87130007
67C10017 00E7A023 BFC5
@00000007
4C4C4548 004F
@00004000
0000002A
```

Two changes occurred:

1. **The `@` address was divided by the width.** Byte address `0x00010000`
   became index `0x00004000`; `.srodata` at `0x1C` became `0x7`.
   `@` denotes an **array index**, not a byte address — its unit depends on the
   data width.
2. **Bytes were packed into little-endian words.** `41 11 06 C6` → `C6061141`,
   i.e. byte `41` occupies bits [7:0]. Correct for a 32-bit RISC-V load, but
   *only* if the target array is 32-bit wide.

> **Rule:** `--verilog-data-width N` must equal the word width of the target
> array in bytes.
>
> - `ahb_sram.mem` is `reg [7:0] mem[0:32767]` → **N = 1** (the default).
> - VeeR `ram_core` is `reg [38:0] ram_core[0:4095]` → needs **39 bits**, which
>   is not a byte multiple — one more reason ICCM/DCCM cannot take a plain
>   `$readmemh`.

Note the ragged tail in the width-4 output: `BFC5` (two tokens, not four).
`$readmemh` zero-extends it, which means bytes *outside* the ELF become `0`
rather than `X` for that final word only.

---

# PART E — The third problem the draft misses: address rebasing

Draft §35 says "the image generator must not simply concatenate sections." True,
but it omits the concrete failure mode that **your own RTL exhibits today**.

Two array styles coexist in this project:

**VeeR's testbench memory — `core/Cores-VeeR-EL2/testbench/ahb_sif.sv:45`:**

```systemverilog
bit [7:0] mem[bit [31:0]];   // sparse ASSOCIATIVE array; index = absolute byte address
```

`@80000000` works directly, because the index *is* the address.

**Your memory — `rtl/ahb/ahb_sram.sv:44,91`:**

```systemverilog
reg [7:0] mem [0:SIZE_BYTES-1];                          // dense array; index = 0 .. SIZE_BYTES-1
wire [AW-1:0] word_addr = {addr_q[AW-1:3], 3'b000};      // low bits only; AW = clog2(SIZE_BYTES)
```

The index is an **offset from zero**, not an absolute address. A 32 KB array has
valid indices `0..32767`.

**Failure mode:** `.data` at `0x00010000` produces `@00010000`. Loading that file
into the 32 KB IMEM array addresses index `65536` — **out of range**.

Therefore draft §34 "Option A — one flat memory image" **does not work with the
current RTL**. The options:

| Option | Mechanism | Cost |
|---|---|---|
| **A′** | Split the ELF into `imem.mem` + `dmem.mem`, `@` addresses **rebased to 0** | Needs an address-aware converter |
| **B′** | Change the arrays to sparse associative (VeeR `ahb_sif` style) | Simplest, but modifies RTL |
| **C′** | Keep one flat file and rebase inside `$readmemh` | **Not possible** — `$readmemh` takes a filename |
| **D′** | One array spanning the whole address space | Wasteful |

This is *why* draft §9 lists `imem.mem / iccm.mem / dccm.mem` — the draft never
says so. The reason is: **each image's `@` records must be relative to that
memory's array index zero.**

**Related latent defect:** `ahb_sram.BASE_ADDR` (line 18) is declared but never
referenced in the body. The module masks off low address bits and relies entirely
on `ahb_interconnect`'s `HSEL` decode to keep addresses in range. It works today
but aliases silently if the decode ever changes. Worth fixing or documenting.

---

# PART F — Correction 3: ICCM/DCCM and ECC

## F.1 What ECC is, from zero

Memory cells can flip bits. A Hamming code appends check bits so that a **1-bit
error can be located and corrected** and a **2-bit error can be detected**.

VeeR uses **(39,32) SECDED**: 32 data bits + 7 check bits. The encoder is just
XOR trees — `core/Cores-VeeR-EL2/design/lib/beh_lib.sv:659`:

```systemverilog
module rvecc_encode ( input [31:0] din, output [6:0] ecc_out );
  assign ecc_out_temp[0] = din[0]^din[1]^din[3]^din[4]^din[6]^...^din[30];
  assign ecc_out_temp[1] = din[0]^din[2]^din[3]^din[5]^din[6]^...^din[31];
  ...
  assign ecc_out[6:0] = {(^din[31:0])^(^ecc_out_temp[5:0]), ecc_out_temp[5:0]};
endmodule
```

Each check bit covers a fixed subset of data bits. The decoder
(`beh_lib.sv:676`) recomputes them and XORs with the stored bits to produce a
**syndrome**; syndrome `0` means no error.

## F.2 Where it physically lives — Case D, not Case A/B/C

`core/Cores-VeeR-EL2/design/lib/mem_lib.sv:32`:

```systemverilog
`define EL2_RAM(depth, width)
module ram_``depth``x``width(...);
reg [(width-1):0] ram_core [(depth-1):0];    // ONE combined array
```

For ICCM/DCCM this is `ram_4096x39`, instantiated **four times** (one per bank).

**The draft's Case A / B / C do not describe VeeR:**

| Draft case | Reality |
|---|---|
| A — plain data array | ✗ width is 39, not 32 |
| B — separate `data_mem[]` / `ecc_mem[]` | ✗ there is one combined array |
| C — ECC generated by a wrapper/macro model | ✗ the *core* generates ECC on writes; the RAM is dumb |

**Correct description (call it Case D):**

```text
Per bank b ∈ {0,1,2,3}:
    ram_core[4096] of 39 bits
    ram_core[i][31:0]  = data
    ram_core[i][38:32] = ECC (7 bits)

Address → {bank, index} interleave (64 KB region, 4 banks):
    bank  = addr[3:2]        // get_dccm_bank / get_iccm_bank, tb_top.sv:3085 / :3098
    index = addr[15:4]
```

Packing confirmed at `design/lsu/el2_lsu_dccm_mem.sv:107-110` and
`design/ifu/el2_ifu_iccm_mem.sv:117-120`:

```systemverilog
dccm_wr_data_bank[i] = wr_data_bank[i][31:0];
dccm_wr_ecc_bank[i]  = wr_data_bank[i][38:32];
```

## F.3 Four independent ways a naive `$readmemh` breaks

Assume `$readmemh("dccm.mem", <bank>.ram_core)`:

| # | Failure | Why |
|---|---|---|
| 1 | **Word-width mismatch** | Array word = 39 bits; hex tokens are 8 or 32 bits. `$readmemh` zero-extends → `ram_core[i][38:32] = 0`. |
| 2 | **ECC never generated** | ECC bits stay 0 — see F.4, this is not benign. |
| 3 | **Bank/index interleave ignored** | `$readmemh` writes `ram_core[0],[1],[2]…` sequentially. Address `0x00000010` belongs to bank 1 index 1, not bank 0 index 1. Data lands in the wrong bank. |
| 4 | **Address-XOR infection** (conditional) | If `dccm_addr_xor = 1`, the core stores `data ^ word_addr` and XORs on read; the loader must apply the same XOR. Default in this build is `0` and it requires lockstep — **verify, do not assume**. |

## F.4 The killer: naive preload silently corrupts instructions

The draft says naive `$readmemh` "is only valid if the targeted RTL array
representation is compatible with that initialization method." That is diplomatic.
The accurate statement is:

> **It is not compatible, and the failure mode is silent wrong-instruction
> execution — not a clean error report.**

Reproducing `rvecc_encode` / `rvecc_decode` from `beh_lib.sv` exactly
(self-check: valid ECC ⇒ syndrome `0x00`), then preloading a 39-bit array with
plain 32-bit hex so that the ECC field is zero:

```text
word loaded        syndrome   decoder verdict                     what the CPU actually gets
0x00000013         0x4F       SINGLE-BIT → bogus "correction"     0x00000413  (was addi x0,x0,19)
0x00A18023         0x49       SINGLE-BIT → bogus "correction"     0x00A18033  (sb to a different offset!)
0xC6061141         0x25       DOUBLE-BIT → uncorrectable           fetch/load faults
0x0000006F         0x06       DOUBLE-BIT → uncorrectable           fetch/load faults
0x00000000         0x00       no error (ECC(0) == 0 coincidentally) OK
```

Reading that carefully — it is worse than an error report:

- When the data's overall parity is odd, the decoder sees a non-zero syndrome
  with `ecc_check[6] = 1`, declares a **single-bit error**, **flips a bit**
  (`beh_lib.sv:707`: `dout_plus_parity = single_ecc_error ? (error_mask ^ din_plus_parity) : …`),
  and hands the CPU a *different value than was loaded*. `sb a0,0(gp)` becomes a
  store to a different address. **Silent functional corruption.**
- When overall parity is even, it declares **double-bit → uncorrectable**, i.e.
  NMI / exception.
- **All-zero memory is accidentally valid**, because `riscv_ecc32(0) = 0`. That
  is exactly why VeeR's own loader contains this otherwise puzzling ternary.

**Honest caveat:** these errors only surface if something actually reads the
memory and the ECC check is enabled on that path (`en` in `rvecc_decode`). In the
current Phase-2 configuration nothing does — see F.6.

### Reproduction script

Save as `ecc_demo.py` and run `python3 ecc_demo.py`:

```python
# Exact replica of rvecc_encode / rvecc_decode from design/lib/beh_lib.sv

def encode(din):
    b = [(din >> i) & 1 for i in range(32)]
    e = [0] * 6
    e[0] = b[0]^b[1]^b[3]^b[4]^b[6]^b[8]^b[10]^b[11]^b[13]^b[15]^b[17]^b[19]^b[21]^b[23]^b[25]^b[26]^b[28]^b[30]
    e[1] = b[0]^b[2]^b[3]^b[5]^b[6]^b[9]^b[10]^b[12]^b[13]^b[16]^b[17]^b[20]^b[21]^b[24]^b[25]^b[27]^b[28]^b[31]
    e[2] = b[1]^b[2]^b[3]^b[7]^b[8]^b[9]^b[10]^b[14]^b[15]^b[16]^b[17]^b[22]^b[23]^b[24]^b[25]^b[29]^b[30]^b[31]
    e[3] = b[4]^b[5]^b[6]^b[7]^b[8]^b[9]^b[10]^b[18]^b[19]^b[20]^b[21]^b[22]^b[23]^b[24]^b[25]
    e[4] = b[11]^b[12]^b[13]^b[14]^b[15]^b[16]^b[17]^b[18]^b[19]^b[20]^b[21]^b[22]^b[23]^b[24]^b[25]
    e[5] = b[26]^b[27]^b[28]^b[29]^b[30]^b[31]
    # ecc_out[6:0] = { overall_parity, ecc_out_temp[5:0] }
    return e + [((sum(e) + bin(din).count("1")) % 2)]

def decode(din, ecc_in):
    b = [(din >> i) & 1 for i in range(32)]
    c = [0] * 7
    c[0] = ecc_in[0]^b[0]^b[1]^b[3]^b[4]^b[6]^b[8]^b[10]^b[11]^b[13]^b[15]^b[17]^b[19]^b[21]^b[23]^b[25]^b[26]^b[28]^b[30]
    c[1] = ecc_in[1]^b[0]^b[2]^b[3]^b[5]^b[6]^b[9]^b[10]^b[12]^b[13]^b[16]^b[17]^b[20]^b[21]^b[24]^b[25]^b[27]^b[28]^b[31]
    c[2] = ecc_in[2]^b[1]^b[2]^b[3]^b[7]^b[8]^b[9]^b[10]^b[14]^b[15]^b[16]^b[17]^b[22]^b[23]^b[24]^b[25]^b[29]^b[30]^b[31]
    c[3] = ecc_in[3]^b[4]^b[5]^b[6]^b[7]^b[8]^b[9]^b[10]^b[18]^b[19]^b[20]^b[21]^b[22]^b[23]^b[24]^b[25]
    c[4] = ecc_in[4]^b[11]^b[12]^b[13]^b[14]^b[15]^b[16]^b[17]^b[18]^b[19]^b[20]^b[21]^b[22]^b[23]^b[24]^b[25]
    c[5] = ecc_in[5]^b[26]^b[27]^b[28]^b[29]^b[30]^b[31]
    c[6] = ((bin(din).count("1") + sum(ecc_in)) % 2)
    nz = any(c)
    single = nz and c[6]
    double = nz and not c[6]
    pos = sum(v << i for i, v in enumerate(c[:6]))
    # din_plus_parity[38:0] built exactly as in beh_lib.sv:702
    dp = [0] * 39
    dp[38] = ecc_in[6]
    for i in range(6):  dp[37 - i] = b[31 - i]
    dp[31] = ecc_in[5]
    for i in range(15): dp[30 - i] = b[25 - i]
    dp[15] = ecc_in[4]
    for i in range(7):  dp[14 - i] = b[10 - i]
    dp[7] = ecc_in[3]
    for i in range(3):  dp[6 - i] = b[3 - i]
    dp[3], dp[2], dp[1], dp[0] = ecc_in[2], b[0], ecc_in[1], ecc_in[0]
    out = dp[:]
    if single and 1 <= pos <= 39:
        out[pos - 1] ^= 1
    val = (sum(out[32 + i] << i for i in range(6)) << 26) | \
          (sum(out[16 + i] << i for i in range(15)) << 11) | \
          (sum(out[8 + i] << i for i in range(7)) << 4) | \
          (sum(out[4 + i] << i for i in range(3)) << 1) | out[2]
    return c, pos, single, double, val

print("self-check (valid ECC must give syndrome 0):")
for w in [0x00000013, 0x00A18023, 0xC6061141, 0x0000006F]:
    c, _, s, d, val = decode(w, encode(w))
    print(f"  0x{w:08X} syndrome=0x{sum(v<<i for i,v in enumerate(c)):02X} "
          f"{'OK' if (not s and not d and val == w) else 'FAIL'}")

print("\nnaive preload (39-bit array, ECC field = 0):")
for w in [0x00000013, 0x00A18023, 0xC6061141, 0x0000006F, 0x00000000]:
    c, _, s, d, val = decode(w, [0] * 7)
    syn = sum(v << i for i, v in enumerate(c))
    if s and val != w:   v = f"SINGLE-BIT -> CPU fetches 0x{val:08X}"
    elif s:              v = "SINGLE-BIT"
    elif d:              v = "DOUBLE-BIT -> uncorrectable"
    else:                v = "no error (ECC(0)==0)"
    print(f"  0x{w:08X} syndrome=0x{syn:02X}  {v}")
```

## F.5 VeeR's reference implementation — the thing to copy

`core/Cores-VeeR-EL2/testbench/tb_top.sv` already solves this correctly:

```systemverilog
// tb_top.sv:2211-2219 — executed before reset is released
$readmemh("program.hex",  lmem.mem);      // system-bus memories: sparse byte arrays
$readmemh("program.hex",  imem.mem);
preload_dccm();
preload_iccm();

// tb_top.sv:2894-2928 preload_iccm
addr = 'hffff_fff0;                        // range descriptor inside lmem
saddr = {lmem.mem[addr+3],...,lmem.mem[addr]};
...
for (addr = saddr; addr <= eaddr; addr += 4) begin
    data = {imem.mem[addr+3],...,imem.mem[addr]};
`ifdef RV_ICCM_ADDR_XOR
    slam_iccm_ram(addr, {riscv_ecc32(data), data ^ {addr[..],addr[..]}});
`else
    slam_iccm_ram(addr, data == 0 ? 0 : {riscv_ecc32(data), data});
`endif
end

// tb_top.sv:2970-3038 — hierarchical backdoor into the generate loop
`define DRAM(bk) Gen_dccm_enable.dccm_loop[bk].dccm.dccm_bank.ram_core
`define IRAM(bk) Gen_iccm_enable.iccm_loop[bk].iccm.iccm_bank.ram_core
task slam_iccm_ram(input [31:0] addr, input [38:0] data);
    bank = get_iccm_bank(addr, idx);
    case (bank)
      0: `IRAM(0)[idx] = data;
      1: `IRAM(1)[idx] = data;
      ...
```

Key observations:

1. **The ECC is computed by the loader, not stored in the file.** The `.mem`
   file stays plain 32-bit data. This is the correct architecture and the
   draft should say so explicitly.
2. The hierarchy path sits inside a **generate loop** — one call per bank, with
   `bank`/`index` computed by `get_iccm_bank()` / `get_dccm_bank()`.
   Draft §16's warning "do not invent those hierarchy paths" is exactly right.
3. VeeR's testbench lives in the **locked submodule** — it cannot be edited, but
   the *technique* can be replicated in a project-owned `tb/tb_memory_init.sv`.
4. `$readmemh` at `:2211-2212` targets `lmem.mem` / `imem.mem` only — the
   system-bus memories. **VeeR itself never `$readmemh`s ICCM or DCCM.**
5. `riscv_ecc32()` is a 7-line mask function at `tb_top.sv:3073` — copy it verbatim.

## F.6 The escape hatch the draft missed: ICCM/DCCM are simply not used

This is the pragmatic insight nobody wrote down.

**The current Phase-2 configuration never touches ICCM or DCCM.**

```text
p2_soc snapshot = default_ahb + -set=reset_vec=0x00000000

boot PC = 0x00000000
            └ inside ICCM (0xEE000000..0xEE00FFFF)?  NO
            └ → IFU forwards the fetch to the IFU bus → ahb_interconnect → IMEM  ✓

.data/.bss/stack = 0x00010000..0x00017FFF
            └ inside DCCM (0xF0040000..0xF004FFFF)?  NO
            └ → LSU forwards to the LSU bus → DMEM  ✓

ICCM @ 0xEE000000  → enabled, instantiated, never read → ECC never checked
DCCM @ 0xF0040000  → enabled, instantiated, never read → ECC never checked
```

VeeR's routing rule (`docs/source/memory-map.md`) is explicit: an access inside
the ICCM/DCCM region stays core-local; everything else goes to the bus. Because
the linker places nothing at `0xEE…` / `0xF004…`, those arrays sit idle.

**Frozen decision:**

> **Mode 1 (system IMEM/DMEM) is the project configuration. ICCM/DCCM are
> present but architecturally unused. ECC preload is therefore out of scope for
> Phases 3–5 — as an explicit, documented, *guarded* decision, not as an
> oversight.**

Guardrails that make it safe:

1. The linker script `MEMORY` regions must **not** include `0xEE000000` or
   `0xF0040000`.
2. A build-time assertion that `.text` / `.data` / `.bss` / stack addresses fall
   outside those ranges.
3. A testbench check — draft §33 lists *"[ ] ICCM image supplied when ICCM
   disabled"*; extend it to *"[ ] any section placed in an ICCM/DCCM region when
   Mode = system-bus"*.
4. Record the active mode in `build/manifest.txt` (draft §36).
5. `tb_memory_init.sv` should be **shaped so the VeeR `slam` loader can be added
   later without a rewrite**, if ICCM execution is ever wanted (it avoids bus
   latency).

This converts "ECC is a scary unknown" into "ECC is a scoped, deferred,
explicitly guarded item."

## F.7 The PRM statements, located

```text
core/Cores-VeeR-EL2/docs/source/error-protection.md:107
  "Memories with parity or ECC protection must be initialized with correct
   parity or ECC. Otherwise, a read access to an uninitialized memory may report
   an error. The method of initialization depends on the organization and
   capabilities of the memory. Initialization might be performed by a memory
   self-test or depend on firmware to overwrite the entire memory range (e.g.,
   via DMA accesses)."

:111
  "If the DCCM is uninitialized, a load following a store to the same DCCM
   address may get incorrect data. If firmware initializes the DCCM, aligned
   word-sized stores should be used (because they don't check ECC), followed by
   a fence, before any load instructions to DCCM addresses are executed."
```

The second paragraph yields a **firmware-only escape route**: aligned word stores
bypass the ECC check on the write path, so `startup.S` can initialise DCCM by
storing zeros word-by-word followed by a `fence`. Combined with a `slam` preload
for ICCM (which software cannot easily initialise before executing from it), the
two mechanisms are complementary.

---

# PART G — Reset vector and entry-point consistency

Draft §20 is right that these must agree. The mechanics, precisely:

`reset_vec` is **not** an RTL parameter. `configs/veer.config` marks it
*"Testbench, Overridable"* — it never enters `el2_param.vh`. Instead the
testbench drives a port:

```systemverilog
// tb/tb_veer_p2_soc.sv:28 and :84
reg [31:0] reset_vector = `RV_RESET_VEC;
...
.rst_vec(reset_vector[31:1]),        // note: [31:1] — LSB implied 0
```

Three places must agree:

| Where | Value today |
|---|---|
| `veer.config -set=reset_vec=` | Phase 1: `0x80000000`; Phase 2: `0x00000000` |
| First `@` record of the hex image | VeeR canned: `@80000000`; `p2_prog.hex`: `@00000000` |
| Future `sw/linker/veer.ld` location counter | **must be `0x00000000`** |

Two failure modes, neither of which fails loudly:

| Mistake | Result |
|---|---|
| Default target + linker at `0x0` | CPU fetches `0x80000000` → `ahb_default_slave` → 2-cycle ERROR → `HRESP=1` → boot exception |
| `reset_vec=0` + linker at `0x80000000` | CPU fetches `0x0` containing zeros → `c.nop`/illegal → hang |

Both present as "simulation runs forever", which is why draft §33's
*"[ ] CPU never begins execution"* plus a watchdog are mandatory.

Because the port is `rst_vec[31:1]`, the vector is implicitly halfword-aligned —
satisfied automatically by RISC-V instruction alignment rules.

---

# PART H — Numbered amendments to fold into the specification

Ranked by how badly each would bite.

### H.1 — §8.2: stop hedging, name the command

```make
firmware.ihex: firmware.elf
	$(OBJCOPY) -O ihex $< $@

firmware.mem: firmware.elf
	$(OBJCOPY) -O verilog --verilog-data-width 1 $< $@
```

Add the rule: *"Intel HEX is a delivery/diff artifact only. It is never a
simulation input."*

### H.2 — §17: replace Case A/B/C with Case D

Case D as specified in §F.2 above, plus:

> *"ECC is computed by the loader at preload time and is never present in the
> `.mem` file."*

### H.3 — §35: add the rebase and width rules (currently missing)

> Each generated image's `@` addresses **must be relative to the target array's
> index 0**, because `ahb_sram.mem` is a dense array indexed
> `0..SIZE_BYTES-1`. Absolute addresses are valid only for sparse associative
> arrays (VeeR `ahb_sif` style).
>
> `--verilog-data-width` must equal the target array's word width in bytes.

### H.4 — §12/§14: resolve the loading-ownership conflict

The draft says the **testbench** owns loading via `+HEX=` plusargs. Today loading
is done by **RTL**:

```systemverilog
// rtl/ahb/ahb_sram.sv:47-50  — inside synthesizable RTL
initial begin
    for (i = 0; i < SIZE_BYTES; i = i + 1) mem[i] = 8'h00;
    if (HEX_FILE != "") $readmemh(HEX_FILE, mem);
end

// rtl/soc_top.sv:16            parameter IMEM_HEX = "";
// tb/tb_veer_p2_soc.sv:194     soc_top #(.IMEM_HEX("p2_prog.hex"), .DMEM_HEX("")) u_soc (...);
```

That collides directly with draft §24 (*"the RTL should not know about
`hello.c`"*) — the RTL currently knows about `p2_prog.hex`. Pick one and write it
down:

| Option | Description | Pros | Cons |
|---|---|---|---|
| **T — TB-owned** | Remove `HEX_FILE`/`$readmemh` from `ahb_sram`; hierarchical backdoor task in `tb_memory_init.sv` + `+IMEM_HEX=` plusarg | Matches the draft as written; the only option that also covers ICCM/DCCM; runtime image selection | Requires an RTL change |
| **R — RTL-owned** | Keep the parameter; the TB derives the path from `$value$plusargs` and passes it as a parameter override when instantiating `soc_top` | Smallest diff to the proven Phase-2 flow; also valid for FPGA BRAM init | RTL still "knows" a hex filename (via a parameter) |

**Recommendation:** Option **R for Phase 3** (system IMEM/DMEM only, minimal
churn), with the interface shaped so Option **T** can be adopted later. Either
way, state the choice in §25.

### H.5 — §25 Image Contract: add three missing fields

```text
word width (bytes)   : 1 for byte arrays, 4 for word arrays
address base         : 0 — relative to each memory's array index 0
.bss / NOBITS policy : startup.S zeros .bss; arrays also pre-zeroed by the loader
ECC policy           : not applicable (Mode 1) — documented and guarded
```

### H.6 — §21: note the existing hierarchical-access precedent

The testbench already reaches into the array for its PASS monitor:

```systemverilog
// tb/tb_veer_p2_soc.sv:300
if (rst_l && !done && u_soc.u_dmem.mem[2] === 8'hFF) ...
```

Hierarchical TB→RTL access is therefore already established in this codebase.
`tb_memory_init` following suit is consistent, not novel.

### H.7 — §15: initialization timing is already satisfied — say so

The draft's proposed sequence matches what Phase 2 already does:

```systemverilog
// ahb_sram initial block runs at t=0 (zero-fill, then $readmemh)

// tb/tb_veer_p2_soc.sv:269-274
rst_l   = 1'b1;  rst_l   = #5  1'b0;  rst_l   = #25 1'b1;   // assert @5ns, release @30ns
porst_l = 1'b1;  porst_l = #1  1'b0;  porst_l = #10 1'b1;
```

Memory init at t = 0, reset asserted at 5 ns, released at 30 ns. The ordering
requirement is met. Add a note so nobody "fixes" something that is not broken.

### H.8 — §11 Makefile: fix `ARCH`

```make
MARCH := rv32imc_zicsr_zifencei    # not just rv32imc
MABI  := ilp32
```

Verified against GCC 16.1.0 on this machine (§C.1).

### H.9 — New checklist items

**G. Memory Image — add:**

- [ ] `--verilog-data-width` matches the target array word width
- [ ] `@` addresses rebased to array index 0
- [ ] `.bss` / `NOBITS` zeroed by `startup.S` **and** by loader pre-fill
- [ ] ECC policy recorded: *unused (Mode 1)* — documented and guarded

**B. VeeR Configuration — add:**

- [ ] `dccm_addr_xor` / `iccm_addr_xor` confirmed `= 0`, **or** the loader
      applies the XOR
- [ ] `lockstep_enable` confirmed (it gates `addr_xor`)
- [ ] `reset_vec` value recorded alongside the linker entry address

---

# PART I — Verification ladder: proven vs not

```text
PROVEN (log + waveform evidence)
  [x] Toolchain builds: /opt/riscv GCC 16.1.0, Binutils 2.47.20260726
  [x] C → ELF → Intel HEX (generic; toolchain record §15)
  [x] RV32IMC / ILP32 ELF attributes               (verified for this document)
  [x] objcopy -O verilog produces $readmemh-compatible images
  [x] Phase 1: VeeR resets, fetches, executes, AHB transaction, TEST_PASSED
  [x] Phase 2: project fabric + VeeR boots from IMEM @ 0x0 through it, PASS
  [x] Reset-before-init ordering already correct in tb_veer_p2_soc

NOT PROVEN
  [ ] A real C program compiled by GCC running on the SoC
  [ ] Linker script matching the p2_soc memory map
  [ ] ELF → firmware.mem → ahb_sram → boot → main()
  [ ] .data placement / .bss clear / stack setup in startup.S
  [ ] Any peripheral driver (UART / Timer / GPIO / NET / CRC / AES)
  [ ] Any interrupt
```

**Important:** Phase 1 used VeeR's *canned* `hello_world.hex`. Phase 2 used
`scripts/p2_prog_gen.py`, a hand-written Python mini-assembler emitting
`p2_prog.hex` directly — **no compiler, no linker, no ELF**. The entire software
path specified in the draft has therefore never been exercised end-to-end on this
SoC. That is the gap.

## The single highest-value milestone

```text
sw/src/startup.S  +  sw/src/main.c  +  sw/linker/veer.ld
        │
        │ riscv64-unknown-elf-gcc -march=rv32imc_zicsr_zifencei -mabi=ilp32
        ▼
   firmware.elf ──readelf -h/-A/-S──► assert RV32 / ILP32 / .text@0x0 / .data@0x10000
        │
        ├── objcopy -O ihex ──────────────────────► firmware.ihex   (artifact, never simulated)
        └── objcopy -O verilog --verilog-data-width 1 ──► firmware.mem
                                                             │
        soc_top #(.IMEM_HEX("firmware.mem"))  ◄──────────────┘
                                                             │
        tb_veer_p2_soc: reset → fetch @0x0 → startup.S → main() → signal PASS
```

`startup.S` must do, in order:

1. Set `sp` to the top of the DMEM stack region (linker symbol).
2. Place `.data` directly at its final address so no load-time copy is required
   (simplest for a flat SoC image — do this first). Copy-from-`AT()` can come
   later.
3. Zero `.bss` (the `NOBITS` problem of §C.3).
4. `call main`.
5. On return, write the PASS magic to the DMEM mailbox byte
   (`u_dmem.mem[2] = 8'hFF`) — reusing the **existing** Phase-2 monitor with zero
   testbench changes.

That single run proves the whole chain: toolchain → linker → image conversion →
RTL load → reset → fetch → C runtime → `main()`. Everything else in the
specification exists to support it.

---

# Summary of the three corrections

| # | Correction | Verdict | Evidence |
|---|---|---|---|
| 1 | The task is `$readmemh`, not `$freadmemh` | **Correct** | `$readmemh` takes a filename and parses hex text; `$fread` takes a file handle and reads raw binary (§D.1) |
| 2 | Intel HEX ≠ `$readmemh` input | **Correct** | Field-by-field decode of `:10000000…` vs `@00000000` + tokens; `objcopy -O verilog` is the right converter and VeeR's `tools/Makefile:300` already uses it (§D.2–D.3) |
| 3 | ECC-protected ICCM/DCCM cannot be blindly filled | **Correct, and stronger than stated** | Exact `rvecc_decode` replica: naive preload silently flips instruction bits (`0x00000013 → 0x00000413`, `0x00A18023 → 0x00A18033`) or raises uncorrectable DED; zeros are coincidentally valid (§F.4) |

Plus one amendment the draft does not contain at all:

| # | Additional issue | Where |
|---|---|---|
| 4 | **Address rebasing / data width** — `ahb_sram` uses a dense array indexed from 0, so `@` records must be rebased per memory and `--verilog-data-width` must match the array word width | §E, §H.3 |
