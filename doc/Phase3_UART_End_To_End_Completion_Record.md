# PHASE 3 — UART End-to-End on the SoC: Completion Record

**Project:** RISC-V Network Telemetry SoC
**Phase:** 3 — AHB→AXI bridge + UART attached at `0x1000_0000`, VeeR end-to-end
**Status:** PASS (E2E + TB1, exit 0)
**Date:** 2026-09-26
**Toolchain:** Synopsys VCS U-2023.03 + Verdi U-2023.03-SP1
**Reproduce:** `run/p3_uart_flow.csh` (exit 0 = E2E PASS **and** TB1 PASS)

---

## 1. What was built

| File | Desc |
|---|---|
| `rtl/ahb/ahb_to_axi_bridge.sv` | AHB-Lite (64-bit) → two 32-bit AXI ports (`m_axi`/`s_axi` via the AXI interconnect → UART). `HSIZE==3` beat is split into two back-to-back 32-bit AXI accesses at `HADDR` and `HADDR+4`, then re-merged into `HRDATA`. Byte-lane `WSTRB` derived from `HSIZE`+`HADDR[2:0]` |
| `rtl/ahb/ahb_interconnect.sv` | 4-slave decode (IMEM / DMEM / UART / default ERROR): `addr_sel`, `data_sel`, one-hot `hsel_*` all widened to 3 bits; **data-phase ownership-based** arbitration and response steering (see §4.2) |
| `rtl/soc_top.sv` | Instantiates `u_fabric`, `u_imem`, `u_dmem`, `u_ahb2axi`, `u_uart`; exposes `uart_tx_o`/`uart_rx_i`/`uart_irq` and the interconnect AXI wires |
| `rtl/uart/uart_axi_slave.v` | AXI4-Lite → UART IP register access (already landed in `c0665ed`) |
| `rtl/uart/ip/axi_uart_top.v` | Vendored UART IP. **Patched** — TX FIFO soft-reset released at power-on (§4.1) |
| `tb/tb_veer_uart_soc.sv` | E2E bench: VeeR + `soc_top`, auto-calibrating 8N1 receiver, DMEM terminator + LSR checks |
| `tb/tb_ahb_fabric.sv` | TB1, now **T1–T14 / 23 checks**. New: `T13` 64-bit split UART read, `T14` cross-master HREADY hold |
| `scripts/p3_uart_prog_gen.py` | RV32I mini-assembler for the E2E payload program (§2) |
| `run/p3_uart_flow.csh`, `run/p3_uart_soc_run.f`, `run/uart_rtl.f` | One-shot flow + filelists |

The path under test is the whole project in miniature:

```
VeeR EL2 (IFU/LSU) → ahb_interconnect → ahb_to_axi_bridge → AXI
    → uart_axi_slave → axi_uart_top → uart_tx_o (8N1 serial)
```

## 2. E2E program (`scripts/p3_uart_prog_gen.py`, IMEM `0x0000_0000`)

```
lui  s0, 0x10000        # s0 = 0x1000_0000 UART
lui  s1, 0x10           # s1 = 0x0001_0000 DMEM
addi t0, x0, 0x8        # MRAC: region-1 (0x1xxx_xxxx) side_effect=1, cacheable=0
csrw 0x7c0, t0          #   -> LSU MMIO loads never load-buffer forwarded
addi a0, x0, 'U' ; sw a0, 0(s0) ; poll LSR.THRE ; ...   # x5, payload "UART\n"
poll LSR.TEMT                     # wait for the shift register to drain
lw   t0, 0x14(s0) ; sw t0, 4(s1)  # LSR -> DMEM[4..7] (read-back through the bridge)
addi t2, x0, 0xFF  ; sb t2, 2(s1) # completion terminator -> DMEM[2]
park
```

VeeR boots at `reset_vec=0x0000_0000` (new `uart_soc` snapshot, `default_ahb`).

**PASS criteria (all must hold):** 5 serial bytes `55 41 52 54 0a`;
`DMEM[2]==0xFF`; `DMEM[4][6:5]==2'b11` (THRE|TEMT) and `DMEM[4][0]==0` (no OE);
`DMEM[5..7]==0`; `uart_irq==0`.

## 3. Gate results

| # | Gate | Evidence |
|---|---|---|
| 1 | VeeR boots through the 4-slave fabric | `[335000] CPU running, reset_vec=0x00000000` |
| 2 | LSU MMIO write → bridge → AXI → THR | `[3415000 ns] CPU wrote DMEM terminator (program parked)` |
| 3 | LSR poll loop completes (THRE then TEMT) | program reaches the terminator — would hang otherwise |
| 4 | Serial framing, 8N1 | `UART MONITOR: calibrated bit period = 8690000 ns (869 clk)` |
| 5 | Payload integrity on the wire | `55 41 52 54 0a` = `"UART\n"`, 0 mismatches |
| 6 | LSR read-back across AHB→AXI bridge | `DMEM[4..7] : 60 00 00 00` |
| 7 | Completion terminator visible to the TB | `DMEM[2] : 0xff` |
| 8 | TX-only (no spurious IRQ) | `uart_irq : 0` |
| 9 | No exceptions during the run | `grep -c "EXC cause=" sim_uart_e2e.log` = **0** |
| 10 | E2E result | `UART_E2E_RESULT: PASS (VeeR -> AHB -> AXI -> UART -> uart_tx)` |
| 11 | Fabric regression incl. new T13/T14 | `P2 FABRIC: PASS=23 FAIL=0` → `P2_TB1_RESULT: PASS` |
| 12 | Isolated UART regressions still clean | `UART AXI SLAVE DIRECT: PASS`, `AXI INTERCONNECT -> UART INTEGRATION: PASS`, 2-master 19/0 |

Final run: `run/p3_uart_flow.csh`, exit **0**, 2026-09-26 17:42.
Logs: `/tmp/opencode/uart_e2e/tb/sim_uart_e2e.log`, `run_all.log`; TB1 in the same flow.

## 4. Root causes fixed during verification

### 4.1 UART IP: TX FIFO held in soft-reset from power-on

**Symptom (15:48 and 16:30 runs):** every frame carried the first payload byte —
`RX[0]=0x55` correct, then
`RX[1]=0x55 MISMATCH (expected 0x41)`, `RX[2]=0x55`, `RX[3]=0x55`, `RX[4]=0x55`.

**Cause:** `axi_uart_top`'s write FSM resets into `ResetWriteState` with
`tx_fifo_reset_int <= 1'b1`, and `ResetWriteState` kept re-asserting
`tx_fifo_reset_int_d = 1'b1` until the *first* AXI write reached
`AckWriteState`. `axi_internal_fifo` ignores `push_i` and clears
`head/tail/valid` while `rst_i` is high, so the FIFO never came out of reset
coherent with the transmit stream.

**Fix:** `rtl/uart/ip/axi_uart_top.v:405` — `ResetWriteState` now drives
`tx_fifo_reset_int_d = 1'b0`. `arstn_i` already clears the FIFO on hardware
reset, so the synchronous soft-reset had nothing left to do. (The `default:`
branch still asserts it and returns the FSM to `ResetWriteState`; that path is
unreachable and only produces a one-cycle flush.)

### 4.2 AHB fabric: dropped address phases and mis-steered responses

**Symptom (16:30 run):** `grep -c "EXC cause=2"` = **24,719** — VeeR trapped
illegal-instruction in a restart loop, alternating `PC=0x14` and `PC=0x0`.

**Cause:** two related defects in `ahb_interconnect`:

1. `addr_is_lsu = lsu_active` unconditionally. HREADY doubles as "my address
   phase was accepted", so whenever the IFU issued a fetch in the same cycle
   the LSU was active, the IFU's address was muxed away, the LSU's HREADY=1
   completed the LSU's data phase, and the IFU's fetch was **silently
   dropped** — VeeR then executed whatever was left on `HRDATA`.
2. Response steering used only the registered `data_is_lsu` (a one-cycle-true
   flag after the address phase ended), so a master could be told "your data
   phase is done" while another master's slave was driving.

**Fix:** registered data-phase owner (`data_sel`, `data_is_lsu`) is now
decisive:

```systemverilog
addr_is_lsu = (dp_is_lsu && lsu_active) ? 1'b1 :
              (dp_is_ifu && ifu_active) ? 1'b0 :   // data-phase owner keeps
              lsu_active;                          //   the bus; else LSU first
ifu_hready  = (ifu_granted || dp_is_ifu) ? mux_hreadyout : ~ifu_active;
ifu_hrdata  = dp_is_ifu ? mux_hrdata : '0;
```

A master that is not granted sees `HREADY=0` (its address phase is held, not
dropped), an idle master sees `HREADY=1`, and only the data-phase owner sees
the slave's `HRDATA`/`HRESP`. Documented LSU-over-IFU priority (v3 §11.8)
still applies whenever the data-phase owner is idle.

`axi4_to_ahb` derives `HTRANS` only from registered `ahb_hready_q`, so the new
`htrans → hready` dependency introduces **no combinational loop**.

**Regression:** TB1 `T14` — IFU address phase held while `data_sel==3'b011`
(UART data phase), then completes with correct IMEM data.

### 4.3 AHB→AXI bridge: 64-bit beat returned only one 32-bit half

**Symptom:** `UART_E2E_RESULT: TIMEOUT FAIL (rx_count=5 dmem_done=0)` with all
five serial bytes correct — the program parked in the `LSR.TEMT` poll and
never wrote `DMEM[2]`.

**Cause:** VeeR EL2's MRAC leaves regions non-side-effect by default, so
`el2_lsu_bus_buffer` aligns `obuf_addr` down to the 8-byte boundary and issues
`arsize=3` (`obuf_sideeffect ? obuf_addr : {obuf_addr[31:3],3'b0}`). A `lw` of
LSR at `0x1000_0014` therefore arrives as `HADDR=0x1000_0010 / HSIZE=3`, and
the LSR word lives in the **upper** half of `HRDATA`. The bridge issued a
single 32-bit AXI read and drove `HRDATA[63:32]=0`, so the CPU read 0 forever
and the TEMT poll never terminated.

**Fix:** `size_q==3'b011` now runs two back-to-back 32-bit AXI accesses
(`wide64`, `aw_addr`/`ar_addr`, `rdata_hi_q`, `wr_second_q`/`rd_second_q`) and
re-merges them: `hrdata = wide64 ? {rdata_hi_q, rdata_q} : lane_hi ? {rdata_q,32'h0} : {32'h0,rdata_q}`.
`AWSIZE`/`ARSIZE` are clamped to `3'b010` on the 32-bit AXI port.

**Regression:** TB1 `T13` — `HADDR=0x1000_0010 / HSIZE=3` must return
`HRDATA[63:32]==0x0000_0060`, `HRDATA[31:0]==0`, `HRESP=0`.

### 4.4 MMIO side-effect attribute set in software

With 4.1–4.3 fixed the run passes either way, but the SoC now also writes MRAC
explicitly (`csrw 0x7c0, t0` with `t0=0x8` → `MRAC[3]=1` = region-1 side
effect, `MRAC[2]=0` = non-cacheable; `mrac_in[even] &= ~mrac_in[odd]` keeps
cacheable clear). Two effects:

* `obuf_sideeffect=1` stops `obuf_nosend` load-forwarding of LSR polls and
  makes VeeR issue size-correct, naturally-aligned MMIO accesses
  (`0x1000_0014 / hsize=2` instead of the 8-byte-aligned `hsize=3` form).
* MRAC has **no hardware reset** (`mrac_ff` is a plain `rvdffe`), so this write
  also gives the attribute register a defined value at power-on.

Verified after the change: `run/p3_uart_flow.csh` exit 0, E2E PASS + TB1 23/23.

## 5. File change inventory (this phase)

| File | Change | Impact |
|---|---|---|
| `rtl/ahb/ahb_interconnect.sv` | 3-bit decode; data-phase-owner arbitration + response steering | kills the illegal-instruction restart loop (§4.2) |
| `rtl/ahb/ahb_to_axi_bridge.sv` | 64-bit AHB beat split into two 32-bit AXI accesses, re-merged | LSR/THRM reads across the bridge (§4.3) |
| `rtl/uart/ip/axi_uart_top.v` | `ResetWriteState`: `tx_fifo_reset_int_d` `1'b1`→`1'b0` | correct payload on `uart_tx` (§4.1) |
| `scripts/p3_uart_prog_gen.py` | `csrw` encoder + MRAC init preamble | defined, side-effect MMIO attribute (§4.4) |
| `tb/tb_ahb_fabric.sv` | `T13` (64-bit split read), `T14` (cross-master HREADY hold); header updated | 21 → **23** checks |
| `tb/tb_veer_uart_soc.sv` | debug instrumentation removed; failure-only diagnostics retained | log noise down, PASS criteria unchanged |

## 6. Known limitations and required amendments

1. **§10.1 register map deviation — report as an amendment.** The arch doc's
   UART table does not match the IP. The implemented (IP-native) map is:
   `0x00` THR/RBR, `0x04` IER, `0x08` baud divisor (**DLAB=1**),
   `0x0C` LCR, `0x14` LSR. Decision: keep the IP-native map and amend §10.1 —
   re-writing the offsets would mean forking the vendored IP.
2. **UART is TX-only.** `uart_irq` is tied off and checked `0`; RX and the
   interrupt path are unverified.
3. **Baud is the IP reset default** — `UART_BAUDRATE_DIV_INIT=868` → bit period
   8690 ns (869 clk) @ 100 MHz ≈ 115 kbaud. No DLAB programming is done.
4. **`hsize=3` on the UART window is accepted but not architecturally
   meaningful.** T13 proves the bridge behaviour, not a UART requirement.
5. **`tb_veer_p2_soc.sv` / `tb_ahb_cycle_monitor.sv` are dirty in the working
   tree from a separate (fw0 AHB R/W monitor) workstream** — not part of this
   phase and deliberately excluded from the Phase-3 commit.
6. **Simulation only.** No synthesis, FPGA or PPA numbers (Phase 8, stays last).

## 7. Traceability (v3 arch doc)

| v3 § | Item | Status |
|---|---|---|
| §9 / §10.1 | UART at `0x1000_0000`, 4 KB | implemented; register map deviates — amendment (§6.1) |
| §11.8 | LSU priority over IFU | preserved; data-phase owner takes precedence when issuing |
| §12 | AHB-Lite fabric | 4-slave decode + response steering |
| §13 | AXI subsystem | bridge + interconnect + UART slave |
| §24 (M3) | UART on the SoC | **PASS** |

## 8. Status

**M3 — UART on the SoC: PASS.** Next up: M4 (AES through the same bridge),
which reuses `ahb_to_axi_bridge` unchanged and only needs a fabric decode entry
plus a driver.
