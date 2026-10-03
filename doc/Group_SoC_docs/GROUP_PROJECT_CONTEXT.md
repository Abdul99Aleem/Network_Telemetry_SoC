# Group Project Context — Secure Network Telemetry SoC

**Purpose:** a single, self-contained handover document for the group project
repository. It records what the project *is*, what has actually been *built and
verified*, what is only *planned*, and exactly how to rebuild and rerun
everything — so that a new member can pick it up without access to the original
author's shell history.

**Compiled:** 2026-10-03
**Derived from:** `Network_Telemetry_SoC` @ `main` (25 commits, HEAD `15a7c1e`)
**Upstream remote:** <https://github.com/Abdul99Aleem/Network_Telemetry_SoC.git>

---

## How to read this document

Every claim below is tagged so that intent is never confused with reality:

| Tag | Meaning |
|---|---|
| **[DONE]** | Implemented in RTL/firmware **and** proven by a simulation log with a pass token |
| **[PARTIAL]** | Written and simulated in isolation, **not** attached to the SoC top |
| **[DESIGN]** | Specified in the frozen architecture / plan, **no RTL yet** |
| **[BROKEN]** | Was working, but does **not** run in the current environment — must be repaired |
| **[TODO]** | Known deviation, open question, or outstanding amendment |

Read §16 (Known mismatches and open items) before writing any RTL. It is the
single highest-value section in this file.

---

## 1. Project vision

An edge SoC that inspects network traffic **in hardware**, assembles a 128-bit
telemetry record, encrypts it with a hardware AES-128 engine, and reports it
over UART — all driven by a RISC-V core.

The motivation is local accountability: edge devices must characterise their own
traffic instead of shipping raw packets to a central analyser that may be slow,
down, or untrusted. The interesting part is the **division of labour**:

- **Hardware** does the repetitive, timing-critical work — byte-by-byte packet
  parsing, CRC32 integrity checking, AES-128 encryption.
- **The RISC-V core** does the judgement work — configuration, interrupt
  handling, telemetry record assembly, crypto job submission, reporting.

### 1.1 Definition of done

One end-to-end scenario proven by one system-level testbench:

```text
  testbench streams Ethernet frames (8-bit pkt_valid/pkt_data/pkt_last)
        │
        ▼
  Network Telemetry Engine ── parses headers, counts packets/bytes/errors,
        │                      captures addrs/ports/length, stamps timestamp
        ├── CRC32 ──────────── integrity/FCS check running concurrently
        │
        ▼  packet-complete interrupt
  VeeR EL2 (RV32IMC, AHB-Lite)
        │  reads hardware-captured fields over MMIO
        │  assembles the 128-bit telemetry record in software
        ▼
  AES-128 accelerator ────── encrypts the record (interrupt-driven completion)
        │
        ▼
  UART (TX) ──────────────── reports packet stats + CRC status + ciphertext
```

**Status: [DESIGN]** — this final demo does not exist yet. Everything currently
in the repository is groundwork for it: a booted CPU, a working system bus, two
accelerators proven in isolation, and the first peripheral wired onto the SoC.

---

## 2. State of this repository right now

```text
doc/Group_SoC_docs/
├── GROUP_PROJECT_CONTEXT.md          # this file
├── SoC_Address_Map.xlsx              # canonical address map (8 sheets)
├── Block_diagram.png                 # system block diagram
├── Network_Telemetry_SoC_Address_Map.xlsx   # detailed Rev B workbook (10 sheets)
└── RISC_V_Secure_Network_Telemetry_SoC_Initial_Project_Plan.md   # group plan
```

**The group repository contains design documents only. It contains no RTL, no
firmware, no testbenches and no build system yet.** Everything in §4–§13
describes the *source* repository that the RTL must be migrated from.

> **Note [TODO]:** the folder currently holds **four** artefacts, not two — the
> clean address map, the block diagram, the detailed Rev B workbook, and the
> group project plan. Decide which are canonical before the first commit.

### 2.1 What has to be migrated, and in what order

The source repository is a working, self-contained Git project. Migration is a
**copy**, not a rewrite — but it must be done in dependency order because the
firmware, the VeeR snapshot and the simulation filelist all reference paths and
addresses that the new design changes.

| Order | What | Why it must come in this order |
|---|---|---|
| 1 | `rtl/ahb/`, `rtl/interconnects/` | Everything else hangs off the AHB fabric and the AXI 2×8 fabric |
| 2 | `rtl/uart/` + `rtl/aes/` | The two implemented AXI slaves; both need base-address reparameterisation (§7.3) |
| 3 | `rtl/soc_top.sv` | Needs the new decode (guard windows) before any new peripheral is added |
| 4 | `core/Cores-VeeR-EL2` submodule | Must be initialised before any simulation can elaborate |
| 5 | `tb/` | Benches encode addresses and pass tokens |
| 6 | `sw/` | `soc.h` and `veer.ld` hard-code the memory map; both need updating first |
| 7 | `sim/`, `run/`, `Makefile` | Contains hard-coded absolute paths that break on relocation (§15) |
| 8 | `scripts/`, `doc/` | Generators and evidence records |

---

## 3. Architecture

### 3.1 Two-plane split

The design is deliberately split into a **control plane** and a **data plane**.
This is the central architectural decision and everything else follows from it.

**Control plane [DONE as infrastructure]**

```text
  VeeR EL2 (RV32IMC, AHB-Lite)
        │  MMIO reads/writes, interrupt-driven
        ▼
  AHB-Lite fabric  ──►  AHB→AXI bridge  ──►  AXI 2×8 interconnect  ──►  slaves
```

The CPU never touches packet bytes. It reads *already-captured* hardware fields
over MMIO and issues control writes.

**Data plane [DESIGN]**

```text
  pkt_valid/pkt_data/pkt_last
        │
        ▼
  Ethernet MAC ──► Timestamp ──► Parser/Classifier ──► NTE
                                       │                │
                                       ▼                ▼
                                    CRC32          Packet/Flow Buffer
                                                            │
                                                            ▼
                                                     DMA Controller
```

The data plane moves bytes; the control plane configures it and harvests its
results.

### 3.2 Top-level external ports

From the frozen architecture §2.1. No physical Ethernet interface is exposed —
frames arrive over a byte-wide streaming interface from a testbench or an
upstream MAC.

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk` | in | 1 | Main synchronous SoC clock |
| `reset_n` | in | 1 | Active-low functional reset |
| `pkt_valid` | in | 1 | `pkt_data` is a valid byte this cycle |
| `pkt_data` | in | 8 | Incoming Ethernet frame byte |
| `pkt_last` | in | 1 | Final valid byte of the current frame |
| `uart_tx` | out | 1 | UART transmit (TX-only by design) |
| `gpio[3:0]` | out | 4 | Hardware-visible status outputs |

GPIO semantics: `gpio[0]` = `CPU_ALIVE`, `gpio[1]` = `PKT_RX`,
`gpio[2]` = `AES_BUSY`, `gpio[3]` = `PKT_ERR`.

### 3.3 Clock and reset

- Single `clk` domain **[DONE]**. VeeR's internal `core_clk` is generated in the
  testbench by `always #5` (10 ns period).
- `reset_n` active-low feeds the fabric, SRAMs, bridge and UART wrapper **[DONE]**.
- The VeeR `veer_wrapper` additionally drives `rst_l` and `porst_l`; the
  testbench ties `nmi_int` low and `sb_hsel`/`dma_hsel` inactive because the
  debug and DMA masters are unused **[DONE]**.

---

## 4. CPU core

| Property | Value |
|---|---|
| Core | **VeeR EL2**, RV32IMC |
| Upstream | `chipsalliance/Cores-VeeR-EL2` |
| Licence | Apache-2.0 |
| Integration | Git submodule — **wrapped, never forked** |
| Pinned commit | `06ad26aa8951d0f91068d19d106ed97f8f8ed257` (`06ad26a`) |
| Submodule path | `core/Cores-VeeR-EL2` |
| Bus | AHB-Lite, 64-bit data / 32-bit address |
| Config target | `default_ahb` |
| Snapshot | `p2_soc` |
| `reset_vec` | `0x00000000` (SoC boots from IMEM, not the core-local memories) |
| Interrupts | VeeR PIC, 3 external sources (§8) |

**Rule: never edit the submodule.** Wrap it. A second submodule exists inside it
(`third_party/picolibc`) which is only needed if VeeR's own `program.hex` rule
is allowed to build with GCC instead of its canned hex (§13.4).

### 4.1 Core-local memories — deliberately unused

VeeR exposes ICCM at `0xEE00_0000–0xEE00_FFFF` and DCCM at
`0xF004_0000–0xF004_FFFF`. This project runs in **Mode 1**: no section may ever
land in those ranges. The linker script asserts this (§11.3) and gate G6 fails
the build if a symbol appears in `0xee…`/`0xf0…`.

---

## 5. IP inventory and provenance

| Block | Origin | Licence | State |
|---|---|---|---|
| **CPU** — VeeR EL2 RV32IMC | `chipsalliance/Cores-VeeR-EL2` | Apache-2.0 | **[DONE]** submodule, pinned |
| **AES-128 core** | OpenCores `aes_core` — Rudolf Usselmann, `asics.ws::aes:1.1` | OpenCores permissive | **[PARTIAL]** vendored, AXI slave written, not on SoC |
| **UART** | `m4j0rt0m/axi-lite_uart-ipcore` — Abraham J. Ruiz R. | MIT | **[DONE]** vendored into `rtl/uart/ip/`, on SoC at `0x10000000` |
| **AHB-Lite fabric** | written for this project | — | **[DONE]** |
| **AHB→AXI bridge** | written for this project | — | **[DONE]** |
| **AXI 2×8 interconnect + arbiter + priority encoder** | written for this project | — | **[DONE]** (isolated benches) |
| **Ethernet MAC** | to be selected | — | **[DESIGN]** |
| **CRC32/FCS** | `alexforencich/verilog-lfsr` (MIT) specified | MIT | **[DESIGN]** no RTL |
| **Timestamp unit** | — | — | **[DESIGN]** |
| **Packet parser / classifier** | — | — | **[DESIGN]** |
| **NTE** (network telemetry engine) | the main original contribution | — | **[DESIGN]** |
| **Packet/flow buffer** | — | — | **[DESIGN]** |
| **DMA controller** | — | — | **[DESIGN]** |
| **SHA-256 accelerator** | — | — | **[DESIGN]** |
| **Custom timer, GPIO, watchdog, PRNG, SPI, expansion window** | — | — | **[DESIGN]** |

> **[TODO] AES provenance discrepancy.** The project PRD names the AES IP as
> `secworks/aes`, but the RTL that was actually cloned, compiled and tested
> identifies itself as `asics.ws::aes:1.1` (files `aes_cipher_top.v`,
> `aes_key_expand_128.v`, `aes_sbox.v`). The documentation follows the RTL that
> really runs, not the PRD.

> **[TODO] Duplicate AES sources.** The AES core exists in **two** places:
> `aes/aes_core-master/rtl/verilog/` (full upstream: 7 files, includes the
> inverse cipher) and `rtl/aes/ip/` (5-file subset used by the interconnect
> regressions). The 5 common files are **byte-identical** — verified by diff.
> `aes/axi_aes_wrapper.v` is a third, older copy; the filelists use
> `rtl/aes/axi_aes_wrapper.v`. Consolidate to one copy during migration.

---

## 6. RTL structure

32 RTL modules (excluding testbenches).

```text
rtl/
├── soc_top.sv                    # SoC top: AHB fabric + IMEM + DMEM + bridge + UART + default slave
├── ahb/
│   ├── ahb_interconnect.sv       # 2 masters (IFU, LSU) × 4 slaves
│   ├── ahb_sram.sv               # parameterised AHB-Lite SRAM (IMEM/DMEM)
│   ├── ahb_default_slave.sv      # claims everything else, returns AHB ERROR
│   └── ahb_to_axi_bridge.sv      # AHB-Lite slave → AXI4 master
├── interconnects/
│   ├── axi_interconnect.v        # generic AXI fabric
│   ├── axi_interconnect_wrap_2x8.v  # 2 slaves × 8 masters, windowed
│   ├── arbiter.v                 # round-robin / block / LSB-high
│   └── priority_encoder.v
├── aes/
│   ├── aes_axi_slave.v           # full-AXI4 AES slave wrapper
│   ├── axi_aes_wrapper.v         # AXI4-Lite wrapper (older copy)
│   └── ip/                       # vendored AES core (5 files)
└── uart/
    ├── uart_axi_slave.v          # full-AXI4 UART slave wrapper
    ├── axi_uart_wrapper.v        # AXI 2×8 + UART on M02 (isolated benches)
    └── ip/                       # vendored UART IP (6 files)
```

### 6.1 `soc_top` — important structural detail

**`soc_top` does not instantiate VeeR.** The IFU and LSU AHB-Lite master ports
are *inputs* to `soc_top`; the testbench instantiates `veer_wrapper` and wires
the two together. This is deliberate — it lets the fabric be tested against
directed BFM masters without a CPU, and lets the CPU be tested against the
fabric in the same simulation.

Instantiation order inside `soc_top`:

1. `ahb_interconnect u_fabric` — defaults `ADDR_WIDTH=32`, `DATA_WIDTH=64`
2. `ahb_sram #(.BASE_ADDR(32'h0000_0000), .SIZE_BYTES(32768), .HEX_FILE(IMEM_HEX)) u_imem`
3. `ahb_sram #(.BASE_ADDR(32'h0001_0000), .SIZE_BYTES(32768), .HEX_FILE(DMEM_HEX)) u_dmem`
4. `ahb_to_axi_bridge #(.ID_WIDTH(8)) u_ahb2axi`
5. `uart_axi_slave #(.ID_WIDTH(8)) u_uart`
6. `ahb_default_slave u_default`

Parameters: `IMEM_HEX = ""` (empty ⇒ zero-filled), `DMEM_HEX = ""`.
Localparam: `UART_ID_WIDTH = 8`.

### 6.2 Current AHB decode (exact)

From `rtl/ahb/ahb_interconnect.sv`:

```systemverilog
wire imem_match = (mux_haddr[31:15] == 17'h0000);  // 0x0000_0000 / 32 KB
wire dmem_match = (mux_haddr[31:15] == 17'h0002);  // 0x0001_0000 / 32 KB
wire uart_match = (mux_haddr[31:12] == 20'h10000); // 0x1000_0000 / 4 KB

wire sel_imem = mux_active &&  imem_match;
wire sel_dmem = mux_active && !imem_match &&  dmem_match;
wire sel_uart = mux_active && !imem_match && !dmem_match &&  uart_match;
wire sel_def  = mux_active && !imem_match && !dmem_match && !uart_match;
```

**Consequence:** Timer, GPIO, NTE, AES, CRC32 and every new block currently
decode to the **default ERROR slave**. Any access returns an AHB error and,
because VeeR traps on `HRESP=ERROR`, will raise an illegal-instruction /
bus-fault trap in software. This is correct for unbuilt blocks but means the
fabric cannot be extended by simply adding a peripheral file — the decode and
the slave count must both change.

### 6.3 AXI 2×8 window parameters (current)

`rtl/interconnects/axi_interconnect_wrap_2x8.v`, `M_REGIONS=1`,
`S_COUNT=2`, `M_COUNT=8`:

| Master | Base | Addr width | Decode |
|---|---|---|---|
| M00 | `0x0000_0000` | 15 | 32 KB |
| M01 | `0x0001_0000` | 15 | 32 KB |
| M02 | `0x1000_0000` | 12 | 4 KB |
| M03 | `0x1000_1000` | 12 | 4 KB |
| M04 | `0x1000_2000` | 12 | 4 KB |
| M05 | `0x1000_3000` | 12 | 4 KB |
| M06 | `0x1000_4000` | 12 | 4 KB |
| M07 | `0x1000_5000` | 12 | 4 KB |

All windows: `CONNECT_READ = 2'b11`, `CONNECT_WRITE = 2'b11`, `SECURE = 1'b0`.
This 8-window ceiling is why the design is capped at six AXI peripherals
(UART + five) without a fabric change.

---

## 7. Address map — **canonical**

**Source of truth: `SoC_Address_Map.xlsx` in this repository.** It supersedes
the memory map in the frozen architecture document §9 and in the group plan §18,
both of which still carry the older contiguous 4 KB layout (§7.3).

The workbook is design-only: it deliberately contains **no** change log, no
open items, no freeze status and no repository implementation status. Those
lives in this document instead.

### 7.1 Canonical layout

| Range | Size | Block | Role in the system | State |
|---|---|---|---|---|
| `0x0000_0000`–`0x0000_7FFF` | 32 KB | **IMEM** (`u_imem`) | instruction fetch and execute; boot image | **[DONE]** |
| `0x0000_8000`–`0x0000_FFFF` | 32 KB | *IMEM upper hole* | reserved, no slave | — |
| `0x0001_0000`–`0x0001_7FFF` | 32 KB | **DMEM** (`u_dmem`) | data, stack, firmware mailbox, DMA destination | **[DONE]** |
| `0x1000_0000`–`0x1000_0FFF` | 4 KB | UART | telemetry, debug and encrypted-result reporting (TX only) | **[DONE]** |
| `0x1000_1000`–`0x1000_1FFF` | 4 KB | *guard* | isolation buffer | — |
| `0x1000_2000`–`0x1000_2FFF` | 4 KB | Timer | CPU/system timing; `TIMER_IRQ` | **[DESIGN]** |
| `0x1000_3000`–`0x1000_3FFF` | 4 KB | *guard* | isolation buffer | — |
| `0x1000_4000`–`0x1000_4FFF` | 4 KB | GPIO | status/debug outputs (`CPU_ALIVE`, `PKT_RX`, `AES_BUSY`, `PKT_ERR`) | **[DESIGN]** |
| `0x1000_5000`–`0x1000_5FFF` | 4 KB | *guard* | isolation buffer | — |
| `0x1000_6000`–`0x1000_6FFF` | 4 KB | Network Telemetry Engine (NTE) | packet/byte/error counters, frame length, metadata, telemetry snapshot | **[DESIGN]** |
| `0x1000_7000`–`0x1000_7FFF` | 4 KB | *guard* | isolation buffer | — |
| `0x1000_8000`–`0x1000_8FFF` | 4 KB | AES-128 Accelerator | encrypt the 128-bit telemetry record | **[PARTIAL]** |
| `0x1000_9000`–`0x1000_9FFF` | 4 KB | *guard* | isolation buffer | — |
| `0x1000_A000`–`0x1000_AFFF` | 4 KB | CRC-32 / FCS Checker | Ethernet frame integrity checking | **[DESIGN]** |
| `0x1000_B000`–`0x1000_BFFF` | 4 KB | *guard* | isolation buffer | — |
| `0x1000_C000`–`0x1000_CFFF` | 4 KB | Ethernet MAC | receive/transmit framing, MAC address, frame boundaries | **[DESIGN]** |
| `0x1000_D000`–`0x1000_DFFF` | 4 KB | *guard* | isolation buffer | — |
| `0x1000_E000`–`0x1000_EFFF` | 4 KB | Hardware Timestamp Unit | 64-bit packet and event timestamp capture | **[DESIGN]** |
| `0x1000_F000`–`0x1000_FFFF` | 4 KB | *guard* | isolation buffer | — |
| `0x1001_0000`–`0x1001_0FFF` | 4 KB | Packet / Flow Buffer | packet FIFO, flow records, telemetry and event queue | **[DESIGN]** |
| `0x1001_1000`–`0x1001_1FFF` | 4 KB | *guard* | isolation buffer | — |
| `0x1001_2000`–`0x1001_2FFF` | 4 KB | DMA Controller | move buffered packet and telemetry data into DMEM | **[DESIGN]** |
| `0x1001_3000`–`0x1001_3FFF` | 4 KB | *guard* | isolation buffer | — |
| `0x1001_4000`–`0x1001_4FFF` | 4 KB | SHA-256 Accelerator | digest and integrity authentication of telemetry | **[DESIGN]** |
| `0x1001_5000`–`0x1001_5FFF` | 4 KB | *guard* | isolation buffer | — |
| `0x1001_6000`–`0x1001_6FFF` | 4 KB | Packet Parser / Classifier | Ethernet II (later IPv4/UDP) metadata extraction and classification | **[DESIGN]** |
| `0x1001_7000`–`0x1001_7FFF` | 4 KB | *guard* | isolation buffer | — |
| `0x1001_8000`–`0x1001_8FFF` | 4 KB | Watchdog Timer | fault recovery and system supervision | **[DESIGN]** |
| `0x1001_9000`–`0x1001_9FFF` | 4 KB | *guard* | isolation buffer | — |
| `0x1001_A000`–`0x1001_AFFF` | 4 KB | PRNG | random / security-support function | **[DESIGN]** |
| `0x1001_B000`–`0x1001_BFFF` | 4 KB | *guard* | isolation buffer | — |
| `0x1001_C000`–`0x1001_CFFF` | 4 KB | SPI Master | external low-speed connectivity (optional) | **[DESIGN]** |
| `0x1001_D000`–`0x1001_DFFF` | 4 KB | *guard* | isolation buffer | — |
| `0x1001_E000`–`0x1001_EFFF` | 4 KB | Reserved for expansion | unassigned peripheral window | reserved |
| `0x1001_F000`–`0x1001_FFFF` | 4 KB | *guard* | isolation buffer | — |

Access is **IFU read/execute** for IMEM and **LSU read/write** for everything
else. The code aperture is `0x0000_0000`–`0x0000_FFFF` (64 KB reserved, 32 KB
used).

Unmapped regions, named explicitly in the workbook: `GAP-01` (IMEM upper hole,
`0x0000_8000`–`0x0000_FFFF`), `GAP-02` (low region, `0x0001_8000`–`0x0FFF_FFFF`),
`GAP-03` (high region, `0x1002_0000`–`0xFFFF_FFFF`).

The workbook accounts for the full `0x0000_0000`–`0xFFFF_FFFF` range with **no
gaps and no overlaps**; 37 address-map rows total, every row satisfying
`End = Start + Size - 1`.

### 7.2 The 8 KB slot rule — window + guard

**Every peripheral occupies an 8 KB slot made of a 4 KB window followed by a
4 KB guard.**

```text
 slot N   base = 0x1000_0000 + N × 0x2000
          ├─ +0x0000 .. +0x0FFF : 4 KB window  (registers; decodes addr[11:0])
          └─ +0x1000 .. +0x1FFF : 4 KB guard   (NOT decoded → bus error)
```

Two rules matter for RTL:

1. **The window decodes only the low 12 address bits.** `AWADDR[11:0]`. The
   window is therefore exactly 4 KB regardless of the slot pitch.
2. **The guard is deliberately left undecoded** — it is *not* on the fabric at
   all. Any access to a guard address falls through to the error path and
   returns a bus error.

Rationale for the guard: a stray access past the end of one peripheral becomes
a clean, attributable bus error instead of a silent alias into the next
peripheral's registers. Because guards are never decoded, implementing them
costs nothing — an access that matches no window window-slave already lands on
the ERROR slave (§6.2).

> Watchdog, PRNG, SPI and the expansion window are **provisional** assignments
> in the workbook — placed so the aperture has no unallocated gap, and
> explicitly marked as droppable if their scope does not materialise.

### 7.3 Migration deltas — addresses that changed

This is the most important table in the document. Five peripherals moved when
the 8 KB-slot scheme was adopted, and three pieces of RTL/firmware encode the
**old** addresses.

| Block | Old (frozen v3 / plan §18) | **New (canonical)** | What encodes the old address |
|---|---|---|---|
| UART | `0x1000_0000` | `0x1000_0000` *(unchanged)* | `uart_axi_slave.v` `UART_BASE` |
| Timer | `0x1000_1000` | **`0x1000_2000`** | decode only |
| GPIO | `0x1000_2000` | **`0x1000_4000`** | decode only |
| NTE | `0x1000_3000` | **`0x1000_6000`** | decode only |
| AES-128 | `0x1000_4000` | **`0x1000_8000`** | `aes_axi_slave.v` `AES_BASE = 32'h1000_4000` ⚠ |
| CRC32 | `0x1000_5000` | **`0x1000_A000`** | decode only |

**Action items arising:**

1. `rtl/aes/aes_axi_slave.v` has `localparam AES_BASE = 32'h1000_4000`. Under
   the canonical map AES lives at `0x1000_8000` and AXI window **M06** must be
   reparameterised. **The AES regression must be re-run from scratch** — the
   passing result quoted in §13.3 was obtained at the old address.
2. `rtl/interconnects/axi_interconnect_wrap_2x8.v` M03–M07 all shift:
   M03 `0x1000_2000`, M04 `0x1000_4000`, M05 `0x1000_6000`,
   M06 `0x1000_8000`, M07 `0x1000_A000`. Note each window's `ADDR_WIDTH`
   becomes **13** (8 KB), not 12.
3. `rtl/ahb/ahb_interconnect.sv` decode must change from one 4 KB compare per
   block to one 8 KB compare per slot.
4. `sw/include/soc.h` has `AES_BASE 0x10004000u` — must become `0x10008000u`.
5. `sw/linker/veer.ld` is unaffected (IMEM/DMEM only), but its *comments*
   reference the old §9 map.
6. `doc/RISC_V_Network_Telemetry_SoC_Architecture_Document_v3.md` §9 and §10.x,
   and group plan §18, still carry the old addresses and need an amendment.

### 7.4 AXI master assignment under the canonical map

| AXI master | Base | Peripheral |
|---|---|---|
| M02 | `0x1000_0000` | UART |
| M03 | `0x1000_2000` | Timer |
| M04 | `0x1000_4000` | GPIO |
| M05 | `0x1000_6000` | NTE |
| M06 | `0x1000_8000` | AES-128 |
| M07 | `0x1000_A000` | CRC32 |

Six AXI peripherals fit the existing 8-window fabric. The remaining ten blocks
(MAC, Timestamp, Buffer, DMA, SHA-256, Parser, Watchdog, PRNG, SPI, Expansion)
are recorded as **"not assigned"** in the workbook. They need either a second
fabric instance, a wider interconnect, or AHB-Lite slaves behind
`ahb_interconnect` directly. **Decide this before writing RTL** — it determines
the fabric topology.

### 7.5 Register maps, bits, interrupts, probes

`SoC_Address_Map.xlsx` carries these as separate sheets and is authoritative:

| Sheet | Contents |
|---|---|
| `Cover` | Scope, revision, how to read |
| `1. Address Map` | The 37 canonical rows with roles, sizes, access types |
| `2. Window Decode` | Slot → window/guard arithmetic, decoded bits, AXI assignment |
| `3. Register Maps` | Per-block register offsets and where the map is a proposal |
| `4. Register Bits` | Field-level bit positions and access modes |
| `5. Interrupt Map` | Source IDs, assertion conditions, enable bits, clear mechanisms, machine cause IDs |
| `6. Test-Plan Probes` | Where to observe each block for verification |
| `7. Unmapped & Guard Ranges` | Explicit hole list |

### 7.6 Interrupt architecture

VeeR's **PIC** is used — not an external OR gate. Source IDs **1–3 are
assigned**; IDs **4–8 are proposals**.

| ID | Block | Signal | Assertion condition | Status |
|---|---|---|---|---|
| 1 | Network Telemetry Engine | `NET_IRQ` | packet completion **AND** telemetry snapshot available **AND** network IRQ enabled | assigned |
| 2 | AES-128 Accelerator | `AES_IRQ` | encryption complete **AND** AES IRQ enabled (enable in `AES.CONTROL` bit 1) | assigned |
| 3 | Timer | `TIMER_IRQ` | `COUNT` reached `COMPARE` **AND** `CONTROL.IRQ_EN` set | assigned |
| 4 | DMA Controller | `DMA_IRQ` | transfer complete **OR** transfer error, gated by DMA IRQ enable | proposed |
| 5 | Packet / Flow Buffer | `BUF_IRQ` | occupancy ≥ `THRESHOLD`, or overflow | proposed |
| 6 | Ethernet MAC | `MAC_IRQ` | `RX_DONE`, `TX_DONE` or `ERROR` | proposed |
| 7 | SHA-256 Accelerator | `SHA_IRQ` | digest computation complete | proposed |
| 8 | Watchdog Timer | `WDT_IRQ` | watchdog timeout | proposed (scope TBC) |

Blocks deliberately **without** an interrupt:

| Block | Why |
|---|---|
| UART | transmit only; software polls `LSR.THRE`/`LSR.TEMT`. `IER` @ `0x10000004` exists but is unused. |
| Packet Parser / Classifier | streaming data-plane block; the NTE raises the event instead. |
| CRC-32 / FCS | the CRC result is packet-associated, so the natural event is the NTE packet-completion interrupt. |
| PRNG, SPI | optional blocks; no interrupt proposed. |
| Controller registers | the PIC is configured through the CPU's own control/status space, not MMIO. |

The three assigned sources match frozen architecture §12.2 exactly
(`1 = NET`, `2 = AES`, `3 = Timer`) and are connected to the VeeR PIC
independently — **not ORed together**.

---

## 8. Firmware (`sw/`)

Bare-metal C, RV32IMC, freestanding, no HAL and no dynamic linking.

| Property | Value |
|---|---|
| Compiler prefix | `riscv64-unknown-elf-` (cross-compiled to RV32) |
| `-march` | `rv32imc_zicsr_zifencei` (frozen) |
| `-mabi` | `ilp32` (frozen) |
| Optimisation | `-O0 -g` |
| CFLAGS | `-ffreestanding -fno-builtin -Wall -Wextra -Iinclude` |
| LDFLAGS | `-nostartfiles -nostdlib -T linker/veer.ld -Wl,-Map -Wl,--gc-sections` |
| Output | `sw/build/firmware.elf`, `imem.mem`, `dmem.mem`, `firmware.ihex`, `manifest.txt` |

### 8.1 Memory layout

```text
IMEM  0x0000_0000 .. 0x0000_7FFF   32 KB   .text, .rodata, .data load image (LMA)
MBOX  0x0001_0000 .. 0x0001_000F   16 B    reserved PASS mailbox
DMEM  0x0001_0010 .. 0x0001_7FFF          .data (VMA), .bss, stack
                                          __stack_top = 0x0001_8000
```

### 8.2 PASS mailbox contract

`startup.S` writes the first 16 bytes of DMEM; the testbench reads them. This is
a **frozen contract** — changing it breaks `tb_veer_p2_soc.sv` with no
monitor change.

| Offset | Value | Meaning |
|---|---|---|
| `[0]` | `0x50` | `'P'` signature low |
| `[1]` | `0x32` | `'2'` signature high |
| `[2]` | `0xFF` | trigger |
| `[3]` | — | fail id (0 = pass) |
| `[4..7]` | `0x00003250` | CPU read-back word |

### 8.3 `firmware.ihex` must never reach the simulator

The Intel-HEX file is a **delivery artefact only**. `$readmemh` cannot parse it.
Gate **G13** fails the build if any `*.ihex` appears in the simulation working
directory.

Both `imem.mem` and `dmem.mem` must be:
- one hex byte per token (`--verilog-data-width 1`),
- LF line endings (`objcopy -O verilog` emits CRLF, and `$readmemh` treats `\r`
  as part of the token — a whole class of silent corruption),
- free of Intel-HEX `:` records,
- addressed with `@` records inside the 32 KB array (no `@` ≥ `0x8000`,
  no negative index).

`dmem.mem` needs special handling: `objcopy` emits `@` records from the section
**LMA**, not its VMA, so `--change-addresses` alone yields a negative index. The
Makefile overrides the LMA outright with `--change-section-lma .data=<index>`.

### 8.4 `fw0` — what the firmware proves

`sw/src/main.c` is deliberately minimal: every statement is chosen to force a
**countable AHB cycle**. It validates `.rodata` fetch, the `.data` LMA→VMA copy,
`.bss` zero-fill, then writes/reads/checksums a DMEM block. It returns a
numbered fail id (1–6) rather than trapping, so a red run is debuggable in
Verdi without a re-run. Deliberately absent: `.text` writes, stack temporaries,
a trap handler, and UART/AES MMIO.

---

## 9. Build and gate flow

### 9.1 Root `Makefile` — a delegator only

```text
make all       = firmware → mem → veer-config → rtl → sim
make firmware  → sw/build/firmware.elf
make inspect   → ELF/section/symbol gates G1–G7, G11
make mem       → imem.mem + dmem.mem + firmware.ihex (G8–G10, G12)
make veer-config → build/snapshots/p2_soc
make rtl       → VCS compile
make sim       → run + gate on P2_TB2_RESULT and AHB_RW_MONITOR (+ G13)
make verdi     → open the FSDB with run/fw_wave.rc
make wave      → print the verdi command instead of launching
make clean     → remove sw/build, build/sim, build/snapshots
```

Root holds **no build logic**. Firmware → `sw/Makefile`; simulation →
`sim/Makefile`. Decision D6: the VeeR snapshot is **project-local** at
`build/snapshots/p2_soc` (never `/tmp`, which is root-owned).

### 9.2 The 13 firmware gates

| Gate | What it proves |
|---|---|
| G1 | `firmware.elf` produced |
| G2 | frozen `-march`/`-mabi` pair echoed by the build |
| G3 | ELF32 / RISC-V |
| G4 | exact `Tag_RISCV_arch` string; no F/D extensions |
| G5 | entry == `_start` == `0x0`; `__stack_top` == `0x00018000` |
| G6 | all sections inside IMEM/DMEM; nothing in ICCM/DCCM |
| G7 | freestanding `-nostdlib` link; no dynamic section; no undefined symbols; no region overflow |
| G8 | `imem.mem` / `dmem.mem` / `firmware.ihex` non-empty |
| G9 | every `@` record inside the 32 KB dense array |
| G10 | byte-per-token, LF endings, never Intel HEX |
| G11 | `imem.mem` head == first instruction encoding |
| G12 | manifest written with Mode 1 / `addr_xor` fields |
| G13 | simulation: both terminal tokens present, and no `.ihex` in the sim dir |

### 9.3 Linker guardrails

`sw/linker/veer.ld` asserts, at link time:

- `_start == 0x00000000` (must match `reset_vec`)
- the mailbox reservation never collides with `.data`
- at least 512 bytes of stack above `.bss`
- `__stack_top == 0x00018000`
- `.text`/`.data`/`.bss` stay inside IMEM/DMEM
- nothing lands in ICCM (`0xEE000000–0xEE010000`) or DCCM
  (`0xF0040000–0xF0050000`)

### 9.4 Never add `-lgcc`

Amendment A1, and it is load-bearing. The `/opt/riscv` toolchain ships **only
ELF64 `libgcc.a`** — no RV32 multilib. With `-nostartfiles` alone the link
succeeds (archives pull nothing until a symbol is referenced), then the first
64-bit helper such as `__udivdi3` or any `memcpy` aborts with:

```text
libgcc.a(div.o): file class ELFCLASS64 incompatible with ELFCLASS32
```

`-nostdlib` turns that late confusing error into a plain
`undefined reference to __udivdi3` at the offending source. Never add `-lgcc`.

---

## 10. Simulation and verification

### 10.1 Toolchain

| Tool | Version | Path |
|---|---|---|
| VCS | U-2023.03 | `/home/student/snps_tools_target/vcs/U-2023.03` |
| Verdi | U-2023.03-SP1 | `/home/student/snps_tools_target/verdi/U-2023.03-SP1` |
| License | — | `SNPSLMD_LICENSE_FILE=27021@14.139.1.126` (set in `/home/student/cshrc`) |

**Both `VCS_HOME` and `VERDI_HOME` must be *exported***, not merely used to
build `PATH` — the `vcs` wrapper resolves its own helper scripts from
`$VCS_HOME/bin`.

Compile flags:

```text
-full64 -sverilog -debug_access+all -kdb
+define+RV_OPENSOURCE +error+500 -timescale=1ns/10ps
```

Both tools are present at those paths **[DONE]**. `which vcs verdi` must resolve
after sourcing `/home/student/cshrc`.

**No open-source simulator flow exists.** There is no Verilator or Icarus
target anywhere in the repository. VCS/Verdi are mandatory — plan for lab
machines with a Synopsys licence, or port the filelist to Verilator as a
separate task.

### 10.2 VeeR snapshot generation

```bash
env BUILD_PATH=$PWD/build/snapshots/p2_soc RV_ROOT=$RV_ROOT \
  $RV_ROOT/configs/veer.config -target=default_ahb -snapshot=p2_soc \
  -set=reset_vec=0x00000000
```

`default_ahb` has **no AXI** — when debugging Phase 1/2, inspect `ic_`, `lsu_`,
`mux_` AHB signals, not AXI signals.

### 10.3 Simulation file list

`sim/filelist.f` expands `$RV_ROOT`, `$FW_PROJ`, `$FW_SNAP`:

1. `+incdir+` for VeeR testbench, VeeR design include, and the snapshot
2. `common_defines.vh`, `el2_def.sv`, `el2_pdef.vh`, then `-f $RV_ROOT/testbench/flist`
3. project SoC RTL: `ahb_interconnect`, `ahb_sram`, `ahb_default_slave`, `soc_top`
4. `-f $FW_PROJ/run/uart_rtl.f` (the UART subsystem + bridge)
5. `tb/tb_ahb_cycle_monitor.sv` **before** the top — `tb_veer_p2_soc` instantiates it
6. `tb/tb_veer_p2_soc.sv`, `-top tb_veer_p2_soc`

### 10.4 Testbenches

Eleven self-checking SystemVerilog benches in `tb/`:

| Bench | Purpose |
|---|---|
| `tb_ahb_fabric.sv` | directed AHB-Lite fabric regression (TB1), 23 checks |
| `tb_ahb_cycle_monitor.sv` | AHB read/write-cycle monitor module (**not** a top) |
| `tb_veer_p2_soc.sv` | VeeR boots through the fabric, writes the DMEM mailbox (TB2) |
| `tb_veer_uart_soc.sv` | VeeR → AHB → AXI → UART → `uart_tx` end-to-end |
| `tb_uart_axi_slave.sv` | UART slave direct |
| `tb_axi_interconnect_uart.sv` | AXI interconnect → UART |
| `tb_axi_interconnect_uart_2master.sv` | two masters contending on UART |
| `tb_aes_axi_slave.sv` | AES slave direct |
| `tb_axi_interconnect_aes.sv` | AXI interconnect → AES |
| `tb_axi_interconnect_aes_2master.sv` | two masters contending on AES |

> The README refers to "ten testbenches"; `tb/` holds eleven files. One of them
> (`tb_ahb_cycle_monitor.sv`) is a monitor module rather than a standalone top,
> which is where the discrepancy comes from.

### 10.5 Pass tokens — the regression contract

Every claim is gated on a literal string in the simulation log. This is the
project's core verification discipline: **never claim PASS without a log and a
waveform.**

| Flow | Token(s) |
|---|---|
| Phase 1 VeeR bring-up | `TEST_PASSED` + `minstret = 330, mcycle = 1134` |
| Phase 2 fabric | `P2_TB1_RESULT: PASS`, `P2_TB2_RESULT: PASS` |
| AHB read/write monitor | `AHB_RW_MONITOR: PASS` |
| AXI + AES | `AXI INTERCONNECT -> AES INTEGRATION: PASS` |
| AXI + AES 2-master | `PASS checks : 19 / FAIL checks : 0` |
| UART direct | `UART AXI SLAVE DIRECT: PASS` |
| AXI → UART | `AXI INTERCONNECT -> UART INTEGRATION: PASS` |
| UART 2-master | `PASS checks : 19 / FAIL checks : 0` |
| Phase 3 UART end-to-end | `UART_E2E_RESULT: PASS` |
| Phase 3 fabric re-run | `P2 FABRIC: PASS=23 FAIL=0`, `P2_TB1_RESULT: PASS` |
| Firmware image gates | `[SW] PASS G1` … `[SW] PASS G12` |
| Simulation image gate | `[SIM] PASS no *.ihex in $(WORK)` |

The AES known-answer vector used everywhere:

```text
key        000102030405060708090a0b0c0d0e0f
plaintext  00112233445566778899aabbccddeeff
ciphertext 69c4e0d86a7b0430d8cdb78070b4c55a
```

### 10.6 Known-answer monitor numbers (fw0)

```text
imem_rd=2393  imem_wr=0
dmem_rd=366   dmem_wr=164
bus_err=0     def=0
```

`imem_wr=0` is correct and expected — `.text` is never written.

### 10.7 Verification methodology: directed today, UVM next

The current benches are **flat/directed**: BFM tasks drive the bus, an
expected-value scoreboard compares, and a `pass_count`/`fail_count` pair decides
the exit status. Known-answer vectors, response monitors and one-hot `HSEL`
checks do the heavy lifting. That style is correct for bus bring-up but does not
scale: stimulus lives in one large `initial` block, there is no reusable driver,
no coverage model, and changing scenario means editing the testbench.

The planned migration is a layered **UVM** environment, IP by IP:

| UVM element | Planned use |
|---|---|
| `uvm_agent` (driver/monitor/sequencer) | AHB-Lite master agent (IFU+LSU), AXI master agent, AXI slave agent, UART TX agent |
| `uvm_sequence` + `uvm_sequence_item` | AHB/AXI transactions, UART byte streams, packet-chunk stimuli |
| `uvm_scoreboard` + analysis ports | AES known-answer ciphertext, CRC/FCS results, telemetry records |
| `covergroup` functional coverage | address-map regions, `HTRANS`/`HBURST`/`HSIZE`, AXI strobes, ERROR responses, IRQ events |
| **`uvm_component_utils` + factory overrides** | swap a BFM for the real VeeR master, or a reference model for the synth core, **without editing the environment** |
| **`uvm_config_db#(virtual ...)`** | hand virtual interfaces down from the top TB in `build_phase` — no hierarchical references, so the env is portable |
| `uvm_reg` | the MMIO map itself as a register block |
| `uvm_report_server` | one collection point; the exit code CI would gate on |

Migration order: **AXI+AES** (already isolated and passing) → **UART** →
**AHB fabric + VeeR master agent** → **SoC-level virtual sequence** (the §1.1
goal as one `uvm_test`).

None of the UVM work exists yet.

---

## 11. Milestones

### 11.1 Verified baseline

| Milestone | Deliverable | Status |
|---|---|---|
| M1 | VeeR EL2 bring-up (`default_ahb`) | **[DONE]** |
| M2 | AHB-Lite fabric, IMEM/DMEM, VeeR-through-fabric (TB1+TB2) | **[DONE]** |
| — | AXI 2×8 interconnect + AES-128, isolated | **[DONE]** |
| — | UART AXI subsystem, isolated (direct / interconnect / 2-master) | **[DONE]** |
| — | RISC-V GNU toolchain bring-up | **[BROKEN]** — see §14 |
| M3 | UART on the SoC: bridge at `0x1000_0000` + E2E testbench | **[DONE]** |
| — | `fw0` firmware: build → images → VeeR boot → AHB R/W in Verdi | **[DONE]** when environment is intact |
| M4 | AES on the SoC (bridge + driver) | **[TODO]** |
| M5 | Network Telemetry Engine + CRC32 + IRQs | **[TODO]** |
| M6 | Full SoC + bare-metal app + end-to-end TB | **[TODO]** |

### 11.2 Three real bugs fixed in Phase 3

Recorded because each one is a trap the next person will hit:

1. **AHB→AXI bridge returned only one half of VeeR's 64-bit AHB read.** The
   LSR poll never terminated. Fixed by 64b↔32b lane splitting in the bridge.
2. **Fabric arbiter dropped the IFU address phase whenever the LSU was active.**
   Result: 24,719 illegal-instruction traps. Fixed; locked down by new fabric
   checks T13/T14 (23/23).
3. **Vendored UART IP held its TX FIFO in soft-reset from power-on.** Every
   frame carried the first byte twice. Fixed by an explicit FIFO reset.

### 11.3 AHB→AXI bridge, in detail

`ahb_to_axi_bridge.sv` (344 lines) converts a 64-bit AHB-Lite slave port into a
32-bit full-AXI4 master port, single outstanding transaction, with
64b↔32b lane splitting for wide AHB beats. Only `ID_WIDTH` is a parameter; no
depth or FIFO parameters. It is the reusable path for **every** future
peripheral — which is why M4 onwards reuses it rather than inventing anything
new.

---

## 12. Verification records to migrate

| Document | Purpose |
|---|---|
| `RISC_V_Network_Telemetry_SoC_Architecture_Document_v3.md` | Frozen architecture: memory map, registers, phases, DoD |
| `RISC_V_Network_Telemetry_SoC_Port_List.md` | Top-level port list |
| `RISC_V_Network_Telemetry_SoC_Progress_and_Architecture.md` | Progress + AXI/AES baseline |
| `Phase1_VeeR_Bringup_Completion_Record.md` | Phase 1 evidence |
| `Phase2_AHB_Fabric_Completion_Record.md` | Phase 2 evidence |
| `Phase3_UART_End_To_End_Completion_Record.md` | Phase 3 evidence + the three root causes above |
| `AES_AXI_Integration_Verification_Record.md` | AES/AXI evidence |
| `RISC_V_GNU_Toolchain_Setup_and_Validation_Record.md` | Cross-toolchain install/validation |
| `RISC_V_SW_Build_and_Simulation_Image_Architecture_Specification.md` | Frozen firmware build → image flow |
| `SW_HW_Memory_Image_Architecture_First_Principles_and_Spec_Amendments.md` | Image-conversion first principles + amendments H.1–H.9 |
| `Firmware_Build_and_AHB_RW_Verification_Plan.md` | Execution plan, steps 1–3a done |
| `Fw0_C_Toolchain_Build_and_Gate_Record.md` | Build output, gates G1–G13, two image defects found |
| `Firmware_Build_and_AHB_RW_Verification_Record.md` | fw0 evidence, cycle-by-cycle AHB tables, findings N8–N10 |
| `RISC_V_Secure_Network_Telemetry_SoC_Initial_Project_Plan.md` | The group plan (already in this repo) |

**[TODO]** The AES verification record still carries a 05-Sep status table in
which `AES core completion`, `STATUS.DONE` and `BUSY deassertion` are shown as
failing. Those were fixed afterwards and the regression now runs 19 PASS /
0 FAIL. The table must be updated to match the log.

---

## 13. Environment setup — from scratch

### 13.1 VCS / Verdi

```csh
csh
source /home/student/cshrc        # VCS_HOME, VERDI_HOME, licence, PATH
which vcs verdi                   # both must resolve
```

`/home/student/cshrc` sets `VCS_HOME`, `VERDI_HOME`,
`SNPSLMD_LICENSE_FILE=27021@14.139.1.126` and prepends both `bin` directories
to `PATH`.

### 13.2 RISC-V cross-compiler — **[BROKEN]**

The firmware flow **does not build in the current environment.** The compiler
documented in the source repository is not installed:

| Expected | Status |
|---|---|
| `/opt/riscv/bin/riscv64-unknown-elf-gcc` (GCC 16.1.0, self-built) | **missing** |
| `/root/tools/riscv-gnu/2023.04.29/bin/…` (GCC 12.2.0, pinned) | **missing** |
| `/etc/profile.d/riscv.sh` | **missing** |
| `riscv64-unknown-elf-gcc` on `PATH` | **not found** |

**This is not a small gap.** `/opt/riscv` was a source build of upstream
`riscv-gnu-toolchain` (tag `2026.08.27`) into an **ELF64-only** toolchain with
no RV32 multilib — which is exactly why §9.4 forbids `-lgcc`. A distro
`riscv64-unknown-elf-gcc` will have the same multilib gap. **The rebuild must
target RV32 multilib**, or `sw/Makefile`'s gates G3–G7 will fail.

Rebuild procedure, from the recorded history:

```bash
# packages
dnf install -y dnf-plugins-core texinfo meson ninja-build

git clone https://github.com/riscv/riscv-gnu-toolchain
cd riscv-gnu-toolchain
./configure --prefix=/opt/riscv          # generates Makefile from Makefile.in
make -j$(nproc)                          # full build incl. GDB
echo 'export PATH=/opt/riscv/bin:$PATH' > /etc/profile.d/riscv.sh
```

Verify with `riscv64-unknown-elf-gcc --version` and confirm
`lib/gcc/riscv64-unknown-elf/*/rv32imc/ilp32/libgcc.a` exists.

### 13.3 Core submodule

```bash
git submodule update --init --recursive
git submodule status      # must show a leading space then 06ad26a
```

### 13.4 VeeR's own `program.hex` trap

VeeR's `program.hex` rule builds with GCC **if `riscv64-unknown-elf-gcc` is on
`PATH`**, which then needs VeeR's `third_party/picolibc` submodule and fails
with `ERROR: Neither directory contains a build file meson.build`.

Two ways around it:

1. **Hide the cross compiler** so VeeR uses its canned hex (fast; this is how
   the Phase-1 PASS was produced):

   ```csh
   setenv PATH `echo $PATH | tr ":" "\n" | grep -v riscv | paste -sd:`
   ```

2. Or initialise picolibc (needs network + meson/ninja):
   `git -C core/Cores-VeeR-EL2 submodule update --init third_party/picolibc`

### 13.5 Running the regressions

```csh
cd run

./p1_full_flow.csh          # VeeR bring-up        -> TEST_PASSED
./p1_open_verdi.csh         # Verdi on dump.fsdb + p1_wave.rc
./p2_full_flow.csh          # TB1 + TB2            -> both PASS
./uart_full_flow.csh        # [1/3] direct [2/3] interconnect [3/3] 2-master
./p3_uart_flow.csh          # uart_soc + E2E TB + fabric re-run; exit 0 = pass
```

Isolated subsystems, invoked directly with VCS:

```csh
vcs -full64 -sverilog -f aes_axi_interconnect_run.f -debug_access+all -kdb -l compile_aes.log
./simv -l sim_aes.log        # AXI INTERCONNECT -> AES INTEGRATION: PASS
```

Firmware + SoC (from the repository root, after the toolchain is rebuilt):

```bash
make -C sw all inspect      # gates G1–G13
make                        # full flow: firmware -> images -> snapshot -> compile -> run -> gate
make verdi                  # open the FSDB with run/fw_wave.rc
```

### 13.6 Verdi

```csh
setenv DISPLAY :0           # physical display; do NOT force :42 on a headless box
verdi -ssf <wave.fsdb> -dbdir simv.daidir -sswr run/<name>_wave.rc &
```

Every PASS in this project has a waveform behind it. Reproducing the evidence
means reproducing the waveform.

---

## 14. Hard-coded paths — fix these during migration

The source repository was developed at `/home/student/Documents/honours_project`
and has since been renamed. **That path no longer exists**, and neither does
`/tmp/opencode/veer_p2`. Several flows are therefore broken today **[BROKEN]**.

| File | Embedded path | Effect |
|---|---|---|
| `run/uart_rtl.f` | `/home/student/Documents/honours_project/rtl/…` (absolute, 9 lines) | **`sim/filelist.f` includes this file** ⇒ the whole firmware simulation flow fails to compile |
| `run/p1_full_flow.csh`, `p1_hello_world_ahb.csh`, `p1_open_verdi.csh` | `RV_ROOT=…/honours_project/core/Cores-VeeR-EL2`, `/tmp/opencode/veer_p1` | Phase 1 flow fails |
| `run/p2_full_flow.csh`, `p2_open_verdi.csh` | `PROJ=…/honours_project`, `/tmp/opencode/veer_p2`, tool homes, licence host | Phase 2 flow fails |
| `run/p2_fabric_run.f`, `p2_veer_soc_run.f` | absolute `…/honours_project/rtl/…` | Phase 2 benches fail |
| `run/p2_veer_soc_run.f` | `/tmp/opencode/veer_p2/snapshots/p2_soc/…` | Phase 2 bench fails if a different workdir is passed |
| `run/p1_wave.rc`, `p2_wave.rc`, `p2_veer_wave.rc` | absolute FSDB paths | Verdi signal groups fail |
| `run/uart_*.f` | `../rtl/…` relatives | **portable** |
| `run/uart_full_flow.csh` | relative | **portable** |

**Fix strategy:** make every filelist use `$FW_PROJ` / `$RV_ROOT` environment
expansion, exactly as `sim/filelist.f` already does, and delete the absolute
paths. `sim/filelist.f` is the model to copy.

Note the layering trap: `sim/filelist.f` looks portable but pulls in
`run/uart_rtl.f`, which is not. Fixing `run/uart_rtl.f` is the single
highest-value portability fix in the repository.

---

## 15. Known mismatches and open items

Read this before writing RTL.

| # | Item | Severity | Action |
|---|---|---|---|
| 1 | **Canonical address map vs frozen architecture §9 / plan §18** | **high** | Amend both documents to the 8 KB-slot map, or re-derive the map. Five peripherals move. |
| 2 | **AES at `0x1000_4000` in RTL vs `0x1000_8000` canonically** | **high** | Reparameterise `aes_axi_slave.v` and the M06 window, then **re-run the whole AES regression** — the old PASS is void. |
| 3 | **RISC-V cross-compiler missing** | **high** | Rebuild with RV32 multilib (§13.2). Nothing firmware-related runs until then. |
| 4 | `run/uart_rtl.f` absolute paths break the firmware sim flow | **high** | Convert to `$FW_PROJ` expansion. |
| 5 | `sw/include/soc.h` `AES_BASE` is the old address | medium | Update to `0x10008000u`. |
| 6 | Fabric decodes only IMEM/DMEM/UART/ERROR | medium | Add 8 KB-slot decode as peripherals land. Consider whether a 4-slave AHB fabric is the right shape. |
| 7 | AXI fabric caps at six peripherals | medium | Decide: second fabric, wider interconnect, or AHB slaves. Blocks the MAC/SHA-256/DMA work. |
| 8 | UART register map deviates from architecture §10.1 | medium | The IP uses `0x00` THR/RBR, `0x04` IER, `0x08` baud (DLAB=1), `0x0C` LCR, `0x14` LSR. **Keep the IP-native map** and rewrite §10.1 to match — do not fork the vendored core. |
| 9 | AES verification record's status table is stale | low | Update to the 19 PASS / 0 FAIL log. |
| 10 | AES core duplicated in `aes/` and `rtl/aes/ip/`; a third wrapper copy | low | Consolidate to one. |
| 11 | AES PRD names `secworks/aes`; RTL is `asics.ws::aes:1.1` | low | Document the discrepancy (already in the AES record); do not claim secworks provenance. |
| 12 | Guard windows are specified but only implicitly enforced | low | Guards already behave correctly *by accident*: an undecoded address falls to the default ERROR slave. Make it explicit when the decode is rewritten, and prove it with a test that reads `0x1000_1000` and expects a bus error. |
| 13 | `tb_ahb_cycle_monitor.sv` listed as a testbench in one place, a module in another | low | Cosmetic; fix the count. |
| 14 | No open-source simulator fallback | low | VCS is a hard dependency. Port to Verilator if the group has no licence. |
| 15 | Single-author history, no CI, no top-level `LICENSE` | low | Add CI and a LICENSE. Vendored cores keep their own. |
| 16 | Synthesizability never attempted | low | Explicitly last. Everything so far is simulation. |

---

## 16. Git policy for the group repository

**Tracked** — anything needed to reproduce a result: RTL, testbenches, flow
scripts and filelists, generators, docs, and the pinned CPU submodule.

**Ignored** — anything a tool regenerates: `simv`, `csrc/`, `*.log`,
`*.fsdb`, `*.vcd`, `verdiLog/`, `novas.*`, coverage databases, firmware build
outputs, editor/OS junk, plus third-party drop-ins whose sources already live
in `rtl/`.

Rules:

1. `core/Cores-VeeR-EL2` is a **locked submodule** — never edit; wrap, don't fork.
2. Commit per phase **with evidence**. Never claim PASS without a log and a waveform.
3. `git status` should show nothing but intended changes. An untracked source
   file is a new asset that belongs in the repository.
4. New flow scripts or filelists in `run/` are tracked automatically — the
   ignore file whitelists `run/*.{f,csh,tcl,rc}` by pattern rather than by name.
5. No source pattern (`*.v`, `*.sv`, `*.vh`, `*.c`, `*.h`) is ever ignored.

---

## 17. First actions for the group

1. **Read** this document, then `SoC_Address_Map.xlsx`, then the group plan.
2. **Decide** §15 items 1, 7 and 12 — the address map, the fabric topology and
   the guard scheme. Everything downstream depends on these three.
3. **Rebuild the environment** (§13): submodule, then the RV32-multilib
   cross-compiler. VCS/Verdi are already present.
4. **Fix the hard-coded paths** (§14), starting with `run/uart_rtl.f`.
5. **Migrate in dependency order** (§2.1).
6. **Re-run every baseline regression** (§10.5) before changing anything, so the
   group has a known-good reference point.
7. **Reparameterise AES** to `0x1000_8000` and re-run its regression (§7.3).
8. Only then start M4 (AES on the SoC) and M5 (NTE + CRC32 + IRQs).

---

## 18. Self-verification checklist

Run from the repository root after any migration step:

```bash
# core pinned and initialised
git submodule status | grep '^ 06ad26a' && grep -c '^\[submodule' .gitmodules

# nothing tracked is ignored; no source file is ignored
git ls-files | git check-ignore --stdin | wc -l        # 0
git check-ignore rtl/uart/uart_axi_slave.v; echo $?     # 1 (not ignored)

# every referenced path exists
for p in rtl/soc_top.sv rtl/ahb rtl/aes rtl/uart rtl/interconnects \
         scripts sw sim tb run Makefile core/Cores-VeeR-EL2/configs/veer.config; do
  [ -e "$p" ] || echo "MISSING: $p"
done

# no absolute paths from the old checkout survive
grep -rn "honours_project\|/tmp/opencode/veer" --include='*.f' --include='*.csh' \
     --include='*.rc' --include='*.tcl' . | grep -v Binary

# addresses agree across RTL, firmware and the canonical map
grep -rn "1000_4000\|10004000" rtl/ sw/          # must be empty (AES moved)

# regressions (needs Synopsys env)
csh -fc 'source /home/student/cshrc; cd run; ./p2_full_flow.csh; echo EXIT=$status'
make -C sw all inspect && make sim               # gates G1–G13
```

Expected: every command above reports success, and each regression prints the
pass token from §10.5.
