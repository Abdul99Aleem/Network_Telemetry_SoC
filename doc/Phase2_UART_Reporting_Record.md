# Phase 2 Record — UART Reporting and Testbench Plumbing

**Project:** RISC-V Network Telemetry SoC
**Phase:** Phase 2 of `doc/Complete_Updated_C_Peripheral_and_Memory_Test_Suite_Plan.md` §5
**Date:** 2026-10-17
**Branch:** `feature/c-peripheral-test-suite`
**Result:** all acceptance criteria met; fw0 baseline bit-identical to the post-MRAC revision.

**Repo rule honoured:** every PASS/FAIL below is quoted from a log produced today,
with the exact command and its exit status.

---

# 1. What was built

| File | State | Purpose |
|---|---|---|
| `sw/include/uart.h` | new | register map, LCR/LSR bits, `UART_REG32`, `BAUD = 8`, poll bound |
| `sw/src/uart.c` | new | `uart_init`, `uart_putc/puts/puthex32/putdec`, `uart_drain`, sticky error flag |
| `sw/tests/test_main.c` | edited | per-test `Tn <name> PASS/FAIL` lines, `SUITE_BEGIN`/`SUITE_END` summary, `uart_drain()` before return, new `t_uart_status` case |
| `tb/tb_veer_p2_soc.sv` | edited | `uart_tx_o`/`uart_irq_o` connected, self-calibrating receiver, transcript parser, UART↔DMEM cross-check, `+wave` FSDB gate, `+uart_corrupt`, raised timeouts |
| `sim/Makefile` | edited | `TB_PLUSARGS`, `+expect_uart` gate, `test-suite-uart-corrupt` target, honest FSDB message |

No AES integration. No interrupt wiring.

---

# 2. UART contract, as verified

**Register map** — from `rtl/uart/uart_axi_slave.v:141-149`:

| Reg | Off | Behaviour |
|---|---|---|
| THR/RBR | `0x00` | write TX byte (DLAB=0) |
| IER | `0x04` | writes served; **reads bypassed to 0** |
| BAUD | `0x08` | writes served (DLAB=1); **reads bypassed to 0** |
| LCR | `0x0C` | writes served; **reads bypassed to 0** |
| LSR | `0x14` | bit 0 DATA_READY, 5 THRE, 6 TEMT — served both ways |

The driver **never reads IER/LCR/BAUD**. `uart_axi_slave.v:153-156` forwards only
offsets whose `addr[4:2]` is `0` or `5` to the IP, so every other read completes
locally with `32'h0000_0000`. A read of LCR returning 0 does not mean the write
failed, and asserting otherwise would encode a wrapper quirk as a contract.

**Divisor latching quirk honoured.** `axi_uart_top.v:502` does
`uart_baudrate_div_int_d = baudrate_divisor_int` in `AckWriteState`, so a BAUD
written while DLAB=1 goes live on the *next* AXI write. `uart_init()` therefore
always follows the BAUD write with the LCR write that clears DLAB:

```
LCR = 0x83 (DLAB=1, 8N1) -> BAUD = 8 -> LCR = 0x03 (DLAB=0, divisor now live)
```

## 2.1 No contract discrepancy found — one display artefact resolved

The first run appeared to show `bit period = 90000 ns` for divisor 8, 1000× the
naive `(8+1) × 10 ns`, which would have been a real RTL discrepancy.

It was a **formatting artefact, not a hardware discrepancy**. With
`` `timescale 1ns / 1ps ``, `%0t` renders a `time` value in picoseconds while the
arithmetic is in nanoseconds, so the same 90 ns printed as `90000`. The
testbench already printed a third figure, `bit_period / 10 = 9 clk`, which was
correct all along; the two fields simply disagreed by the unit scale.

Resolved by printing the value both ways, permanently, so it is auditable:

```text
[12855000 ns] UART MONITOR: calibrated bit period = 90000 ns (90 ns, 9 clk)
```

**90 ns per bit is exactly `(8 + 1) × 10 ns`** — divisor 8 takes effect precisely
as the RTL intends. No RTL change was made and no check was weakened.

## 2.2 Where the simulation time actually goes

Per-character cost is ~3.4 µs, not the 900 ns a byte occupies on the wire. The
dominant term is the AHB→AXI round trip for each LSR poll: 198 characters ×
~3.4 µs ≈ 673 µs against an observed run of 806 µs. Amortising the poll across
the 32-deep TX FIFO would cut this substantially; it is left as a Phase 4
consideration because it is a performance change, and Phase 2 already fits its
budget with ~20× headroom.

---

# 3. Transcript format

```
SUITE_BEGIN
T0 t_selftest PASS
T1 t_bss_is_zero PASS
T2 t_dmem_roundtrip PASS
T3 t_uart_status PASS
SUITE_END ntests=4 npass=4 nfail=0 first_fail=4294967295 code=0 got=0x00000000 want=0x00000000
```

`SUITE_BEGIN` deliberately starts with `'S'` = `0x53`, which has bit0 set. The
reused calibration from `tb_veer_uart_soc.sv:311-319` measures the bit period by
timing the rising edge one bit period after the start bit's falling edge, which
is only valid when bit0 is 1. Changing that first character would break the
calibration, so it is documented at both ends.

The testbench **parses** the transcript rather than string-comparing it against a
golden copy, and cross-checks every field against the DMEM table. That is what
makes "UART and DMEM agree" a checked claim.

---

# 4. Acceptance evidence

## 4.1 `make -C sim test-suite` — PASS, exit 0

```text
[TB] FSDB: disabled (pass +wave to enable)
[TB] UART_MONITOR: calibrated bit period = 90000 ns (90 ns, 9 clk)
[785945000] TEST_RESULT: ntests=4 npass=4 nfail=0
[785945000] TEST_RESULT: first_fail idx=4294967295 code=0 got=0 want=0
[785945000] P2_TB2_RESULT: PASS (P2 program ran through project fabric)
[TB] AHB_CYCLES imem_rd=20880 imem_wr=0 dmem_rd=2945 dmem_wr=2276
[TB] AHB_CYCLES uart_rd=199 uart_wr=198 def=0 bus_err=0 ifu_offtarget=0
[TB] AHB_RW_MONITOR: PASS (mailbox reached; thresholds imem_rd>=8 dmem_rd>=8 dmem_wr>=8 bus_err==0 def==0)
[TB] UART_CHECK: parsed ntests=4 npass=4 nfail=0 first_fail=-1 code=0 got=0x00000000 want=0x00000000
[TB] UART_CHECK: PASS (195 byte transcript, 4 test lines, UART agrees with DMEM)
[805945000] UART_CHECK_RESULT: PASS
[SIM] PASS  P2_TB2_RESULT: PASS
[SIM] PASS  AHB_RW_MONITOR: PASS
[SIM] DONE
```

Transcript, verbatim from the log:

```text
[TB] UART_TRANSCRIPT_BEGIN
SUITE_BEGIN[TB] |
T0 t_selftest PASS[TB] |
T1 t_bss_is_zero PASS[TB] |
T2 t_dmem_roundtrip PASS[TB] |
T3 t_uart_status PASS[TB] |
SUITE_END ntests=4 npass=4 nfail=0 first_fail=4294967295 code=0 got=0x00000000 want=0x00000000[TB] |
[TB] UART_TRANSCRIPT_END
```

## 4.2 `make -C sim test-suite-negative` — FAIL, exit 2

```text
T0 t_selftest PASS[TB] |
T1 t_bss_is_zero PASS[TB] |
T2 t_dmem_roundtrip PASS[TB] |
T3 t_uart_status PASS[TB] |
T4 t_negative_control FAIL[TB] |
SUITE_END ntests=5 npass=4 nfail=1 first_fail=4 code=1 got=0x00000001 want=0x00000002[TB] |
```

```text
[850705000] TEST_RESULT: ntests=5 npass=4 nfail=1
[850705000] TEST_RESULT: first_fail idx=4 code=1 got=1 want=2
[850705000] P2_TB2_RESULT: FAIL (bad DMEM contents 00 00 00 00 00 00)
[TB] UART_CHECK: parsed ntests=5 npass=4 nfail=1 first_fail=4 code=1 got=0x00000001 want=0x00000002
[TB] UART_CHECK: PASS (213 byte transcript, 5 test lines, UART agrees with DMEM)
[SIM] FAIL: no 'P2_TB2_RESULT: PASS'
MAKE_EXIT=2
```

`MAKE_EXIT=2`, nonzero. The transcript names the failing test, and
`got=0x00000001 want=0x00000002` is the exact operand pair of the deliberate
`CHECK_EQ(1u, 2u)`.

**Why `UART_CHECK_RESULT: PASS` on a failing run is correct:** that gate answers
"does the serial report agree with the DMEM table?" — and it does, faithfully
reporting the failure. The suite verdict comes from `P2_TB2_RESULT`, which
correctly reports FAIL. Separating the two is the point: a UART that *hid* a
failure would show `UART_CHECK_RESULT: FAIL`, which is what §4.4 demonstrates.

## 4.3 `make -C sim test-fw0` — PASS, both tokens, exit 0

```text
[TB] FSDB: disabled (pass +wave to enable)
[90685000] TEST_RESULT: none (no .results table in this image)
[90685000] P2_TB2_RESULT: PASS (P2 program ran through project fabric)
[TB] AHB_CYCLES imem_rd=2417 imem_wr=0 dmem_rd=382 dmem_wr=164
[TB] AHB_CYCLES uart_rd=0 uart_wr=0 def=0 bus_err=0 ifu_offtarget=0
[TB] AHB_RW_MONITOR: PASS (mailbox reached; thresholds imem_rd>=8 dmem_rd>=16 dmem_wr>=16 bus_err==0 def==0)
[110685000] UART_CHECK_RESULT: SKIP (+expect_uart not set)
[SIM] PASS  P2_TB2_RESULT: PASS
[SIM] PASS  AHB_RW_MONITOR: PASS
[SIM] PASS  no *.ihex
```

`uart_rd=0 uart_wr=0` confirms fw0 still performs no peripheral access.

## 4.4 Wrong UART payload — the gate rejects it, exit 2

```text
make -C sim test-suite-uart-corrupt      (TB_PLUSARGS="+expect_uart +uart_corrupt")
```

```text
[TB] UART_CHECK: +uart_corrupt set - byte 0 will be corrupted
[13620000 ns] UART RX[0] = 0x00 '.'
[785945000] P2_TB2_RESULT: PASS (P2 program ran through project fabric)
[TB] UART_CHECK: FAIL - missing SUITE_BEGIN (captured 195 bytes)
[TB] UART_CHECK: FAIL (1 condition(s), 195 byte transcript)
[805945000] UART_CHECK_RESULT: FAIL
[SIM] FAIL: UART_CHECK_RESULT is not PASS
MAKE_EXIT=2
```

A single corrupted byte out of 195 is caught. The monitor tokens still PASS —
correctly, because the firmware ran fine; only the serial evidence was wrong.

## 4.5 FSDB is opt-in

| Command | Log | Artifact |
|---|---|---|
| `make -C sim test-fw0` | `[TB] FSDB: disabled (pass +wave to enable)` / `[SIM] FSDB none` | **no `.fsdb`** |
| `make -C sim run … TB_PLUSARGS="+expect_uart +wave"` | `[TB] FSDB: enabled (+wave) -> p2_veer_soc.fsdb` | `.fsdb`, 2,021,144 bytes |

The non-`+wave` path also *removes* any stale FSDB, so an old waveform can never
be mistaken for the current run's.

## 4.6 Monitor still rejects insufficient activity and unexpected errors

```text
# insufficient activity: min 999999 vs actual dmem_rd=2945
[TB] AHB_CYCLES imem_rd=20880 imem_wr=0 dmem_rd=2945 dmem_wr=2276
[TB]   FAIL reason: dmem_rd=2945 < 999999
[TB] AHB_RW_MONITOR: FAIL (mailbox reached, 1 condition(s))
[SIM] FAIL: no 'AHB_RW_MONITOR: PASS'
MAKE_EXIT=2
```

```text
# ICCM probe with its declared expectations -> PASS
[TB] AHB_RW_MONITOR: PASS (watchdog timeout; thresholds imem_rd>=8 dmem_rd>=1 dmem_wr>=1 bus_err==2 def==1)

# same image, expecting zero errors while def=1 bus_err=2 -> FAIL on both
[TB]   FAIL reason: bus_err=2 != expected 0 (HRESP asserted 2 time(s))
[TB]   FAIL reason: def=1 != expected 0 (1 transfer(s) hit the default ERROR slave)
[TB] AHB_RW_MONITOR: FAIL (watchdog timeout, 2 condition(s))
```

Neither the activity minima nor the error expectations were relaxed. The ICCM
probe exits 2 in both cases because `P2_TB2_RESULT: TIMEOUT FAIL` is correct —
ICCM really is unreachable (Phase 0).

## 4.7 Build gates and root flow

```text
make -C sw inspect                                          -> 10 gates PASS
make -C sw BUILD=build/suite MAIN_SRC=tests/test_main.c inspect -> 10 gates PASS
make                                                       -> [ROOT] fw0 flow complete — both tokens gated in 'make sim'
```

## 4.8 DCCM probe regression

```text
[5535000] MBOX[8..15] spike fields : iccm_rb=00000000 dccm_rb=5a5a5678
[5535000] P2_TB2_RESULT: PASS
[TB] AHB_RW_MONITOR: PASS (thresholds imem_rd>=8 dmem_rd>=8 dmem_wr>=8 bus_err==0 def==0)
[SIM] PASS  no *.ihex
```

---

# 5. fw0 baseline — unchanged within this revision

| | pre-MRAC (audit §3) | **post-MRAC (current)** |
|---|---|---|
| `imem_rd` | 2393 | **2417** |
| `dmem_rd` | 366 | **382** |
| `dmem_wr` | 164 | **164** |
| `def` / `bus_err` | 0 / 0 | 0 / 0 |
| finish | 90,915,000 ns | 90,685,000 ns |

**These are two different baselines and must not be conflated.** The shift
happened when Phase 1 added the three-instruction MRAC prologue to `startup.S`;
it is that prologue's fetch and pipeline cost. `dmem_wr` is unchanged, proving
the `.data`/`.bss` copy loops are untouched.

**Phase 2 did not move these figures at all.** Repeating `test-fw0` after every
Phase 2 change gives identical `imem_rd=2417 dmem_rd=382 dmem_wr=164`, finish
90,685,000 ns. The fw0 ELF layout is also byte-identical to Phase 1:

```text
[ 3] .data   PROGBITS 00010010 001584 000004 00  WA
[ 6] .bss     NOBITS   00010014 002014 000080 00  WA
000002ac A __imem_image_end
00010094 B __bss_end
```

`sw/src/uart.c` lives in the `src/` tree and is therefore compiled for fw0, but
`--gc-sections` discards it entirely because fw0 references none of it — hence
`__imem_image_end` is still 684 and `.bss` still 128 bytes.

---

# 6. Two testbench parser bugs found and fixed

Both were caught by the gate itself failing on a *correct* run, which is the
point of having a gate.

1. **`find_kv` required a preceding newline.** The summary line is
   space-separated (`npass=`, `nfail=`, `first_fail=`, `got=`, `want=`), so every
   key after the first returned `-1`, and `scan_dec(-1)` then indexed
   `rx_bytes[-1]` out of bounds and returned 0. The log showed a convincing but
   entirely fictional `ntests=4 npass=0 nfail=0 first_fail=0`. Fixed to an
   unanchored substring search, with an explicit `from < 0` guard in `scan_dec`.

2. **PASS-line detection compared the whole line against `" PASS\n"`.** A real
   line is `T0 t_selftest PASS\n` (18 bytes), so it could never match, and every
   run reported "0 PASS line(s)". Fixed to compare only the trailing 6 bytes.

A third, cosmetic issue was fixed at the same time: `%0t` prints in picoseconds
while arithmetic is in nanoseconds, which made the calibration look 1000× off.

---

# 7. Not in this phase

- **AES RTL integration** — `AES_BASE` stays documented as *not decoded on the
  AHB fabric*. No RTL touched.
- **Interrupt wiring** — §5.10 remains **BLOCKED — RTL**; `uart_irq` is now
  connected at the `soc_top` pin but is still not routed to the VeeR PIC, so no
  software can observe it.

Carried forward to Phase 3: `memtest_core.c` for IMEM, DMEM and DCCM (MEM-11);
MEM-10/ICCM stays **BLOCKED — RTL/ARCH**.

Carried to Phase 4: FIFO-batch the THRE poll to cut per-character simulation
cost; full UART register coverage (UART-01..11), including asserting the
IER/LCR/BAUD zero-read as *expected* wrapper behaviour; RX remains untestable
while `soc_top` ties `uart_rx_i` high.