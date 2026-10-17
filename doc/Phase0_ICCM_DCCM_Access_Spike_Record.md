# Phase 0 Record — ICCM / DCCM Access Spike

**Project:** RISC-V Network Telemetry SoC
**Phase:** Phase 0 of `doc/Complete_Updated_C_Peripheral_and_Memory_Test_Suite_Plan.md` §3
**Date:** 2026-10-17
**Branch:** `feature/c-peripheral-test-suite`
**Result:** **DCCM reachable from C. ICCM NOT reachable from C data access.**

**Repo rule honoured:** every PASS/FAIL below is quoted from a simulation log
produced today, and the fw0 regression is re-verified after the change.

---

# 1. The question

Phase 0 exists to answer one thing: can user-mode C reach the two VeeR core-local
memories?

| Region | Base | Size | Config |
|---|---|---|---|
| ICCM | `0xEE00_0000` | 64 KB | `RV_ICCM_ENABLE 1`, `RV_ICCM_SADR 32'hee000000`, 4 banks |
| DCCM | `0xF004_0000` | 64 KB | `RV_DCCM_ENABLE 1`, `RV_DCCM_SADR 32'hf0040000`, 4 banks |

(`build/snapshots/p2_soc/common_defines.vh:133-145, 71-89`)

This was open because the frozen initial firmware architecture deliberately
leaves both unused, and the linker script actively forbids sections from landing
in those ranges (`sw/linker/veer.ld:98-127`).

---

# 2. Method

Probe: `sw/src/spike.c`, built into its own build dir so the proven fw0
artifacts are untouched.

```bash
# one region per run — a faulting access traps and startup.S parks forever
make -C sw BUILD=build/spike_dccm MAIN_SRC=src/spike.c \
     EXTRA_CFLAGS=-DSPIKE_ONLY_DCCM all
make -C sim rtl
make -C sim run SW_BUILD=$PWD/sw/build/spike_dccm
```

The probe writes a distinct pattern to word 0, reads it back, and publishes the
raw readback to `DMEM[8..11]` (ICCM) and `DMEM[12..15]` (DCCM) — bytes inside the
16-byte mailbox reservation that neither the frozen `startup.S` contract nor
`tb/tb_veer_p2_soc.sv:302-307` touches. Both regions are probed
**write-then-read only**, because the TB's `ram_4096x39` banks have no reset
value.

No PMP or MRAC programming is done, and none is needed:

- PMP defaults to allow-all — `pmp_entries=16` but every entry resets `OFF`, so
  no entry matches and `access_fault_check` leaves `access_fail=0`
  (`el2_pmp.sv:167-178`).
- `MRAC` governs external bus regions, not the core-local memories.

---

# 3. Results

## 3.1 DCCM — REACHABLE

```text
[5535000] MBOX[8..15] spike fields : iccm_rb=00000000 dccm_rb=5a5a5678
[5535000] P2_TB2_RESULT: PASS (P2 program ran through project fabric)
[TB] AHB_CYCLES imem_rd=143 imem_wr=0 dmem_rd=9 dmem_wr=14
[TB] AHB_CYCLES uart_rd=0 uart_wr=0 def=0 bus_err=0 ifu_offtarget=0
```

`dccm_rb=5a5a5678` is the exact value written (`PROBE_DCCM = 0x5A5A5678`).
Critically, `def=0` and `bus_err=0`: the access **never touched the AHB fabric**,
so it was served by the internal core-local DCCM.

## 3.2 ICCM — NOT REACHABLE

```text
[TB] 3355000 DEFAULT slave claimed: lsu addr=0xee000000 hwrite=1
[TB] 3365000 AHB_BUS_ERROR: ic_hresp=0 lsu_hresp=1 addr=ic:0x000000c8 lsu:0xee000000
[TB] 3375000 AHB_BUS_ERROR: ic_hresp=0 lsu_hresp=1 addr=ic:0x000000c8 lsu:0xee000000
[TB] AHB_CYCLES imem_rd=87 imem_wr=0 dmem_rd=4 dmem_wr=7
[TB] AHB_CYCLES uart_rd=0 uart_wr=0 def=1 bus_err=2 ifu_offtarget=0
[TB] AHB_RW_MONITOR: FAIL (watchdog timeout, 4 condition(s))
[2000000000] MBOX[8..15] spike fields : iccm_rb=00000000 dccm_rb=00000000
[2000000000] P2_TB2_RESULT: TIMEOUT FAIL
```

The C store to `0xEE00_0000` went **out of the external LSU AHB port**
(`lsu addr=0xee000000`), matched no slave, and was claimed by
`ahb_default_slave` (`def=1`, `bus_err=2`). The read-back then faulted too. The
CPU took the bus exception and `startup.S:trap_handler` parked forever, so the
run ended in the TB watchdog (`iccm_rb` was never published, because the store
faulted before the publish statement executed).

---

# 4. Root cause

Not a permission problem — a **routing** problem, and it is architectural in
this core version:

| | Serving module | Driven by | C data access |
|---|---|---|---|
| ICCM | `el2_ifu_iccm_mem` (`design/ifu/`, instantiated at `el2_mem.sv:166`) | **IFU** — `iccm_rw_addr`, `iccm_wren`, `iccm_rden` are outputs of `el2_ifu` (`el2_ifu.sv:149-152`, `iccm_wren` commented "ICCM write enable (through the DMA)") | **no route** |
| DCCM | `el2_lsu_dccm_mem` (`design/lsu/`) | **LSU** | works |

The ICCM is an instruction/DMA-side memory. A compiler-generated load or store
has no path to it, so the address falls through to the external bus and errors.
This matches the empirical result exactly, and it is why no amount of PMP/MRAC
configuration would change the outcome.

---

# 5. Consequences for the plan

1. **Phase 3 scope narrows.** `t_dcm.c` proceeds as designed (DCCM, 64 KB,
   write-before-read). **`t_iccm.c` is dropped** — there is nothing to test, and
   the correct steady-state assertion is the opposite of a memory test: a C
   access to `0xEE00_0000` must be documented as routing to the ERROR slave.
2. **MEM-10 (ICCM) becomes BLOCKED — RTL/ARCH**, not merely conditional.
   MEM-11 (DCCM) is unblocked and becomes a real test.
3. **Decision D1 is validated as necessary**, twice over:
   - the ICCM run failed on `def != 0` / `bus_err != 0`;
   - the DCCM run passed `P2_TB2_RESULT: PASS` but failed
     `AHB_RW_MONITOR` on the *minimum* thresholds (`dmem_rd=9 < 16`,
     `dmem_wr=14 < 16`) purely because a short probe image makes fewer DMEM
     accesses than fw0.

   So the monitor needs expected counts for the error counters **and** per-variant
   minimums for the activity counters. Both are in scope for decision D1.
4. **The imprecise-exception finding (§5.3.1) is confirmed empirically.** The
   ICCM run trapped and parked exactly as predicted, which is why the flag-guarded
   trap handler is required before BUS-05/06/07.

---

# 6. Incidental findings

## 6.1 Gate G5 was over-specified (fixed)

G5 asserted `nm` shows `00018000 B __stack_top`, matching the section-type letter.
With an **empty `.bss`** — which the probe image has — GNU ld drops the zero-size
section and attributes the symbol to `.data`, reporting `D`:

```text
fw0   : 00018000 B __stack_top
spike : 00018000 D __stack_top
```

The address is identical and `__data_size` stays `4`, so this was never a
correctness issue — only the reported letter. G5 now pins the **address** (which
is the real contract, and is already enforced by the link-time
`ASSERT(__stack_top == 0x00018000)` at `veer.ld:108`) and no longer matches the
letter. Any future `.bss`-less test image would otherwise have failed a gate it
did not violate.

## 6.2 The TB now dumps spike fields on timeout

`tb/tb_veer_p2_soc.sv` prints `MBOX[8..15] spike fields` in **both** the mailbox
monitor and the timeout path. Without the timeout dump, values published before a
fault are lost from the log — which is exactly what happened on the first ICCM
attempt, before the probe was split per region.

---

# 7. Regression — fw0 unchanged

Re-run after every change, on the default `sw/build` image:

```text
[90915000] MBOX[8..15] spike fields : iccm_rb=00000000 dccm_rb=00000000
[90915000] P2_TB2_RESULT: PASS (P2 program ran through project fabric)
[TB] AHB_CYCLES imem_rd=2393 imem_wr=0 dmem_rd=366 dmem_wr=164
[TB] AHB_CYCLES uart_rd=0 uart_wr=0 def=0 bus_err=0 ifu_offtarget=0
[TB] AHB_RW_MONITOR: PASS (mailbox reached; thresholds imem_rd>=8 dmem_rd>=16 dmem_wr>=16 bus_err==0 def==0)
[SIM] PASS  P2_TB2_RESULT: PASS
[SIM] PASS  AHB_RW_MONITOR: PASS
[SIM] PASS  no *.ihex
```

Cycle counts are identical to `doc/SoC_Phase_Status_Audit.md` §3
(`imem_rd=2393 dmem_rd=366 dmem_wr=164`). Gates G1–G13 all PASS on both the fw0
and spike images. The added `MBOX[8..15]` line is purely additive and reads
`00000000 00000000` for fw0, which does not write those bytes.

---

# 8. Build plumbing added (decision D2 groundwork)

| Change | File | Purpose |
|---|---|---|
| `MAIN_SRC ?= src/main.c` | `sw/Makefile` | build any alternate `main()` into its own `BUILD` dir |
| `EXTRA_CFLAGS ?=` appended to `CFLAGS` | `sw/Makefile` | select probe region / future `-DTEST_SELECT_*` |
| `SW_BUILD ?= $(SW_DIR)/build` | `sim/Makefile` | point the sim at a variant image |
| new `run` target | `sim/Makefile` | re-run the existing `simv` against a swapped image with **no VCS recompile**; `sim: rtl run` |

`$readmemh` executes in an `initial` block at t=0, so one elaborated `simv`
serves every variant. This is the mechanism decision D1/D2
(§6.1, §6.2) will build on.

---

# 9. Next

Phase 1 — test framework (`test.h`, `.test_list` registry, MRAC in `startup.S`,
`.results` linker section, gates G14/G15). The `MAIN_SRC` / `EXTRA_CFLAGS` /
`SW_BUILD` hooks added here are the same ones `-DTEST_SELECT_*` will use.