# Execution Plan — C Test Suite for All SoC Memories and Peripherals

**Project:** RISC-V Network Telemetry SoC
**Scope:** A C-language test suite exercising every memory region and every
peripheral that is reachable from the CPU on this SoC, wired into the existing
`make` → `imem.mem` → VCS → `simv` flow, reporting per-test results over both
the UART and a DMEM result table.
**Status:** PLANNED — no code written yet. Phases 0–4 are self-contained;
Phase 5 (AES) is gated on an explicit decision, see §9.
**Date:** 2026-10-17
**Branch:** `main`

**Repo rule honoured throughout:** *never claim PASS without a log.* Every
phase below defines the exact token that must appear in a surviving log before
that phase may be called PASS.

**Related records:**
`doc/SoC_Phase_Status_Audit.md` (per-phase evidence and corrections) ·
`doc/Firmware_Build_and_AHB_RW_Verification_Plan.md` (the fw0 plan this
extends) · `doc/Fw0_C_Toolchain_Build_and_Gate_Record.md` (gates G1–G13) ·
`doc/Phase3_UART_End_To_End_Completion_Record.md` ·
`doc/AES_AXI_Integration_Verification_Record.md` ·
`doc/RISC_V_SW_Build_and_Simulation_Image_Architecture_Specification.md`
(FROZEN rev 1.5 — not restated here).

---

# 0. Why this work

`doc/SoC_Phase_Status_Audit.md:35-37` states the headline gap:

> These are **two separate results**, produced by two different testbenches with
> two different programs. They have never been joined. The single largest gap
> in the project is that **no C firmware has ever accessed any peripheral**.

The two proven chains are:

```
C firmware -> GCC -> ELF -> imem.mem/dmem.mem -> VeeR EL2
          -> ahb_interconnect -> IMEM/DMEM -> VCS -> FSDB -> Verdi
```

and, independently:

```
VeeR EL2 -> ahb_interconnect -> ahb_to_axi_bridge
         -> uart_axi_slave -> axi_uart_top -> uart_tx_o
```

The UART chain is real but is driven by `scripts/p3_uart_prog_gen.py`, a Python
mini-assembler — not by C. This plan joins them, and extends coverage to the
core-local memories that no test currently touches at all.

---

# 1. State re-verified against the tree (2026-10-17)

Everything in this section was re-checked against the working tree today, not
inherited from earlier records.

## 1.1 Memory regions reachable from C

| Region | Base | Size | Path | Reset value |
| --- | --- | --- | --- | --- |
| IMEM | `0x0000_0000` | 32 KB | AHB fabric → `ahb_sram` (`soc_top.sv:119`) | `$readmemh(IMEM_HEX)`, else zero |
| DMEM | `0x0001_0000` | 32 KB | AHB fabric → `ahb_sram` (`soc_top.sv:130`) | zero |
| ICCM | `0xEE00_0000` | 64 KB | core-local, 4× `ram_4096x39` in TB (`tb_veer_p2_soc.sv:237`) | **uninitialised (X)** |
| DCCM | `0xF004_0000` | 64 KB | core-local, 4× `ram_4096x39` in TB (`tb_veer_p2_soc.sv:221`) | **uninitialised (X)** |

Re-verified: `iccm_enable => 1`, `iccm_size => 64`, `iccm_region => '0xe'`,
`iccm_offset => '0xe000000'`, `dccm_enable => '1'`, `dccm_size => 64`,
`dccm_region => '0xf'`, `dccm_offset => '0x40000'` — all from
`build/snapshots/p2_soc/perl_configs.pl:635-704`. These match the guardrail
`ASSERT`s already in `sw/linker/veer.ld:98-127` exactly.

## 1.2 Peripherals reachable from C

| Peripheral | Base | Decode | Reachable |
| --- | --- | --- | --- |
| UART | `0x1000_0000` | `ahb_interconnect.sv:169` | **yes** |
| AES | `0x1000_4000` | none | **no** → ERROR slave |
| Timer / GPIO / NET / CRC32 | `0x1000_1000`+ | none | **no** → no RTL exists |

`rtl/ahb/ahb_interconnect.sv:167-174`:

```systemverilog
wire imem_match = (mux_haddr[31:15] == 17'h0000); // 0x0000_0000/32K
wire dmem_match = (mux_haddr[31:15] == 17'h0002); // 0x0001_0000/32K
wire uart_match = (mux_haddr[31:12] == 20'h10000); // 0x1000_0000/4K
wire sel_def    = mux_active && !imem_match && !dmem_match && !uart_match;
```

`uart_match` covers `0x1000_0000`–`0x1000_0FFF` only. `0x1000_4000` fails all
three compares and lands on `sel_def` → `ahb_default_slave` → AHB ERROR.

## 1.3 AES is not on GitHub

The AES component is extensively proven **in isolation** (audit rows 52–55:
`AES AXI SLAVE TEST PASSED`, `69c4e0d86a7b0430d8cdb78070b4c55a`,
`PASS checks : 19 / FAIL checks : 0`). What does not exist is the SoC
integration. Checked today across every branch:

```
main, feature/sw-build-ahb-rw, uart-end-to-end,
origin/main, origin/feature/sw-build-ahb-rw
```

`grep -c 'aes_axi_slave\|AES_BASE'` against `rtl/soc_top.sv` on **all five**
returns `0`. `git stash list` is empty. `git fetch --all --dry-run` returns
nothing. The milestone is `M4 | AES on the SoC + C driver | NOT STARTED`
(`doc/SoC_Phase_Status_Audit.md:57`).

## 1.4 Toolchain: no reinstall required

Checked today, because this determines whether the suite needs runtime support
code.

| Question | Answer | Evidence |
| --- | --- | --- |
| GCC present? | yes, 16.1.0 | `riscv64-unknown-elf-gcc --version` |
| RV32 multilib? | **no** — `-print-multi-lib` → `.` only | single target |
| libgcc present? | yes, rv64-only | `/opt/riscv/lib/gcc/riscv64-unknown-elf/16.1.0/libgcc.a` |

Decisive test — linked with the project's exact flags
(`-march=rv32imc_zicsr_zifencei -mabi=ilp32 -O0 -ffreestanding -fno-builtin
-nostdlib -nostartfiles`):

| Construct | Result |
| --- | --- |
| `a / b`, `a % b` (32-bit) | **links clean** → `divu` / `remu` (RV32M) |
| `a << n`, `a >> n` (variable `n`) | **links clean** → `sll` / `srl` (RV32I) |
| `a * b` (32-bit) | **links clean** → `mul` |
| `unsigned long long / b` | **FAILS** → `undefined reference to __udivdi3` |

**Conclusions.** No `sw/src/rt_support.c`. No reinstall. Walking-bit patterns
(`1u << i`, `v <<= 1`) and `% 4` are all fine and can be written naturally. The
single standing rule for the suite is: **no `long long` division or modulo.**

This corrects an assumption worth recording, because it is a natural and
plausible mistake — RV32I's `SLL`/`SRL`/`SRA` take a *variable* shift amount
from `rs2` (only `SLLI` needs a constant), and the frozen `MARCH` contains `M`,
so the divider is hardware.

---

# 2. Constraints that shape the design

## 2.1 ICCM/DCCM have no reset value — write before read

`tb/tb_veer_p2_soc.sv:221-246` instantiates `ram_4096x39` with no init file and
no reset on `Q`. Any location never written by the core reads back as `X`.

**Rule:** the suite must never assert "reads as zero" for ICCM/DCCM, and every
read must be preceded by a write to that location. ECC is self-consistent
because the core writes its own computed 7-bit ECC in and reads it back
unchanged (`{iccm_bank_wr_ecc, iccm_bank_wr_data}` in, `{bank_ecc, bank_dout}`
out); `iccm_ecc_single_error`/`dccm_ecc_single_error` are tied off at
`tb_veer_p2_soc.sv:181-182` regardless.

## 2.2 MRAC must be programmed or MMIO silently disappears

VeeR's LSU load buffer will forward repeated polls of the same load address.
Without `MRAC` bit 3 the repeated LSR polls never reach the bus, and the
monitor reports `uart_rd=0`.

**Rule:** `sw/src/startup.S` must set `MRAC` bit 3
(`MRAC_UART_SIDE_EFFECT = 1 << 3`, CSR address `0x7C0`) and issue `fence.i`
before any MMIO access. Reference: `scripts/p3_uart_prog_gen.py:28-33`. The
current `startup.S` never touches MRAC. MRAC has no hardware reset value.

## 2.3 The simulation budget is ~22x too small

| Quantity | Value |
| --- | --- |
| Core clock | 10 ns period, `tb_veer_p2_soc.sv:23` (`always #5`) |
| fw0 completion | 90,915 ns (`build/sim/fw0/sim.log`) |
| Current monitor watchdog | 1,900,000 ns (`tb_veer_p2_soc.sv:329`) |
| Current TB timeout | 2,000,000 ns |

A 32 KB sweep is ~16K writes + ~16K reads. At roughly 4–8 cycles per AHB
transaction that is ~2 ms of sim time **per memory per pattern**. Four memories
× several patterns lands in the 50–200 ms range — roughly 25–100× the current
budget.

**Rules:** (a) `WATCHDOG_NS` and the `#2000000` timeout must both be raised by
~100×; (b) FSDB must be compressed or narrowed, or the run will emit a
multi-GB waveform; (c) UART must be programmed with `BAUD = 8`, not the reset
default `868`, or each log line costs ~350 µs of sim time.

---

# 3. Phase 0 — ICCM/DCCM permission spike

**Purpose.** Resolve the open question the plan is gated on: are ICCM and DCCM
actually accessible from user-mode C? This is genuinely uncertain — ICCM/DCCM
sit behind the **PMP**, not `MRAC` (which governs external bus regions), and
the `default_ahb` config's `protection.*` PMP defaults have never been verified
against these addresses.

**This phase is first because it decides Phase 3's scope.** Everything else is
independent of it.

**Implementation.** One small C function in the existing `main.c`, no new
files:

1. `volatile uint32_t *iccm = (uint32_t *)0xEE000000u;` write `0xA5A5_1234`.
2. Read back, compare.
3. Same at `0xF004_0000`.
4. Publish both readback values plus a two-bit verdict to the existing DMEM
   mailbox `[4..7]`, then trigger `[2] = 0xFF` as usual.
5. **No** MRAC/CSR programming yet — the point is to find out whether it is
   needed.

**Evidence required.** `make sim` log showing `P2_TB2_RESULT: PASS` plus the two
readback values, and a Verdi capture of one write and one read on
`el2_mem_export.iccm_wren_bank` / `iccm_addr_bank` showing the transaction
reaching the banks.

**Decision rule.**

| Spike result | Action |
| --- | --- |
| readback matches on both | Phase 3 includes `t_iccm.c` and `t_dccm.c` as written |
| readback is `X` on both | Likely a C-language / access-mode issue — investigate before writing tests |
| one region works, one does not | Scope Phase 3 to the working region; record why |
| readback matches but only after CSR setup | Fold the required setup into `startup.S` as part of Phase 2 |

---

# 4. Phase 1 — Test framework

No tests yet. This phase must land and go green on its own.

## 4.1 `sw/include/test.h` — new

```c
#ifndef TEST_H
#define TEST_H
#include <stdint.h>

/* A test returns 0 on pass, nonzero on fail; the value is the fail code. */
typedef struct {
    const char *name;
    int (*fn)(void);
} test_case_t;

/* Emits one entry into the .test_list section. Referenced by the runner
   through __test_list_start / __test_list_end, so adding a test file never
   requires editing the runner. */
#define TEST_CASE(fn)                                        \
    static const test_case_t tc_##fn                         \
        __attribute__((section(".test_list"), used))         \
        = { #fn, fn };

#define TEST_MAGIC        0x54534553u   /* 'T''E''S''T' */
#define RESULTS_BASE      0x00010010u

/* Results table, written by the runner, read by the TB. */
typedef struct {
    uint32_t magic;            /* TEST_MAGIC                    */
    uint32_t ntests;
    uint32_t npass;
    uint32_t nfail;
    uint32_t first_fail_idx;
    uint32_t first_fail_code;
    uint32_t first_fail_addr;  /* where, if the test recorded one */
} test_results_hdr_t;

typedef struct {
    const char *name;          /* pointer into .rodata (IMEM)    */
    uint32_t    code;          /* 0 = pass                       */
} test_results_ent_t;

void test_fail(const char *name, uint32_t code, uint32_t addr);

#define CHECK_EQ(what, got, want)                                        \
    do {                                                                 \
        uint32_t _g = (uint32_t)(got), _w = (uint32_t)(want);            \
        if (_g != _w) {                                                  \
            test_fail((what), 1u, _g);                                   \
            return 1;                                                    \
        }                                                                \
    } while (0)

#endif
```

`volatile` is load-bearing throughout: at `-O0` with these flags the compiler
still needs to be prevented from caching MMIO reads, and the whole point of the
`MRAC` change in §2.2 is defeated if the compiler also elides the load.

## 4.2 `sw/tests/test_main.c` — new

The runner. Iterates `__test_list_start[] .. __test_list_end[]`, calls each
`fn()`, writes the results table, returns the first nonzero code so the
existing `startup.S` mailbox convention (`bnez a0, .Lmailbox_fail`) keeps
working unchanged. On completion it writes the PASS trigger.

## 4.3 `sw/src/startup.S` — edit

Insert as **step 0**, before the existing step 1 (set `sp`):

```asm
    li   t0, 0x7C0            # MRAC
    csrw 0x7C0, t0            # side_effect=1 (bit 3) → no load-buffer bypass
    fence.i
```

Rationale in §2.2. `fence.i` is available because `MARCH` contains `zifencei`
(gate G4 already asserts the exact arch string).

## 4.4 `sw/linker/veer.ld` — edit

Add a `.results` NOLOAD section **first** in the DMEM region, so it lands at
`0x0001_0010` and `.data` shifts above it:

```ld
    .results (NOLOAD) : { KEEP(*(.test_results)) } > DMEM
```

Export `__results_start`, `__results_size`, `__imem_image_end` (end of the
`.data` LMA inside IMEM), and `__scratch_base` / `__scratch_size`.

All existing `ASSERT`s remain valid: `__stack_top` is
`ORIGIN(DMEM)+LENGTH(DMEM)`, and since the `MEMORY` block is untouched that is
still `0x0001_8000`, satisfying the `ASSERT(__stack_top == 0x00018000)` at
`veer.ld:108`.

`__imem_image_end` is the safety boundary for `t_imem.c`: writing below it
overwrites the running program.

## 4.5 `sw/Makefile` — edit

`OBJS` is hardcoded at `sw/Makefile:79`:

```make
OBJS := $(BUILD)/startup.o $(BUILD)/main.o $(BUILD)/lib.o
```

There is no `wildcard` anywhere in the build, so every new `.c` currently
requires a manual Makefile edit. Change to:

```make
SRCS := $(wildcard src/*.c) $(wildcard tests/*.c)
OBJS := $(BUILD)/startup.o $(patsubst %.c,$(BUILD)/%.o,$(notdir $(SRCS)))
```

Two new gates, continuing the existing G1–G13 numbering:

- **G14** — `nm -u` over every object must be empty. With `-nostdlib` this is
  the only early warning for a `long long` division sneaking in (§1.4).
- **G15** — `__imem_image_end` + the largest test scratch requirement must stay
  below `0x0000_8000`, so the memory tests cannot grow into their own code.

## 4.6 `sw/include/soc.h` — edit

- Add `ICCM_BASE 0xEE000000u`, `DCCM_BASE 0xF0040000u`, `RESULTS_BASE`.
- Add the full UART register map from `rtl/uart/uart_axi_slave.v:141-149`.
- Add the AES register map from `rtl/aes/aes_axi_slave.v:85-103`.
- **Fix the stale comment on `AES_BASE`.** `soc.h:38` carries
  `0x10004000u /* spec §9.1 */`, but the canonical implemented address is
  `0x1000_4000` (`aes_axi_slave.v:85`, `README.md` §13). §7.3 makes the
  implemented address correct.

**Phase 1 exit criterion:** `make all` green, all gates G1–G15 PASS, zero tests
in the list, `P2_TB2_RESULT: PASS` still emitted with an empty results table.

---

# 5. Phase 2 — Reporting plumbing

## 5.1 `sw/src/uart.c` — new

`uart_init()`, `uart_putc()`, `uart_puts()`, `uart_puthex32()`,
`uart_putdec()`. `uart_putc` is a direct C port of the unrolled loop at
`scripts/p3_uart_prog_gen.py:28-33` (write THR, poll LSR, test THRE, branch).

Register map, from `rtl/uart/uart_axi_slave.v:141-149`:

| Register | Offset | Abs | Notes |
| --- | --- | --- | --- |
| THR / RBR | `0x00` | `0x1000_0000` | WO TX / RO RX |
| IER | `0x04` | `0x1000_0004` | bit 0 IRQ enable; **reads bypassed to 0** |
| BAUD | `0x08` | `0x1000_0008` | divisor when DLAB=1; **reads bypassed to 0** |
| LCR | `0x0C` | `0x1000_000C` | bit 7 DLAB, 2 stop, 3 parity en, 4 parity mode; **reads bypassed to 0** |
| LSR | `0x14` | `0x1000_0014` | bit 0 DATA_READY, 5 THRE, 6 TEMT — **the only status read served** |

The bypass is deliberate, from `uart_axi_slave.v:153-156`:

```systemverilog
function automatic logic is_ip_read_offset(input [4:0] off);
    is_ip_read_offset = (off[4:2] == 3'd0) || (off[4:2] == 3'd5);
endfunction
```

Only RBR/THR and LSR reach the IP; every other read completes locally with
`32'h0000_0000`. The suite asserts these return 0 as **expected behaviour**,
so a future RTL change that starts honouring them fails the suite loudly.

`uart_init()` must program `BAUD = 8` (§2.3c), via the DLAB set/latch/clear
sequence: `LCR |= 0x80` → `BAUD = 8` → `LCR = 0x03` (8N1).

Note the latching quirk at `axi_uart_top.v:408`: `AckWriteState` does
`uart_baudrate_div_int <= baudrate_divisor_int`, so the divisor written while
DLAB=1 becomes live on the **next** AXI write, not the one that set it.

## 5.2 `tb/tb_veer_p2_soc.sv` — edit

Currently `soc_top` is instantiated at `tb_veer_p2_soc.sv:194` with
`uart_tx_o` / `uart_irq_o` **left dangling**. Changes:

1. Wire `.uart_tx_o(uart_tx)` and `.uart_irq_o(uart_irq)`.
2. Port the self-calibrating serial receiver from `tb_veer_uart_soc.sv` — it
   derives `bit_period` from the `'U' == 0x55` calibration byte, then uses
   `exp_byte()` / `uart_rx_byte()`. Reuse rather than rewrite.
3. Dump the results table by hierarchical reference
   (`u_soc.u_dmem.mem[...]`), the same idiom already used for the mailbox.
4. Raise `WATCHDOG_NS` at line 329 and the `#2000000` timeout per §2.3a.
5. Constrain FSDB per §2.3b.

## 5.3 `sim/Makefile` — edit

Gate on the new per-test tokens alongside the existing
`P2_TB2_RESULT: PASS` and `AHB_RW_MONITOR: PASS`.

**Phase 2 exit criterion:** `make sim` green; a deliberately failing test
produces a named line on the UART transcript, a `code != 0` entry in the dumped
results table, `first_fail_idx`/`first_fail_code` correct, and
`P2_TB2_RESULT: FAIL`.

---

# 6. Phase 3 — Memory tests

## 6.1 Structure

One parametrized core, instantiated four times. This is the main DRY win: the
patterns are identical and only the bounds and capability flags differ.

**`sw/tests/memtest_core.c`** — `memtest_region(name, base, size, flags)`:

| Pattern | Purpose |
| --- | --- |
| width sweep | 8 / 16 / 32-bit store+load across a stride grid |
| walking ones | `v <<= 1` over 32 positions, each bit as a word |
| walking zeros | `~v` over 32 positions |
| address-unique | `addr ^ pattern` per word — catches aliased or stuck lines |
| block + checksum | sequential fill, then read back and accumulate a checksum |
| retention | full sweep, then re-check a sample — catches destructive refresh |
| boundary probes | first and last legal word of the region |
| no-leak-below | first word of region and its immediate predecessor |

All patterns use `%` and `<<` freely — both are hardware instructions (§1.4).
No `long long` division anywhere.

## 6.2 Per-region instantiations

| File | Region | Constraint |
| --- | --- | --- |
| `t_imem.c` | `0x0000_0000` / 32 KB | **writes restricted to `[__imem_image_end, 0x0000_7FFF]`**. Boundary probes at `0x0000_7FF8`. |
| `t_dmem.c` | `0x0001_0010` .. `0x0001_7FFF` | full sweep; scratch must not collide with the stack growing down from `0x0001_8000` |
| `t_iccm.c` | `0xEE00_0000` / 64 KB | **conditional on Phase 0**; write-before-read always (§2.1) |
| `t_dccm.c` | `0xF004_0000` / 64 KB | **conditional on Phase 0**; write-before-read always (§2.1) |

## 6.3 `t_bus.c` — bus and decode tests

Asserts that unmapped regions return an AHB ERROR:

| Address | Expectation |
| --- | --- |
| `0x2000_0000` | AHB ERROR — `sel_def` |
| `0x1000_1000` | AHB ERROR — reserved, no slave |
| `0x1000_4000` | AHB ERROR — **AES base, not decoded** |
| `0x1000_0FF8` | last word of the UART window — must **not** error |
| `0x1000_1000` vs `0x0000_7FFC` | both edges of the IMEM/DMEM regions |

Including `0x1000_4000` here is deliberate. It turns "AES is not integrated" from
a comment into an **executable assertion**. When Phase 5 lands and the decode is
added, this test fails, which is the correct behaviour — it is the tripwire
that proves Phase 5a actually took effect.

Note the AHB ERROR raises an exception on VeeR, so these tests need an expected
trap path rather than a normal return. `startup.S:trap_handler` currently parks
forever, which would stall the sim into the watchdog. Phase 3 must extend the
trap handler to recognise expected traps, or these cases must run behind a
flag the trap handler sets. **This is the subtlest integration point in the
whole plan and should be prototyped first.**

---

# 7. Phase 4 — UART tests

**`sw/tests/t_uart.c`**, exercising the driver built in Phase 2.

| Case | Expectation |
| --- | --- |
| LSR after reset | `0x0000_0060` — THRE (bit 5) \| TEMT (bit 6) |
| THRE/TEMT polling | both stay set while idle |
| THRE after a TX byte | clears then returns set; poll before each write |
| FIFO depth | fill past `_AXI_UART_FIFO_DEPTH_` = 32 and confirm no data loss |
| LCR write | write `0x03` (8N1), then re-assert via a behavioural check |
| DLAB + BAUD sequence | `LCR=0x83` → `BAUD=8` → `LCR=0x03`; divisor live on next write (§5.1) |
| IER / LCR / BAUD readback | return `0x0000_0000` — **expected** wrapper bypass, asserted as such |
| TX known payload | TB decodes the exact expected bytes off `uart_tx_o` |
| `uart_rx_i` | tied to `1'b1` at `soc_top.sv:212`, so RX is idle-high and `DATA_READY` stays clear |
| `uart_irq` | stays low — TX-only build, matching `doc/Phase3_UART_End_To_End_Completion_Record.md` |

The RX line is a hard consequence of `soc_top.sv:212`
(`.uart_rx_i(1'b1)`). No RX test is possible until `soc_top` exposes a real
`uart_rx_i` port — that is a separate change, out of scope here, and must be
documented rather than papered over.

---

# 8. Phase 5 — AES

**Gated on an explicit decision. See §9.**

## 8.1 5a — Fabric decode + instantiation (RTL, no C)

Milestone **M4**, `doc/SoC_Phase_Status_Audit.md:57`.

In `rtl/ahb/ahb_interconnect.sv:167-174`, widen the peripheral window from
4 KB to 64 KB and split it:

```systemverilog
wire periph_match = (mux_haddr[31:16] == 16'h1000);  // 0x1000_0000/64K
wire uart_match   = periph_match && (mux_haddr[15:12] == 4'h0);
wire aes_match    = periph_match && (mux_haddr[15:12] == 4'h4);
```

This places AES at `0x1000_4000`, the canonical implemented address from
`aes_axi_slave.v:85` and `README.md` §13, and leaves the UART at
`0x1000_0000` with its window intact. The `sel_*` priority chain and the
`data_sel` encoding at lines 209-210 gain an AES slot.

Then in `rtl/soc_top.sv`: instantiate `aes_axi_slave`, add a second
`ahb_to_axi_bridge`, and add `aes_irq_o` to the port list (`uart_axi_slave.v`
already exposes `aes_irq`).

**Risk.** This touches the fabric decode that the audit records as **PROVEN**
(`P2_TB1_RESULT: PASS`, `P2 FABRIC: PASS=23 FAIL=0`). Every existing Phase 2/3
result depends on it. `tb_ahb_fabric.sv` T1–T14 must be re-run unchanged as the
regression gate for this sub-phase. **Do not skip that.**

## 8.2 5b — `t_aes.c`

Register map, from `rtl/aes/aes_axi_slave.v:85-103`, all 32-bit, 4-byte spaced:

| Register | Offset | Read | Write |
| --- | --- | --- | --- |
| CONTROL | `0x00` | `0x0000_0000` | bit 0 START, bit 1 CLEAR DONE/IRQ (both need `write_strb[0]`) |
| STATUS | `0x04` | `[0]` busy, `[1]` done | ignored |
| KEY0..KEY3 | `0x08`..`0x14` | `key0_reg`.. | byte-strobe via `apply_wstrb` |
| DATA0..DATA3 | `0x18`..`0x24` | `data0_reg`.. | byte-strobe |
| RESULT0..RESULT3 | `0x28`..`0x34` | `result0_reg`.. | **read-only** |

Word order, from the comments in the RTL:
`key = {KEY3, KEY2, KEY1, KEY0}`, `aes_text_in = {data3, data2, data1, data0}`.

Known-answer vector, lifted from the already-proven `tb_aes_axi_slave.sv:361-381`:

```
key         00010203_04050607_08090a0b_0c0d0e0f
plaintext   00112233_44556677_8899aabb_ccddeeff
ciphertext  69c4e0d86a7b0430d8cdb78070b4c55a
```

Cases: KEY/DATA readback; CONTROL START → STATUS busy=1 → poll for done;
RESULT0..3 match the vector; `aes_irq` asserts; CONTROL bit 1 clears done and
IRQ; RESULT writes are ignored; START while `busy_reg` is set is ignored
(`aes_axi_slave.v` gates it); byte-strobe partial writes to KEY/DATA; default
offsets read `0x0000_0000`.

---

# 9. Open decisions

## 9.1 Does Phase 5a go in this plan?

Phase 5a is the only genuine RTL work, and it modifies fabric decode that is
currently PROVEN. Two defensible answers:

- **Land Phases 0–4 first, then review Phase 5a as its own change.** The C
  suite is then independently valuable and mergeable, and the riskiest edit is
  reviewed in isolation against a known-good baseline.
- **Include 5a now.** Closes the project's largest documented gap in one pass,
  and §6.3's `0x1000_4000` tripwire proves it landed.

**Recommendation: land Phases 0–4 first.** The C suite stands on its own and
demonstrably closes the audit's headline gap without touching PROVEN RTL.

## 9.2 FSDB strategy for long runs

Per §2.3b, a 50–200 ms run with `-debug_access+all` will be enormous. Options:
constrain `fsdb_dump_limit` in the TB (keeps debug access, caps depth) · gate
dumping behind a `+wave` plusarg so routine runs are fast · dump only around
per-test boundaries. **Recommendation: `+wave` plusarg**, since routine test
runs should not pay for waveforms at all, and the repo rule requires a waveform
only when investigating a failure.

---

# 10. Sequencing

| Phase | Depends on | Blocks | Ends green when |
| --- | --- | --- | --- |
| 0 — ICCM/DCCM spike | — | 3 (ICCM/DCCM files) | `make sim` PASS + readback values in log |
| 1 — framework | — | 2, 3, 4 | `make all` green, G1–G15 PASS, empty test list |
| 2 — reporting | 1 | 3, 4 | intentional failure surfaces on UART **and** in DMEM |
| 3 — memory tests | 1, 2, (0) | 4 | all memory patterns PASS |
| 4 — UART tests | 1, 2 | — | UART cases PASS |
| 5a — AES RTL | 4 | 5b | `tb_ahb_fabric.sv` T1–T14 still PASS |
| 5b — AES driver | 5a | — | known-answer vector PASS from C |

Phases 3 and 4 are independent and can proceed in parallel once 2 lands.

**Recommended order:** 0 → 1 → 2 → 3 → 4 → [decision on 9.1] → 5a → 5b.

---

# 11. Risks

| # | Risk | Impact | Mitigation |
| --- | --- | --- | --- |
| R1 | Sim timeout too small for memory sweeps (§2.3) | watchdog failure, no results | raise timeout ~100× in Phase 2, before Phase 3 |
| R2 | AHB ERROR traps stall the sim (`trap_handler` parks forever) | `t_bus.c` hangs | prototype the expected-trap path first (§6.3) |
| R3 | FSDB volume | multi-GB waves, slow runs | `+wave` plusarg (§9.2) |
| R4 | `t_imem.c` writes into its own code | simulator crash or infinite self-modifying loop | `__imem_image_end` bound + gate G15 at link time |
| R5 | UART output dominates sim time | budget blown by logging alone | `BAUD = 8`, compact transcripts |
| R6 | `long long` division lands in a test | link failure, blocked build | gate G14 (`nm -u`) |
| R7 | MMIO reads elided by the compiler | tests silently pass without touching hardware | `volatile` everywhere + MRAC in `startup.S` |
| R8 | ICCM/DCCM not user-accessible | Phase 3 scope shrinks | Phase 0 spike resolves this first |
| R9 | Phase 5a breaks PROVEN fabric decode | regression across Phases 2–4 | re-run `tb_ahb_fabric.sv` T1–T14 as the gate |
| R10 | `.results` section collides with `.data` | link failure or silent overlap | linker `ASSERT` + G15 |
| R11 | Parallel `opencode` session edits `rtl/` mid-change | merge conflict (previously real — see `Firmware_Build_and_AHB_RW_Verification_Plan.md` N1) | confirm no live sibling sessions before Phase 5a |

---

# 12. Definition of done

The suite is complete when all of the following hold, each with a surviving log:

1. `make all` builds clean; gates **G1–G15** all PASS.
2. `make sim` emits `P2_TB2_RESULT: PASS` and `AHB_RW_MONITOR: PASS`.
3. Every test in `.test_list` has an entry in the DMEM results table with a
   named, non-zero-on-failure code.
4. The UART transcript contains one line per test.
5. A deliberately broken test is shown to produce: a named UART line, a
   non-zero table entry, correct `first_fail_idx`/`first_fail_code`, and
   `P2_TB2_RESULT: FAIL`.
6. Coverage: IMEM, DMEM, ICCM, DCCM (if Phase 0 permits), UART registers,
   bus/decode behaviour.
7. No test accesses an address the fabric does not decode, except the
   deliberately-asserted ERROR cases in `t_bus.c`.
8. Every claimed PASS cites its log line. Every FAIL cites its waveform.