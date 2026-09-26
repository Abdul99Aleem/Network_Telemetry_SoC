# RISC-V Network Telemetry SoC

## Embedded Software Build and RTL Simulation Image Architecture Specification

### Specification status

**Status:** FROZEN — baseline architecture with corrections incorporated and repository facts verified.

**Purpose:** Freeze the software-to-simulation image flow before implementing the integrated VeeR firmware environment.

**Primary processor:** VeeR EL2 RV32IMC

**Software:** Bare-metal embedded C

**Compiler:** RISC-V GNU Toolchain

**Build system:** GNU Make

**RTL simulator:** Synopsys VCS

**Testbench language:** SystemVerilog

**Memory initialization:** Simulation-time memory image loading

### Revision record

| Rev | Change |
| --- | ------ |
| 1.0 | Initial specification draft. |
| 1.1 | **Correction A:** the standard SystemVerilog task is `$readmemh`, not `$freadmemh`. `$fread` is a different system task for binary/file-handle reads. All hex memory-image loading uses `$readmemh`. |
| 1.2 | **Correction B:** Intel HEX is **not** the `$readmemh` input format. `objcopy -O ihex` produces records such as `:10000000...` which `$readmemh` does not consume. The software flow therefore requires a **simulation memory-image generation step separate from the generic Intel HEX artifact**. The flow is `ELF → simulator-native memory image → $readmemh`; Intel HEX is retained only as a separate delivery artifact. |
| 1.3 | **Correction C (ECC):** VeeR ICCM/DCCM are ECC-protected core-local memories. The PRM requires ECC/parity-protected memories to be initialized with correct protection information; blindly filling the internal data array is **not** equivalent to a valid ECC initialization. The raw-`$readmemh`-into-`ram_core` loader example from the draft was **deleted** and replaced with a testbench backdoor loader design (Section 12). |
| 1.4 | **Repository verification pass:** all previously open items (VeeR configuration, memory map, ECC storage structure, reset vector, sim-image tool support, snapshot/tool flow, hierarchy paths) were resolved against the actual repository contents (Section 3). Frozen decisions recorded (Section 2). Implementation plan frozen (Section 21). |
| 1.5 | **Companion review folded in** (`doc/SW_HW_Memory_Image_Architecture_First_Principles_and_Spec_Amendments.md`, amendments H.1–H.9): ECC case relabelled **Case D** (single combined array — the draft's Case B meant *separate* arrays and is wrong); `--verilog-data-width` rule added; flat-vs-split image decision added; loading-ownership conflict (H.4) resolved **in favour of testbench ownership** with new empirical evidence (VCS ignores `$value$plusargs` when feeding a parameter — Option R is dead, see §9.2); Mode-1 "ICCM/DCCM unused" escape hatch adopted with guardrails (§9.3); PRM citations, bank-mapping formulas, silent-corruption failure modes, proven/not-proven ladder, and H.9 checklist items added. |

### Document conventions

* `[x]` = verified/resolved against the repository during this revision.
* `[ ]` = still to be done during implementation.
* All file paths are repository-relative unless absolute paths are given explicitly.

---

# 1. Overall Architecture

The project has two explicitly separated paths.

```text
                    RISC-V SoC DEVELOPMENT FLOW
                    ===========================

                         SOFTWARE PATH
                         -------------


       Embedded C source
             |
             v
       +-------------+
       | GCC / RISC-V|
       | Toolchain   |
       +-------------+
             |
             | RV32IMC / ILP32
             v
       +-------------+
       |    ELF      |
       | executable  |
       +-------------+
             |
             +----------------------+
             |                      |
             v                      v
      ELF inspection          Image conversion
      readelf/objdump               |
                                    v
                              +-------------+
                              | Memory Image|
                              +-------------+
                                    |
                       +------------+------------+
                       |                         |
                       v                         v
                Intel HEX                  SV HEX /
                (delivery only)            readmemh image
                                             |
                                             v
                    ==============================
                         HARDWARE / SIMULATION
                    ==============================

                              SV Testbench
                                  |
                                  | image path (+HEX plusargs)
                                  v
                         +-------------------+
                         | Memory Init       |
                         | Service           |
                         +-------------------+
                                  |
                +-----------------+------------------+
                |                 |                  |
                v                 v                  v
           system IMEM         ICCM               DCCM
           (byte SRAM,         (39-bit ECC        (39-bit ECC
            plain readmemh)     backdoor           backdoor
                                loader)            loader)
                |                 |                  |
                +-----------------+------------------+
                                  |
                                  v
                            VeeR EL2 DUT
                                  |
                                  v
                           SoC RTL system
```

The architectural principle:

> **The software build produces the executable image. The SystemVerilog environment owns loading that image into the simulation model.**

The compiler, linker, and simulator must not be coupled together through ad-hoc commands.

---

# 2. Frozen Decisions

These decisions were made during specification review and are **binding** for implementation.

| # | Decision | Rationale |
| - | -------- | --------- |
| D1 | **Boot model = Phase-2 proven path.** `reset_vec = 0x0000_0000`; `.text`/`.rodata` in **system IMEM** at `0x0000_0000` (32 KB, byte SRAM, plain `$readmemh`, no ECC). | Already proven end-to-end by `tb/tb_veer_p2_soc.sv` + `run/p2_full_flow.csh` (Phase 2 PASS). |
| D2 | **`.data`/`.bss`/stack in system DMEM** at `0x0001_0000` (32 KB, no ECC) for first firmware. DCCM/ICCM code-data placement is a **later milestone**, not day-1. | Avoids blocking first boot on the ECC loader; DMEM path is proven. |
| D3 | **ICCM/DCCM images are loaded by a testbench backdoor loader** (SV task computes SECDED ECC and de-interleaves banks), fed a plain 32-bit-word `.mem` via plusarg — replicating VeeR's own proven `slam_iccm_ram`/`slam_dccm_ram` pattern. **No** raw `$readmemh` into `ram_core`; **no** Python-side precomputed ECC images. | ECC logic stays next to the RTL that defines it; image format stays simple. |
| D4 | **New Make flow wraps, does not touch, existing `run/*.csh` flows.** The `p1`/`p2` csh scripts remain as working reference until `make sim` is proven. | Preserves the known-good flows during migration. |
| D5 | **`firmware.ihex` is a pure delivery artifact.** It is never consumed by `$readmemh`. | Correction B. |
| D6 | **Snapshot output moves to a project-local directory** (`build/snapshots/…`), not `/tmp`. New `sim/filelist.f` references the local path. | The current `run/p2_veer_soc_run.f` hardcodes the volatile `/tmp/opencode/veer_p2/snapshots/p2_soc`. |
| D7 | **Frozen `-march=rv32imc_zicsr_zifencei`, `-mabi=ilp32`.** | Correct for GCC 16 (binutils ≥ 2.38 requires explicit `_zicsr_zifencei`). Hardware config also has bitmanip defaults enabled (`veer.config` `bitmanip_zba=1`, …); hardware is a **superset**, so the minimal ISA string is always safe. Upstream `tools/Makefile` uses `rv32imc_zicsr_zifencei_zba_zbb_zbc_zbs` on GCC ≥ 11 — can be adopted later if bitmanip codegen is wanted. |
| D8 | **`startup.S` performs the standard `.data` copy and `.bss` clear even though the testbench preloads memory.** Linker: `.data` VMA = DMEM, LMA = IMEM; startup copies LMA→VMA then zeroes `.bss`. | Firmware must be hardware-correct, not simulation-only — works even where DMEM is not preloaded. (Companion review §PART I suggested the simpler "place `.data` directly at its final address, no copy" variant; that is accepted as a possible fw0 simplification but the copy form is the frozen default because it keeps a single source of truth in IMEM.) |
| D9 | **The testbench is the single owner of memory initialization.** The TB service parses plusargs and performs zero-fill + hierarchical `$readmemh`. Consequently the `initial` block in `rtl/ahb/ahb_sram.sv` (zero-fill + `$readmemh(HEX_FILE, mem)`) **must be removed** (moved into the TB service), and the `HEX_FILE`/`IMEM_HEX`/`DMEM_HEX` parameters retired. | Three reasons: (1) *runtime* plusargs cannot flow through elaboration-time parameters — verified on this machine: VCS accepts `$value$plusargs` inside a parameter-initializing function but the parameter still resolves to its default at elaboration (`+HEX=OVERRIDE.mem` → printed `HEXFILE=DEFAULT.hex`), killing companion amendment H.4's Option R; (2) letting RTL parse plusargs itself was rejected because the image contract would leak into RTL *and* ICCM/DCCM (arrays living in the TB) would still need a second mechanism; (3) **initial-block race** — module `initial` blocks at t=0 have nondeterministic relative order, so a TB `$readmemh` racing an RTL zero-fill could be wiped. Single owner = no race. Hierarchical TB→RTL access already has precedent: the Phase-2 PASS monitor reads `u_soc.u_dmem.mem[2]` (`tb/tb_veer_p2_soc.sv:300`). |
| D10 | **Mode 1 is the project configuration: ICCM/DCCM are instantiated but architecturally unused.** Guardrails: linker `MEMORY` must not include `0xEE00_xxxx`/`0xF004_xxxx`; a build-time check asserts no section/stack address falls in those ranges; the TB fails if `+ICCM_HEX`/`+DCCM_HEX` are supplied under Mode 1 *or* if any loaded section overlaps a core-local region; the active mode is recorded in `build/manifest.txt`; `tb_memory_init` must be shaped so the `slam_*` loader can be added later without a rewrite. | Because `reset_vec=0` and `.data` is in system DMEM, nothing ever fetches from ICCM or loads from DCCM, so their ECC is never checked. This converts "ECC is a scary unknown" into a scoped, deferred, explicitly **guarded** item (companion §F.6) rather than an oversight. |
| D11 | **Split per-memory images (Option A′), not one flat image.** `imem.mem` and `dmem.mem` are generated separately, each with `@` addresses rebased to its own array index 0. | A single flat image cannot work: `ahb_sram.mem` is a *dense* array indexed `0..SIZE_BYTES-1`, so a `.data` marker like `@00010000` is out of range for the 32 KB array. Sparse absolute-address arrays exist only in VeeR's own `ahb_sif.sv` testbench, not in project RTL (companion §E; addresses `@…` are array *indices*, not byte addresses). |

---

# 3. Verified Repository Baseline (as of revision 1.5)

Every item in this section was inspected directly in the repository. These facts replace the "must be confirmed" placeholders of the draft.

## 3.1 Toolchain

| Item | Value | Status |
| ---- | ----- | ------ |
| Compiler | `riscv64-unknown-elf-gcc` 16.1.0 | [x] on PATH, installed under `/opt/riscv/bin` |
| Binutils | 2.47.20260726 | [x] |
| `objcopy` verilog output | `objcopy --info` lists `verilog`; `--verilog-data-width <n>` supported | [x] **Correction B resolution: `-O verilog` is the sim-image generator** |
| `objdump`, `readelf` | present | [x] |
| VCS | `VCS_HOME=/home/student/snps_tools_target/vcs/U-2023.03` (**not on PATH**) | [x] sim Makefile must set env |
| Verdi | `VERDI_HOME=/home/student/snps_tools_target/verdi/U-2023.03-SP1` | [x] |
| pyelftools | **not installed** | [x] avoid depending on it; use `objcopy` |

## 3.2 VeeR EL2 source and configuration

* Submodule: `core/Cores-VeeR-EL2/` — full upstream `chipsalliance/Cores-VeeR-EL2` checkout (pinned `06ad26aa`, `2.0-350`).
* Configuration is generated at build time by `core/Cores-VeeR-EL2/configs/veer.config` (Perl) — there are **no** checked-in `el2_param.vh` files; generated outputs (`el2_pdef.vh`, `el2_param.vh`, `common_defines.vh`, `defines.h`, `link.ld`, …) land in `$BUILD_PATH`.
* Configurations actually used by this project:

| Phase | Command | Effect |
| ----- | ------- | ------ |
| P1 | `veer.config -target=default_ahb -snapshot=default_ahb` | AHB-Lite build |
| P2 | `veer.config -target=default_ahb -snapshot=p2_soc -set=reset_vec=0x00000000` | AHB-Lite, **reset vector 0x00000000** (boots from project IMEM) |

* Snapshot currently produced at `/tmp/opencode/veer_p2/snapshots/p2_soc` and hardcoded in `run/p2_veer_soc_run.f` — **volatile; superseded by decision D6**.

## 3.3 Frozen VeeR memory/SoC parameters (default_ahb / p2_soc)

| Resource | Value |
| -------- | ----- |
| ICCM | **enabled**, 64 KB, `0xEE00_0000 – 0xEE00_FFFF`, 4 banks × `ram_4096x39`, `ICCM_ECC_WIDTH=7` |
| DCCM | **enabled**, 64 KB, `0xF004_0000 – 0xF004_FFFF`, 4 banks × `ram_4096x39`, `DCCM_ECC_WIDTH=7`, `DCCM_FDATA_WIDTH=39` |
| PIC | base `0xF00C_0000`, 32 KB, 31 interrupts |
| I-cache | 16 KB, 2-way, 64 B lines, `ICACHE_ECC=1`, `WAYPACK=1` (cold-fills from bus → **no preload required**) |
| Bus | AHB-Lite, 64-bit data (`RV_EXT_DATAWIDTH=64`) |
| Reset vector | p2_soc: **`0x0000_0000`** (input port `rst_vec[31:1]`, active-low, async assert / sync release) |
| NMI vector | `0x1111_0000` |
| `dccm_addr_xor` / `iccm_addr_xor` | 0 / 0 (loader must still mirror these if ever enabled, via `RV_DCCM_ADDR_XOR` / `RV_ICCM_ADDR_XOR`) |
| Project IMEM | `ahb_sram` @ `0x0000_0000`, 32 KB, byte array, no ECC |
| Project DMEM | `ahb_sram` @ `0x0001_0000`, 32 KB, byte array, no ECC |

No overlap exists between project IMEM/DMEM (`0x0000_xxxx`) and VeeR core-local regions (`0xEExx`/`0xF0xx`).

## 3.4 ICCM/DCCM ECC storage structure — **Case D confirmed** (single combined array)

The original draft offered three cases (A plain data array / B separate `data_mem[]`+`ecc_mem[]` / C ECC generated by a wrapper). **None of them describes VeeR.** The verified structure is labelled **Case D** (companion review §F.2):

| Draft case | Reality |
| ---------- | ------- |
| A — plain 32-bit data array | ✗ row width is 39, not 32 |
| B — separate `data_mem[]` / `ecc_mem[]` arrays | ✗ there is **one** combined array |
| C — ECC generated by a wrapper/macro model | ✗ the *core* generates ECC on writes; the RAM macro is dumb storage |
| **D — one combined array, ECC inline** | ✓ `ram_core[39]` = `{ecc[6:0], data[31:0]}` per row, 4 banks |

* Storage macro: `core/Cores-VeeR-EL2/design/lib/mem_lib.sv`, `` `EL2_RAM(depth,width) ``:
  ```systemverilog
  reg [(width-1):0] ram_core [(depth-1):0];   // ONE combined array
  ```
* For ICCM/DCCM the instance is `ram_4096x39` → **each row is 39 bits = data `[31:0]` + SECDED ECC `[38:32]`** (7 bits, `rvecc_encode`/`rvecc_decode` in `design/lib/beh_lib.sv:659/676`).
* Packing confirmed in RTL:
  * `design/lsu/el2_lsu_dccm_mem.sv:107-110` — `{ecc, data}` split between `dccm_wr_data_bank` / `dccm_wr_ecc_bank`.
  * `design/ifu/el2_ifu_iccm_mem.sv:117-120` — same for ICCM.
* **Bank mapping** (4 banks, `DCCM_BITS = ICCM_BITS = 16`), from `tb_top.sv:3085-3112` `get_dccm_bank`/`get_iccm_bank`:
  ```text
  bank  = addr[3:2]        // within the 64 KB region
  index = addr[15:4]       // 0..4095 → ram_core[bank][index]
  ```
  Example: byte address `+0x0010` → bank 0, index 1. Sequential `$readmemh` fills `bank0[0], bank0[1], …` regardless of address — the interleave is exactly what `$readmemh` cannot do.
* Consequences:
  1. ECC lives **inline in the same vector** — there is no `ecc_mem[]` to initialize separately.
  2. A raw `$readmemh(file, ram_core)` would require **39-bit tokens** *and* correct **bank de-interleaving** — it is the wrong tool (Correction C).
  3. A **zero fill of `39'h0` is a valid ECC state** (SECDED encoding of data `0` is `0`), so zero-initializing the array is ECC-clean — this is why VeeR's loader contains the otherwise puzzling `data == 0 ? 0 : {riscv_ecc32(data),data}` ternary.
* Proven in-tree loader (to be adapted, not reinvented): `core/Cores-VeeR-EL2/testbench/tb_top.sv`
  * `riscv_ecc32()` (line ~3073, 7-line mask function — copy verbatim), `preload_iccm()`/`preload_dccm()` (2894/2931), `slam_iccm_ram()`/`slam_dccm_ram()` (2974/2999) with `get_iccm_bank()`/`get_dccm_bank()`, `init_iccm()` zero-fill (3040).
  * Addresses ECC over the **true data**, applying `RV_*_ADDR_XOR` only to the stored data word (config-dependent "infection").
  * Note: VeeR's own TB `$readmemh`s **only** the system-bus memories (`lmem.mem`/`imem.mem`, `tb_top.sv:2211-2212`); it never `$readmemh`s ICCM/DCCM — always the backdoor path.
* Project-side RAM instantiation (what our loader targets): `tb/tb_veer_p2_soc.sv:214-248`
  * DCCM: `dccm_loop[i].dccm_bank.ram_core` (4 banks)
  * ICCM: `iccm_loop[i].iccm_bank.ram_core` (4 banks)

## 3.5 Existing project flow (baseline to be wrapped)

| File | Role |
| ---- | ---- |
| `rtl/soc_top.sv` | `IMEM_HEX`/`DMEM_HEX` **parameters** → `u_imem`/`u_dmem` |
| `rtl/ahb/ahb_sram.sv` | `reg [7:0] mem [0:SIZE_BYTES-1]`; zero-fill, then `$readmemh(HEX_FILE, mem)` if non-empty. Note: `BASE_ADDR` parameter is currently unused (aliasing relies on interconnect `HSEL`). |
| `tb/tb_veer_p2_soc.sv` | Full DUT: `veer_wrapper` + `soc_top` + behavioral ICCM/DCCM/I$ RAMs; hardcoded `IMEM_HEX("p2_prog.hex")`; halt/run reset dance; DMEM-signature PASS/FAIL/timeout monitor |
| `run/p2_full_flow.csh` | snapshot gen → `scripts/p2_prog_gen.py` (hand-assembled hex, **not GCC**) → VCS → run |
| `run/p2_veer_soc_run.f` | filelist; hardcodes `/tmp/opencode/veer_p2/...` snapshot |
| `.gitignore` | **Problem:** globally ignores `main.c`, `test.c`, `program.hex`, `*.elf`, `*.bin`, `*.lst`, `*.map` — would exclude `sw/src/main.c` from version control. Must be scoped to build dirs (Section 18). |

---

# 4. Software Path

## 4.1 Software source

```text
sw/
├── src/
│   ├── startup.S
│   ├── main.c
│   ├── uart.c
│   ├── timer.c
│   ├── gpio.c
│   ├── network.c
│   ├── crc.c
│   ├── aes.c
│   └── interrupts.c
│
├── include/
│   ├── platform.h
│   ├── uart.h
│   ├── timer.h
│   ├── gpio.h
│   ├── network.h
│   ├── crc.h
│   └── aes.h
│
├── linker/
│   └── veer.ld
│
├── Makefile
│
└── build/
```

The exact source partition can evolve, but the separation between application, startup, linker description and generated artifacts must remain.

Architectural division (from the project architecture document): initialization/configuration and peripheral interaction belong to software; packet reception, parsing, CRC and AES transformation belong to hardware.

## 4.2 Compiler configuration

ISA and ABI are controlled explicitly — the executable name `riscv64-unknown-elf-gcc` does **not** imply RV64. The build **must not** rely on compiler defaults.

Frozen variables:

```make
CROSS_COMPILE := riscv64-unknown-elf-

CC      := $(CROSS_COMPILE)gcc
AS      := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump
READELF := $(CROSS_COMPILE)readelf

MARCH := rv32imc_zicsr_zifencei
MABI  := ilp32
```

Frozen flags (Section 11 has the full block): `-march=$(MARCH) -mabi=$(MABI)`, `-ffreestanding -fno-builtin -Wall -Wextra`, `-nostartfiles -T linker/veer.ld`.

## 4.3 Linker script

`linker/veer.ld` determines `.text`, `.rodata`, `.data`, `.bss`, stack, alignment, entry point and region boundaries.

**Frozen memory map (decision D1/D2):**

```text
MEMORY
{
    IMEM (rx)  : ORIGIN = 0x0000_0000, LENGTH = 32K   /* system IMEM, no ECC */
    DMEM (rwx) : ORIGIN = 0x0001_0000, LENGTH = 32K   /* system DMEM, no ECC */
}

.text    -> IMEM
.rodata  -> IMEM
.data    VMA -> DMEM,  LMA -> IMEM   /* startup.S copies at boot (D8) */
.bss     -> DMEM                     /* cleared by startup.S */
stack    -> DMEM top (0x0001_7FFF, descending, 16-byte aligned)
ENTRY(_start)
```

Rules:

* Region sizes must match RTL exactly (32 KB / 32 KB).
* No region overlap; overflow checks (`ASSERT`/`_stack`/`__memory_*` symbols) in the linker script.
* Generate and retain a link map (`.map`).
* **Do not** place anything at `0xEE00_xxxx` (ICCM) or `0xF004_xxxx` (DCCM) until the later DCCM milestone (Section 12.4).

## 4.4 VeeR memory-placement constraint

VeeR has two classes of memory — core-local (ICCM, DCCM, PIC registers) and system-bus attached (project IMEM/DMEM, MMIO). The PRM requires them to occupy **different** regions. The verified map in Section 3.3 satisfies this: project memories at `0x0000_0000`/`0x0001_0000`, core-local at `0xEE…`/`0xF0…`. Any future memory-map change must re-verify non-overlap.

---

# 5. ELF Generation and Mandatory Validation

Build sequence: `startup.S` + `main.c` + drivers → compiler → objects → linker (`veer.ld`) → **`build/firmware.elf`**.

The ELF is the **authoritative** artifact (sections, symbols, addresses, entry, attributes, debug info). HEX images are derived artifacts.

Mandatory post-link validation (`make inspect`):

```bash
riscv64-unknown-elf-readelf -h build/firmware.elf
riscv64-unknown-elf-readelf -A build/firmware.elf
```

Checklist:

```text
[ ] ELF class = ELF32
[ ] Machine = RISC-V
[ ] ISA attributes = rv32imc + zicsr + zifencei   (expected string below)
[ ] ABI = ilp32
[ ] entry address = reset vector (0x0000_0000) == _start
[ ] section addresses (.text/.rodata in IMEM; .data/.bss in DMEM)
[ ] section sizes within region lengths
[ ] no region overflow
[ ] link map generated
```

Expected `readelf -A` output (verified on this machine with GCC 16.1.0):

```text
Attribute Section: riscv
File Attributes
  Tag_RISCV_stack_align: 16-bytes
  Tag_RISCV_arch: "rv32i2p1_m2p0_c2p0_zicsr2p0_zifencei2p0_zmmul1p0_zca1p0"
```

GCC expands `rv32imc` into `rv32i2p1_m2p0_c2p0` and appends the explicitly named extensions; `zicsr`/`zifencei` are **mandatory** in modern binutils (without them `csrw`/`fence.i` fail to assemble — startup and interrupt setup need both).

This gate exists because the earlier generic `hello.elf` was never proven to be the correct RV32IMC/ILP32 image for VeeR.

---

# 6. Two Different HEX Artifacts (Correction B)

## 6.1 Intel HEX — delivery artifact only

```bash
riscv64-unknown-elf-objcopy -O ihex build/firmware.elf build/firmware.ihex
```

* Format: records such as `:10000000...` with address/length/checksum.
* Useful as a general firmware delivery artifact.
* **NEVER passed to `$readmemh`.**

## 6.2 Simulator memory image — `$readmemh` input

```text
build/imem.mem      /* byte tokens, IMEM-region addressing */
build/dmem.mem      /* byte tokens, DMEM-region addressing */
```

Generator (verified available — `objcopy --info` lists `verilog`; VeeR's own `tools/Makefile:300` uses exactly this command):

```bash
riscv64-unknown-elf-objcopy -O verilog --verilog-data-width 1 \
    --only-section=.text --only-section=.rodata --only-section=.data \
    --change-addresses=-0x00000000 \
    build/firmware.elf build/imem.mem
```

Constraints discovered during review:

1. **Rebase rule (H.3 / D11):** `objcopy -O verilog` emits `@<hex>` markers, but `ahb_sram.mem` is a **dense** array indexed `0..SIZE_BYTES-1`. `@` denotes an **array index, not a byte address**, and absolute addresses are valid only for sparse associative arrays (VeeR's `ahb_sif` style). Therefore:
   * per-region generation (`--only-section`) is mandatory;
   * addresses must be **rebased to the region base** (`--change-addresses=-BASE`), so DMEM images use local indices `0x0000_0000…0x0000_7FFF`, not `0x0001_xxxx` (an `@00010000` marker against a 32 KB array addresses index 65536 — out of range).
2. **Width rule (H.3):** `--verilog-data-width N` must equal the target array's word width in bytes:
   * `ahb_sram.mem` is `reg [7:0] mem[0:32767]` → **N = 1** (the default) — one hex token per byte;
   * at N = 4, objcopy **divides the `@` addresses by 4** and packs bytes little-endian into words (`41 11 06 C6` → `C6061141`) — correct only for a 32-bit-wide array; VeeR `ram_core` is 39 bits wide (not a byte multiple) — one more reason ICCM/DCCM cannot take a plain `$readmemh`.
3. **`.bss` / NOBITS policy (H.9):** `.bss` is `NOBITS` — there are literally zero bytes for it in the ELF, so **no conversion tool can ever produce them**. It is covered by **both** mechanisms: `startup.S` zeroes it at boot (D8), *and* the loader pre-fills the RAM array with zeros. The two together are harmless; either alone is sufficient for simulation, but startup keeps the firmware hardware-correct.
4. The Makefile must hide these details behind `make mem`.

The Makefile must never express the flow as `ELF → Intel HEX → $readmemh`.

## 6.3 Flat image vs split images (original Option A vs B — resolved)

| Option | Mechanism | Verdict |
| ------ | --------- | ------- |
| **A — one flat `firmware.mem`** | single file, absolute addresses | ✗ **rejected**: dense `ahb_sram` arrays cannot accept absolute `@00010000` markers; would also conflate two memories |
| **A′ — split `imem.mem` + `dmem.mem`, `@` rebased to each array's index 0** | per-region `objcopy` | ✅ **chosen (D11)** |
| B′ — change arrays to sparse associative (VeeR `ahb_sif` style) | simplest loader | ✗ modifies proven RTL; rejected |
| C′ — one flat file, rebase inside `$readmemh` | — | ✗ impossible: `$readmemh` takes a filename, no transform hook |
| D′ — one array spanning the whole address space | — | ✗ wasteful |
| B (original) — separate ICCM/DCCM images | per-core-local images | ✅ adopted **later**, at the DCCM milestone, as plain 32-bit-word images for the backdoor loader |

This is *why* the image model lists `imem.mem`/`dmem.mem` (and later `iccm.mem`/`dccm.mem`): **each image's `@` records must be relative to that memory's array index zero.**

---

# 7. Recommended Image Model

```text
sw/build/
├── firmware.elf        authoritative
├── firmware.map
├── firmware.dis        objdump -d -S
├── firmware.ihex       delivery only
├── imem.mem            sim image → system IMEM
├── dmem.mem            sim image → system DMEM
├── iccm.mem            (later milestone; 32-bit words, backdoor-loaded)
├── dccm.mem            (later milestone; 32-bit words, backdoor-loaded)
└── manifest.txt        build metadata (Section 17)
```

(A single flat `firmware.mem` alias is **not** part of the model — flat images were rejected in §6.3/D11.)

Not every file must exist simultaneously; the selection follows the frozen boot model (ICCM/DCCM files only appear at the DCCM milestone).

---

# 8. Makefile Architecture

## 8.1 Root Makefile interface

| Target | Responsibility |
| ------ | -------------- |
| `firmware` | C/assembly → `firmware.elf` (delegates `make -C sw`) |
| `inspect` | ELF architecture/linker validation gate |
| `mem` | ELF → sim memory images (`imem.mem`, `dmem.mem`) + `firmware.ihex` |
| `veer-config` | Generate project-local VeeR snapshot (decision D6) |
| `rtl` | Compile VeeR + SoC + TB (VCS) |
| `sim` | Build simulator (`simv`) |
| `run` | Execute simulation with generated images via plusargs |
| `all` | Complete software + simulation flow |
| `clean` | Remove generated artifacts (SW + sim) |

Delegation: root → `sw/Makefile` (compiler flags) and `sim/Makefile` (VCS flags). Never one enormous Makefile; never modifying RTL from the SW build (Section 19).

## 8.2 `sw/Makefile` frozen variables

```make
CROSS_COMPILE := riscv64-unknown-elf-
CC      := $(CROSS_COMPILE)gcc
OBJCOPY := $(CROSS_COMPILE)objcopy
OBJDUMP := $(CROSS_COMPILE)objdump
READELF := $(CROSS_COMPILE)readelf

MARCH := rv32imc_zicsr_zifencei
MABI  := ilp32

CFLAGS := \
    -march=$(MARCH) -mabi=$(MABI) \
    -O0 -g \
    -ffreestanding -fno-builtin \
    -Wall -Wextra

LDFLAGS := \
    -march=$(MARCH) -mabi=$(MABI) \
    -nostartfiles \
    -T linker/veer.ld \
    -Wl,-Map=$(BUILD)/firmware.map
```

Targets: `all elf dis ihex mem inspect manifest clean`.

## 8.3 `sim/Makefile`

```make
VCS_HOME ?= /home/student/snps_tools_target/vcs/U-2023.03
VERDI_HOME ?= /home/student/snps_tools_target/verdi/U-2023.03-SP1
PATH := $(VCS_HOME)/bin:$(PATH)
```

* `veer-config` recipe: `env BUILD_PATH=$(REPO)/build/snapshots/p2_soc RV_ROOT=$(RV_ROOT) $(RV_ROOT)/configs/veer.config -target=default_ahb -snapshot=p2_soc -set=reset_vec=0x00000000`.
* `sim/filelist.f` (new) references `build/snapshots/p2_soc/...` — **not** `/tmp/opencode/...` (decision D6).
* `run` invokes `./simv +IMEM_HEX=$(SW_BUILD)/imem.mem +DMEM_HEX=$(SW_BUILD)/dmem.mem …`.

Conceptual dependency graph:

```text
make sim
   +--> veer-config          (snapshot)
   +--> make firmware        (ELF)
   +--> make mem             (imem.mem / dmem.mem / .ihex)
   +--> make rtl             (VCS compile)
   +--> simv +IMEM_HEX=... +DMEM_HEX=...
```

---

# 9. Simulation Path

The simulator sees **memory images through plusargs**, not `main.c` and not `firmware.elf` (no ELF loader/debug mechanism is in scope).

```text
imem.mem / dmem.mem  (or iccm.mem / dccm.mem later)
        |
        v
  SV Testbench (plusarg parse + file validation)
        |
        v
  Memory Initialization Service
        |
        +----> system IMEM  (hierarchical $readmemh)
        +----> system DMEM  (hierarchical $readmemh)
        +----> ICCM/DCCM    (backdoor ECC loader — Section 12)
        |
        v
  hold reset -> release reset -> CPU execution
```

## 9.1 Plusarg interface

```text
+IMEM_HEX=<path>     system IMEM image   (mandatory)
+DMEM_HEX=<path>     system DMEM image   (optional — overlay after zero-fill)
+ICCM_HEX=<path>     ICCM data image     (later milestone; Mode 2 only)
+DCCM_HEX=<path>     DCCM data image     (later milestone; Mode 2 only)
+RESET_CYCLES=<N>    reset hold duration
+TIMEOUT=<N>         watchdog cycles     (optional)
```

Example:

```bash
./simv +IMEM_HEX=../sw/build/imem.mem +DMEM_HEX=../sw/build/dmem.mem
```

Parsing pattern:

```systemverilog
if (!$value$plusargs("IMEM_HEX=%s", imem_file))
    $fatal(1, "[TB] +IMEM_HEX not specified");
if ($fopen(imem_file, "r") == 0)
    $fatal(1, "[TB] image not found: %0s", imem_file);
```

Policy: **`+IMEM_HEX` is mandatory** (without it the CPU would fetch `X`); **`+DMEM_HEX` is optional** — under D8 the startup copy + `.bss` clear establish DMEM contents anyway, so the DMEM overlay is a redundancy/verification aid. Both arrays are always **zero-filled first**, then the optional overlay is applied — this guarantees no `X` survives in never-written DMEM locations (stack etc.).

Never hard-code `$readmemh("firmware.mem", …)` in the testbench — the same RTL must run firmware A/B, regression, interrupt, AES and network images without source edits.

## 9.2 Loading ownership: testbench vs RTL (H.4 resolved with evidence)

The draft had a conflict: plusargs are specified as the interface, but today the **RTL** loads memory (`ahb_sram` `initial` → `$readmemh(HEX_FILE, mem)`, path supplied via `soc_top` parameter `IMEM_HEX("p2_prog.hex")`), which also collides with the boundary rule *"the RTL should not know about `hello.c`"*. Companion amendment H.4 laid out the options:

| Option | Mechanism | Verdict |
| ------ | --------- | ------- |
| **R2** — plusarg → parameter → RTL `$readmemh(HEX_FILE)` | TB derives path, passes as parameter override | ✗ **empirically dead**: plusargs are not visible at elaboration. Tested on this machine with VCS U-2023.03 — a parameter-initializing function calling `$value$plusargs("HEX=%s",…)` compiled fine but printed `HEXFILE=DEFAULT.hex` even when run with `+HEX=OVERRIDE.mem`. Companion H.4's "recommended for Phase 3" therefore **cannot work**. |
| **R1** — RTL `initial` parses `$value$plusargs` itself | no parameter involved | ✗ rejected: the image contract (`+IMEM_HEX` name, `$readmemh`) leaks into synthesizable RTL, *and* ICCM/DCCM arrays live in the TB anyway → two mechanisms instead of one. |
| **T — TB-owned (chosen, D9)** | TB service: zero-fill + hierarchical `$readmemh` after plusarg parse | ✅ runtime-selectable, one mechanism for all memories, RTL clean of image knowledge. |

Consequences of choosing T (must all be implemented):

1. **Remove the `initial` block from `rtl/ahb/ahb_sram.sv`** (zero-fill + `$readmemh`) and retire `HEX_FILE`/`IMEM_HEX`/`DMEM_HEX` parameters. *Why removal is mandatory:* two `initial` blocks at t=0 have **nondeterministic relative order**; if the TB's `$readmemh` ran first and the RTL's zero-fill second, the image would be silently wiped. Single owner = no reasoning about event-scheduling needed.
2. Zero-fill moves into the TB service (it is needed there anyway for ICCM/DCCM).
3. Hierarchical TB→RTL access is **already precedent** in this codebase — the Phase-2 PASS monitor reads `u_soc.u_dmem.mem[2]` (`tb/tb_veer_p2_soc.sv:300`) — so `tb_memory_init` following suit is consistent, not novel.

## 9.3 Initialization modes (original §22) — Mode 1 frozen, with guardrails

| Mode | Memories initialized | Status |
| ---- | -------------------- | ------ |
| **Mode 1 — system IMEM/DMEM** | `+IMEM_HEX`, `+DMEM_HEX` → plain `$readmemh` | ✅ **the project configuration (D10)** |
| **Mode 2 — ICCM/DCCM** | `+ICCM_HEX`, `+DCCM_HEX` → backdoor ECC loader (§12) | deferred to the DCCM milestone |
| **Mode 3 — auto-selected** | TB derives which memories exist from the RTL config (`RV_ICCM_ENABLE`/`RV_DCCM_ENABLE` macros from `common_defines.vh`) and initializes only those | target end-state; Mode 1's guardrails implement its checks from day 1 |

**The Mode-1 escape hatch (why this is safe):** with `reset_vec = 0x0000_0000`, boot PC `0x0000_0000` is *not* inside ICCM (`0xEE00_0000…0xEE00_FFFF`), so the IFU forwards fetches to the bus → IMEM. `.data`/`.bss`/stack at `0x0001_0000…0x0001_7FFF` are *not* inside DCCM (`0xF004_0000…0xF004_FFFF`), so the LSU forwards to the bus → DMEM. The core-local arrays are instantiated but **never read, so ECC is never checked** (VeeR routing rule: accesses inside the ICCM/DCCM region stay core-local, everything else goes to the bus — `docs/source/memory-map.md`).

Guardrails that make it a *guarded* decision rather than an oversight (all fold into D10):

1. Linker `MEMORY` regions exclude `0xEE00_xxxx` / `0xF004_xxxx`.
2. Build-time check (linker `ASSERT` / map inspection): no `.text`/`.data`/`.bss`/stack address inside a core-local range.
3. TB failure condition: any section/image overlapping a core-local region while Mode 1 is active (§14).
4. Active mode recorded in `build/manifest.txt` (§17).
5. `tb_memory_init` shaped so the `slam_*` loader can be added later without a rewrite (§12.2).

---

# 10. SystemVerilog Testbench Structure

```text
tb/
├── tb_veer_p2_soc.sv      (existing DUT integration — extended)
├── tb_memory_init.sv      memory initialization service
├── tb_clock_reset.sv      clock/reset service
├── tb_monitor.sv          UART/GPIO/CPU monitors
├── tb_scoreboard.sv
└── tb_pkg.sv
```

(The exact split may evolve; the requirement is a **dedicated initialization service**, not scattered `$readmemh` calls.)

The memory initialization service owns:

```text
plusarg discovery
file validation ($fopen probe -> $fatal if missing)
region enable / mode checks          (§9.3 guardrails)
memory initialization (per memory type: zero-fill, $readmemh, or ECC backdoor)
initialization logging               (§15)
reset sequencing                     (§11)
```

Full testbench service inventory (original §31 — keeps infrastructure reusable):

```text
tb_top
 |
 +-- clock/reset service
 +-- memory initialization service      (this section)
 +-- firmware/image service             (plusargs, validation)
 +-- UART monitor
 +-- GPIO monitor
 +-- CPU execution monitor              (first-fetch / PC trace)
 +-- timeout watchdog
 +-- scoreboard                         (PASS/FAIL, DMEM signature)
 +-- packet generator                   (later: network telemetry stimulus)
```

---

# 11. Initialization Timing

```text
time 0
  |
  +--> parse plusargs, validate image files
  +--> initialize/zero-fill all present memories   (ECC-clean)
  +--> load images
  +--> initialize peripheral/testbench state
  +--> assert reset
  +--> hold reset for RESET_CYCLES
  +--> release reset
  +--> CPU begins execution
```

Recommended skeleton:

```systemverilog
initial begin
    parse_plusargs();
    validate_images();
    initialize_memories();
    reset_n = 1'b0;
    repeat (RESET_CYCLES) @(posedge clk);
    reset_n = 1'b1;
end
```

Critical requirement:

> **The CPU must not be allowed to execute from an uninitialized instruction memory.**

**Already satisfied today — do not "fix" what is not broken (H.7):** in the existing Phase-2 testbench, memory init runs at t = 0 (the `initial` block — which D9 relocates into the TB service but keeps at t = 0), reset is asserted at 5 ns and released at 30 ns (`tb_veer_p2_soc.sv:269-274`). The ordering requirement is met; the new service must preserve this ordering.

Note: the existing `tb_veer_p2_soc.sv` reset/halt/run sequence (reset → halt → ack → run → debug halt/run dance) is proven and must be preserved or consciously simplified — not silently removed.

---

# 12. ICCM/DCCM ECC Treatment (Correction C — resolved design)

## 12.1 Why raw `$readmemh` is disallowed

**PRM citations** (`core/Cores-VeeR-EL2/docs/source/error-protection.md:107/:111`):

> "Memories with parity or ECC protection must be initialized with correct parity or ECC. Otherwise, a read access to an uninitialized memory may report an error. The method of initialization depends on the organization and capabilities of the memory. Initialization might be performed by a memory self-test or depend on firmware to overwrite the entire memory range (e.g., via DMA accesses)."

> "If the DCCM is uninitialized, a load following a store to the same DCCM address may get incorrect data. If firmware initializes the DCCM, aligned word-sized stores should be used (because they don't check ECC), followed by a fence, before any load instructions to DCCM addresses are executed."

Verified storage structure (§3.4, Case D): a single 39-bit `ram_core` row per bank holding `{ecc[6:0], data[31:0]}`. Four independent ways a naive `$readmemh("dccm.mem", <bank>.ram_core)` breaks:

| # | Failure | Why |
| - | ------- | --- |
| 1 | **Word-width mismatch** | array word = 39 bits; hex tokens are 8/32 bits → `$readmemh` zero-extends → `ram_core[i][38:32] = 0` |
| 2 | **ECC never generated** | ECC field stays 0 — see below, this is *not* benign |
| 3 | **Bank/index interleave ignored** | `$readmemh` fills `bank0[0], bank0[1], …` sequentially; address `+0x10` actually belongs at bank 0 index 1 (`bank = addr[3:2]`, `index = addr[15:4]`) but file order has no relation to that mapping — data lands in the wrong rows |
| 4 | **Address-XOR "infection"** (conditional) | if `dccm_addr_xor = 1`, the core stores `data ^ word_addr`; loader must apply the same XOR. This build: `dccm_addr_xor = 0`, `iccm_addr_xor = 0` — **verify per snapshot, do not assume** |

**Failure mode is silent corruption, not a clean error.** With `ecc = 0` preloaded, `rvecc_decode` interprets the nonzero syndrome as an error *on the loaded value itself*:

```text
word loaded     decoder verdict                     what the CPU actually gets
0x00000013      SINGLE-BIT → bogus "correction"     0x00000413  (was addi x0,x0,19)
0x00A18023      SINGLE-BIT → bogus "correction"     0x00A18033  (sb to a different offset!)
0xC6061141      DOUBLE-BIT → uncorrectable          fetch/load faults
0x00000000      no error (ECC(0) == 0 coincidentally) OK
```

When the data's overall parity is odd the decoder declares a **single-bit error**, *flips a bit* and hands the CPU a **different value than was loaded** — a store instruction silently becomes a store to another address. When parity is even it declares uncorrectable (exception/NMI). An honest caveat: these errors only surface on a memory that is actually **read** with ECC checking enabled — which is precisely why Mode 1 (§9.3, nothing core-local is ever read) makes the risk dormant, and why the guardrails must keep it dormant.

**Both raw-`$readmemh` variants are forbidden** by this specification.

## 12.2 Chosen design: testbench backdoor loader (D3)

Adapt the proven VeeR pattern:

```systemverilog
// TB-side, once, before reset release:
//   1. zero-fill:  foreach bank: ram_core = '{default:39'h0}   // ECC-valid (ecc(0)=0)
//   2. for each 32-bit word in the plain <mem>.mem image:
//        bank = get_<mem>_bank(addr, idx);          // mirror RTL bank mapping
//        ecc  = riscv_ecc32(data);                  // same equations as beh_lib.sv
//        if (RV_*_ADDR_XOR) store {ecc, data ^ xormask(addr)}
//        else                store {ecc, data}
//        hierarchy[bank][idx] = word;
```

* Image format: **plain 32-bit word `.mem`** via `+ICCM_HEX`/`+DCCM_HEX` (one word per line, region-relative addressing). **ECC is computed by the loader at preload time and is never present in the `.mem` file.**
* Bank mapping (copy from `tb_top.sv:3085-3112`, 4-bank branch): `bank = addr[3:2]`, `index = addr[15:4]` for both ICCM and DCCM in this config.
* Hierarchy targets (project TB): `dccm_loop[i].dccm_bank.ram_core`, `iccm_loop[i].iccm_bank.ram_core`.
* ECC equations: copy `riscv_ecc32()` verbatim from `testbench/tb_top.sv:3073` (already validated against RTL) — do **not** reimplement SECDED from scratch in Python (the companion document's `ecc_demo.py` replica exists as a cross-check, not as the production encoder).
* If `RV_DCCM_ADDR_XOR`/`RV_ICCM_ADDR_XOR` are ever enabled in the snapshot, the loader must apply the identical XOR (VeeR stores `data ^ mask`, ECC is over the true data).

## 12.3 Policy matrix

| Situation | Action |
| --------- | ------ |
| ICCM/DCCM enabled, no image supplied | Zero-fill `39'h0` (X-safe, ECC-valid) |
| ICCM/DCCM enabled, image supplied | Backdoor ECC load per 12.2 |
| ICCM/DCCM disabled in config | No init; supplying `+ICCM_HEX`/`+DCCM_HEX` is a **fatal error** (Section 14) |
| I-cache | No preload (cold-fill from bus, data comes from initialized IMEM) |
| System IMEM/DMEM | Plain `$readmemh` (byte array, no ECC) |

## 12.4 Later milestone (out of scope for first boot)

Placing `.data`/`.bss`/stack in DCCM, or `.text` in ICCM, requires: linker-map change, `icc/dccm.mem` generation, activation of the backdoor loader path — and for ICCM boot a config snapshot with `reset_vec` inside the ICCM region. Deferred per decision D2/D10.

**Complementary firmware escape route (PRM `error-protection.md:111`):** aligned word-sized stores do **not** check ECC on the write path, so firmware itself can initialize DCCM by storing words followed by a `fence`, before any load to DCCM addresses. For ICCM (code must execute *from* it), firmware cannot easily initialize before fetching — hence the `slam` backdoor preload remains necessary there. The two mechanisms are complementary: preload for ICCM, optional store-based init for DCCM.

Until this milestone activates, the Mode-1 guardrails (§9.3 / D10) must detect any accidental placement of a section in a core-local region.

## 12.5 IMEM ≠ ICCM, DCCM ≠ system DMEM (original §18/§19)

These pairs must never be conflated — they are different architectural resources with different owners:

```text
Instruction side                         Data side

  CPU IFU                                  CPU LSU
    |                                        |
    +--> ICCM (core-local, ECC)              +--> DCCM (core-local, ECC)
    |    0xEE00_0000, no bus transaction      |    0xF004_0000, no bus transaction
    |    backdoor-loaded (§12)                |    backdoor-loaded (§12)
    |                                        |
    +--> AHB-Lite IFU bus                    +--> AHB-Lite LSU bus
           |                                        |
           v                                        v
    system IMEM (project SRAM, no ECC)     system DMEM (project SRAM, no ECC)
    0x0000_0000, plain $readmemh           0x0001_0000, plain $readmemh
```

* Fetching from ICCM requires **no** external AHB-Lite transaction; fetching from system IMEM goes through the interconnect.
* Under Mode 1 (frozen), firmware uses only the **bus-attached** pair: instructions from system IMEM, data from system DMEM. The linker script determines which pair `.text`/`.data`/`.bss`/stack land in — and D10 forbids core-local ranges until the DCCM milestone.

---

# 13. Reset Vector Dependency

The PRM specifies the SoC supplies the reset vector through `rst_vec[31:1]`; reset is active-low, asynchronously asserted, synchronously deasserted.

```text
snapshot config (reset_vec=0x00000000)
        |                linker script (_start @ 0x00000000)
        +-------+--------+
                |
                v
        same entry address
```

Frozen: `reset_vec = 0x0000_0000` (p2_soc) **must equal** `ENTRY(_start)` **must equal** `.text` base. The testbench must not assume `PC = 0` independently of the snapshot (`reset_vector` is already read from `` `RV_RESET_VEC `` in `tb_veer_p2_soc.sv:28`).

Three places must agree, and **neither failure mode is loud**:

| Where | Value today |
| ----- | ----------- |
| `veer.config -set=reset_vec=` | P1: `0x80000000`; P2: **`0x00000000`** |
| First `@` record of the sim image | `imem.mem` must start at rebased `@00000000` |
| `sw/linker/veer.ld` location counter / `ENTRY` | **must be `0x0000_0000`** |

| Mistake | Result |
| ------- | ------ |
| default target (`0x8000_0000`) + linker at `0x0` | CPU fetches `0x80000000` → `ahb_default_slave` → 2-cycle ERROR → `HRESP=1` → boot exception |
| `reset_vec=0` + linker at `0x8000_0000` | CPU fetches `0x0` containing zeros/`X` → hang |

Both present as *"simulation runs forever"* — which is why the failure conditions (§14) mandate `"[ ] CPU never begins execution"` plus a watchdog. Note the port is `rst_vec[31:1]`, so the vector is implicitly halfword-aligned (satisfied automatically by RISC-V instruction alignment).

---

# 14. Failure Conditions

The testbench must fail immediately (do not run millions of cycles) on:

```text
[ ] +IMEM_HEX missing / image file not specified
[ ] image file cannot be opened ($fopen probe fails)
[ ] unsupported memory configuration
[ ] +ICCM_HEX supplied when ICCM disabled in config
[ ] +DCCM_HEX supplied when DCCM disabled in config
[ ] +ICCM_HEX/+DCCM_HEX supplied under Mode 1 (guardrail, §9.3/D10)
[ ] any loaded section / stack address overlaps an ICCM or DCCM region
    while Mode 1 is active          (guardrail, §9.3/D10)
[ ] image size exceeds target memory size
[ ] `@` record in an image out of range for its target array (rebase error, §6.2)
[ ] reset never released
[ ] CPU never begins execution (no fetch after reset)
[ ] simulation timeout
[ ] unexpected bus error (HRESP != OKAY)
[ ] memory initialization failure
```

PASS/FAIL must be reported with an unambiguous terminal token (the existing `P2_TB2_RESULT: PASS/FAIL` style is the template).

---

# 15. Initialization Logging (Verification Level 5)

At simulation start, print only memories that actually exist:

```text
[TB] Image: imem.mem (32768 bytes)
[TB] IMEM initialized (0x0000_0000..0x0000_7FFF)
[TB] DMEM initialized (0x0001_0000..0x0001_7FFF)
[TB] ICCM zero-filled (0xEE00_0000..0xEE00_FFFF, ECC clean)
[TB] DCCM zero-filled (0xF004_0000..0xF004_FFFF, ECC clean)
[TB] RESET asserted / released
```

---

# 16. Verification Architecture

| Level | Check | Pass criteria |
| ----- | ----- | ------------- |
| 1 Compiler | `main.c → firmware.elf` | ELF generated |
| 2 ISA | `readelf -h/-A` | RV32, arch string exactly as §5 (`rv32i2p1_…_zicsr2p0_zifencei2p0_…`), ILP32 |
| 3 Linker | section/entry addresses | match Section 4.3 & snapshot params |
| 4 Image conversion | `.ihex` + `.mem` exist; `@addr` within region; byte order/width correct; spot-check words vs `objdump` | images represent expected contents |
| 5 TB init | init log + ECC-clean zero-fill | only existing memories reported |
| 6 CPU boot | reset → reset vector → first instruction → `startup.S` → `main()` | first fetch address == entry |
| 7 Peripheral access | UART/Timer/GPIO/Network/CRC/AES register accesses | driver smoke tests pass |

First-instruction check: `objdump -d` of `firmware.elf` must show `_start` at `0x0000_0000` with the same bytes as the head of `imem.mem`.

---

# 17. Build Metadata

Generate `sw/build/manifest.txt`:

```text
Toolchain:   riscv64-unknown-elf-gcc 16.1.0
Binutils:    2.47.20260726
MARCH:       rv32imc_zicsr_zifencei
MABI:        ilp32
Linker:      sw/linker/veer.ld
Git commit:  <sha>
Build date:  <iso8601>
ELF:         sw/build/firmware.elf   (entry 0x00000000)
IHEX:        sw/build/firmware.ihex   (delivery only)
IMEM image:  sw/build/imem.mem        (width=1 byte/token, rebased to 0)
DMEM image:  sw/build/dmem.mem        (width=1 byte/token, rebased to 0)
VeeR snapshot: build/snapshots/p2_soc (target=default_ahb, reset_vec=0x00000000)
Init mode:   Mode 1 — system IMEM/DMEM; ICCM/DCCM unused, ECC guardrails active
addr_xor:    iccm=0 dccm=0  (from snapshot; loader must mirror if non-zero)
```

---

# 18. Directory Structure

```text
honours_project/
├── rtl/                  (existing)
├── sw/                   NEW
│   ├── src/
│   ├── include/
│   ├── linker/veer.ld
│   ├── build/            (generated, gitignored)
│   └── Makefile
├── tb/                   (existing + memory-init service)
├── sim/                  NEW
│   ├── Makefile
│   ├── filelist.f        (project-local snapshot paths)
│   └── run/              (generated, gitignored)
├── build/                NEW — VeeR snapshots + top-level artifacts (gitignored)
├── core/Cores-VeeR-EL2/  (submodule, read-only)
├── run/                  (existing csh flows — untouched, D4)
├── scripts/              (existing + image helpers if needed)
├── doc/
└── Makefile              NEW — root delegator
```

### Version-control / gitignore rules

Source (tracked): `.c .S .h .ld .sv .v .f Makefile .csh .py`.

Generated (ignored, **scoped under build dirs** — requires fixing the current global ignores of `main.c`/`*.elf`/`*.bin`/`*.lst`/`*.map` in `.gitignore`):

```text
sw/build/
sim/run/
build/snapshots/
simv
simv.daidir/
csrc/
*.fsdb
*.vpd
*.log
*.mem
*.ihex
*.hex        (except explicitly tracked fixtures, if any)
*.elf
*.map
*.dis
```

---

# 19. Responsibility Boundaries

```text
Software Build
       |
       | image contract (firmware.elf / *.mem)
       v
Simulation Environment
       |
       | RTL compile + plusargs
       v
VeeR + SoC
```

* The Makefile must **not** modify RTL source.
* The SV testbench must **not** invoke GCC.
* The RTL must not know about `hello.c` — and after D9, must not contain **any** image filename, `$readmemh`, or plusarg name.
* The compiler must not know about VCS hierarchy.
* Existing `run/*.csh` flows are wrapped, not edited (D4).

---

# 20. Image Contract (frozen interface)

**Inputs:** firmware source + `sw/linker/veer.ld` + VeeR snapshot parameters.

**Software outputs:**

```text
firmware.elf      authoritative
firmware.ihex     delivery only (never $readmemh)
imem.mem          sim image → system IMEM
dmem.mem          sim image → system DMEM
```

**Format attributes of every `.mem` image (H.5 — freeze these):**

```text
token format      : hex, one byte per token (objcopy --verilog-data-width 1)
address base      : 0 — @ records are relative to each memory's array index 0
endian/byte order : byte stream as in ELF (little-endian); words packed only
                    if a future consumer is word-wide
.bss / NOBITS     : not in any image; startup.S zeroes .bss AND loader pre-zeroes
ECC               : not present in any image (Mode 1: ICCM/DCCM unused and
                    guardrailed; later: computed by the TB backdoor loader)
size limit        : token count ≤ target array depth (checked at load)
```

**Simulation inputs:** `imem.mem`, `dmem.mem` via `+IMEM_HEX`, `+DMEM_HEX` (later: `iccm.mem`/`dccm.mem` via `+ICCM_HEX`/`+DCCM_HEX`, backdoor ECC-loaded).

**Testbench responsibilities:** parse plusargs; validate paths/files/config compatibility; **own all memory initialization** (zero-fill + load, D9); initialize memories ECC-clean; hold/reset release; monitor execution; PASS/FAIL/TIMEOUT.

**DUT responsibilities:** fetch instructions; execute firmware; access data memory and peripherals; generate interrupts.

---

# 21. Implementation Plan (frozen order)

| Step | Work item | Key points |
| ---- | --------- | ---------- |
| S1 | Create `sw/` tree + `linker/veer.ld` | MEMORY IMEM/DMEM per §4.3; overflow asserts; `ENTRY(_start)` |
| S2 | `startup.S` | set `sp=0x0001_8000`; copy `.data` (LMA→VMA); clear `.bss`; call `main`; trap vector (D8) |
| S3 | `sw/Makefile` | frozen vars/flags §8.2; targets `elf dis ihex mem inspect manifest clean` |
| S4 | `make mem` image rules | `objcopy -O verilog --only-section … --change-addresses=-BASE` per §6.2 |
| S5 | `veer-config` target | project-local `build/snapshots/p2_soc` (D6) |
| S6 | `sim/filelist.f` | reference local snapshot (replaces `/tmp` hardcode) |
| S7 | TB memory-init service | plusargs, `$fopen` validation, hierarchical `$readmemh`, ECC-clean zero-fill, logging, failure conditions (§14); shaped so `slam_*` loader can be added later (§9.3) |
| S7b | RTL ownership cleanup (D9) | remove the `initial` block from `rtl/ahb/ahb_sram.sv`; retire `HEX_FILE`/`IMEM_HEX`/`DMEM_HEX` parameters; **do this in the same change as S7** (avoids the t=0 zero-fill/`$readmemh` race) |
| S8 | TB image wiring | replace hardcoded `IMEM_HEX("p2_prog.hex")` with plusarg service (D9); preserve reset/halt/run sequence |
| S9 | `sim/Makefile` + root `Makefile` | VCS env; delegating targets (§8) |
| S10 | `.gitignore` fix | scope global `main.c`/`*.elf` ignores to build dirs (§18) |
| S11 | Firmware 0 (idle loop) | prove `make sim` end-to-end: boot → first fetch → run → PASS/timeout |
| S12 | Firmware milestones 1–7 | §22 |
| S13 | (later) DCCM/ICCM milestone | backdoor ECC loader + linker placement (D2, §12.4) |

---

# 22. Firmware Milestones

Staged firmware — do **not** start with the complete telemetry application.

| # | Firmware | Goal |
| - | -------- | ---- |
| 0 | boot + PASS signal | CPU exits reset → `startup.S` → `main()` → writes the Phase-2 PASS signature to the DMEM mailbox (`u_dmem.mem[0]='P'`, `[1]='2'`-style magic ending with `mem[2]=8'hFF`) so the **existing** `tb_veer_p2_soc` monitor fires with zero monitor changes |
| 1 | GPIO register write | CPU → GPIO register → `gpio[0]` |
| 2 | UART register write | CPU → UART → `uart_tx` |
| 3 | DCCM/DMEM memory test | store → load → compare |
| 4 | Timer interrupt | timer → IRQ → ISR |
| 5 | AES register program | CPU → AES → ciphertext |
| 6 | Network telemetry | packet → Network Engine → IRQ → CPU → telemetry |
| 7 | Complete application | packet → telemetry → CRC → IRQ → CPU → 128-bit record → AES → UART |

**The single highest-value milestone is fw0** — it proves the entire unproven chain in one run:

```text
sw/src/startup.S + sw/src/main.c + sw/linker/veer.ld
        │  riscv64-unknown-elf-gcc -march=rv32imc_zicsr_zifencei -mabi=ilp32
        ▼
firmware.elf ──readelf -h/-A/-S──► assert RV32 / ILP32 / .text@0x0 / .data@0x10000
        │
        ├── objcopy -O ihex ───────────────────────► firmware.ihex  (never simulated)
        └── objcopy -O verilog --verilog-data-width 1 ──► imem.mem / dmem.mem
                     │  (rebased per §6.2)
                     ▼
        TB service: zero-fill → $readmemh(+IMEM_HEX/+DMEM_HEX) → reset
                     ▼
        fetch @0x0 → startup.S → main() → PASS signature → existing monitor
```

`startup.S` order (frozen, D8):

1. Set `sp` to the top of the linker-provided stack symbol (DMEM top, 16-byte aligned).
2. Copy `.data` from LMA (IMEM) to VMA (DMEM). *(Companion §PART I suggested placing `.data` directly at its final address with no copy as the fw0 simplification — permitted, but the copy form is the default: it works even when DMEM is not preloaded.)*
3. Zero `.bss` (the NOBITS rule, §6.2).
4. `call main`.
5. On return (fw0), write the PASS magic to the DMEM mailbox bytes — reusing the existing Phase-2 monitor.

This single run proves: toolchain → linker → image conversion → RTL load → reset → fetch → C runtime → `main()`. Everything else in this specification exists to support it.

This follows the project's layered verification strategy (CPU software validation before end-to-end packet → CPU → AES → UART).

Testbench services (reusable infrastructure): clock/reset, memory-init, image service, UART monitor, GPIO monitor, CPU execution monitor, timeout watchdog, scoreboard, packet generator.

---

# 23. Implementation Checklist

## A. Toolchain

* [x] `/opt/riscv` installed; `riscv64-unknown-elf-gcc` 16.1.0 on PATH
* [x] `objcopy`/`objdump`/`readelf` available
* [x] `objcopy -O verilog` support confirmed
* [x] VCS/Verdi homes identified (not on PATH — env set by `sim/Makefile`)

## B. VeeR configuration

* [x] Supplied RTL = upstream submodule `core/Cores-VeeR-EL2` @ `06ad26aa`
* [x] RV32IMC confirmed; `-march` frozen = `rv32imc_zicsr_zifencei` (D7)
* [x] `-mabi` frozen = `ilp32`
* [x] Bus = AHB-Lite (default_ahb)
* [x] ICCM enabled, 64 KB, `0xEE00_0000`
* [x] DCCM enabled, 64 KB, `0xF004_0000`
* [x] I-cache 16 KB ECC (no preload needed)
* [x] PIC @ `0xF00C_0000`
* [x] Reset vector `0x0000_0000` (p2_soc)
* [x] System memory regions: IMEM `0x0000_0000`/32 KB, DMEM `0x0001_0000`/32 KB
* [x] ECC storage structure = combined 39-bit `ram_core` (Case D — §3.4)
* [x] `dccm_addr_xor` / `iccm_addr_xor` confirmed `= 0` in this snapshot (loader mirrors them if ever non-zero)
* [ ] `lockstep_enable` confirmed (it gates `addr_xor`) — verify per snapshot
* [x] `reset_vec` value recorded alongside the linker entry address (manifest, §17)

## C. Linker script

* [ ] `MEMORY` regions defined (IMEM/DMEM per §4.3)
* [ ] `.text/.rodata → IMEM`; `.data` VMA=DMEM LMA=IMEM; `.bss → DMEM`; stack top
* [ ] `ENTRY(_start) = 0x0000_0000`
* [ ] sizes match RTL; no overlap; overflow asserts; map generated

## D. Firmware

* [ ] `startup.S` (sp, `.data` copy, `.bss` clear, traps)
* [ ] `main.c`, UART/GPIO/Timer/Network/CRC/AES drivers, headers

## E. Makefile

* [ ] frozen compiler/ISA/ABI variables; CFLAGS/LDFLAGS
* [ ] `elf dis ihex mem inspect manifest clean` (sw)
* [ ] `veer-config rtl sim run all clean` (root/sim)
* [ ] VCS env wiring; project-local snapshot paths

## F. ELF validation

* [ ] `make inspect` gate: ELF32/RISC-V/rv32imc+zs/ext/ilp32/entry/section addresses+sizes

## G. Memory images

* [x] Generator chosen: `objcopy -O verilog` (Correction B resolution)
* [ ] `--verilog-data-width` matches the target array word width (= 1 for `ahb_sram`)
* [ ] `@` addresses rebased to each array's index 0; out-of-range `@` checked (§14)
* [ ] endianness/width verified; word spot-check vs `objdump`
* [ ] `.bss` / `NOBITS` zeroed by `startup.S` **and** by loader pre-fill
* [ ] ECC policy recorded in manifest: *unused (Mode 1)* — documented and guarded
* [ ] `.ihex` generated but never consumed by `$readmemh`

## H. SystemVerilog testbench

* [ ] memory-init service (plusargs, validation, logging, failure conditions §14)
* [ ] hierarchical `$readmemh` for IMEM/DMEM (D9); **`+IMEM_HEX` mandatory, `+DMEM_HEX` optional** (§9.1)
* [ ] zero-fill before overlay; no `X` left in unread DMEM locations
* [ ] ICCM/DCCM ECC-clean zero-fill
* [ ] image files validated before reset release; init before reset (§11)
* [ ] Mode-1 guardrails: reject `+ICCM_HEX/+DCCM_HEX`; reject core-local section overlap (§9.3)
* [ ] preserve proven reset/halt/run sequence
* [ ] monitors + watchdog + PASS/FAIL tokens
* [ ] (paired with S7b) `ahb_sram` `initial` removed — no second t=0 initializer exists

## I. Memory initialization (ECC)

* [x] hierarchy identified: `dccm_loop[i].dccm_bank.ram_core`, `iccm_loop[i].iccm_bank.ram_core`
* [x] array name/width: `ram_core`, 39 bits = `{ecc[6:0], data[31:0]}`
* [x] bank mapping + ECC reference implementation available (`slam_*`, `riscv_ecc32`)
* [x] raw `$readmemh` into `ram_core` forbidden (Correction C)
* [ ] backdoor loader implemented and unit-checked against `rvecc_encode`
* [ ] first-instruction-after-reset verified

## J. CPU bring-up

* [ ] reset asserted/released; first fetch @ `0x0000_0000`; `startup.S`; stack; `.data`; `.bss`; `main()`
* [ ] Firmware 0/1/2 PASS

## K. Peripheral bring-up

* [ ] UART/Timer/GPIO/Network/CRC/AES register access; PIC configured; timer/net/AES interrupts

## L. End-to-end

* [ ] packet → Network Engine → CRC → telemetry snapshot → NET IRQ → CPU ISR → timestamp → 128-bit record → AES → AES IRQ → ciphertext → UART

---

# 24. Definition of Done for This Infrastructure

Complete only when this single command works:

```bash
make sim
```

and produces a flow equivalent to:

```text
$ make sim

[TB] SNAPSHOT build/snapshots/p2_soc (default_ahb, reset_vec=0x00000000)
[SW] CC      startup.S
[SW] CC      main.c
[SW] LINK    firmware.elf
[SW] CHECK   ISA=rv32imc_zicsr_zifencei
[SW] CHECK   ABI=ilp32
[SW] CHECK   ENTRY=0x00000000
[SW] IMAGE   imem.mem  dmem.mem  firmware.ihex
[HW] BUILD   VeeR + SoC + TB (VCS)

[TB] IMAGE   +IMEM_HEX=sw/build/imem.mem  +DMEM_HEX=sw/build/dmem.mem
[TB] IMEM    initialized (0x0000_0000..0x0000_7FFF)
[TB] DMEM    initialized (0x0001_0000..0x0001_7FFF)
[TB] ICCM    zero-filled (ECC clean)
[TB] DCCM    zero-filled (ECC clean)
[TB] RESET   asserted -> released

[CPU] BOOT @0x00000000
[CPU] main()

[TB] PASS
```

This is the infrastructure milestone frozen **before implementing the full embedded application**.

---

# 25. Verification Status — Proven vs Not Proven (as of revision 1.5)

```text
PROVEN (log + waveform evidence)
  [x] Toolchain builds: /opt/riscv GCC 16.1.0, Binutils 2.47.20260726
  [x] C → ELF → Intel HEX (generic; toolchain record)
  [x] RV32IMC / ILP32 ELF attributes (expected arch string recorded in §5)
  [x] objcopy -O verilog produces $readmemh-compatible images
  [x] VCS parameter/plusarg experiment (§9.2) — Option R2 dead
  [x] Phase 1: VeeR resets, fetches, executes, AHB transaction, TEST_PASSED
  [x] Phase 2: project fabric + VeeR boots from IMEM @ 0x0 through it, PASS
  [x] Reset-before-init ordering already correct in tb_veer_p2_soc
  [x] ECC storage structure, bank mapping, PRM citations (§3.4, §12.1)

NOT PROVEN (the gap this specification exists to close)
  [ ] A real C program compiled by GCC running on the SoC
  [ ] Linker script matching the p2_soc memory map
  [ ] ELF → imem.mem/dmem.mem → ahb_sram → boot → main()
  [ ] .data placement / .bss clear / stack setup in startup.S
  [ ] Any peripheral driver (UART / Timer / GPIO / NET / CRC / AES)
  [ ] Any interrupt
```

**Critical context:** Phase 1 used VeeR's *canned* `hello_world.hex`; Phase 2 used `scripts/p2_prog_gen.py`, a hand-written Python mini-assembler emitting `p2_prog.hex` directly — **no compiler, no linker, no ELF**. The entire software path specified here has therefore *never been exercised end-to-end on this SoC*. Closing that gap is exactly the fw0 milestone (§22) and the Definition of Done (§24).

---

# Appendix A — Corrections summary (why the draft changed)

1. **`$readmemh`, not `$freadmemh`.** `$fread` is a binary file-handle read (`$fopen` → integer handle → raw bytes); `$readmemh` takes a filename and parses hex text with `@` records. Hex memory images use `$readmemh`.
2. **Intel HEX ≠ `$readmemh` input.** `objcopy -O ihex` output (`:10000000…` records with lengths/checksums/record types) is not consumed by `$readmemh`. The flow is `ELF → objcopy -O verilog → *.mem → $readmemh`; `firmware.ihex` remains a parallel delivery artifact only. The installed binutils **does** support `-O verilog` (and upstream VeeR's own `tools/Makefile:300` already uses it), which resolves the draft's "dedicated conversion utility" placeholder.
3. **ICCM/DCCM ECC is a hardware correctness requirement, not a testbench detail.** Verified: one combined 39-bit `ram_core` row = `{ecc[6:0], data[31:0]}` per bank — **Case D**, not the draft's Case A/B/C (§3.4). Raw `$readmemh` into that array is forbidden: it silently *corrupts* loaded words (bogus single-bit "corrections") rather than failing cleanly (§12.1). Loading goes through a TB backdoor loader that computes SECDED ECC and de-interleaves banks (`bank=addr[3:2]`, `index=addr[15:4]`), mirroring VeeR's proven `slam_*`/`riscv_ecc32` pattern. Zero-fill `39'h0` is the ECC-clean default for un-imaged regions.
4. **Previously "open" configuration items are now verified facts** (Section 3): both ICCM and DCCM are enabled at fixed addresses, reset vector is `0x0000_0000` in the p2_soc snapshot, the system IMEM/DMEM path is proven, and the memory map has no core-local/system-bus conflicts.
5. **Build-flow gaps identified during review:** volatile `/tmp` snapshot dependency, VCS not on PATH, elaboration-time `HEX_FILE` parameters vs runtime plusargs, and global `.gitignore` patterns that would exclude `sw/src/main.c` — all captured in the implementation plan (S5, S6, S7b, S9, S10).
6. **Address rebasing and data width (the correction the draft lacked entirely).** `@` records are array *indices*, not byte addresses; `ahb_sram`'s dense arrays require per-region rebasing, and `--verilog-data-width` must equal the target array's word width in bytes (§6.2/§6.3).
7. **Loading ownership resolved with evidence** — companion amendment H.4's recommended "RTL-owned via plusarg-fed parameter" was tested on this machine and **does not work** (plusargs invisible at elaboration); testbench ownership with removal of `ahb_sram`'s `initial` block is frozen (D9/§9.2).

# Appendix B — Key file reference

| Purpose | Path |
| ------- | ---- |
| VeeR config generator | `core/Cores-VeeR-EL2/configs/veer.config` |
| RAM macro (ECC array) | `core/Cores-VeeR-EL2/design/lib/mem_lib.sv` |
| ECC encode/decode | `core/Cores-VeeR-EL2/design/lib/beh_lib.sv` (`rvecc_encode`:659, `rvecc_decode`:676) |
| Proven backdoor loader | `core/Cores-VeeR-EL2/testbench/tb_top.sv` (`preload_*`:2894/2931, `slam_*`:2974/2999, `get_*_bank`:3085/3098, `riscv_ecc32`:3073) |
| PRM: ECC init requirement | `core/Cores-VeeR-EL2/docs/source/error-protection.md:107/:111` |
| PRM: memory routing (core-local vs bus) | `core/Cores-VeeR-EL2/docs/source/memory-map.md` |
| PRM: build args (ICCM/DCCM/reset_vec) | `core/Cores-VeeR-EL2/docs/source/build-args.md` |
| Memory export interface | `core/Cores-VeeR-EL2/design/lib/el2_mem_if.sv` |
| Project SoC | `rtl/soc_top.sv` (params retired per D9) |
| Project SRAM (dense byte array; `initial` removed per D9) | `rtl/ahb/ahb_sram.sv` |
| Project VeeR TB (RAM instances, PASS monitor) | `tb/tb_veer_p2_soc.sv` |
| P2 flow | `run/p2_full_flow.csh`, `run/p2_veer_soc_run.f` |
| Phase records | `doc/Phase1_VeeR_Bringup_Completion_Record.md`, `doc/Phase2_AHB_Fabric_Completion_Record.md` |
| Toolchain record | `doc/RISC_V_GNU_Toolchain_Setup_and_Validation_Record.md` |
| Companion review (amendments H.1–H.9, first-principles analysis) | `doc/SW_HW_Memory_Image_Architecture_First_Principles_and_Spec_Amendments.md` |

# Appendix C — Relationship to the companion review document

`doc/SW_HW_Memory_Image_Architecture_First_Principles_and_Spec_Amendments.md` is an independent first-principles review of the draft specification. Its amendments were evaluated item-by-item for this revision:

| Amendment | Disposition in this specification |
| --------- | --------------------------------- |
| H.1 — name `objcopy -O verilog` | ✅ adopted (§6.2) |
| H.2 — relabel ECC case as **Case D** | ✅ adopted (§3.4, Appendix A.3) |
| H.3 — rebase + width rules | ✅ adopted (§6.2) |
| H.4 — loading ownership (R vs T) | ⚠️ **overridden**: companion recommended Option R "for Phase 3", but the VCS plusarg-in-parameter experiment (§9.2) shows R cannot deliver runtime image selection; **Option T (TB-owned) frozen** as D9, including the `ahb_sram` `initial`-removal race rationale |
| H.5 — image-contract fields | ✅ adopted (§20) |
| H.6 — hierarchical-access precedent | ✅ adopted (D9, §9.2) |
| H.7 — init timing already satisfied | ✅ adopted (§11) |
| H.8 — fix `MARCH` | ✅ already frozen as D7 |
| H.9 — checklist items | ✅ adopted (§23 B/G/H) |
| §F.6 — Mode-1 escape hatch + guardrails | ✅ adopted as D10 / §9.3 |
| §F.4/§F.7 — silent-corruption analysis, PRM citations, firmware store/fence escape route | ✅ adopted (§12.1, §12.4) |
| §PART I — proven/not-proven ladder, fw0 mailbox trick, startup order | ✅ adopted (§22, §25; direct-`.data`-placement variant noted under D8) |
| §PART A — opencode session meta | ℹ️ not specification content; omitted |
