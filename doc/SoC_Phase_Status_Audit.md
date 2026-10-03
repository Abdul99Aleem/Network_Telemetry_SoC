# SoC Phase Status Audit

**Date:** 2026-10-03
**Scope:** Individual SoC contribution only. Group project documents under
`doc/Group_SoC_docs/` are explicitly out of scope and were not used as
evidence.
**Purpose:** State, per phase, what is genuinely proven end-to-end, what is
proven only in isolation, and what has not been started. Corrects several
claims that are currently overstated in `README.md` §5.2 and in two
completion records.

**Repo rule honoured:** *never claim PASS without a log.* Every PASS below is
quoted from a surviving artifact on disk. Where an artifact is missing, the
phase is marked **ASSERTED**, not PASS.

---

## 1. Headline

The strongest verified chains are:

```
C firmware -> GCC -> ELF -> imem.mem/dmem.mem -> VeeR EL2
          -> ahb_interconnect -> IMEM/DMEM -> VCS -> FSDB -> Verdi
```

and, independently:

```
VeeR EL2 -> ahb_interconnect -> ahb_to_axi_bridge
         -> uart_axi_slave -> axi_uart_top -> uart_tx_o
```

These are **two separate results**, produced by two different testbenches with
two different programs. They have never been joined. The single largest gap
in the project is that **no C firmware has ever accessed any peripheral**
(see §4).

---

## 2. Phase status summary

| Phase | Scope | Status | Evidence |
|---|---|---|---|
| Phase 1 | VeeR EL2 bring-up (stock VeeR TB, canned hex) | **ASSERTED** | `doc/Phase1_VeeR_Bringup_Completion_Record.md`. Workdir `/tmp/opencode/veer_p1` no longer exists; no log/FSDB survives |
| Phase 2 | AHB-Lite fabric, IMEM, DMEM, ERROR slave | **PROVEN** | `P2 FABRIC: PASS=16 FAIL=0`, `P2_TB1_RESULT: PASS` |
| Phase 2 | VeeR executing through the project fabric | **PROVEN** | `P2_TB2_RESULT: PASS (P2 program ran through project fabric)` |
| Phase 3 | UART on the SoC via AHB→AXI bridge | **PROVEN** | `UART_E2E_RESULT: PASS (VeeR -> AHB -> AXI -> UART -> uart_tx)` |
| Phase 3 | Fabric regression incl. bridge (T1–T14) | **PROVEN** | `P2 FABRIC: PASS=23 FAIL=0` |
| fw0 | RISC-V GCC toolchain, ELF/linker/image gates | **PROVEN** | `doc/Fw0_C_Toolchain_Build_and_Gate_Record.md`, gates G1–G13; image sizes re-verified on disk |
| fw0 | C firmware executing on VeeR, AHB R/W in Verdi | **PROVEN** | `build/sim/fw0/sim.log` — see §3 |
| — | AES-128 core, isolated | **PROVEN** | `Test Done. Found 0 Errors.` |
| — | AES AXI slave: registers, DONE, IRQ, known-answer | **PROVEN** | `AES AXI SLAVE TEST PASSED`, ciphertext `69c4e0d86a7b0430d8cdb78070b4c55a` |
| — | AES via AXI 2×8, single master | **PROVEN** | `AXI INTERCONNECT -> AES INTEGRATION: PASS` |
| — | AES via AXI 2×8, two masters | **PROVEN** | `PASS checks : 19` / `FAIL checks : 0` |
| — | UART AXI slave direct / via 2×8 / 2-master | **UNBACKED** | claimed PASS, no surviving log — see §5.2 |
| M4 | AES on the SoC + C driver | **NOT STARTED** | no RTL, no driver, no TB |
| M5 | Network Telemetry Engine + CRC32 + interrupts | **NOT STARTED** | no RTL at all |
| M6 | Full bare-metal telemetry app + E2E TB | **NOT STARTED** | — |
| Phase 8 | Synthesis / FPGA / PPA | **NOT STARTED** | `doc/Phase3…:196` "Simulation only" |

---

## 3. Phase 2 and fw0 — the C firmware path (PROVEN)

C firmware has been compiled, loaded into the simulation memory images,
executed by VeeR EL2 through the custom AHB-Lite fabric, and its AHB
transactions have been verified cycle-by-cycle in VCS/Verdi.

Verbatim from `build/sim/fw0/sim.log`:

```
[90915000] P2_TB2_RESULT: PASS (P2 program ran through project fabric)
[TB] AHB_CYCLES imem_rd=2393 imem_wr=0 dmem_rd=366 dmem_wr=164
[TB] AHB_CYCLES uart_rd=0 uart_wr=0 def=0 bus_err=0 ifu_offtarget=0
[TB] AHB_RW_MONITOR: PASS (mailbox reached; thresholds imem_rd>=8 dmem_rd>=16 dmem_wr>=16 bus_err==0 def==0)
```

Independently re-verified on disk: `firmware.elf` 12312 B, `imem.mem`
2040 B, `dmem.mem` 22 B, `firmware.ihex` 1912 B — all match the quoted gate
values in `doc/Fw0_C_Toolchain_Build_and_Gate_Record.md`.

### The critical caveat

`uart_rd=0 uart_wr=0`. The fw0 firmware performs **no peripheral access at
all**. This is deliberate and documented, not an oversight:

- `sw/src/main.c:23` — `- UART/AES MMIO (plumbing is on the sibling UART branch)`
- `sw/include/soc.h:36-37` — `UART_BASE 0x10000000u /* … rtl/uart/ present only on the sibling UART branch */`
- `doc/Firmware_Build_and_AHB_RW_Verification_Record.md:411-412` — "Aggregate:
  uart_rd = 0, uart_wr = 0 (fw0 never touches the UART — correct, fw0 has no
  UART code)"

So fw0 proves the **toolchain and the CPU/memory path**, not the peripheral
path.

---

## 4. Phase 3 — UART end-to-end (PROVEN, but not C firmware)

Verbatim result block:

```
 serial bytes : UART.  (payload "UART\n", bit period 8690000 ns)
              : 55 41 52 54 0a
 DMEM[2]      : 0xff (expect FF)
 DMEM[4..7]   : 60 00 00 00 (LSR via bridge, expect 60 00 00 00)
 uart_irq     : 0 (expect 0, TX-only)
 UART_E2E_RESULT: PASS (VeeR -> AHB -> AXI -> UART -> uart_tx)
```

This is a genuine VeeR-driven E2E result through the bridge. However:

**The program is not C.** `run/p3_uart_flow.csh:37` generates the image with

```
python3 $PROJ/scripts/p3_uart_prog_gen.py $WORK/tb/uart_prog.hex
```

`scripts/p3_uart_prog_gen.py` is an **RV32I mini-assembler written in Python**.
It hand-encodes `lui`/`sw`/`lw`/CSR writes to poll `LSR.THRE`/`LSR.TEMT` and
push `"UART\n"` at `THR` (`0x1000_0000`). It sets `MRAC = 0x7C0` with
`side_effect` on the UART region so LSR loads are not forwarded from the load
buffer — a real and correct piece of bring-up work, but not software
engineering in the C sense.

**Consequence:** the project has a C-firmware result that touches no
peripheral, and a peripheral result driven by an assembler script. Joining
them is the substance of M4.

---

## 5. Corrections to claims currently in the repository

### 5.1 There is no AXI 2×8 fabric between the bridge and the UART on the SoC

The architecture diagram in circulation shows:

```
VeeR -> AHB-Lite -> AHB->AXI Bridge -> AXI 2x8 Fabric -> UART AXI Slave -> UART IP
```

This is **not what `rtl/soc_top.sv` builds.** In `rtl/soc_top.sv`:

- `ahb_to_axi_bridge … u_ahb2axi` (line 156) drives local wires `awid`,
  `arid`, `awaddr`, … (lines 143–154)
- `uart_axi_slave … u_uart` (line 187) consumes **those same wires** (lines
  190–210)

It is a point-to-point connection. `axi_interconnect_wrap_2x8` is
**not instantiated anywhere in `soc_top.sv`**, and neither
`run/p3_uart_soc_run.f` nor `run/uart_rtl.f` nor `sim/filelist.f` contains
any `axi_interconnect*` file (verified: `grep -c axi_interconnect` returns
`0, 0, 0`).

The 2×8 interconnect is instantiated only inside the standalone wrappers
`rtl/uart/axi_uart_wrapper.v:147` and `rtl/aes/axi_aes_wrapper.v:129`, which
are used by the isolated AXI benches only.

**Therefore the Phase-3 E2E PASS proves nothing about the AXI 2×8
interconnect.** The interconnect's only evidence is the standalone
(no-CPU) benches.

`doc/Phase3_UART_End_To_End_Completion_Record.md:16` and `:18` are factually
wrong on this point; they also claim `soc_top` exposes `uart_rx_i` and AXI
interconnect wires. The actual port list (`rtl/soc_top.sv:50-52`) is
`uart_tx_o` and `uart_irq_o` only, and RX is hard-tied at line 212:
`.uart_rx_i(1'b1)`.

The accurate chain, per `tb/tb_veer_uart_soc.sv:7-11`, is:

```
VeeR EL2 -> ahb_interconnect -> ahb_to_axi_bridge -> uart_axi_slave
         -> axi_uart_top -> uart_controller -> uart_transmitter -> uart_tx_o
```

### 5.2 The isolated UART AXI regressions have no surviving artifact

`README.md:245` cites, as evidence:

```
UART AXI SLAVE DIRECT: PASS
AXI INTERCONNECT -> UART INTEGRATION: PASS
2-master 19/0  — run 2026-09-26 15:18
```

No log anywhere in the repository or in `/tmp/opencode` contains the first
two tokens. The only UART AXI log present, `run/sim_uart_axi.log`, is
**truncated mid-test** — it ends at:

```
 UART AXI SLAVE DIRECT TEST (no interconnect)
 UART BASE = 10000000, BAUD_DIV = 8
TX IDLE HIGH PASS
```

with no `$finish`, no PASS token and no check summary. Its mtime (Sep 26
12:53) is *older* than `run/compile_uart_axi.log` (15:02), so the later
compile's `simv` run never rewrote it. `run/uart_full_flow.csh` greps for
exactly those tokens, so a completed run would have left them.

Treat gate 12 of `doc/Phase3…` as **UNBACKED** until re-run. The AES
equivalents *are* backed (`run/sim_aes_axi.log`,
`run/sim_aes_axi_interconnect.log`, `run/sim_aes_2master.log`).

### 5.3 AES was never driven by the VeeR CPU

Every AES PASS in this project was produced by an AXI bus-functional-model
testbench with **no processor in the design**. Verified: `grep -icE
"veer_wrapper|rvtop|soc_top"` returns `0` for `tb/tb_aes_axi_slave.sv`,
`tb/tb_axi_interconnect_aes.sv` and `tb/tb_axi_interconnect_aes_2master.sv`.
No AES filelist (`run/aes_axi_run.f`, `run/aes_axi_interconnect_run.f`,
`run/aes_axi_2master_run.f`) contains a VeeR source file.

This is stated correctly in the progress document:

> `doc/RISC_V_Network_Telemetry_SoC_Progress_and_Architecture.md:1872`
> "No VeeR CPU transaction is currently part of this AXI/AES test."

and at `:120`: "This is an **isolated IP verification stage**, not yet the
final VeeR SoC connection."

### 5.4 Two completion records are stale and must not be quoted as-is

**`doc/AES_AXI_Integration_Verification_Record.md`** is 1709 lines and its
current-status sections are wrong. Lines 920 and 1550-1556 report:

```
AES completion             FAIL
DONE assertion             FAIL
BUSY deassertion           FAIL
AES IRQ                    Pending
RESULT correctness         Pending
VeeR integration           Pending
```

The log the document itself cites (`run/sim_aes_axi.log`) contradicts this:

```
DONE asserted
AES IRQ asserted
AXI READ   ADDR=10004028 DATA=70b4c55a
...
 AES AXI SLAVE TEST PASSED
 Ciphertext = 69c4e0d86a7b0430d8cdb78070b4c55a
```

The status is PASS; the prose is stale. `doc/Phase1…:143` and
`doc/Phase2…:136` already flag it as *"(stale DONE-timeout — superseded by
PASS logs)"*. `README.md:243` nonetheless cites this document as the PASS
evidence — **the status is right, the citation is wrong.**

**`doc/RISC_V_Network_Telemetry_SoC_Progress_and_Architecture.md`** is stale
in two directions:

- Lines 212-252 still list IMEM, DMEM and UART as `Planned`. All three are
  implemented and VeeR-driven.
- Lines 1240-1241, 1845-1848 and 1894-1898 say the corrected two-master AES
  test *"still needs to be rerun"*, and give `19 PASS / 0 FAIL` as an
  *expectation*. `run/sim_aes_2master.log` (Sep 26 12:53) already contains:

  ```
  TWO-MASTER AES VERIFICATION SUMMARY
   PASS checks : 19
   FAIL checks : 0
  *** TWO-MASTER AES TEST PASSED ***
  ```

- Its §27 "What Has Been Proven" claims 9 proven items while Appendix D
  (lines 2371-2385) has **all 15 definition-of-done boxes unticked**,
  including "IRQ verification" and "Single-master register test". Appendix D
  is the conservative and accurate version.

### 5.5 UART interrupt and RX are unverified

`doc/Phase3…:187-188`:

> "UART is TX-only. uart_irq is tied off and checked 0; RX and the interrupt
> path are unverified."

`uart_irq` is in fact a real output driven by `uart_axi_slave`
(`rtl/soc_top.sv:212`), not tied off — it is simply observed to be 0 because
the bench never enables it. Baud is the IP reset default
(`UART_BAUDRATE_DIV_INIT=868`, no DLAB programming). Interrupts overall are
planned only: `aes_irq` → PIC → VeeR is described at
`doc/RISC_V_Network_Telemetry_SoC_Progress_and_Architecture.md:1725-1742` as
depending on an undecided VeeR configuration.

---

## 6. IP-by-IP classification

### 6.1 Integrated and proven end-to-end from VeeR

| IP | Notes |
|---|---|
| VeeR EL2 | Phase 1 ASSERTED (stock TB); Phase 2/3/fw0 PROVEN through project fabric |
| `ahb_interconnect` | 2 masters (IFU/LSU), 4 slaves, arbitration, PASS=23 |
| `ahb_sram` (IMEM 32 KB @ `0x0000_0000`) | `imem_rd=2393`, `imem_wr=0` canary honoured |
| `ahb_sram` (DMEM 32 KB @ `0x0001_0000`) | `dmem_rd=366`, `dmem_wr=164` |
| `ahb_default_slave` | `def=0`, `bus_err=0` |
| `ahb_to_axi_bridge` | exercised via UART; 64-bit AHB-Lite → 32-bit AXI4 |
| `uart_axi_slave` | register reads verified via LSR `60 00 00 00` |
| UART IP (`axi_uart_top` → transmitter) | TX only; `55 41 52 54 0a` on the wire |
| `startup.S` relocation (`.data` LMA→VMA) | gate G8; `data_marker` check in `main.c` |

### 6.2 Implemented and proven, but isolated (no CPU in the loop)

| IP | Evidence | Why isolated |
|---|---|---|
| `axi_interconnect` / `_wrap_2x8` / `arbiter` / `priority_encoder` | AES and UART benches, single and 2-master | never instantiated in `soc_top` |
| `aes_axi_slave` | `AES AXI SLAVE TEST PASSED`, DONE, IRQ, KAT | no VeeR in filelist |
| AES-128 core + IP | `Test Done. Found 0 Errors.` | as above |

### 6.3 Not started — no RTL exists

| Block | Address in v3 §9 map | Current decode |
|---|---|---|
| Timer | `0x1000_1000` | `ahb_default_slave` (ERROR) |
| GPIO | `0x1000_2000` | `ahb_default_slave` (ERROR) |
| Network Telemetry Engine | `0x1000_3000` | `ahb_default_slave` (ERROR) |
| AES on SoC | `0x1000_4000` | `ahb_default_slave` (ERROR) |
| CRC32 / FCS | `0x1000_5000` | `ahb_default_slave` (ERROR) |

`rtl/soc_top.sv:9-10`:

> "Remaining peripheral regions (Timer/GPIO/NET/AES/CRC) decode to the
> default ERROR slave (v3 §9 map reserved)."

There is no `rtl/timer/`, `rtl/gpio/`, `rtl/net*/` or `rtl/crc*/`
directory. Decode logic in `rtl/ahb/ahb_interconnect.sv:169-174` selects
UART on `0x10000` and routes everything else unmatched to the default slave.

Also not started: any C driver for any peripheral, the interrupt/PIC
aggregation path, the packet→telemetry→AES→UART application, and UVM.

---

## 7. What may honestly be claimed today

1. A RISC-V GCC toolchain was brought up and validated, producing
   `firmware.elf` and byte-per-token memory images under a strict gate set
   (G1–G13).
2. C firmware compiled by that toolchain was loaded into simulation memory
   images and executed by VeeR EL2 through the custom AHB-Lite fabric, with
   its AHB read/write cycles verified cycle-by-cycle in VCS and inspected in
   Verdi.
3. VeeR EL2 drove a program through `ahb_interconnect` →
   `ahb_to_axi_bridge` → `uart_axi_slave` → UART IP, and the serial bytes
   `55 41 52 54 0a` ("UART\n") were observed and checked, with register
   read-back and a fabric regression of 23/23.
4. The AXI 2×8 interconnect and the AES-128 accelerator are proven as
   memory-mapped AXI peripherals, including DONE, interrupt assertion and the
   NIST known-answer ciphertext — **verified with an AXI bus-functional
   model, not with the processor.**

The following may **not** be claimed:

- that C firmware has accessed a peripheral (it has not);
- that the AXI 2×8 fabric is on the SoC path (it is not);
- that AES has been integrated with VeeR (it has not);
- that Timer, GPIO, the Network Telemetry Engine or CRC32 exist as RTL
  (they do not);
- that any interrupt has been delivered to the CPU (none has).

---

## 8. Recommended next step

M4 as currently worded ("AES on the SoC (bridge + driver)") understates the
real work. The correct next milestone is:

> **M4 — C firmware driving a real peripheral over the SoC bus.**

Concretely, the minimum credible M4 is:

1. Add a `uart` MMIO driver to `sw/` (TX + LSR polling), built by the
   existing `sw/Makefile` into `imem.mem`.
2. Run `sw/build/imem.mem` through `tb_veer_uart_soc.sv` (replacing the
   Python-assembler image) and require `uart_rd>0`, `uart_wr>0` in
   `tb_ahb_cycle_monitor.sv`.
3. Only then instantiate the AES AXI slave behind the bridge in `soc_top`
   and add an interrupt path.

Steps 1-2 close the single largest credibility gap in the project and reuse
existing, already-passing infrastructure. Step 3 is the actual M4.

Two documentation defects should be fixed alongside: re-run and capture the
isolated UART AXI benches (§5.2), and correct `README.md:243` and `:245` to
cite surviving logs rather than stale records.
