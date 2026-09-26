# fw0 C Toolchain — Build and Gate Record

| Field | Value |
| ----- | ----- |
| Phase | fw0 — "C on silicon" (spec §22 milestone 0) |
| Branch | `feature/sw-build-ahb-rw` |
| Steps covered | Plan **Step 1** (write the C file) and **Step 2** (Makefile + hex) |
| Spec | `doc/RISC_V_SW_Build_and_Simulation_Image_Architecture_Specification.md` rev 1.5, steps `S1`/`S2`/`S3`/`S4`, verification levels **L1–L4** |
| Plan | `doc/Firmware_Build_and_AHB_RW_Verification_Plan.md` §3, §4 |
| Date | 2026-09-26 |
| Status | **G1–G12 PASS. G13 pending Step 3a (sim time).** |

> **Scope note.** This record covers the firmware build flow only. No RTL was
> modified and no simulation was run. Step 3a (AHB cycle monitor + Verdi) is
> recorded separately once executed.

---

## 1. What was delivered

| File | Lines | Purpose |
| ---- | ----- | ------- |
| `sw/linker/veer.ld` | 127 | Memory map, `.data` LMA/VMA split, linker guardrail `ASSERT`s |
| `sw/src/startup.S` | 113 | Reset / C-runtime bring-up + Phase-2 PASS signature |
| `sw/src/main.c` | 100 | fw0 memory-probe `main()` with distinct fail ids |
| `sw/src/lib.c` | 87 | Freestanding `memcpy`/`memset`/`memmove`/`memcmp`/`strlen`/`strcpy` |
| `sw/include/soc.h` | 45 | Board BSP: map, mailbox contract, MMIO accessors |
| `sw/Makefile` | 311 | Frozen flags (§8.2 + A1), image rules, gates G1–G12 |
| `.gitignore` | +14 | `*.mem`, `*.ihex`, `*.dis`, `sw/build/`, `build/`, `sim/run/`, `manifest.txt` |

Zero existing files were modified except `.gitignore`. RTL, `run/`, and
`tb/tb_veer_p2_soc.sv` are untouched.

---

## 2. Frozen decisions applied

| ID | Decision | Where |
| ---- | -------- | ----- |
| **D7** | `-march=rv32imc_zicsr_zifencei -mabi=ilp32` | `sw/Makefile:81-82` |
| **D8** | `startup.S` order: sp → mtvec → `.data` copy → `.bss` clear → `main()` → mailbox → park | `sw/src/startup.S` |
| **D9** | Testbench owns image loading (not exercised yet — Step 3a) | — |
| **D11** | Split `imem.mem` + `dmem.mem`, each `@` rebased to its own array index 0 | `sw/Makefile` image rules |
| **A1** | `LDFLAGS` adds `-nostdlib` (see §5) | `sw/Makefile:96` |

### 2.1 Linker map (as built)

```
IMEM  0x0000_0000 .. 0x0000_7FFF   32 KB   code + rodata + .data LMA
MBOX  0x0001_0000 .. 0x0001_000F   16 B    Phase-2 PASS mailbox (reserved, no section)
DMEM  0x0001_0010 .. 0x0001_7FFF          .data VMA + .bss + stack
__stack_top = 0x0001_8000
```

The `MBOX` region exists so `.data` cannot land on the mailbox bytes. Without
it, `startup.S` would overwrite a live `.data` variable when writing the
signature — a silent landmine rather than a link error.

### 2.2 Observed section layout

```
  [ 1] .text    PROGBITS  00000000 001000 00025a 00  AX
  [ 2] .rodata  PROGBITS  0000025c 00125c 000040 00   A
  [ 3] .data    PROGBITS  00010010 002010 000004 00  WA
  [ 4] .bss     NOBITS    00010014 002014 000080 00  WA
  text=666  data=4  bss=128  dec=798
```

Symbols: `_start=0x00000000`, `main=0x0000010a`, `__data_load=0x0000029c`,
`__data_start=0x00010010`, `__bss_start=0x00010014`, `__bss_end=0x00010094`,
`__stack_top=0x00018000`.

---

## 3. Reproduce

```bash
cd sw
make clean && make all      # elf + mem + manifest (runs G8, G9, G10, G12)
make inspect                # runs G1-G7, G11
make dis                    # build/firmware.dis
```

---

## 4. Gate results (plan §4.2)

| Gate | Level | Assertion | Observed | Result |
| ---- | ----- | --------- | -------- | ------ |
| **G1** | L1 | `make elf` exits 0 → `firmware.elf` exists | `12312` bytes | ✅ |
| **G2** | L1 | frozen `-march` / `-mabi` echoed | `rv32imc_zicsr_zifencei` / `ilp32` | ✅ |
| **G3** | L2 | `readelf -h`: `ELF32`, `RISC-V` | `Class: ELF32`, `Machine: RISC-V` | ✅ |
| **G4** | L2 | exact arch string | `rv32i2p1_m2p0_c2p0_zicsr2p0_zifencei2p0_zmmul1p0_zca1p0` | ✅ |
| **G5** | L3 | `e_entry == _start == 0x00000000`, `__stack_top == 0x00018000` | both confirmed by `nm -n` | ✅ |
| **G6** | L3 | sections in `0x0000_xxxx`/`0x0001_xxxx`, none at `0xEE…`/`0xF004…` | `.text/.rodata` ≤ `0x0000029c`; `.data/.bss` at `0x00010010…0x00010094`; no symbol address begins `ee`/`f0` | ✅ |
| **G7** | L3 | link under `-nostdlib`, no `.dynamic`, no undefined symbols | `There is no dynamic section in this file.` + `nm -u` empty | ✅ |
| **G8** | L4 | all three images exist and are non-empty | `imem.mem 2040 B`, `dmem.mem 22 B`, `firmware.ihex 1912 B` | ✅ |
| **G9** | L4 | `imem.mem` first `@00000000`; every `@ < 0x8000` | imem `@00000000`(3 records), dmem `@00000010`(1 record) | ✅ |
| **G10** | L4 | byte-per-token, LF, never Intel HEX | 670 / 4 hex byte tokens, no `:10…` records, no CR | ✅ |
| **G11** | L4 | `objdump` first instruction == head of `imem.mem` | `00018117` == `17 81 01 00` | ✅ |
| **G12** | L4 | manifest with `Init mode: Mode 1`, `addr_xor: iccm=0 dccm=0` | both present | ✅ |
| **G13** | — | `firmware.ihex` never copied to the sim dir | gated inside `make sim`; `PASS no *.ihex in build/sim/fw0` — **2026-09-26** | ✅ |

Full console logs: `make -C sw all` + `make -C sw inspect`.

---

## 5. Two defects found while building the images

Both were caught by gates rather than by inspection. Both are now regressions
the flow guards against.

### 5.1 `dmem.mem` was emitted at a negative array index

**Symptom.**

```console
$ objcopy -O verilog --verilog-data-width 1 --only-section=.data \
      --change-addresses=-0x00010000 firmware.elf dmem.mem
$ cat dmem.mem
@FFFFFFFFFFFF029C
EE FF C0 00
```

**Root cause.** `objcopy -O verilog` emits `@` records from the section
**LMA**, not its VMA. `.data` has `VMA = 0x00010010` but `LMA = 0x0000029C`
(it lives in IMEM). So the shift computes `0x29C - 0x10000`, which wraps to a
64-bit negative value — an index far outside the 32 KB dense array, which
`$readmemh` would either reject or silently mis-place.

**Why the spec §6.2 command is still right for `imem.mem`.** There the LMA is
the physically correct location: the `.data` load bytes really do sit at
`0x0000029C` in IMEM, and `startup.S` copies from exactly there. Only the
DMEM overlay needs the VMA.

**Fix.** Override the LMA outright instead of shifting:

```bash
vma=$(nm firmware.elf | awk '$3=="__data_start"{print "0x" $1}')
off=$(( vma - 0x00010000 ))                 # 0x00000010
objcopy -O verilog --verilog-data-width 1 --only-section=.data \
    --change-section-lma .data=0x00000010 firmware.elf dmem.mem
```

`--change-section-lma` is applied **after** `--change-addresses`, so the two
options cannot be composed — verified directly: combining them yields
`@00010010`, still un-rebased.

**Result:** `dmem.mem` now starts `@00000010`, i.e. `.data` at DMEM array
index `0x00010010 - 0x00010000 = 0x10`, as D11 requires.

**Guard:** gate **G9** now fails on any `@` record ≥ `0x8000` or matching
`@-`/`@F{8,}`.

### 5.2 `objcopy -O verilog` writes CRLF line endings

**Symptom.** A `16#`/`0x` arithmetic parse inside the gate recipe failed with
`syntax error: invalid arithmetic operator (error token is "00000000")`.
Instrumenting showed `idx` was nine characters, not eight:

```console
$ od -c build/imem.mem | head -1
0000000   @   0   0   0   0   0   0   0   0  \r  \n   1   7  ...
```

**Why it matters beyond the gate.** IEEE 1800 §21.7 defines `$readmemh`
whitespace as *{space, tab, newline, formfeed, comment}*. `\r` is not in that
set, so a strict reader can fold the CR into a hex token and mis-parse the
first word of the image. `binutils` `verilog.c` terminates every record with
`\r\n`.

**Fix.** Both image rules post-process with `sed -i 's/\r$//'`, and gate
**G10** asserts no CR remains.

---

## 6. Amendment A1 — refined

The plan originally stated that spec §8.2's `-nostartfiles`-only `LDFLAGS`
"aborts on ELFCLASS mismatch". **That is only half true**, and the record
should say so precisely.

`-nostartfiles` still passes `-lgcc`/`-lc`, but both are *archives*: the linker
pulls a member only when a symbol is referenced. So a pure 32-bit program with
no libc calls links today:

```console
$ riscv64-unknown-elf-gcc -march=rv32imc_zicsr_zifencei -mabi=ilp32 \
      -nostartfiles -T linker/veer.ld startup.o main.o lib.o -o fw.elf
$ echo $?
0                      # links fine without -nostdlib
```

The failure appears only once a libgcc helper is actually needed:

```console
$ riscv64-unknown-elf-gcc ... -nostartfiles needlgcc.o -o neg2.elf     # 64-bit divide
ld: /opt/riscv/lib/gcc/riscv64-unknown-elf/16.1.0/libgcc.a(div.o):
     ABI is incompatible with that of the selected emulation:
     target emulation `elf64-littleriscv' does not match `elf32-littleriscv'
ld: .../libgcc.a(div.o): file class ELFCLASS64 incompatible with ELFCLASS32
ld: final link failed: file in wrong format
```

with `-nostdlib` the same case gives an actionable error instead:

```console
ld: needlgcc.c:(.text+0x6): undefined reference to `__udivdi3'
```

**Conclusion (A1 stands, narrowed).** Keep `-nostdlib` in the frozen
`LDFLAGS`. It costs nothing for fw0 and converts a confusing archive-arch
mismatch — which would first appear at some later milestone when the firmware
grows a 64-bit operation — into a loud, correctly-attributed link error at the
offending source line. **Never add `-lgcc`.**

Confirmed environment facts:

```console
$ ls /opt/riscv/riscv64-unknown-elf/lib/rv32imc_zicsr_zifencei/ilp32/
ls: cannot access '...': No such file or directory     # no rv32 multilib
$ readelf -h /opt/riscv/lib/gcc/riscv64-unknown-elf/16.1.0/libgcc.a | grep Class
  Class: ELF64
```

Toolchain: `riscv64-unknown-elf-gcc (GCC) 16.1.0` at `/opt/riscv/bin`.

---

## 7. Design notes worth keeping

### 7.1 Why `data_marker` must not be `const`

The first build produced `size=0` for `.data` — every gate still passed,
`imem.mem`/`dmem.mem` looked fine, and the startup copy loop degenerated to
nothing because `__data_start == __data_end`. The cause: `const volatile
uint32_t data_marker` is `.rodata`, so the `.data` → `.bss` proof was
vacuous. Making it non-`const` restored a 4-byte `.data` and a real copy.

`main.c` now probes **both**: `ro_probe[]` in `.rodata` (IMEM fetch) and
`data_marker` in `.data` (LMA → VMA relocation), with `return 1` / `return 6`
distinguishing the failures.

### 7.2 Mailbox write ordering

`tb/tb_veer_p2_soc.sv:300` samples `u_dmem.mem[2] === 8'hFF` as the trigger.
`startup.S` therefore writes `[0]`, `[1]`, `[4..7]` **first** and `[2]=0xFF`
**last**, so the monitor can never observe a half-formed signature. On a
non-zero `main()` return it writes `[0]=0x00` (invalidating the magic) before
the trigger, so the monitor reports **FAIL** rather than the testbench
stalling to its watchdog. The fail id is stashed in `[3]`.

The signature `mem[4..7] = 0x00003250` is the frozen Phase-2 contract, not a
test result — it is written unconditionally on the PASS path.

### 7.3 `-fno-tree-loop-distribute-patterns` on `lib.c` only

GCC can recognise the `memset`/`memcpy` loop bodies and rewrite them into calls
to themselves — infinite recursion that only shows up at `-O2` and in a
character that looks like a hang. `lib.c` is compiled with the flag; the flag
is deliberately *not* applied globally so the rest of the firmware keeps
default optimisation behaviour.

### 7.4 `wfi` then spin

`startup.S` parks with `wfi` followed by `j .` — `wfi` keeps the core idle
without burning AHB bandwidth once fw0 has finished, and the spin guarantees
progress on a core with interrupts disabled.

---

## 8. Not covered here — resolved by Step 3a

| Item | Then | Now |
| ---- | ---- | --- |
| G13 (`firmware.ihex` never reaches the sim dir) | needed a simulation run | ✅ **gated inside `make sim`**, see §4 |
| TB plusarg image loading (`D9`, `S7`/`S7b`/`S8`) | deferred to Step 3a | ⏳ **still deferred** — a filename stand-in (`cp imem.mem p2_prog.hex`) is used instead, because `S7b` would remove `rtl/ahb/ahb_sram.sv`'s `initial` and break the parallel session's committed Phase-3 flow. Recorded as **D9-deferred** in `Firmware_Build_and_AHB_RW_Verification_Plan.md` §5.1 and the Step-3a record §3.4 |
| AHB read/write-cycle monitor + Verdi checklist | Step 3a | ✅ `tb/tb_ahb_cycle_monitor.sv` + plan §5.3 all 8 rows — `Firmware_Build_and_AHB_RW_Verification_Record.md` |
| Root `Makefile`, `sim/Makefile`, `build/snapshots/p2_soc` (`D6`) | Step 3a build wiring | ✅ delivered |
| `README.md` status/index rows | left untouched — file carries an unrelated in-flight edit from a parallel session | still open |

---

## 9. Definition of done — Steps 1 & 2

- [x] `sw/` tree exists with linker, `startup.S`, C source, headers
- [x] `make -C sw clean && make -C sw elf` exits 0
- [x] `make -C sw mem` produces `imem.mem`, `dmem.mem`, `firmware.ihex`
- [x] Gates G1–G12 pass and are printed by the Makefile itself
- [x] Gate labels match plan §4.2 exactly (G1–G13)
- [x] Two image-generation defects found, fixed, and regression-guarded
- [x] Amendment A1 evidence recorded
- [x] **G13 — now PASS** (2026-09-26): gated inside `make sim`; see §4 and
      `Firmware_Build_and_AHB_RW_Verification_Record.md` §5.4

**Gates G1–G13: all PASS. Step 2 is complete.**
