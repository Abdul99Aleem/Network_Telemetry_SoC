# Phase 1 Record — C Test Framework

**Project:** RISC-V Network Telemetry SoC
**Phase:** Phase 1 of `doc/Complete_Updated_C_Peripheral_and_Memory_Test_Suite_Plan.md` §4
**Date:** 2026-10-17
**Branch:** `feature/c-peripheral-test-suite`
**Result:** framework lands green; suite PASSES; negative control FAILS as designed; fw0 regression preserved.

**Repo rule honoured:** every claim below is quoted from a log produced today.

---

# 1. What was built

| File | State | Purpose |
|---|---|---|
| `sw/include/test.h` | new | `test_case_t`, `TEST_CASE()` registry macro, result-table layout, `CHECK_EQ` / `CHECK_TRUE` / `CHECK_POLL` |
| `sw/tests/test_main.c` | new | runner: walks `.test_list`, runs each case, fills the result table |
| `sw/linker/veer.ld` | edited | `.results` (NOLOAD, DMEM) and `.test_list` (IMEM) output sections; `__imem_image_end`; five new guardrail `ASSERT`s |
| `sw/src/startup.S` | edited | MRAC prologue as **step 0**; steps 1–7 and the mailbox byte contract untouched |
| `sw/Makefile` | edited | per-tree source selection, `EXTRA_CFLAGS`, gates **G14** and **G15**, G8/G9/G11 fixes |
| `sw/include/soc.h` | edited | ICCM/DCCM bases with measured accessibility; AES_BASE corrected to the canonical spelling |
| `sim/Makefile` | edited | `test-suite`, `test-suite-negative` targets |
| `tb/tb_veer_p2_soc.sv` | edited | `dump_test_results()` task; raw-header fallback |

Scope held: **no AES RTL integration, no interrupt wiring.**

---

# 2. Evidence — the suite PASSES

`make -C sim test-suite`:

```text
[39125000] TEST_RESULT: ntests=3 npass=3 nfail=0
[39125000] TEST_RESULT: first_fail idx=4294967295 code=0 got=0 want=0
[39125000] TEST_CASE[0] name_ptr=0x00000514 code=0
[39125000] TEST_CASE[1] name_ptr=0x00000520 code=0
[39125000] TEST_CASE[2] name_ptr=0x00000530 code=0
[39125000] P2_TB2_RESULT: PASS (P2 program ran through project fabric)
[TB] AHB_CYCLES imem_rd=1037 imem_wr=0 dmem_rd=135 dmem_wr=95
[TB] AHB_RW_MONITOR: PASS (mailbox reached; thresholds imem_rd>=8 dmem_rd>=8 dmem_wr>=8 bus_err==0 def==0)
[SIM] PASS  P2_TB2_RESULT: PASS
[SIM] PASS  AHB_RW_MONITOR: PASS
[SIM] PASS  no *.ihex
[SIM] DONE
```

`first_fail idx=4294967295` is the `TEST_NO_FAIL` sentinel — nothing failed.
Three cases registered purely by `TEST_CASE()`, with the runner unchanged.

## 2.1 Negative control FAILS correctly

Same image plus `-DTEST_NEGATIVE_CONTROL`:

```text
[52765000] TEST_RESULT: ntests=4 npass=3 nfail=1
[52765000] TEST_RESULT: first_fail idx=3 code=1 got=1 want=2
[52765000] TEST_CASE[3] name_ptr=0x00000578 code=1
[52765000] P2_TB2_RESULT: FAIL (bad DMEM contents 00 00 00 00 00 00)
[SIM] FAIL: no 'P2_TB2_RESULT: PASS'
```

The failing case is correctly attributed to index 3, `CHECK_EQ` returned code 1,
and `got=1 want=2` are the exact operands of the deliberate mismatch. The
process exits nonzero.

---

# 3. Bug found and fixed during bring-up

Two real bugs, both caught because the results table is machine-checkable.

## 3.1 `.test_list` was absent from the image

`imem.mem` is built with a frozen `--only-section` list. `.test_list` is a
separate output section, so it was **not** in the image: the suite ELF placed it
at `0x056c..0x0584` while the image stopped at `0x056a`. Every `tc_*.name` and
`tc_*.fn` would have read as zero in hardware and the first `TEST_CASE` call
would have jumped to NULL.

Fixed by adding `--only-section=.test_list`, and **gate G9 now proves it**: it
compares the byte tokens after the `.test_list` `@` record against the section
size. It reported `FAIL G9: .test_list is not fully present in imem.mem` before
the fix and `.test_list at 0000056c, 24 bytes, image holds 24` after.

Note the gate had to be written gap-agnostically: `.text` ends at `0x506` but
`.rodata` starts at `0x508`, and `objcopy` omits the 2-byte alignment gap, so
token count is not the highest address.

## 3.2 An all-green suite reported FAIL

The runner recorded `entries[i].code` only on failure. A passing case kept the
`ENTRY_NOT_RUN` sentinel, which the recount then counted as a failure — so
`npass=0 nfail=3` and the suite returned FAIL with every test actually passing.

Fixed by recording the outcome for **every** case, pass or fail. The recount now
also treats a still-sentinel entry as a failure rather than silently
under-reporting.

## 3.3 Two gate defects fixed (same class as Phase 0's G5)

| Gate | Was | Problem | Fix |
|---|---|---|---|
| **G5** | `grep "^00018000 B __stack_top"` | matched nm's section letter; an empty `.bss` makes ld report `D` | pin the address, which is the real contract |
| **G11** | compared a 4-byte image word against objdump's first instruction | `-march=..._c` emits 16-bit compressed instructions, so `li t0,8` at `_start+0` is 2 bytes and a correct image failed | derive instruction width from the objdump token, compare that many bytes, and lowercase the image word |

G11 failed for real on the first Phase 1 build — the MRAC prologue made
`_start` begin with a compressed `li`.

## 3.4 G8 over-constrained the suite

G8 required `dmem.mem` non-empty. The suite image legitimately has no `.data`
(mutable state is in `.bss` and the NOLOAD `.results` block), so `dmem.mem` is
empty — correct, not a defect. Requiring it would have pushed a fake `.data`
symbol into every test file just to satisfy a gate.

G8 now requires `dmem.mem` if and only if the ELF has a non-empty `.data`.
Negative control, emptying fw0's `dmem.mem`:

```text
[SW] FAIL G8: .data is 0x4 bytes but dmem.mem is empty
```

and restoring it returns `PASS G8`. Also note the field-index trap: `readelf -SW`
prints `[ 3] .data`, so `$2==".data"` never matches — the section size is located
by scanning for the name field instead.

## 3.5 TB indexed DMEM by absolute address

`ahb_sram.mem` is `SIZE_BYTES` deep and `BASE_ADDR` is unused
(`ahb_sram.sv:43`), so the array is indexed by **offset from base**. Reading the
result table with absolute address `0x0001_0010` indexed element 65552 of a
32768-element array — out of bounds, returning `X`:

```text
[36955000] TEST_RAW[0x10010] = xxxxxxxx   (all eight words X)
```

Fixed to `RESULTS_BASE - DMEM_BASE == 0x10`. The `TEST_RAW` fallback was kept so
"magic missing" stays diagnosable from the log instead of being a dead end.

## 3.6 Pre-existing: the documented `make` entry point was broken

`make` at the repo root failed with `No rule to make target 'firmware'` — the
root Makefile delegates `firmware` to `sw/Makefile`, which only ever defined
`elf`. **Reproduced on a clean HEAD with `git stash -u` before Phase 1 changed
anything**, so this predates this work. Added `firmware: elf` as an alias; the
full flow now completes with `[ROOT] fw0 flow complete`.

---

# 4. Build variants

`MAIN_SRC` selects the source set, so variants never disturb each other:

| Command | Sources compiled |
|---|---|
| `make -C sw …` | `src/main.c` + `src/lib.c` (fw0, unchanged) |
| `… MAIN_SRC=tests/test_main.c` | `tests/test_main.c` + `src/lib.c` |
| `… MAIN_SRC=probes/spike.c` | `probes/spike.c` + `src/lib.c` |

`sw/probes/` is **never globbed**, so a probe is only built when named
explicitly — this is what stopped `spike.c` leaking into the fw0 image.

---

# 5. Gates

**fw0 (default) — all green:**

```text
[SW] PASS G1  [SW] PASS G2  [SW] PASS G3  [SW] PASS G4
[SW] PASS G5  [SW] PASS G6  [SW] PASS G7  [SW] PASS G11
[SW]     objdump word  : 42a1 (16-bit instruction)
[SW] PASS G14
[SW]     __imem_image_end = 000002ac (684)
[SW]     >= 4 KB of IMEM remains below the 32 KB ceiling for test scratch
[SW] PASS G15
[SW] PASS G8  [SW] PASS G9  [SW] PASS G10  [SW] PASS G12
```

**Suite variant — all green**, with `dmem.mem` correctly reported as
`empty by design (.data size 0)` and G9 reporting
`.test_list at 0000056c, 24 bytes, image holds 24`.

- **G14** — `nm -u` on the **linked ELF** must be empty. Checking objects was
  wrong: they legitimately show undefined `__bss_start`, `__data_load`, `main`
  etc., which the linker resolves.
- **G15** — `__imem_image_end` must leave ≥ 4 KB of IMEM for test scratch.

---

# 6. Linker guardrails added

```ld
ASSERT(SIZEOF(.results) == 0 ||
       (__results_start == 0x00010010 && __results_end <= 0x00018000), ...)
ASSERT((28 + 64 * 8) <= 0x00007F00, ...)
ASSERT(SIZEOF(.test_list) == 0 || __test_list_end <= 0x00008000, ...)
ASSERT(__imem_image_end + 0x1000 <= 0x00008000, ...)
```

Two things worth knowing for future edits:

1. All are guarded on `SIZEOF(...) == 0` because **fw0 links neither section**,
   and an empty output section leaves its boundary symbols undefined — `ld`
   resolves those to 0 and a bare comparison trips.
2. `ld` cannot see C macros, so the `28 + 64 * 8` reservation size is repeated
   as a literal and must be changed in step with `sw/include/test.h`.
3. GNU `ld` does **not** concatenate adjacent string literals in an `ASSERT`
   message; a wrapped message is a syntax error.

Verified layout:

```text
[ 3] .data       PROGBITS 00010010 001584 000000 00  WA     (0 bytes)
[ 4] .results    NOBITS   00010010 002010 000220 00  WA     (544 = 32 + 64*8)
[ 5] .test_list  PROGBITS 0000056c 00156c 000018 00   A     (24 = 3 * 8)
[ 6] .bss        NOBITS   00010230 002230 000020 00  WA
```

`__test_list_end - __test_list_start == 0x18 == 24`, and `__results_start ==
0x00010010` exactly.

---

# 7. Regression — fw0

```text
[90685000] MBOX[8..15] spike fields : iccm_rb=00000000 dccm_rb=00000000
[90685000] TEST_RESULT: none (no .results table in this image)
[90685000] P2_TB2_RESULT: PASS (P2 program ran through project fabric)
[TB] AHB_CYCLES imem_rd=2417 imem_wr=0 dmem_rd=382 dmem_wr=164
[TB] AHB_CYCLES uart_rd=0 uart_wr=0 def=0 bus_err=0 ifu_offtarget=0
[TB] AHB_RW_MONITOR: PASS (mailbox reached; thresholds imem_rd>=8 dmem_rd>=16 dmem_wr>=16 bus_err==0 def==0)
[SIM] PASS  P2_TB2_RESULT: PASS
[SIM] PASS  AHB_RW_MONITOR: PASS
[SIM] PASS  no *.ihex
[SIM] DONE
```

`TEST_RESULT: none` is the expected line for a non-suite image: fw0 has no
`.results` block, so magic reads 0 and the dump returns after one line.

## 7.1 The activity counts changed, and why

| | pre-Phase-1 | Phase 1 | Δ |
|---|---|---|---|
| `imem_rd` | 2393 | **2417** | +24 |
| `dmem_rd` | 366 | **382** | +16 |
| `dmem_wr` | 164 | **164** | 0 |
| `def` / `bus_err` | 0 / 0 | 0 / 0 | 0 |
| finish time | 90,915,000 ns | 90,685,000 ns | −230,000 |

Caused by the three-instruction MRAC prologue in `startup.S` (fetch and pipeline
cost). `dmem_wr` is unchanged, so the `.data`/`.bss` copy loops are untouched,
and `def=0 bus_err=0` still hold. fw0 performs no MMIO, so the `csrw` is inert
for it.

Verified **deterministic** — repeated `test-fw0` runs give identical counts.

`doc/SoC_Phase_Status_Audit.md` §3 carried the old figures as a quoted baseline;
a correction block has been added there pointing here.

The startup mailbox contract is unchanged: `mem[0]=0x50`, `mem[1]=0x32`,
`mem[2]=0xFF` written last, `mem[3]` fail code, `mem[4..7]=0x00003250`. The TB
check at `tb_veer_p2_soc.sv` was not modified, and `P2_TB2_RESULT: PASS` still
fires from it.

## 7.2 DCCM probe still green

```text
[5535000] MBOX[8..15] spike fields : iccm_rb=00000000 dccm_rb=5a5a5678
[5535000] P2_TB2_RESULT: PASS
[TB] AHB_RW_MONITOR: PASS (thresholds imem_rd>=8 dmem_rd>=8 dmem_wr>=8 bus_err==0 def==0)
```

---

# 8. Not done in this phase

Deliberately out of scope, per instruction:

- **AES RTL integration.** `AES_BASE` in `soc.h` is corrected to the canonical
  spelling and documented as *not decoded on the AHB fabric*. No RTL touched.
- **Interrupt wiring.** §5.10 stays **BLOCKED — RTL**; `soc_top` still has no
  interrupt input.

Carried into Phase 2: the UART `putc` driver, per-test UART lines, the
`MRAC`-dependent polling that this prologue now enables, and the timeout/`
+wave` controls.

Carried into Phase 3: `memtest_core.c` instantiated for IMEM, DMEM and DCCM
(MEM-11). MEM-10/ICCM stays **BLOCKED — RTL/ARCH** per Phase 0.

## 8.1 One correction to earlier work

Phase 0's record and this plan previously described the `soc.h` `AES_BASE` value
as a stale transcription of `0x1000_4000`. That was wrong: `0x10004000` and
`0x1000_4000` are the **same value** with different underscore grouping, not two
addresses. The value was always correct; only the comment was misleading.