# UVM Verification Plan — RISC-V Network Telemetry SoC

**Status:** Planning document (not yet implemented)
**Date:** 2026-10-17
**Scope:** RTL-level UVM environment for the project SoC, incorporating a C-SV handshake service, a bringup service, and realistic deliverable phases grounded in the as-built codebase.

---

## 1. Executive Summary

This plan defines a layered UVM verification environment for the RISC-V Network
Telemetry SoC. It is grounded in the actual RTL (§2), the existing C test
framework (§3), and industry UVM/DV practices researched from DVCon papers,
Verification Academy, the lowRISC DV coding style guide, and chipverify.com's
C-SV coordination articles.

Three architectural decisions distinguish this plan from a generic UVM
template:

1. **Bringup service** (§4): a dedicated UVM component that owns clock
   generation, reset sequencing across the SoC's three polarity domains, and
   the post-reset sanity assertion. No test stimulus begins until the bringup
   service reports READY. This is the SV-side half of the coordination.

2. **C-SV handshake service** (§5): a DPI-C and shared-memory coordination
   layer that lets C firmware running on the VeeR core (or a BFM stand-in)
   synchronize with UVM sequences *before* bus traffic starts. The C side
   writes a magic word to a known DMEM address; the SV side polls (or gets a
   DPI-C call) and only then drives stimulus. This prevents X/Z propagation
   that would occur if the SV testbench drove the bus before the C side had
   initialized peripherals.

3. **Realistic deliverable phases** (§7): seven phases mapped to what is
   actually integrated in `soc_top` today (IMEM, DMEM, UART), what exists as
   isolated RTL but is not yet instantiated (AES, AXI crossbar), and what is
   planned (Network Telemetry Engine). Each phase has a concrete gate
   criterion and a make target.

---

## 2. SoC Inventory (As-Built)

### 2.1 What is integrated in `soc_top` today

| Instance | Module | File | Bus |
|---|---|---|---|
| `u_fabric` | `ahb_interconnect` | `rtl/ahb/ahb_interconnect.sv` | AHB-Lite 2M/4S, 64b |
| `u_imem` | `ahb_sram` 32 KB @ `0x0000_0000` | `rtl/soc_top.sv:119` | AHB slave |
| `u_dmem` | `ahb_sram` 32 KB @ `0x0001_0000` | `rtl/soc_top.sv:130` | AHB slave |
| `u_ahb2axi` | `ahb_to_axi_bridge` | `rtl/ahb/ahb_to_axi_bridge.sv` | AHB→AXI4 |
| `u_uart` | `uart_axi_slave` → `axi_uart_top` | `rtl/uart/uart_axi_slave.v` | AXI4→AXI4-Lite |
| `u_default` | `ahb_default_slave` | `rtl/ahb/ahb_default_slave.sv` | AHB ERROR |

### 2.2 What exists as RTL but is not instantiated

| Block | File | Status |
|---|---|---|
| AES-128 AXI slave | `rtl/aes/aes_axi_slave.v` | Proven in isolation (19 PASS / 0 FAIL); base address `0x1000_4000` conflicts with Rev B canonical map |
| AXI 2×8 crossbar | `rtl/interconnects/axi_interconnect_wrap_2x8.v` | Proven standalone; M03–M07 at Rev-A bases (4 KB pitch) |

### 2.3 Memory map

Target (Rev B canonical, 8 KB pitch):

| Slot | Base | Block |
|---|---|---|
| 0 | `0x1000_0000` | UART (live) |
| 1 | `0x1000_2000` | Timer (not yet) |
| 2 | `0x1000_4000` | GPIO (not yet) |
| 3 | `0x1000_6000` | Network Telemetry (not yet) |
| 4 | `0x1000_8000` | AES-128 (RTL exists, needs base fix) |
| 5 | `0x1000_A000` | CRC32 (not yet) |

SRAM:

| Region | Base | Size |
|---|---|---|
| IMEM | `0x0000_0000` | 32 KB |
| DMEM | `0x0001_0000` | 32 KB |

### 2.4 Known defects to encode

| ID | Defect | Location | Plan treatment |
|---|---|---|---|
| D1 | No interrupt path to CPU | `soc_top.sv`: `extintsrc_req=31'b0` | IRQ monitor at peripheral boundary only; document CPU path broken |
| D2 | AES base `0x1000_4000` vs canonical `0x1000_8000` | `aes_axi_slave.v:85` | Fix in Phase 0: re-parameterize to `0x1000_8000` |
| D3 | No `uart_rx_i` port on `soc_top` | `soc_top.sv:212` | Add port in Phase 0 (or document TX-only for now) |
| D4 | Crossbar M03–M07 at Rev-A bases (4 KB pitch) | `axi_interconnect_wrap_2x8.v:67-91` | Re-parameterize to 8 KB pitch: M02=`0x1000_0000`, M03=`0x1000_2000`, M04=`0x1000_4000`, M05=`0x1000_6000`, M06=`0x1000_8000`, M07=`0x1000_A000` |
| D5 | SB+DMA masters tied off; `RV_LSU2DMA=0` | TB, `defines.h` | Document out of scope; no UVM stimulus |
| D6 | 3 reset styles, 0 synchronizers; UART 2 clocks both tied to `clk` | `soc_top.sv`, `uart_axi_slave.v:261-262` | Reset-sequence tests + CDC assertions |
| D7 | DMEM boundary read at `0x0001_7FFC` → reads past end → real AHB ERROR | `sw/tests/t_bus.c:104-118` | Regression test; expect ERROR |
| D8 | AES 64 KB window aliases into 64 B (`write_addr[5:0]`) | `aes_axi_slave.v:267-268` | Aliasing test (AES-008) |

---

## 3. Existing C Test Framework (Coordination Foundation)

The project already has a mature C test framework that the UVM environment
will build on rather than replace.

### 3.1 Framework structure

- **Linker-driven test discovery**: `TEST_CASE()` macro emits entries into
  `.test_list` section; `test_main.c` walks `__test_list_start` to
  `__test_list_end`. No registry list to maintain.
- **Result table at DMEM**: `test_results_hdr_t` at `RESULTS_BASE`
  (`0x0001_0010`), with per-entry `test_results_ent_t` array. The testbench
  reads this via `u_soc.u_dmem.mem[]` — a backdoor memory read.
- **Serial transcript**: `SUITE_BEGIN` → per-test `T<idx> <name> PASS|FAIL` →
  `SUITE_END ntests=.. npass=.. nfail=..`. The testbench decodes this from
  `uart_tx_o` and cross-checks against the DMEM table.
- **Trap handling**: `startup.S` sets `mtvec` to `trap_handler`; `t_bus.c`
  uses `bus_trap_try()` / `bus_test_resume` for longjmp-style recovery.
- **Mailbox**: `startup.S` writes the Phase-2 PASS signature
  (`P`, `2`, `0xFF` trigger) to DMEM `0x0001_0000` after `main()` returns.

### 3.2 What the C framework already does that UVM must not break

- The DMEM result table is the checked contract between C and SV.
- The serial transcript is the secondary evidence channel.
- The mailbox trigger (`0xFF` at `DMEM[2]`) is the testbench's end-of-test
  signal for the VeeR-flow benches.
- Per-variant monitor thresholds (`+expect_def`, `+expect_buserr`,
  `+min_imem_rd`, etc.) are already plusarg-driven in `sim/Makefile`.

### 3.3 The gap the C-SV handshake service fills

The existing flow has an implicit handshake: the testbench applies reset,
loads IMEM via `$readmemh`, and the CPU starts fetching. The SV monitor is
passive — it watches what the CPU does. There is no explicit "C is ready,
you may now drive stimulus" signal.

This works when the CPU is the *only* master. It breaks when the UVM
environment needs to drive the bus *concurrently* with the CPU (e.g., an
AXI master agent hitting AES while the CPU is idle, or a UART serial agent
injecting RX data while the CPU is polling). Without coordination, the SV
agent might drive before the C side has configured a peripheral, causing
X/Z on the bus or a missed handshake.

---

## 4. Bringup Service

### 4.1 Purpose

The bringup service is a UVM component (`soc_bringup_svc`) that owns the
pre-stimulus initialization of the DUT. It is the first thing that runs in
`run_phase`, and no sequence is allowed to drive the DUT until the bringup
service raises its `READY` flag.

This follows the industry pattern documented in DVCon's "Handling
Asynchronous Resets" paper and the lowRISC DV style guide's recommendation
that "clocks and reset must be generated in SystemVerilog modules,
interfaces, or in the UVM component hierarchy."

### 4.2 Responsibilities

1. **Clock generation**: drive `clk` at the SoC's 100 MHz (10 ns period).
   The existing testbenches use `always #5 core_clk = ~core_clk`.

2. **Reset sequencing across three polarity domains**:
   - `reset_n` (async, active-low) → AHB fabric, IMEM, DMEM, default slave
   - `~reset_n` → `uart_axi_slave.rst` (sync, active-high) → `~rst` →
     `axi_aresetn` (async, active-low)
   - VeeR's `rst_l` / `porst_l` (for `tb_uvm_sys` only)

   The bringup service asserts all domains simultaneously, holds for a
   configurable number of cycles (default 10), then deasserts. It verifies
   all domains are deasserted within 1 clock of each other (CDC assertion,
   defect D6).

3. **Post-reset sanity**: after reset deasserts, the bringup service waits
   a fixed number of cycles (default 5) and then checks:
   - No X on `data_sel` or `hrdata` buses (X-propagation sweep, defect D6)
   - `uart_tx_o == 1` (idle line high)
   - AES `busy_reg == 0`, `done_reg == 0` (reset values, AES-001)
   - UART LSR reset value `0x60` (THRE=1, TEMT=1)

4. **READY signal**: once sanity passes, the bringup service sets a
   `uvm_event` (`bringup_ready`) that all sequences wait on before driving.

### 4.3 Interface

```systemverilog
class soc_bringup_svc extends uvm_component;
  `uvm_component_utils(soc_bringup_svc)

  virtual clk_rst_if  clk_rst_vif;
  uvm_event           bringup_ready;

  // Configuration
  int reset_hold_cycles  = 10;
  int post_reset_cycles  = 5;

  task run_phase(uvm_phase phase);
    phase.raise_objection(this, "bringup");
    apply_reset();
    check_post_reset_sanity();
    bringup_ready.trigger();
    phase.drop_objection(this, "bringup");
  endtask
endclass
```

### 4.4 Reset mid-traffic (INF-003)

The bringup service also provides a `force_reset()` method that sequences
can call to inject a reset mid-traffic (mid-AHB-burst, mid-AXI-beat,
mid-UART-TX, mid-AES-round). After the forced reset, it re-runs the
post-reset sanity and re-triggers `bringup_ready`. This is how INF-003
and NEG-003 are implemented.

---

## 5. C-SV Handshake Service

### 5.1 The problem

When the UVM environment drives stimulus concurrently with C firmware,
the two sides must coordinate:

- **Before C initializes a peripheral**, the SV side must not drive that
  peripheral's registers (or it may overwrite the C-side configuration).
- **Before the SV side injects data** (e.g., UART RX bytes), the C side
  must have enabled the receive path (or the data is lost).
- **After the C side completes a test**, the SV side must read the result
  table before the next test overwrites it.

### 5.2 Industry patterns researched

Three patterns were identified from DVCon papers, Verification Academy, and
chipverify.com:

| Pattern | Mechanism | When to use |
|---|---|---|
| **Shared-memory mailbox** | C writes a magic word to a fixed DMEM address; SV polls the same address via backdoor | Simple, no DPI-C compile needed, works with existing `$readmemh` flow |
| **DPI-C export from SV** | SV exports a function the C side calls at synchronization points | Tighter coupling, requires DPI-C in the firmware link |
| **DPI-C import from C** | C exports a function the SV sequence calls to query C state | SV-driven, requires C function in the simulation binary |

### 5.3 Chosen approach: layered (shared-memory mailbox + optional DPI-C)

The plan uses the shared-memory mailbox as the primary mechanism (it works
with the existing firmware flow, no DPI-C link change needed) and adds
DPI-C as an optional layer for tighter coordination when the C side needs
to push data to the SV side dynamically.

### 5.4 Shared-memory mailbox protocol

**Mailbox location**: DMEM `0x0001_0000` + `0x0100` = `0x0001_0100` (offset
256 from DMEM base, well above the existing result table at `0x0001_0010`
which uses 544 bytes).

**Mailbox layout** (32-bit words):

| Offset | Field | Writer | Meaning |
|---|---|---|---|
| `0x00` | `sv_ready` | SV | `0x5652_4544` ("VRED") = SV bringup done, safe to proceed |
| `0x04` | `c_ready` | C | `0x4352_4544` ("CRED") = C initialization done, safe to drive |
| `0x08` | `test_id` | C | Current test case index (matches `.test_list` index) |
| `0x0C` | `test_cmd` | SV | `0x01` = run next test, `0x02` = inject stimulus, `0x03` = read results |
| `0x10` | `test_status` | C | `0x00` = running, `0x01` = pass, `0x02` = fail, `0x03` = blocked |
| `0x14` | `stimulus_data` | SV | Test-specific data (e.g., byte to inject on UART RX) |
| `0x18` | `stimulus_addr` | SV | Address for targeted stimulus |
| `0x1C` | `result_addr` | C | Address of the result table entry for this test |
| `0x20` | `reserved` | — | Future use |

**Protocol flow**:

```
1. SV bringup service completes → writes 0x56524544 to sv_ready
2. C firmware startup.S completes → writes 0x43524544 to c_ready
3. SV sequence polls c_ready (backdoor read) until it sees 0x43524544
4. SV writes test_cmd = 0x01 (run next test)
5. C reads test_cmd, runs the test, writes test_status
6. SV polls test_status until it is non-zero
7. SV reads the result table at result_addr
8. Loop to step 4 for the next test
```

**C-side implementation** (added to `test_main.c` or a new `sv_mailbox.c`):

```c
#include "soc.h"

#define SV_MBOX_BASE  (DMEM_BASE + 0x0100u)
#define SV_MBOX_SV_READY   (*(volatile uint32_t *)(SV_MBOX_BASE + 0x00))
#define SV_MBOX_C_READY   (*(volatile uint32_t *)(SV_MBOX_BASE + 0x04))
#define SV_MBOX_TEST_ID   (*(volatile uint32_t *)(SV_MBOX_BASE + 0x08))
#define SV_MBOX_TEST_CMD  (*(volatile uint32_t *)(SV_MBOX_BASE + 0x0C))
#define SV_MBOX_TEST_STAT (*(volatile uint32_t *)(SV_MBOX_BASE + 0x10))

#define SV_READY_MAGIC  0x56524544u
#define C_READY_MAGIC   0x43524544u

void sv_handshake_init(void)
{
    /* Wait for SV bringup to complete */
    while (SV_MBOX_SV_READY != SV_READY_MAGIC) { }
    /* Signal C is ready */
    SV_MBOX_C_READY = C_READY_MAGIC;
}

void sv_handshake_wait_cmd(uint32_t cmd)
{
    while (SV_MBOX_TEST_CMD != cmd) { }
}

void sv_handshake_set_status(uint32_t status)
{
    SV_MBOX_TEST_STAT = status;
}
```

**SV-side implementation** (in the UVM sequence):

```systemverilog
class sv_mailbox_seq extends uvm_sequence;
  // Backdoor write to DMEM
  task mbox_write(input int offset, input int data);
    // Uses uvm_config_db to get the soc_top DUT handle
    // Writes to u_dmem.mem[RESULTS_BASE/4 + 0x40 + offset/4]
  endtask

  task mbox_poll(input int offset, input int expected, output int data);
    int timeout = 0;
    do begin
      #10; // 1 clock
      mbox_read(offset, data);
      timeout++;
    end while (data != expected && timeout < 10000);
  endtask
endclass
```

### 5.5 DPI-C layer (optional, Phase 3+)

For tests where the C side needs to push dynamic data to the SV side (e.g.,
"encrypt this specific plaintext"), a DPI-C export is added:

```systemverilog
// Exported from SV to C — C calls this to request stimulus
export "DPI-C" function void sv_dpi_request_stimulus(input int test_id,
                                                      input int data_len);
// Imported from C to SV — SV calls this to deliver stimulus
import "DPI-C" context function int c_dpi_get_test_result(input int test_id);
```

The C side includes a thin DPI shim:

```c
extern void sv_dpi_request_stimulus(int test_id, int data_len);
extern int  c_dpi_get_test_result(int test_id);
```

This is compiled with `-DPI_C` and linked into the VCS binary. The firmware
image itself does not link DPI-C (it runs on the bare-metal core), but the
testbench's C-side companion (a host-side C file compiled by VCS) can use
it to bridge the two worlds.

### 5.6 When the handshake is NOT needed

- **tb_uvm_soc (BFM-driven, no VeeR)**: the bringup service alone suffices.
  No C firmware runs, so no C-SV handshake is needed. The BFM drives all
  stimulus directly.
- **tb_uvm_sys with passive UVM monitors**: when UVM agents are purely
  passive (monitoring, not driving), no handshake is needed because the SV
  side never drives the bus. The C firmware runs, the monitors watch, and
  the scoreboard checks.

The handshake is needed only in **mixed mode**: C firmware runs on VeeR
*and* the UVM environment actively drives some interface (e.g., UART RX
injection, AXI second master).

---

## 6. UVM Hierarchy Design

### 6.1 Directory structure

```
dv/
├── if/
│   ├── ahb_if.sv          # modports: master, slave, monitor (64b AHB-Lite)
│   ├── axi_if.sv          # modports: master, slave, monitor (32b, 8b ID)
│   ├── uart_if.sv         # serial: rx_i, tx_o, baud config
│   └── clk_rst_if.sv      # clk, reset_n + reset sequencing
│
├── agents/
│   ├── ahb/
│   │   ├── ahb_master_agent.sv     # driver+monitor+sequencer (drives ifu_*/lsu_*)
│   │   ├── ahb_slave_agent.sv      # monitor+active responder (imem/dmem/def)
│   │   ├── ahb_seq_item.sv
│   │   ├── ahb_driver.sv
│   │   ├── ahb_monitor.sv
│   │   └── ahb_sequencer.sv
│   ├── axi/
│   │   ├── axi_master_agent.sv    # driver+monitor+seq (drives bridge AXI master)
│   │   ├── axi_slave_agent.sv     # monitor+reg model (uart/aes/dummy)
│   │   ├── axi_seq_item.sv
│   │   ├── axi_driver.sv
│   │   ├── axi_monitor.sv
│   │   └── axi_sequencer.sv
│   ├── uart/
│   │   └── uart_serial_agent.sv   # drives rx_i, monitors tx_o
│   ├── aes/
│   │   └── aes_ref_model_pkg.sv   # pure function FIPS-197 encryptor
│   └── reset/
│       └── reset_ctrl_agent.sv    # porst/rst_l sequencing
│
├── envs/
│   ├── ahb_fabric_env.sv          # fabric + imem/dmem/def agents + scoreboard
│   ├── a2a_bridge_env.sv          # passive AHB monitor + active axi_master + bridge sb
│   ├── uart_periph_env.sv         # axi_slave(uart) + uart_serial + byte model
│   ├── aes_periph_env.sv          # axi_slave(aes) + aes_ref_model
│   └── axi_fabric_env.sv          # 2× axi_master + 8× axi_slave + crossbar sb
│
├── scoreboards/
│   ├── ahb_fabric_sb.sv
│   ├── a2a_bridge_sb.sv
│   ├── axi_fabric_sb.sv
│   ├── uart_sb.sv
│   └── aes_sb.sv
│
├── ref_models/
│   ├── ahb_decode_model.sv        # address decode predictor
│   ├── wstrb_lane_model.sv       # ahb_lanes() WSTRB predictor
│   ├── uart_lsr_model.sv          # LSR semantics predictor
│   └── aes_encrypt_model.sv      # FIPS-197 pure function
│
├── sequences/
│   ├── seq_lib/
│   │   ├── ahb_base_seq.sv
│   │   ├── axi_base_seq.sv
│   │   ├── uart_base_seq.sv
│   │   ├── aes_base_seq.sv
│   │   └── reset_seq.sv
│   ├── directed/                 # one file per test in §8
│   └── random/
│       ├── ahb_random_seq.sv
│       ├── axi_random_seq.sv
│       └── contention_seq.sv
│
├── vseq/                          # virtual sequences
│   ├── vs_fabric_uart_seq.sv
│   ├── vs_fabric_bridge_seq.sv
│   └── vs_soak_seq.sv
│
├── services/
│   ├── soc_bringup_svc.sv         # §4 bringup service
│   ├── sv_mailbox_svc.sv          # §5 C-SV handshake service
│   └── sv_dpi_shim.c              # §5.5 DPI-C layer (compiled by VCS)
│
├── soc_env.sv                     # top env: all 5 sub-envs + cfg + coverage
├── soc_env_pkg.sv
├── soc_cfg.sv                      # cfg object: seed, plusargs, enable flags
├── soc_addr_map_pkg.sv            # Rev B canonical map + decode functions
│
├── tb/
│   ├── tb_uvm_soc.sv              # BFM-driven top (no VeeR)
│   └── tb_uvm_sys.sv              # VeeR + firmware top (nightly gate)
│
└── tests/
    ├── soc_base_test.sv
    └── soc_test_pkg.sv
```

### 6.2 Two testbench tops

| Top | Contents | Purpose | Sim speed |
|---|---|---|---|
| `tb_uvm_soc` | `soc_top` alone. `ahb_master_agent` drives `ifu_*`/`lsu_*` directly. `axi_slave_agent` models UART. `uart_serial_agent` on `uart_tx_o`. | Pure project-RTL DV. No VeeR compile. Full scoreboard. | **Fast** (~30s per test) |
| `tb_uvm_sys` | `veer_wrapper` + `soc_top` + C firmware. UVM agents are passive monitors. One `axi_master_agent` as 2nd initiator. C-SV handshake active. | SoC-level gate: firmware↔RTL contract. Nightly gate. | **Slow** (~10 min per test) |

`tb_uvm_soc` is the workhorse (90% of regression); `tb_uvm_sys` is the
nightly gate (firmware contract proof).

### 6.3 Agent ↔ path coverage

| Path | Agent(s) | Tests |
|---|---|---|
| MP1 (IFU fetch) | `ahb_master_agent` (BFM mode) | FAB-001..014, INT-001 |
| MP2/MP3 (LSU load/store) | `ahb_master_agent` (BFM mode) | FAB-001..014, INT-002 |
| FP1-FP8 (fabric internal) | `ahb_slave_agent` (monitor) | FAB-001..014 |
| UP1-UP5 (bridge + UART AXI) | `axi_master_agent` + `axi_slave_agent` | BRG-001..009, UART-001..016 |
| UP6-UP9 (UART serial) | `uart_serial_agent` | UART-006..011 |
| AP1-AP4 (AES) | `axi_slave_agent` + `aes_ref_model` | AES-001..010 |
| XP1-XP5 (crossbar) | 2× `axi_master_agent` + 8× `axi_slave_agent` | AXI-001..009 |

---

## 7. Deliverable Phases

Each phase has a concrete deliverable, a gate criterion, and a make target.
Phases are ordered by dependency: each builds on the previous.

### Phase 0 — Prerequisite RTL fixes (2 days)

**Deliverable**: RTL changes that unblock UVM integration.

- D2: Re-parameterize AES base to `0x1000_8000` in `aes_axi_slave.v`
- D4: Re-parameterize crossbar M03–M07 to 8 KB pitch in `axi_interconnect_wrap_2x8.v`
- D3: Add `uart_rx_i` port to `soc_top` (or document TX-only for now)
- New `sim/uvm_filelist.f` for UVM compilation
- Add `-ntb_opts uvm-ieee` to VCS flags in `sim/Makefile`

**Gate**: Existing regressions still pass after the base address changes.

**Make target**: `make uv-prep` (runs existing `make sim` to confirm no regression)

### Phase 1 — Infrastructure (4 days)

**Deliverable**: UVM skeleton that compiles, builds, and runs a smoke test.

- `dv/if/` — all four interfaces (`ahb_if`, `axi_if`, `uart_if`, `clk_rst_if`)
- `dv/soc_cfg.sv` — configuration object (seed, plusargs, enable flags)
- `dv/soc_addr_map_pkg.sv` — Rev B canonical map with decode functions
- `dv/services/soc_bringup_svc.sv` — bringup service (§4)
- `dv/services/sv_mailbox_svc.sv` — C-SV handshake service (§5)
- `dv/soc_env.sv` — environment skeleton (empty sub-envs, just the shell)
- `dv/tb/tb_uvm_soc.sv` — testbench top (soc_top + interfaces, no VeeR)
- `dv/tests/soc_base_test.sv` — base test with `run_test()` entry point
- UVM report server: `uvm_report_server` HTML per-layer

**Tests enabled**: INF-001 (smoke), INF-002 (reset sequence), INF-003
(reset mid-traffic), INF-004 (X-propagation sweep)

**Gate**: `make uv-smoke` prints `UVM_RESULT: PASS` and the report server
produces an HTML file with zero errors.

**Make targets**:
- `make uv` — compile UVM env
- `make uv-smoke` — run INF-001..004

### Phase 2 — AHB fabric (4 days)

**Deliverable**: AHB-Lite fabric fully verified with UVM agents.

- `dv/agents/ahb/` — `ahb_master_agent`, `ahb_slave_agent`, sequencer, driver, monitor
- `dv/envs/ahb_fabric_env.sv` — fabric environment with decode model scoreboard
- `dv/scoreboards/ahb_fabric_sb.sv` — expected-vs-observed for address decode, HSEL one-hot, data_sel
- `dv/ref_models/ahb_decode_model.sv` — mirrors `ahb_interconnect.sv:142-144` decode logic
- `dv/ref_models/wstrb_lane_model.sv` — mirrors `ahb_lanes()` in `ahb_to_axi_bridge.sv`

**Tests enabled**: FAB-001 through FAB-014 (14 tests)

**Gate**: `make uv-fabric` — all 14 FAB tests pass, coverage shows 100%
of address-decode bins.

### Phase 3 — AHB→AXI bridge + UART (5 days)

**Deliverable**: Bridge and UART verified with UVM agents.

- `dv/agents/axi/` — `axi_master_agent`, `axi_slave_agent`, sequencer, driver, monitor
- `dv/agents/uart/uart_serial_agent.sv` — serial bit-level agent
- `dv/envs/a2a_bridge_env.sv` — bridge environment
- `dv/envs/uart_periph_env.sv` — UART peripheral environment
- `dv/scoreboards/a2a_bridge_sb.sv` — bridge scoreboard (64-bit split, WSTRB, lane select)
- `dv/scoreboards/uart_sb.sv` — UART scoreboard (byte-level, LSR semantics)
- `dv/ref_models/uart_lsr_model.sv` — LSR predictor (DATA_READY gated by IER0, THRE==TEMT aliasing)
- C-SV handshake service active for `tb_uvm_sys` UART tests

**Tests enabled**: BRG-001..009 (9 tests), UART-001..016 (16 tests)

**Gate**: `make uv-bridge` and `make uv-uart` — all bridge and UART tests pass.

### Phase 4 — AES peripheral (3 days)

**Deliverable**: AES verified with UVM agents and FIPS-197 reference model.

- `dv/agents/aes/aes_ref_model_pkg.sv` — pure function FIPS-197 encryptor
- `dv/envs/aes_periph_env.sv` — AES peripheral environment
- `dv/scoreboards/aes_sb.sv` — AES scoreboard (known-answer, lifecycle, aliasing)
- `dv/ref_models/aes_encrypt_model.sv` — FIPS-197 reference

**Tests enabled**: AES-001..010 (10 tests)

**Gate**: `make uv-aes` — all AES tests pass, FIPS-197 KAT matches
`69c4e0d86a7b0430d8cdb78070b4c55a`.

### Phase 5 — AXI interconnect standalone (3 days)

**Deliverable**: AXI 2×8 crossbar verified standalone.

- `dv/envs/axi_fabric_env.sv` — 2× master + 8× slave + crossbar scoreboard
- `dv/scoreboards/axi_fabric_sb.sv` — routing, strobes, concurrency, DECERR

**Tests enabled**: AXI-001..009 (9 tests)

**Gate**: `make uv-xbar` — all crossbar tests pass with re-parameterized bases.

### Phase 6 — SoC integration + system level (5 days)

**Deliverable**: End-to-end integration tests.

- `dv/vseq/` — virtual sequences (fabric+UART, fabric+bridge, soak)
- `dv/tb/tb_uvm_sys.sv` — VeeR + firmware top
- C-SV handshake service fully active for mixed-mode tests
- `dv/services/sv_dpi_shim.c` — DPI-C layer compiled by VCS

**Tests enabled**: INT-001..007 (7 tests), SYS-001..004 (4 tests)

**Gate**: `make uv-soc` — all integration tests pass.
`make uv-sys` — all system tests pass (nightly gate).

### Phase 7 — Coverage closure + negative tests (2 days)

**Deliverable**: Coverage dashboard + error injection tests.

- Bind SVA modules to RTL
- Coverage merge via `urg`
- HTML coverage dashboard
- NEG-001..005 (5 negative/error injection tests)

**Gate**: `make uv-cov` — coverage report shows 100% of implemented
address-decode bins, all legal HTRANS×HBURST×HSIZE×HWRITE combinations hit.

---

## 8. Testplan

### Layer 0 — Infrastructure (4 tests)

| ID | Test | Checks |
|---|---|---|
| INF-001 | UVM smoke | Env builds, phases execute, report server, 0 errors |
| INF-002 | Reset sequence | 3 polarity domains assert/deassert correctly, converge within 1 clk |
| INF-003 | Reset mid-traffic | Assert reset mid-AHB burst, mid-AXI beat, mid-UART TX; clean restart, no X-prop |
| INF-004 | X-propagation sweep | Force X on addr/ctrl buses at reset; confirm no X escapes into `data_sel`/`hrdata` |

### Layer 1 — AHB-Lite fabric (14 tests)

Maps to existing `tb_ahb_fabric.sv` T1–T14 plus extensions.

| ID | Test |
|---|---|
| FAB-001 | Decode boundaries + first illegal address → ERROR |
| FAB-002 | HSEL one-hot |
| FAB-003 | LSU wins arbitration |
| FAB-004 | IFU wins arbitration |
| FAB-005 | IFU starvation (LSU 100% → IFU never completes; real bug, characterize) |
| FAB-006 | Pipelined back-to-back |
| FAB-007 | Wait-state slave HREADY protocol |
| FAB-008 | Byte/half/word/double lanes |
| FAB-009 | Read-after-write same address |
| FAB-010 | Default slave 2-cycle ERROR |
| FAB-011 | Data-phase ownership `data_sel` |
| FAB-012 | HMASTLOCK/HPROT pass-through |
| FAB-013 | Constrained-random AHB traffic |
| FAB-014 | IMEM/DMEM aliasing (D7: DMEM boundary read at `0x0001_7FFC` → ERROR) |

### Layer 2 — AHB→AXI bridge (9 tests)

| ID | Test |
|---|---|
| BRG-001 | FSM happy path write |
| BRG-002 | FSM happy path read |
| BRG-003 | 64-bit split → merged HRDATA (`{word(addr+4), word(addr)}`) |
| BRG-004 | WSTRB derivation from `ahb_lanes()` |
| BRG-005 | Lane select `HADDR[2]` |
| BRG-006 | AXI ERROR → 2-cycle AHB ERROR (currently unreachable; force for regression) |
| BRG-007 | Back-to-back pipelining |
| BRG-008 | AXI signal legality SVA |
| BRG-009 | Constrained-random bridge stress |

### Layer 3 — UART peripheral (16 tests)

IP-native register map: `0x00` THR/RBR, `0x04` IER, `0x08` BAUD, `0x0C` LCR, `0x14` LSR.

| ID | Test |
|---|---|
| UART-001 | Reset values (LSR=`0x60`, BAUD=868) |
| UART-002 | Register map readback (bypassed vs forwarded) |
| UART-003 | DLAB decode matrix |
| UART-004 | LCR bit-fields (STOP, PARITY, PARITY_MODE) |
| UART-005 | LSR semantics (DATA_READY gated by IER[0]; THRE==TEMT aliasing) |
| UART-006 | Serial TX 8N1 |
| UART-007 | Serial TX parity (even/odd) |
| UART-008 | Serial TX 2 stop bits |
| UART-009 | Baud sweep (divisor ∈ {2, 8, 86, 868, 8680}) |
| UART-010 | FIFO depth 32 + 33rd byte |
| UART-011 | FIFO soft reset (first THR byte NOT dropped — project patch) |
| UART-012 | RX path (requires D3 fix: expose `uart_rx_i`) |
| UART-013 | RX overrun |
| UART-014 | Interrupt at peripheral boundary only (document CPU path broken D1) |
| UART-015 | Constrained-random TX soak |
| UART-016 | Register-access corner cases |

### Layer 4 — AES peripheral (10 tests)

Requires D2 fix first: base = `0x1000_8000`.

| ID | Test |
|---|---|
| AES-001 | Reset values (all 12 data regs `0x0`) |
| AES-002 | Register readback |
| AES-003 | FIPS-197 KAT (key `000102..0f`, pt `001122..ff`, ct `69c4e0d8..c55a`) |
| AES-004 | Lifecycle START/BUSY/DONE (CP13) |
| AES-005 | START-while-BUSY dropped (characterize + assert) |
| AES-006 | CLR_DONE clears DONE+IRQ |
| AES-007 | Byte-strobes (`apply_wstrb`) |
| AES-008 | 64 B aliasing (offsets `0x40..0x3FC` alias `0x00..0x3C`) — D8 |
| AES-009 | 200 random KAT vs pure function |
| AES-010 | IRQ at peripheral boundary |

### Layer 5 — AXI interconnect standalone (9 tests)

M03–M07 re-parameterized to 8 KB pitch.

| ID | Test |
|---|---|
| AXI-001 | Routing all 8 windows from S00/S01 |
| AXI-002 | Byte strobes preserved |
| AXI-003 | 4-beat INCR burst + BID/BRESP |
| AXI-004 | Concurrency (S00→M0 ∥ S01→M1) |
| AXI-005 | Same-target contention (S00∥S01→M02; round-robin fairness) |
| AXI-006 | Unmapped DECERR (RRESP/BRESP=11, RLAST=1) |
| AXI-007 | Channel stability SVA (VALID holds until READY) |
| AXI-008 | Skid buffers (no data loss on W/R output) |
| AXI-009 | Constrained-random multi-master soak |

### Layer 6 — SoC integration (no VeeR, 7 tests)

| ID | Test |
|---|---|
| INT-001 | CPU-BFM → IMEM fetch |
| INT-002 | CPU-BFM → DMEM CRUD |
| INT-003 | CPU-BFM → UART E2E |
| INT-004 | Concurrent IFU fetch + LSU UART access (real contention) |
| INT-005 | Error regions (HRESP=1 unmapped) |
| INT-006 | Mixed masters/slaves soak |
| INT-007 | AXI 2nd initiator simultaneous hits |

### Layer 7 — System level (VeeR + firmware, 4 tests)

| ID | Test |
|---|---|
| SYS-001 | Firmware boot (existing fw0 suite passes under UVM passive monitors) |
| SYS-002 | Passive-monitor cross-check (UVM monitor vs firmware claims) |
| SYS-003 | Interrupt path — BLOCKED on D1 (documented, no RTL change) |
| SYS-004 | Firmware variants (test-suite / memory / bus) |

### Layer 8 — Negative / error injection (5 tests)

| ID | Test |
|---|---|
| NEG-001 | Byte-enable violations (WSTRB=0) |
| NEG-002 | Unmapped-address sweep (all 3 maps: Rev-A, Rev-B canonical, VeeR core-local) |
| NEG-003 | Reset mid-AXI-beat, mid-FIFO-write, mid-AES-round |
| NEG-004 | X-injection on buses |
| NEG-005 | Back-pressure on every AXI channel independently |

---

## 9. Coverage Model

| Covergroup | Target |
|---|---|
| `cg_addr_map` | 100% of implemented regions + guard/error boundaries; cross: region × master × R/W × HSIZE |
| `cg_ahb_ctrl` | 100% legal HTRANS × HBURST × HSIZE × HWRITE |
| `cg_ahb_stall` | Wait-state count 0, 1, 2, 4 |
| `cg_axi_ctrl` | 100% supported AWBURST × AWSIZE × AWLEN × WSTRB |
| `cg_axi_id` | All 2×8 master ID × slave window combinations |
| `cg_uart_cfg` | 100% baud × parity × en × stop × DLAB |
| `cg_uart_serial` | 100% byte value × framing |
| `cg_uart_fifo` | Fill level 0..32 |
| `cg_aes_op` | 100% start-idle/busy/done/cleared |
| `cg_reset` | All reset phase × reset domain combinations |
| `cg_error` | 100% error type × address × master |
| `cg_cdc` | 100% reset style transitions |

Coverage is sampled in the monitor's `run_phase` loop and reported via
`uvm_report_server` HTML per layer. VCS `urg` merges all layers into a
single HTML dashboard.

---

## 10. Assertion Plan

### AHB-Lite (fabric + bridge)

- HSEL one-hot when `HTRANS≠IDLE`; low when IDLE
- Address-phase stability while `HREADY=0`
- ERROR exactly 2 cycles (default slave)
- Non-owner `HREADY=0` while data owned by other
- `data_sel ∈ {3'b000..3'b100}`
- IFU completion bounded when LSU is continuous (starvation characterization)

### AXI4 (bridge + uart_axi_slave + aes_axi_slave + crossbar)

- `AWVALID`/`AWREADY` no deadlock; payload stable while `AWVALID && !AWREADY`
- `WLAST` = beat `AWLEN`
- `BVALID` after `WVALID && WREADY && WLAST`
- `RVALID` after `ARVALID && ARREADY`; `RLAST` correct
- `WSTRB` = `ahb_lanes(HSIZE, HADDR)` at the bridge
- `ARSIZE` derived from `HSIZE`
- `RRESP`/`BRESP ∈ {OKAY, SLVERR, DECERR}`

### UART

- `LSR[6] == LSR[5]` (THRE==TEMT aliasing, lock current behavior)
- `uart_tx_o == 1` when idle
- FIFO ≤ 32
- `DATA_READY → uart_irq_o` iff `IER[0]`

### AES

- `BUSY`/`DONE` never both 0 after start
- `DONE` pulses only after `START`
- `RESULT` stable while `BUSY`

### Reset / CDC

- No X on `data_sel`/`hrdata`/AXI payload after reset deasserts
- All 3 reset domains deassert within 1 clk of each other

---

## 11. Build Integration

### 11.1 Make targets (added to `sim/Makefile`)

```makefile
# UVM targets (sibling to existing make sim)
UV_WORK  := $(REPO)/build/uvm
UV_FLAGS := -full64 -sverilog -debug_access+all -kdb \
            -ntb_opts uvm-ieee +define+RV_OPENSOURCE \
            -timescale=1ns/10ps

.PHONY: uv uv-smoke uv-fabric uv-bridge uv-uart uv-aes uv-xbar uv-soc uv-sys uv-cov

uv:
	@mkdir -p $(UV_WORK)
	cd $(UV_WORK) && vcs $(UV_FLAGS) -f $(REPO)/sim/uvm_filelist.f -l compile_uvm.log

uv-smoke: uv
	cd $(UV_WORK) && ./simv +UVM_TESTNAME=inf_smoke_test -l sim_smoke.log
	@grep -q "UVM_RESULT: PASS" $(UV_WORK)/sim_smoke.log || { echo "FAIL"; exit 1; }

uv-fabric: uv
	cd $(UV_WORK) && ./simv +UVM_TESTNAME=fab_all_tests -l sim_fabric.log
	@grep -q "UVM_RESULT: PASS" $(UV_WORK)/sim_fabric.log || { echo "FAIL"; exit 1; }

# ... (similar for each layer)

uv-cov:
	urg -dir $(UV_WORK)/*.vcd -report $(UV_WORK)/html
	@echo "Coverage dashboard: $(UV_WORK)/html/index.html"
```

### 11.2 Filelist (`sim/uvm_filelist.f`)

```text
+incdir+$FW_PROJ/dv
+incdir+$FW_PROJ/dv/agents/ahb
+incdir+$FW_PROJ/dv/agents/axi
+incdir+$FW_PROJ/dv/agents/uart
+incdir+$FW_PROJ/dv/agents/aes

// UVM library (VCS provides this with -ntb_opts uvm-ieee)

// Project RTL (same as sim/filelist.f, minus VeeR and testbench)
$FW_PROJ/rtl/ahb/ahb_interconnect.sv
$FW_PROJ/rtl/ahb/ahb_sram.sv
$FW_PROJ/rtl/ahb/ahb_default_slave.sv
$FW_PROJ/rtl/ahb/ahb_to_axi_bridge.sv
$FW_PROJ/rtl/soc_top.sv
-f $FW_PROJ/run/uart_rtl.f
$FW_PROJ/rtl/aes/aes_axi_slave.v
$FW_PROJ/rtl/aes/ip/aes_cipher_top.v
$FW_PROJ/rtl/aes/ip/aes_key_expand_128.v
$FW_PROJ/rtl/aes/ip/aes_sbox.v
$FW_PROJ/rtl/aes/ip/aes_rcon.v
$FW_PROJ/rtl/interconnects/axi_interconnect_wrap_2x8.v
$FW_PROJ/rtl/interconnects/axi_interconnect.v
$FW_PROJ/rtl/interconnects/arbiter.v
$FW_PROJ/rtl/interconnects/priority_encoder.v

// UVM DV code
$FW_PROJ/dv/soc_env_pkg.sv
$FW_PROJ/dv/tb/tb_uvm_soc.sv

-top tb_uvm_soc
```

### 11.3 `tb_uvm_sys` filelist (Phase 6)

Adds VeeR wrapper + firmware image, same as `sim/filelist.f` but with
`tb_uvm_sys.sv` as top and the UVM packages.

---

## 12. Relationship to Existing Work

### What does NOT change

- All existing directed testbenches in `tb/` remain unchanged and continue
  to pass. They are the frozen regression baseline.
- `sim/Makefile` and the `make sim` flow are unchanged.
- The C test framework (`test.h`, `test_main.c`, `memtest_core.c`,
  `t_bus.c`, `startup.S`) is unchanged.
- `run/*.csh` flow scripts are unchanged.

### What is added

- `dv/` directory tree (all UVM code)
- `sim/uvm_filelist.f` (UVM compilation filelist)
- `make uv-*` targets in `sim/Makefile`
- Optional: `sw/src/sv_mailbox.c` (C-side handshake shim, linked only when
  `-DSV_HANDSHAKE` is defined)

### What changes (Phase 0 only)

- `rtl/aes/aes_axi_slave.v`: `AES_BASE` from `0x1000_4000` to `0x1000_8000`
- `rtl/interconnects/axi_interconnect_wrap_2x8.v`: M03–M07 re-parameterized
- `sw/include/soc.h`: `AES_BASE` updated to `0x1000_8000`
- `rtl/soc_top.sv`: optionally add `uart_rx_i` port (D3)

---

## 13. Industry References

This plan draws on the following industry sources, researched for this
document:

1. **DVCon: "UVM and C Tests — Perfect Together"** — DPI-C as the bridge
   between UVM sequences and C tests. Pattern: C test writes to shared
   memory, SV sequence polls via backdoor.

2. **Verification Academy: "Having Your Cake and Eating It Too:
   Programming UVM Sequences with DPI-C"** (Rich Edelman, Siemens EDA) —
   API-based approach: SV interface tasks (`read()`, `write()`) called from
   C via DPI-C. Reuse of pre-existing C verification environments.

3. **chipverify.com: "Co-ordinating C Tests with SystemVerilog Sequences"**
   — Spin-loop mailbox: C writes a done flag to a fixed address; SV
   repeatedly reads until it sees the expected value. Two implementation
   variants: backdoor memory read vs. bus-mediated read.

4. **lowRISC DV Coding Style Guide** — Agent/env/scoreboard/sequence
   conventions, `uvm_config_db` usage, factory registration, objection
   management, `DV_CHECK_*` macros, directory structure, DPI-C naming
   (`sv_dpi_` prefix for exports, `c_dpi_` prefix for imports).

5. **DVCon: "Handling Asynchronous Resets"** — Building reset awareness
   into UVM testbench components: `phase_ready_to_end()`, watchdog timers,
   multi-domain reset coordination.

6. **UVM User's Guide 1.2 (Accellera)** — Phasing (`build_phase` →
   `run_phase` → `report_phase`), `run_test()` without test name argument,
   `+UVM_TESTNAME` override, `uvm_report_server`.

7. **DVCon: "UVM Dos and Don'ts for Effective Verification"** — Avoid
   `uvm_do` macros, use `start_item`/`finish_item`, keep sequences generic,
   use `uvm_tlm_analysis_fifo` in scoreboards.

---

## 14. Summary

This plan takes the project's existing directed-testbench regression and
defines a path to a layered UVM environment that:

- **Preserves** the existing C test framework and directed benches as the
  frozen baseline.
- **Adds** a bringup service that owns clock/reset/sanity, ensuring no
  stimulus runs before the DUT is in a known state.
- **Adds** a C-SV handshake service that coordinates firmware and UVM
  sequences via shared-memory mailbox, preventing X/Z propagation from
  uncoordinated bus access.
- **Migrates** IP by IP (fabric → bridge/UART → AES → crossbar → SoC →
  system), with each phase gated on a concrete PASS criterion.
- **Follows** industry conventions from lowRISC, DVCon, and Verification
  Academy for agent structure, factory usage, coverage, and assertions.

The first deliverable is Phase 0 (RTL prerequisite fixes, 2 days), which
unblocks all subsequent UVM work without breaking any existing regression.
