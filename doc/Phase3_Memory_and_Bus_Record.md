# Phase 3 Record — Memory and AHB Bus Tests

**Project:** RISC-V Network Telemetry SoC
**Phase:** Phase 3 of `doc/Complete_Updated_C_Peripheral_and_Memory_Test_Suite_Plan.md` §6
**Date:** 2026-10-17
**Branch:** `feature/c-peripheral-test-suite`
**Result:** memory suite and bus tests land; the assumed CPU-trap path for an AHB ERROR is **disproven by measurement** and the bus test is redesigned around it.

**Repo rule honoured:** every PASS/FAIL below is quoted from a log produced today,
with the exact command and its exit status.

---

# 1. What was built

| File | State | Purpose |
|---|---|---|
| `sw/include/memtest.h` | new | region geometry, capability flags, failure codes, `memtest_region_safe()` guard |
| `sw/tests/memtest_core.c` | new | one region-parameterised pattern engine (width, walk, address-unique, boundary, retention) shared by IMEM/DMEM/DCCM |
| `sw/tests/t_mem.c` | new | MEM-01..09/11 instantiations + the guard control + MEM-09 region isolation |
| `sw/tests/t_bus.c` | new | BUS-05 unmapped-store test, TB-observed; mapped-address control |
| `sw/tests/test_main.c` | edited | `TEST_SELECT_*` area selection, trap-recovery helpers, always-compiled guard control |
| `sw/src/startup.S` | edited | dual-purpose trap handler (park on unexpected, fixed-label resume on expected), recovery globals in `.bss` |
| `sw/linker/veer.ld` | edited | `__memtest_dmem_scratch_lo/hi`, `__trapdiag`, `__imem_image_end` now covers `.test_list`, Phase-3 safety `ASSERT`s |
| `sw/Makefile` | edited | single-translation-unit build for the area files, `memtest.h` dependency |
| `sw/include/test.h` | edited | `extern results` so a memory test can assert its own table survived |
| `tb/tb_ahb_cycle_monitor.sv` | edited | `+bus_watch`, `+expect_def_addr`, per-address provenance, `BUS_CHECK_RESULT` |
| `tb/tb_veer_p2_soc.sv` | edited | `BUS_CHECK` termination, corrected `TRAPDIAG` read |
| `sim/Makefile` | edited | self-contained `test-memory`, `test-bus`, `test-suite*`, `test-spike-*`, negative controls |

Scope held: **no AES RTL integration, no interrupt wiring.**

---

# 2. The AHB ERROR does not trap — measured, and it changes the design

The plan (§5.3.1) asserted that an AHB ERROR reaches the CPU as an **imprecise
exception**, and that BUS-10 should resume at a fixed label. Phase 0 had
observed an ICCM access "trap and park". That observation was **not** a bus
response error — it was an instruction-access fault from the parked handler.
The distinction matters and is now settled by tracing the RTL.

## 2.1 The only producer of an LSU exception

`el2_lsu_lsc_ctl.sv:210` is the sole source of an LSU exception:

```systemverilog
lsu_error_pkt_m.exc_valid =
    (access_fault_m | misaligned_fault_m | lsu_double_ecc_error_m)
```

A bus **response** error is not in that list.

## 2.2 A response error only feeds a performance counter

The traced path:

| Stage | File | Behaviour |
|---|---|---|
| 1 | `rtl/ahb/ahb_default_slave.sv` | asserts `hresp` for the ERROR cycle |
| 2 | `core/Cores-VeeR-EL2/design/lib/axi4_to_ahb.sv:91` | `input ahb_hresp` |
| 3 | same, `:323`, `:344`, `:365` | `slvbuf_error_in = ahb_hresp_q` |
| 4 | same, `:264`, `:268` | `axi_bresp/axi_rresp = 2'b10` (SLVERR) / `2'b11` (DECERR) |
| 5 | `design/lsu/el2_lsu_bus_buffer.sv:873` | `bus_rsp_read_error = bus_rsp_read & (lsu_axi_rresp != 2'b0)` |
| 6 | same, `:785`, `:827`, `:913` | `buf_error` → `lsu_nonblock_load_data_error` / `lsu_imprecise_error_store_any` |
| 7 | `design/el2_veer.sv:923` | `lsu_pmu_bus_error` |
| 8 | `design/el2_dec_tlu_ctl.sv:2651` | `({1{(mhpme_vec[i][9:0] == MHPME_DBUS_ERROR)}} & {lsu_pmu_bus_error})` |

Stage 8 is a **PMU event hit vector**: it increments a counter. It does not
raise a trap. Arming `mhpme3` with event 46 therefore does **not** help; that
was tried before the path was established.

## 2.3 Consequence

At a given address the two layers the plan assumed are mutually exclusive:

- the CPU issues the access and the fabric returns ERROR — the core **stalls**;
- the access is denied before it is issued (PMP/address check) — the core
  **traps**, but the fabric sees nothing.

Neither gives both. So the bus test is redesigned (§2.4) and the CPU-trap
machinery is retained as the fallback for the one case that *does* trap (a
PMP-denied access), documented in `sw/tests/t_bus.c:9-54`.

## 2.4 What `t_bus.c` does instead

It issues exactly **one unmapped store** to `0x10001000` as the last thing the
firmware does, and lets the core stall. The testbench terminates the run on the
fabric evidence:

- `tb_ahb_cycle_monitor` records every default-slave claim and every `HRESP`,
  and gates the counts against declared expectations (`+expect_def` /
  `+expect_buserr`).
- `+expect_def_addr=10001000` pins **which** address produced them, so a
  correct count from the wrong address fails.
- `+bus_watch` makes the testbench finish on the observed ERROR instead of
  waiting for a mailbox the CPU can never write.

Evidence (`make -C sim test-bus`, exit 0):

```text
[TB] BUS_CHECK: +bus_watch set - will terminate on the observed AHB ERROR
[TB] 672265000 DEFAULT slave claimed: lsu addr=0x10001000 hwrite=1
[672285000] BUS_CHECK: PASS (fabric returned ERROR: addr=0x10001000 def=1 bus_err=1)
[672285000] BUS_CHECK_RESULT: PASS
[SIM] PASS  BUS_CHECK_RESULT: PASS   (fabric returned AHB ERROR at the declared address)
```

The wrong-expectation control (`make -C sim test-bus-wrong-expect`, exit 2)
proves the gate is a real check, not a formality:

```text
[672285000] BUS_CHECK: FAIL (addr=0x10001000 want 0x10001000 addr_ok=1; def=1 want 4; bus_err=1 want 1)
[672285000] BUS_CHECK_RESULT: FAIL
[SIM] FAIL: BUS_CHECK_RESULT is not PASS
```

---

# 3. Memory tests

## 3.1 One engine, three regions

`sw/tests/memtest_core.c` holds the patterns; `t_mem.c` instantiates them for
IMEM, DMEM and DCCM. A pattern runs only if the region's flags permit it, so the
suite never asserts something the RTL was never asked to do.

| Pattern | Purpose |
|---|---|
| width sweep | 8/16/32-bit store+load at a stride; neighbours checked |
| walking ones/zeros | `v <<= 1` over 32 positions |
| address-unique | `addr * 2654435761 ^ addr` per word — catches aliasing/stuck lines |
| boundary | first and last legal element |
| retention | write, unrelated traffic, re-read |

## 3.2 Safety is established from linker symbols, not assumptions

Every window is derived from a symbol `veer.ld` exports, and the linker
`ASSERT`s fail the **link** if the map changes underneath the tests:

```text
DMEM scratch = [ align_up(__bss_end,32) , __stack_top - 4096 )
IMEM scratch = [ __imem_image_end , 0x0000_8000 )
```

`memtest_region_safe()` is the last line of defence before a destructive
pattern runs: a DMEM window must lie **inside** those scratch bounds, and an
IMEM window must start at or above `__imem_image_end`. Comparing against the
bounds (rather than re-deriving each reserved region) is what lets the guard
refuse a window parked just below `__stack_top`, which an earlier version
accepted.

## 3.3 Bounded first

Windows are capped (`MEMTEST_WINDOW_DMEM=512`, `IMEM=256`, `DCCM=512`,
`STRIDE=64`) so the safe ranges and the runtime can be measured before
committing to a full 32/64 KB sweep. The full sweep is deliberately not enabled
in this phase.

## 3.4 Evidence

`make -C sim test-memory` (exit 0):

```text
[TB] AHB_MON_EXPECT min_imem_rd=8 min_dmem_rd=8 min_dmem_wr=8 expect_def=0 expect_buserr=0 max_imem_wr=256
[2468765000] TEST_RESULT: ntests=9 npass=9 nfail=0
[2468765000] P2_TB2_RESULT: PASS (P2 program ran through project fabric)
[TB] AHB_RW_MONITOR: PASS (mailbox reached; thresholds imem_rd>=8 dmem_rd>=8 dmem_wr>=8 bus_err==0 def==0 imem_wr<=256)
[2488765000] UART_CHECK_RESULT: PASS
```

Transcript:

```text
SUITE_BEGIN
T0 t_selftest PASS
T1 t_bss_is_zero PASS
T2 t_dmem_roundtrip PASS
T3 t_uart_status PASS
T4 t_mem_guard_refuses_unsafe PASS
T5 t_mem_dmem PASS
T6 t_mem_imem PASS
T7 t_mem_dccm PASS
T8 t_mem_isolation PASS
SUITE_END ntests=9 npass=9 nfail=0 first_fail=4294967295 code=0 got=0x00000000 want=0x00000000
```

MEM-11 (DCCM) is unblocked by Phase 0 and is a real test here; MEM-10 (ICCM)
stays **BLOCKED — RTL/ARCH** and is asserted as an error, not a memory region.

---

# 4. Negative controls

Three, each proving a different thing.

## 4.1 Suite assertion machinery — `test-suite-negative` (exit 2)

```text
[2543795000] TEST_RESULT: ntests=10 npass=9 nfail=1
[2543795000] P2_TB2_RESULT: FAIL (bad DMEM contents 00 00 00 00 00 00)
[2563795000] UART_CHECK_RESULT: PASS
```

`T4 t_negative_control FAIL` with `got=0x00000001 want=0x00000002` — the exact
operand pair of the deliberate `CHECK_EQ(1u, 2u)`. `UART_CHECK_RESULT: PASS` is
correct here: it answers "does the serial report agree with DMEM?", and it does,
faithfully reporting the failure.

## 4.2 UART gate — `test-suite-uart-corrupt` (exit 2)

`+uart_corrupt` rewrites the first captured byte. The monitor tokens still PASS
(the firmware ran fine); only the serial evidence is wrong:

```text
[TB] AHB_RW_MONITOR: PASS (mailbox reached; ... imem_wr<=256)
[2488765000] UART_CHECK_RESULT: FAIL
[SIM] PASS  P2_TB2_RESULT: PASS
[SIM] PASS  AHB_RW_MONITOR: PASS
```

## 4.3 The safety guard — `test-memory-negative` (exit 0, deliberate FAIL)

This is the control for the control. The image is built with
`-DMEMTEST_GUARD_BROKEN`, which makes `memtest_region_safe()` accept every
window, so the guard test's "must refuse" assertions **must** fail:

```text
[2427715000] TEST_RESULT: ntests=9 npass=8 nfail=1
[2427715000] P2_TB2_RESULT: FAIL (bad DMEM contents 00 00 00 00 00 00)
[SIM] PASS  deliberate P2_TB2_RESULT: FAIL observed (NEG_FAIL=1)
```

```text
T4 t_mem_guard_refuses_unsafe FAIL
SUITE_END ntests=9 npass=8 nfail=1 first_fail=4 code=1 got=0x00000001 want=0x00000000
```

The same test in the normal image **passes** (§3.4), so the guard is verified
in both directions: it refuses an unsafe window, and the test detects a guard
that has been loosened. An earlier version of this target passed for the wrong
reason — see §5.1.

---

# 5. Bugs found and fixed during this phase

## 5.1 The guard did not refuse a window parked just below `__stack_top`

`memtest_region_safe()` checked `hi > __stack_top`, so a window ending exactly
at the stack top was accepted even though the stack grows down through it. The
negative control therefore "failed" because of a real guard bug, not because of
a deliberate flaw — a false positive that hid the defect.

Fixed by requiring the DMEM window to lie inside the linker-declared scratch
bounds (`__memtest_dmem_scratch_lo/hi`), which exclude the stack margin. The
normal image now passes the guard test (§3.4) and the broken-guard image fails
it (§4.3).

## 5.2 `saved_sp` was defined twice and emitted into the instruction stream

`bus_test_resume` in `startup.S` contained a `.globl saved_sp` / `.word 0`
block **between** two instructions. Two problems:

1. `test_main.c` already defined `uint32_t saved_sp;`, so the suite link failed
   with `multiple definition of 'saved_sp'`.
2. The `.word 0` was in the executed instruction stream. Had the resume path
   ever run, the CPU would have decoded `0x00000000` as an instruction.

Fixed by moving `trap_expect`, `saved_ra` and `saved_sp` to a `.bss` block in
`startup.S`, declared `extern` in `test_main.c`. They live in `.bss` rather
than in a C file because `startup.S` references them unconditionally and must
therefore link into **every** variant (fw0, probes, suite).

## 5.3 `test-suite` targets were not self-contained

`test-suite`, `test-suite-negative`, `test-suite-uart-corrupt`, the spike
targets, and the Phase-3 variants expected a pre-built image. They now build
their own, and each variant `rm -rf`s its build directory first: a change to
`EXTRA_CFLAGS` does not invalidate make's timestamp dependencies, and a stale
object silently ignored the window bounds, producing a run that timed out.

## 5.4 The spike targets probed ICCM first and parked

`test-spike-dccm` built `probes/spike.c` without `-DSPIKE_ONLY_DCCM`. The
default image probes ICCM first, which faults and parks, so the DCCM readback
was never published and the run timed out. The Phase 0 record built it with
`-DSPIKE_ONLY_DCCM`; the target had lost that. Fixed, and both spikes now
build with the correct region macro.

## 5.5 `TRAPDIAG` read the wrong DMEM bytes

The testbench read `trap_expect` and `resumed_ok` from bytes `0x10..0x17`, which
is the `.results` header (`magic`/`ntests`), and printed those as trap state.
Those globals are ordinary `.bss` symbols whose addresses depend on the layout,
so the TB cannot read them by index. The `TRAPDIAG` line now prints only
`entries`, which is the linker-fixed `__trapdiag` at `0x0001_000C` and is read
correctly.

## 5.6 `test-suite-negative` and `test-suite-uart-corrupt` used `max_imem_wr=0`

The memory tests legitimately write IMEM scratch (bounded by the linker), so the
monitor must be told `MAX_IMEM_WR=256`. Without it the monitor expected zero IMEM
writes and the gate failed on a correct run.

---

# 6. fw0 baseline

The trap machinery added three `.bss` words and instructions to `startup.S`, so
the fw0 figures moved. **Deterministic** across repeated runs.

| | pre-Phase-3 (Phase 2) | **Phase 3 (current)** | Δ |
|---|---|---|---|
| `imem_rd` | 2417 | **2383** | −34 |
| `dmem_rd` | 382 | **382** | 0 |
| `dmem_wr` | 164 | **167** | +3 |
| `def` / `bus_err` | 0 / 0 | 0 / 0 | 0 |

`dmem_wr` +3 is the three extra `.bss` words the startup clear loop now writes.
`imem_rd` moved because the `.text` layout shifted. `dmem_rd` is unchanged, so
the `.data` copy loop is untouched. This supersedes the Phase 2 figures; both
baselines must not be conflated.

---

# 7. Regression — Phase 0 spikes

```text
# DCCM
[6365000] MBOX[8..15] spike fields : iccm_rb=00000000 dccm_rb=5a5a5678
[6365000] P2_TB2_RESULT: PASS (P2 program ran through project fabric)
[TB] AHB_RW_MONITOR: PASS (thresholds imem_rd>=8 dmem_rd>=8 dmem_wr>=8 bus_err==0 def==0)

# ICCM — unreachable, as Phase 0 established
[TB] AHB_RW_MONITOR: PASS (watchdog timeout; thresholds imem_rd>=8 dmem_rd=1 dmem_wr=1 bus_err==2 def==1)
[16000000000] P2_TB2_RESULT: TIMEOUT FAIL
```

Build gates: `make -C sw inspect` and the suite-variant inspect both report
**10 gates PASS** (G1–G7, G11, G14, G15).

---

# 8. Not done in this phase

- **Full memory sweeps.** Windows are bounded (§3.3); the simulation-time and
  FSDB controls from plan §7 must land before enabling them.
- **AES RTL integration** — no RTL touched; `AES_BASE` stays documented as not
  decoded.
- **Interrupt wiring** — plan §5.10 remains **BLOCKED — RTL**.
- **Phase 4 UART tests** — carried forward.

---

# 9. Definition of done — Phase 3 items

- [x] Memory patterns pass for IMEM, DMEM and DCCM (MEM-11) with bounded windows.
- [x] IMEM/DMEM safety bounds enforced by linker `ASSERT`s **and** a runtime guard.
- [x] Unmapped-address test handles the expected ERROR without hanging (redesigned around the no-trap finding).
- [x] `tb_ahb_cycle_monitor` carries expected-error counts and address provenance, and reports an unexpected count as a failure.
- [x] Every PASS has a reproducible log; the three negative controls prove the gates can fail.
- [ ] Full-region sweeps (blocked on §8).
