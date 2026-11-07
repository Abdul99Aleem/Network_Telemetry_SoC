# UVM VIP Interface Analysis
## RISC-V Network Telemetry SoC

**Document status:** Active  
**Last updated:** 2026-10-31  
**Author:** Abdul Aleem  
**RTL reference:** `rtl/soc_top.sv` (frozen architecture v3)

---

## 1. Purpose

This document records which interfaces of `soc_top` are external (cross the
chip boundary and therefore need a UVM VIP) versus internal (wires between
submodules that are invisible to the testbench and do not need a VIP).

The analysis drives two decisions:

1. **Which signal CSVs to feed into `scripts/uvm_full_tb_generator.py`** —
   only external interfaces get a VIP.
2. **What the UVM top-level testbench connects to** — only external ports are
   accessible from outside `soc_top`.

---

## 2. `soc_top` Module Boundary

`soc_top` is the chip-level module. Its port list, taken directly from
`rtl/soc_top.sv`, is:

```systemverilog
module soc_top #(
    parameter IMEM_HEX = "",
    parameter DMEM_HEX = ""
) (
    input  wire        clk,
    input  wire        reset_n,

    // VeeR IFU AHB-Lite master
    input  wire [31:0] ifu_haddr,
    input  wire [2:0]  ifu_hburst,
    input  wire        ifu_hmastlock,
    input  wire [3:0]  ifu_hprot,
    input  wire [2:0]  ifu_hsize,
    input  wire [1:0]  ifu_htrans,
    input  wire        ifu_hwrite,
    output wire [63:0] ifu_hrdata,
    output wire        ifu_hready,
    output wire        ifu_hresp,

    // VeeR LSU AHB-Lite master
    input  wire [31:0] lsu_haddr,
    input  wire [2:0]  lsu_hburst,
    input  wire        lsu_hmastlock,
    input  wire [3:0]  lsu_hprot,
    input  wire [2:0]  lsu_hsize,
    input  wire [1:0]  lsu_htrans,
    input  wire        lsu_hwrite,
    input  wire [63:0] lsu_hwdata,
    output wire [63:0] lsu_hrdata,
    output wire        lsu_hready,
    output wire        lsu_hresp,

    // Physical UART pins
    output wire        uart_tx_o,
    output wire        uart_irq_o
);
```

Total external signals: **25** (clk + reset_n + 10 IFU + 11 LSU + 2 UART).

---

## 3. Internal Data Paths (Not External — No VIP Needed)

The following bus segments exist entirely inside `soc_top`. They are declared
as local `wire` nets and never appear on the module boundary. A UVM VIP
targeting any of these buses would have nothing to connect to from outside
the DUT.

### 3.1 AHB Fabric → Slave Wires

The `ahb_interconnect` routes IFU/LSU transactions to four slaves. Each
slave's AHB port is an internal wire bundle:

| Slave | Signal prefix | Address range |
|---|---|---|
| IMEM | `imem_hsel`, `imem_haddr`, `imem_h*`, `imem_hrdata`, `imem_hreadyout`, `imem_hresp` | `0x0000_0000–0x0000_7FFF` (32 KB) |
| DMEM | `dmem_hsel`, `dmem_haddr`, `dmem_h*`, `dmem_hrdata`, `dmem_hreadyout`, `dmem_hresp` | `0x0001_0000–0x0001_7FFF` (32 KB) |
| Default/ERROR | `def_hsel`, `def_haddr`, `def_h*`, `def_hrdata`, `def_hreadyout`, `def_hresp` | all unmapped regions |
| UART (to bridge) | `uart_hsel`, `uart_haddr`, `uart_h*`, `uart_hrdata`, `uart_hreadyout`, `uart_hresp` | `0x1000_0000–0x1000_0FFF` (4 KB) |

All of these are `wire` declarations inside the `module soc_top` body.
They are never exposed as ports.

### 3.2 AHB→AXI Bridge → UART Slave AXI Wires

Between `u_ahb2axi` (the `ahb_to_axi_bridge`) and `u_uart` (the
`uart_axi_slave`) there is a full AXI4 interconnect — also declared as
local `wire` nets inside `soc_top`:

```
awid, awaddr, awlen, awsize, awburst, awlock, awcache, awprot, awqos,
awuser, awvalid, awready,
wdata, wstrb, wlast, wuser, wvalid, wready,
bid, bresp, buser, bvalid, bready,
arid, araddr, arlen, arsize, arburst, arlock, arcache, arprot, arqos,
aruser, arvalid, arready,
rid, rdata, rresp, rlast, ruser, rvalid, rready
```

These 37 AXI wires are 100% internal. They carry the translated UART
register accesses from the bridge to the UART slave. They are not chip
boundary signals.

### 3.3 Summary: Why These Were Wrong Before

The first generator run produced three VIPs:

| VIP generated | Signals used | Why wrong |
|---|---|---|
| `axi_uvm_tb` | `aes_axi_slave` full AXI4 port | `aes_axi_slave` is not in `soc_top` at all (AES is not yet wired). Even when it is, its AXI port will be internal. |
| `ahb_uvm_tb` | `ahb_interconnect` full port | Includes all four slave ports which are internal wires. The `ifu_*` and `lsu_*` master ports overlap with external pins but the full fabric port list is not the chip boundary. |
| `uart_uvm_tb` | `uart_axi_slave` AXI port | Internal AXI wires between bridge and UART IP — not reachable from outside `soc_top`. |

None of these interfaces can be driven or observed from a testbench that
instantiates `soc_top` as its DUT.

---

## 4. External Interfaces (VIPs Generated)

Two interfaces cross the `soc_top` boundary and require UVM VIPs.

### 4.1 VeeR AHB-Lite Master Interface (`veer_ahb`)

**What it is:** The IFU (instruction fetch) and LSU (load/store) AHB-Lite
master ports from the VeeR EL2 core. In the current SoC (`soc_top`), VeeR
is instantiated *outside* `soc_top` — it drives the IFU/LSU ports into the
chip. The testbench must therefore either instantiate VeeR separately and
wire it in, or use a VIP acting as an AHB-Lite master stimulus generator in
VeeR's place.

**Direction (from testbench perspective):**  
- Testbench drives: all `ifu_h*` inputs + all `lsu_h*` inputs  
- Testbench observes: `ifu_hrdata`, `ifu_hready`, `ifu_hresp`, `lsu_hrdata`, `lsu_hready`, `lsu_hresp`

**Signal count:** 23 (clk + reset_n + 10 IFU + 11 LSU)

**CSV:** `scripts/veer_ahb_signals.csv`

**Generated VIP:** `tb/veer_ahb_uvm_tb/`

| File | Role |
|---|---|
| `veer_ahb_if.sv` | SystemVerilog interface: all 23 signals as `logic` |
| `veer_ahb_item.sv` | `uvm_sequence_item`: rand fields for all input signals (clk/reset excluded) |
| `veer_ahb_sequencer.sv` | `uvm_sequencer` parameterised on `veer_ahb_item` |
| `veer_ahb_driver.sv` | `uvm_driver`: drives items onto `veer_ahb_if`, clocked on `posedge clk` |
| `veer_ahb_monitor.sv` | `uvm_monitor`: observes interface, broadcasts via analysis port |
| `veer_ahb_agent.sv` | `uvm_agent`: composes driver + monitor + sequencer, wire connect |
| `veer_ahb_scoreboard.sv` | `uvm_scoreboard`: skeleton — extend with AHB address/data checkers |
| `veer_ahb_env.sv` | `uvm_env`: top environment with agent + scoreboard |
| `veer_ahb_test.sv` | `uvm_test`: entry point, builds env, called by `run_test()` |
| `veer_ahb_pkg.sv` | Package: includes all above files in compilation order |
| `tb_top.sv` | Top-level module: instantiates interface, calls `run_test()` |

**Protocol notes (for driver completion):**
- AHB-Lite is pipelined: address phase and data phase are offset by one cycle.
- IFU port is read-only (HWRITE is always 0 from the fetch unit); LSU can read or write.
- VeeR uses 64-bit data (`HRDATA[63:0]`); the fabric returns the full 64-bit word.
- `HTRANS`: `2'b00` = IDLE, `2'b10` = NONSEQ (new transfer), `2'b11` = SEQ.
- The driver must hold `HWDATA` stable for the data phase cycle after the address phase.

### 4.2 UART Serial Interface (`uart_serial`)

**What it is:** The physical serial UART TX output and interrupt output that
leave the chip. These are the only UART-related signals on the `soc_top`
boundary. The testbench monitors `uart_tx_o` to decode bytes and checks
`uart_irq_o` for expected interrupt state (zero in TX-only operation).

**Direction (from testbench perspective):**  
- Testbench drives: `clk`, `reset_n` (clock and reset only)  
- Testbench observes: `uart_tx_o` (serial bitstream, 8N1), `uart_irq_o` (expected 0)

**Signal count:** 4 (clk + reset_n + uart_tx_o + uart_irq_o)

**CSV:** `scripts/uart_serial_signals.csv`

**Generated VIP:** `tb/uart_serial_uvm_tb/`

| File | Role |
|---|---|
| `uart_serial_if.sv` | SystemVerilog interface: 4 signals as `logic` |
| `uart_serial_item.sv` | `uvm_sequence_item`: decoded UART byte, parity, framing fields |
| `uart_serial_sequencer.sv` | `uvm_sequencer` — minimal (RX-side agent is passive; no driving needed) |
| `uart_serial_driver.sv` | `uvm_driver`: skeleton — UART TX is output-only from DUT; driver is unused in passive monitor-only configuration |
| `uart_serial_monitor.sv` | `uvm_monitor`: **the key component** — samples `uart_tx_o` bit-by-bit, reconstructs 8N1 frame, broadcasts `uart_serial_item` via analysis port |
| `uart_serial_agent.sv` | `uvm_agent`: composes monitor (passive); driver inactive for RX-only use |
| `uart_serial_scoreboard.sv` | `uvm_scoreboard`: skeleton — extend to compare decoded bytes against expected UART\n sequence |
| `uart_serial_env.sv` | `uvm_env`: top environment with agent + scoreboard |
| `uart_serial_test.sv` | `uvm_test`: entry point |
| `uart_serial_pkg.sv` | Package: includes all above files |
| `tb_top.sv` | Top-level module |

**Protocol notes (for monitor completion):**
- UART format: 8N1 (8 data bits, no parity, 1 stop bit) at baud divisor set in firmware.
- Baud period = 8690 ns (869 clock cycles at 10 ns/cycle) as measured in Phase 3.
- The monitor should auto-calibrate the bit period from the first start-bit falling edge.
- Frame structure: 1 start bit (low) + 8 data bits (LSB first) + 1 stop bit (high).
- `uart_irq_o` should remain 0 throughout TX-only operation (Phase 3 verified).

---

## 5. Interface vs. Data Path Map

```
                        ┌─────────────────────────────────────────────────────┐
                        │                    soc_top                          │
  ┌──────────────────┐  │                                                     │
  │  VeeR AHB VIP   │  │  ahb_interconnect                                  │
  │  (veer_ahb)     │◄─┼─► ifu_h* ◄────────── [EXTERNAL: chip boundary]    │
  │                 │  │  lsu_h* ◄────────── [EXTERNAL: chip boundary]      │
  └──────────────────┘  │      │                                             │
          ↑             │      │  INTERNAL fabric wires (not accessible):    │
     EXTERNAL           │      ├──► imem_h*  → ahb_sram (IMEM)              │
     boundary           │      ├──► dmem_h*  → ahb_sram (DMEM)              │
                        │      ├──► def_h*   → ahb_default_slave            │
                        │      └──► uart_h*  → ahb_to_axi_bridge            │
                        │                           │                        │
                        │                  INTERNAL AXI wires:              │
                        │                  awid/awaddr/.../rdata/rlast/...  │
                        │                           │                        │
                        │                    uart_axi_slave                 │
                        │                           │                        │
  ┌──────────────────┐  │                    uart_tx_o ───────────────────► │
  │  UART Serial VIP │◄─┼─────────────────── [EXTERNAL: chip boundary]      │
  │  (uart_serial)  │  │                    uart_irq_o ──────────────────► │
  └──────────────────┘  └─────────────────────────────────────────────────────┘
```

**Legend:**  
- `[EXTERNAL]` — crosses chip boundary → VIP required  
- `INTERNAL` — local wire inside `soc_top` → no VIP, not accessible

---

## 6. Files Created / Deleted

### Deleted (incorrect, internal-bus VIPs)

| Path | Reason for deletion |
|---|---|
| `scripts/axi_signals.csv` + `scripts/axi_uvm_tb/` | Targeted `aes_axi_slave` AXI port — internal wire, AES not in soc_top |
| `scripts/ahb_signals.csv` + `scripts/ahb_uvm_tb/` | Targeted full `ahb_interconnect` port including internal slave wires |
| `scripts/uart_signals.csv` + `scripts/uart_uvm_tb/` | Targeted `uart_axi_slave` AXI port — internal bridge↔UART wire |
| `tb/axi_uvm_tb/` | Same as above (copy in tb/) |
| `tb/ahb_uvm_tb/` | Same as above |
| `tb/uart_uvm_tb/` | Same as above |

### Created (correct, external-interface VIPs)

| Path | Content |
|---|---|
| `scripts/veer_ahb_signals.csv` | 23 signals: clk, reset_n, IFU[10], LSU[11] |
| `scripts/uart_serial_signals.csv` | 4 signals: clk, reset_n, uart_tx_o, uart_irq_o |
| `tb/veer_ahb_uvm_tb/` | 11-file UVM skeleton for IFU+LSU AHB-Lite master interface |
| `tb/uart_serial_uvm_tb/` | 11-file UVM skeleton for UART physical pin interface |

---

## 7. Next Steps (UVM Environment Completion)

The generated files are skeletons. The following completions are required
before simulation:

### 7.1 `veer_ahb` driver — AHB-Lite protocol

```systemverilog
// In veer_ahb_driver.sv run_phase — replace skeleton with:
task run_phase(uvm_phase phase);
  forever begin
    seq_item_port.get_next_item(req);
    // Address phase
    @(posedge vif.clk);
    vif.ifu_htrans  <= req.ifu_htrans;
    vif.ifu_haddr   <= req.ifu_haddr;
    vif.ifu_hsize   <= req.ifu_hsize;
    // ... all IFU + LSU signals
    // Data phase (next cycle)
    @(posedge vif.clk);
    vif.lsu_hwdata  <= req.lsu_hwdata;
    // Wait for HREADY
    wait(vif.lsu_hready);
    seq_item_port.item_done();
  end
endtask
```

### 7.2 `uart_serial` monitor — 8N1 frame decoder

```systemverilog
// In uart_serial_monitor.sv run_phase — replace skeleton with:
task run_phase(uvm_phase phase);
  uart_serial_item tr;
  int bit_period;
  forever begin
    // Detect start bit (falling edge on uart_tx_o)
    @(negedge vif.uart_tx_o);
    // Auto-calibrate: measure half-bit then sample at centre
    #(bit_period / 2);
    // Sample 8 data bits, LSB first
    for (int i = 0; i < 8; i++) begin
      #bit_period;
      tr.data[i] = vif.uart_tx_o;
    end
    // Consume stop bit
    #bit_period;
    ap.write(tr);
  end
endtask
```

### 7.3 Scoreboard connections

- `veer_ahb_scoreboard`: connect monitor analysis port → expected address/data checker. Use the DMEM mailbox pattern from `tb_veer_p2_soc.sv` as a reference.
- `uart_serial_scoreboard`: connect monitor analysis port → expected byte-sequence checker. Expected sequence for Phase 3: `0x55 0x41 0x52 0x54 0x0a` ("UART\n").

### 7.4 `tb_top.sv` — connect to DUT

Each generated `tb_top.sv` only instantiates the interface and calls
`run_test()`. Add the DUT instantiation and clocking block:

```systemverilog
// veer_ahb_uvm_tb/tb_top.sv additions:
soc_top #(.IMEM_HEX("imem.mem"), .DMEM_HEX("dmem.mem")) u_dut (
    .clk         (vif.clk),
    .reset_n     (vif.reset_n),
    .ifu_haddr   (vif.ifu_haddr),
    // ... all 23 ports
);
```

### 7.5 `uvm_config_db` wiring

```systemverilog
// In tb_top.sv initial block before run_test():
uvm_config_db #(virtual veer_ahb_if)::set(null, "uvm_test_top.*", "vif", vif);
uvm_config_db #(virtual uart_serial_if)::set(null, "uvm_test_top.*", "vif", uart_vif);
```

And in each agent's `build_phase`:

```systemverilog
if (!uvm_config_db#(virtual veer_ahb_if)::get(this, "", "vif", vif))
    `uvm_fatal("NOVIF", "veer_ahb_if not found in config_db")
```

---

## 8. Reference

| RTL file | Role in data path |
|---|---|
| `rtl/soc_top.sv` | Chip top; defines the external boundary |
| `rtl/ahb/ahb_interconnect.sv` | AHB-Lite 2-master × 4-slave fabric (internal) |
| `rtl/ahb/ahb_sram.sv` | IMEM / DMEM slaves (internal) |
| `rtl/ahb/ahb_to_axi_bridge.sv` | AHB-Lite → AXI4 bridge (internal) |
| `rtl/ahb/ahb_default_slave.sv` | ERROR response slave (internal) |
| `rtl/uart/uart_axi_slave.v` | UART AXI slave wrapper (internal) |
| `rtl/uart/ip/` | Vendored UART IP (internal) |
| `scripts/veer_ahb_signals.csv` | Signal list for veer_ahb VIP |
| `scripts/uart_serial_signals.csv` | Signal list for uart_serial VIP |
| `scripts/uvm_full_tb_generator.py` | Generator script |
| `tb/veer_ahb_uvm_tb/` | Generated VIP — AHB-Lite external interface |
| `tb/uart_serial_uvm_tb/` | Generated VIP — UART physical pin interface |
