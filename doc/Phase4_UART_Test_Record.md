# Phase 4 Record — C-Driven UART Tests

**Project:** RISC-V Network Telemetry SoC  
**Phase:** Phase 4 of `doc/Complete_Updated_C_Peripheral_and_Memory_Test_Suite_Plan.md` §5.4  
**Date:** 2026-10-17  
**Branch:** `feature/c-peripheral-test-suite`  
**Result:** all 10 UART test cases pass through the integrated VeeR path; UART transcript and DMEM table cross-check agree; corruption negative control rejects a bad transcript.

**Repo rule honoured:** every PASS/FAIL below is quoted from a log produced today, with the exact command and its exit status.

---

# 1. What was built

| File | State | Purpose |
|---|---|---|
| `sw/tests/t_uart.c` | new | UART-01..10 C test cases exercising the UART through the real SoC path |
| `sw/tests/test_main.c` | edited | Added `TEST_SELECT_UART` to the area-selection `#ifdef` chain |
| `sw/Makefile` | edited | Added `t_uart.c` as a compile dependency for test objects |
| `sim/Makefile` | edited | Added `test-uart` and `test-uart-corrupt` targets, `.PHONY` entries, help text |

No AES integration. No interrupt wiring. No RTL changes.

---

# 2. Test cases

| ID | Test | What it verifies |
|---|---|---|
| UART-01 | `t_uart_lsr_idle` | LSR reports THRE+TEMT at idle; DATA_READY is clear |
| UART-02 | `t_uart_single_byte` | Single-byte TX via `uart_putc`; THRE poll succeeds |
| UART-03 | `t_uart_fixed_string` | Multi-byte string TX; TB decodes byte order |
| UART-04 | `t_uart_thre_poll` | THRE polling with bounded timeout; poll returns after TX |
| UART-05 | `t_uart_temt_completion` | TEMT asserts after `uart_drain()`; shift register drained |
| UART-06 | `t_uart_back_to_back` | Back-to-back bytes without intermediate drain |
| UART-07 | `t_uart_fifo_stress` | 48 bytes (1.5× FIFO depth 32) — forces THRE throttling |
| UART-08 | `t_uart_baud_config` | Re-init (DLAB→BAUD=8→DLAB clear) is idempotent; TX works after |
| UART-09 | `t_uart_wrapper_reads` | IER/BAUD/LCR reads return 0 (wrapper bypass); LSR is served (nonzero) |
| UART-10 | `t_uart_tx_no_side_effects` | No unexpected LSR error bits after TX; DATA_READY stays clear |

UART-11 (RX) is **BLOCKED**: `soc_top` ties `uart_rx_i` to `1'b1`, so no RX test is possible.

---

# 3. Acceptance evidence

## 3.1 `make -C sim test-uart` — PASS, exit 0

```text
[2301775000] TEST_RESULT: ntests=14 npass=14 nfail=0
[2301775000] P2_TB2_RESULT: PASS (P2 program ran through project fabric)
[TB] AHB_CYCLES imem_rd=60333 imem_wr=0 dmem_rd=7140 dmem_wr=6448
[TB] AHB_CYCLES uart_rd=582 uart_wr=571 def=0 bus_err=0 ifu_offtarget=0
[TB] AHB_RW_MONITOR: PASS (mailbox reached; thresholds imem_rd>=8 dmem_rd>=8 dmem_wr>=8 bus_err==0 def==0 imem_wr<=0)
[TB] UART_CHECK: parsed ntests=14 npass=14 nfail=0 first_fail=-1 code=0 got=0x00000000 want=0x00000000
[TB] UART_CHECK: PASS (565 byte transcript, 14 test lines, UART agrees with DMEM)
[2321775000] UART_CHECK_RESULT: PASS
[SIM] PASS  P2_TB2_RESULT: PASS
[SIM] PASS  AHB_RW_MONITOR: PASS
```

Transcript (verbatim from the log):

```text
SUITE_BEGIN
T0 t_selftest PASS
T1 t_bss_is_zero PASS
T2 t_dmem_roundtrip PASS
T3 t_uart_status PASS
T4 t_uart_lsr_idle PASS
AB
T5 t_uart_single_byte PASS
UARTTEST
T6 t_uart_fixed_string PASS
X
T7 t_uart_thre_poll PASS
Z
T8 t_uart_temt_completion PASS
BACK2BACK
T9 t_uart_back_to_back PASS
012345678901234567890123456789012345678901234567
T10 t_uart_fifo_stress PASS
BAUDOK
T11 t_uart_baud_config PASS
T12 t_uart_wrapper_reads PASS
Q
T13 t_uart_tx_no_side_effects PASS
SUITE_END ntests=14 npass=14 nfail=0 first_fail=4294967295 code=0 got=0x00000000 want=0x00000000
```

The data bytes emitted by each test (AB, UARTTEST, X, Z, BACK2BACK, digits, BAUDOK, Q) appear on their own transcript lines, separated from the test report lines by trailing newlines. The testbench parser counts 14 test lines and 14 PASS lines, matching the DMEM table.

## 3.2 `make -C sim test-uart-corrupt` — FAIL, exit 2

```text
[TB] UART_CHECK: +uart_corrupt set - byte 0 will be corrupted
[TB] UART_CHECK: FAIL - missing SUITE_BEGIN (captured 565 bytes)
[TB] UART_CHECK: FAIL (1 condition(s), 565 byte transcript)
[2321775000] UART_CHECK_RESULT: FAIL
[SIM] FAIL: UART_CHECK_RESULT is not PASS
MAKE_EXIT=2
```

A single corrupted byte is caught. The monitor tokens still PASS (the firmware ran fine); only the serial evidence is wrong.

---

# 4. Design notes

## 4.1 Transcript line separation

Tests that emit data bytes (UART-02, 04, 05, 10) append a trailing `\n` after the data so the bytes form their own transcript line. Without this, the data merges with the test report line the runner emits next (e.g. `ABT5 t_uart_single_byte PASS\n`), and the testbench parser does not recognise it as a test line because it does not start with `T`.

Tests that emit strings already ending in `\n` (UART-03, 06, 08) do not need an additional newline. UART-07 (FIFO stress) appends `\n` after the digit sequence.

## 4.2 What is not tested

- **UART-11 (RX):** `soc_top` ties `uart_rx_i` to `1'b1`, so no start edge is possible. RX testing is blocked until a real RX port is exposed.
- **Interrupt delivery:** `uart_irq` is connected at the `soc_top` pin but not routed to the VeeR PIC (plan §5.10). UART-10 verifies the firmware-visible side (no unexpected LSR bits after TX). The TB-level pin observation is the existing `uart_irq` wire, which stays low for the TX-only build.

## 4.3 Simulation cost

Per-character cost is ~3.4 µs (dominated by the AHB→AXI round trip for each LSR poll, not the line rate). The 14-test UART suite runs in ~2.3 ms of simulation time with `BAUD=8`, well within the 15 ms watchdog.

---

# 5. Regression — fw0 and other targets unchanged

The fw0 baseline is byte-identical to Phase 3 (no source files affecting fw0 were changed). All other regression targets (test-suite, test-memory, test-bus, test-suite-negative, test-memory-negative, test-bus-wrong-expect, test-suite-uart-corrupt, test-spike-dccm, test-spike-iccm) were re-run after the Phase 4 changes and produce the same results.

---

# 6. Definition of done — Phase 4 items

- [x] UART C-driven tests pass through the integrated VeeR path (14/14 PASS).
- [x] UART transcript and DMEM result table agree (UART_CHECK_RESULT: PASS).
- [x] UART corruption negative control rejects a bad transcript (exit 2).
- [x] The pre-existing Python-generated UART E2E regression (`p3_uart_flow.csh`) is not affected (no RTL changes).
- [x] No gate was weakened to make a test pass.
- [ ] UART-11 (RX) — BLOCKED: `uart_rx_i` tied high in `soc_top`.
- [ ] Interrupt delivery — BLOCKED — RTL: no IRQ path to VeeR PIC.
