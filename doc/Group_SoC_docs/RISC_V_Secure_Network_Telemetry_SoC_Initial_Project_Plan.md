# Secure Network Telemetry and Edge Processing SoC
## Initial Project Plan and Architecture Specification

**Project type:** RISC-V SoC / RTL System Integration / Hardware-Software Co-Design  
**Processor:** VeeR EL2, RV32IMC  
**System bus:** AHB-Lite  
**Primary verification:** RTL simulation + bare-metal C  
**Architecture status:** Initial group-level architecture plan  
**Document status:** Working baseline for implementation planning  
**Last updated:** 2026-10-03

---

## 1. Document Purpose

This document captures the current SoC plan agreed for the project. It combines the existing VeeR EL2 / AHB-Lite / Network Telemetry / AES / CRC / UART architecture with the newly selected network-oriented IP blocks:

- Ethernet MAC
- Hardware Timestamp Unit
- SHA-256 Accelerator
- Packet/Flow Buffer
- Packet Parser / Classifier function

UART is retained as the software-visible telemetry and debug output path.

The intent is to provide one coherent implementation plan rather than a collection of unrelated IP demonstrations.

> **Important baseline rule:** The existing project architecture and verification records remain the implementation baseline. Newly selected Ethernet/security/buffering blocks are additions to the group-level architecture and are not yet equivalent to already-verified RTL.

---

# 2. Project Vision

The SoC is planned as a:

> **Secure Network Telemetry and Edge Processing SoC based on VeeR EL2**

The system combines a RISC-V control plane with a hardware network data plane.

The SoC receives Ethernet traffic, checks frame integrity, timestamps packet events, parses/classifies packet information, collects network telemetry, buffers packet/flow information, and uses hardware cryptographic accelerators to protect telemetry before reporting it through UART.

The RISC-V processor is the **control and management plane**. Repetitive high-rate packet operations are intended to remain in hardware.

---

# 3. Core Design Philosophy

The architecture follows five principles.

### 3.1 Hardware data plane

Packet bytes should not have to traverse the CPU through MMIO one byte at a time.

The high-rate path remains a streaming hardware path:

```text
Ethernet
   |
   v
Ethernet MAC
   |
   v
CRC / FCS Check
   |
   v
Timestamp
   |
   v
Packet Parser / Classifier
   |
   +--------------------+
   |                    |
   v                    v
Network Telemetry    Packet / Flow Buffer
Engine (NTE)             |
   |                     |
   +----------+----------+
              |
              v
             DMA
              |
              v
        System Memory
```

### 3.2 CPU control plane

VeeR EL2 configures and services the hardware blocks through memory-mapped registers.

```text
VeeR EL2
   |
   v
AHB-Lite
   |
   +--> Ethernet MAC registers
   +--> NTE registers
   +--> Timestamp registers
   +--> Packet/Flow Buffer registers
   +--> DMA registers
   +--> AES registers
   +--> SHA-256 registers
   +--> CRC registers
   +--> UART registers
   +--> Timer
   +--> GPIO
   +--> Interrupt controller
```

### 3.3 Hardware/software partitioning

Hardware handles:

- packet streaming
- Ethernet framing
- CRC/FCS checking
- packet length tracking
- packet/byte/error accounting
- timestamp capture
- packet parsing/classification
- buffering
- DMA movement
- cryptographic acceleration

Software handles:

- initialization
- configuration
- rule programming
- event handling
- telemetry retrieval
- cryptographic job submission
- reporting
- diagnostics

### 3.4 Application-driven integration

The intended application flow is:

```text
Network traffic
      |
      v
Hardware packet processing
      |
      v
Telemetry / event generation
      |
      v
RISC-V software
      |
      v
Hardware cryptography
      |
      v
UART telemetry reporting
```

### 3.5 Verification-first development

Every major block must have:

1. standalone verification,
2. interface verification,
3. SoC integration verification,
4. end-to-end verification.

---

# 4. Current IP Set

## 4.1 Processing

| IP / Block | Role | Status |
|---|---|---|
| VeeR EL2 | RV32IMC CPU / control plane | Existing baseline |
| IMEM | Instruction storage | Existing baseline |
| DMEM | Data/stack storage | Existing baseline |

## 4.2 Network Data Plane

| IP / Block | Role | Status |
|---|---|---|
| Ethernet MAC | Ethernet frame RX/TX interface | **New planned IP** |
| CRC-32 / FCS Checker | Ethernet integrity checking | Existing architecture; integration baseline |
| Packet Parser / Classifier | Extract packet metadata and classify traffic | **Planned architecture block** |
| Network Telemetry Engine (NTE) | Packet/byte/error counters, length and telemetry snapshot | Existing custom IP |
| Hardware Timestamp Unit | Precise packet/event timestamp capture | **New planned IP** |
| Packet / Flow Buffer | Packet storage, flow records and telemetry/event buffering | **New planned IP** |
| DMA Controller | Move buffered data between hardware and memory | Planned / integration target |

## 4.3 Security

| IP / Block | Role | Status |
|---|---|---|
| AES-128 Accelerator | Encrypt telemetry records | Existing integration; completion path still requires final verification |
| SHA-256 Accelerator | Hash / integrity authentication support | **New planned IP** |
| PRNG | Random/security-support function | Planned |
| Watchdog Timer | Fault recovery / system supervision | Planned |

## 4.4 System / Peripheral

| IP / Block | Role | Status |
|---|---|---|
| Custom Interrupt Controller / PIC integration | Aggregate network, AES, timer and other events | Existing architecture |
| Timer | Timing / software timing / timestamp support baseline | Existing architecture |
| UART | Telemetry, debug and encrypted-result reporting | **SoC E2E verified** |
| GPIO | Status/debug outputs | Existing architecture |
| SPI | External low-speed peripheral connectivity | Planned / optional project peripheral |

> **FFT is not part of the current network-centric architecture.** It is intentionally removed from the main system plan so the SoC has a clear network/security identity.

---

# 5. High-Level Architecture

```text
                         SECURE NETWORK TELEMETRY
                         AND EDGE PROCESSING SoC
                              VeeR EL2 Based

 ┌───────────────────────┐
 │       VeeR EL2        │
 │       RV32IMC         │
 │    Control Plane      │
 └──────────┬────────────┘
            │
            │ AHB-Lite
            v
 ┌─────────────────────────────────────────────────────────────┐
 │                  AHB-Lite SYSTEM INTERCONNECT              │
 │        Address Decode / Routing / Response Handling         │
 └───┬──────┬──────┬──────┬──────┬──────┬──────┬─────────────┘
     │      │      │      │      │      │      │
     v      v      v      v      v      v      v
   IMEM   DMEM    UART  Timer   GPIO   NTE   AES/SHA

                         CONTROL / STATUS
                              │
                              │
                              v
                    ┌─────────────────────┐
                    │ Interrupt Controller│
                    └─────────────────────┘


 NETWORK DATA PLANE

 Ethernet PHY / external interface
              │
              │ MII / GMII / RGMII
              v
       ┌───────────────┐
       │ Ethernet MAC  │
       │   RX / TX     │
       └───────┬───────┘
               │
               │ packet stream
               v
       ┌───────────────┐
       │ CRC / FCS     │
       │ Checker       │
       └───────┬───────┘
               │
               v
       ┌────────────────────┐
       │ Timestamp Unit     │
       │ 64-bit counter     │
       └─────────┬──────────┘
                 │
                 v
       ┌────────────────────┐
       │ Packet Parser /    │
       │ Classifier         │
       └───────┬──────┬─────┘
               │      │
               │      └───────────────┐
               v                      v
       ┌───────────────┐      ┌─────────────────┐
       │ Network       │      │ Packet / Flow   │
       │ Telemetry     │      │ Buffer          │
       │ Engine (NTE)  │      │                 │
       └───────┬───────┘      └────────┬────────┘
               │                       │
               │ telemetry/event       │ buffered data
               └──────────┬────────────┘
                          v
                    ┌────────────┐
                    │ DMA Engine │
                    └─────┬──────┘
                          │
                          v
                       DMEM / RAM


 SECURITY / REPORTING

          Telemetry record
                 │
        ┌────────┴─────────┐
        v                  v
 ┌─────────────┐    ┌─────────────┐
 │ AES-128     │    │ SHA-256     │
 │ Encryption  │    │ Hash/Digest │
 └──────┬──────┘    └──────┬──────┘
        │                  │
        └────────┬─────────┘
                 v
              VeeR EL2
                 |
                 v
          ┌─────────────┐
          │ UART TX     │
          └──────┬──────┘
                 v
              uart_tx
```

---

# 6. Two-Plane Architecture

## 6.1 Network Data Plane

The network data plane is the performance-critical path.

```text
Ethernet PHY/interface
        |
        v
Ethernet MAC
        |
        v
CRC/FCS
        |
        v
Timestamp
        |
        v
Parser / Classifier
        |
        +--------------------+
        |                    |
        v                    v
       NTE              Packet/Flow Buffer
        |                    |
        +---------+----------+
                  |
                  v
                 DMA
                  |
                  v
               Memory
```

The packet stream must not be routed through AHB-Lite byte-by-byte.

## 6.2 Control Plane

```text
VeeR EL2
   |
   v
AHB-Lite
   |
   +--> MAC configuration
   +--> NTE configuration/status
   +--> Timestamp control/status
   +--> Buffer configuration/status
   +--> DMA descriptors/control
   +--> CRC status
   +--> AES configuration/data
   +--> SHA-256 configuration/data
   +--> UART output
   +--> Timer
   +--> GPIO
```

---

# 7. Ethernet MAC

## 7.1 Purpose

The Ethernet MAC becomes the connectivity anchor of the SoC.

It separates the project from a pure packet-testbench architecture and provides a clean network-facing boundary.

## 7.2 Responsibilities

The MAC should own:

- Ethernet RX framing
- Ethernet TX framing
- MAC address configuration
- frame boundary detection
- RX/TX packet streaming
- MAC status
- link/status indication where applicable
- interface toward an external PHY or simulation model

The MAC should not own:

- network telemetry counters
- cryptographic processing
- packet classification rules
- DMA memory management

## 7.3 Proposed logical interfaces

```text
External PHY
   |
   | MII / GMII / RGMII
   v
Ethernet MAC
   |
   +--> RX packet stream
   +--> TX packet stream
   |
   +--> AHB-Lite configuration/status registers
```

For the first implementation milestone, the external PHY may be replaced by a simulation-side MAC/PHY model if board-level Ethernet is outside scope.

---

# 8. CRC / FCS

CRC remains a separate responsibility from the MAC.

The current architecture already defines CRC-32/FCS checking as a concurrent packet-processing function.

```text
RX Packet Stream
       |
       +------------------> CRC/FCS Checker
       |
       +------------------> Parser / NTE path
```

Outputs include:

- CRC result
- valid/invalid indication
- error status
- packet completion association

The CRC result must be associated with the correct packet completion event.

---

# 9. Hardware Timestamp Unit

## 9.1 Purpose

The timestamp unit provides hardware timing information for packet events.

The goal is to avoid relying exclusively on software-observed interrupt latency.

## 9.2 Proposed implementation

```text
              +----------------------+
clk --------->| 64-bit Timestamp     |
reset ------->| Counter              |
              +----------+-----------+
                         |
                         v
                 Packet Event Capture
                         |
                         v
                 Timestamp Register
```

## 9.3 Capture events

The initial event should be:

- packet start and/or packet completion

The exact frozen event should be selected before RTL implementation.

## 9.4 CPU interface

The CPU should be able to:

- read current timestamp
- read captured packet timestamp
- clear/re-arm capture status if required
- optionally configure timestamp enable

## 9.5 Relationship to existing Timer

The existing custom Timer remains the software/system timer.

The new Hardware Timestamp Unit is network-data-plane oriented.

This distinction is important:

| Block | Primary purpose |
|---|---|
| Timer | CPU/system timing and interrupts |
| Timestamp Unit | Packet/event timing in the network data path |

---

# 10. Packet Parser / Classifier

## 10.1 Purpose

The parser/classifier turns raw Ethernet bytes into useful metadata and traffic categories.

It is the bridge between:

```text
raw packet bytes
```

and:

```text
network telemetry + flow information
```

## 10.2 Initial parsing scope

The existing implementation-oriented architecture is based on Ethernet II frames.

The PRD describes a broader Ethernet/IPv4/UDP parsing goal.

Therefore the implementation should be staged:

### Baseline

- Ethernet II header
- source MAC
- destination MAC
- EtherType
- frame length

### Extension

- IPv4 header
- source IP
- destination IP
- protocol
- UDP source port
- UDP destination port

The IPv4/UDP stage should not be treated as already implemented unless separately verified.

## 10.3 Classification

The classifier can eventually support rules such as:

```text
Rule:
EtherType == IPv4
        |
        v
IPv4
        |
        +--> UDP
        +--> TCP
        +--> Other

Rule:
UDP destination port == X
        |
        v
Telemetry class
```

The first implementation should keep the rule mechanism small and deterministic.

---

# 11. Network Telemetry Engine (NTE)

## 11.1 Existing role

The NTE is the project's main custom network-monitoring IP.

It is not a generic CPU performance monitor.

It performs network-specific telemetry.

## 11.2 Existing packet-stream model

The current architecture uses:

```text
pkt_valid
pkt_data[7:0]
pkt_last
```

The NTE operates on a synchronous byte stream.

## 11.3 Existing responsibilities

The NTE performs or exposes:

- packet counting
- byte counting
- error accounting
- frame-length tracking
- packet metadata
- telemetry snapshot
- packet completion event
- network interrupt

## 11.4 Planned evolution

With the new architecture:

```text
Ethernet MAC
     |
     v
Parser / Classifier
     |
     +--> NTE
     |
     +--> Packet/Flow Buffer
```

The NTE should focus on statistics and telemetry rather than becoming a packet-storage block.

---

# 12. Packet / Flow Buffer

## 12.1 Purpose

The buffer prevents the CPU from having to process every packet immediately.

It provides temporary hardware-side storage for:

- packet data
- flow records
- telemetry records
- event records

## 12.2 Logical organization

```text
        Packet / Flow Buffer
        ┌──────────────────┐
        │ Packet FIFO      │
        ├──────────────────┤
        │ Flow Records     │
        ├──────────────────┤
        │ Telemetry Queue  │
        └──────────────────┘
```

## 12.3 Why it is needed

Without buffering:

```text
packet -> event -> CPU -> software
```

can become a CPU bottleneck.

With buffering:

```text
packet -> hardware buffer -> DMA -> memory
                       |
                       +--> CPU processes later
```

The buffer therefore decouples network arrival from software service latency.

## 12.4 Initial implementation recommendation

Start with a deterministic ring/FIFO structure.

Freeze:

- depth
- entry width
- packet descriptor format
- write pointer
- read pointer
- overflow behavior
- full/empty semantics
- interrupt threshold

before RTL implementation.

---

# 13. DMA Controller

## 13.1 Purpose

DMA moves buffered packet/telemetry data without requiring the CPU to copy every word.

```text
Packet/Flow Buffer
        |
        v
     DMA
        |
        v
     DMEM/RAM
```

## 13.2 CPU role

VeeR configures:

- source address
- destination address
- transfer length
- descriptor/control
- start
- interrupt enable

DMA performs:

- transfer
- completion
- error reporting

## 13.3 First milestone

A simple single-channel DMA is sufficient for the initial implementation.

Scatter-gather DMA should not be required unless the team has time after the core path is stable.

---

# 14. AES-128 Accelerator

## 14.1 Purpose

AES-128 protects the 128-bit telemetry record.

Existing architecture:

```text
NTE event
   |
   v
VeeR software
   |
   v
128-bit telemetry record
   |
   v
AES-128
   |
   v
ciphertext
   |
   v
UART
```

## 14.2 Existing software interface

The documented AES window is:

```text
0x1000_4000 - 0x1000_4FFF
```

Registers include:

```text
CONTROL
STATUS
KEY0..KEY3
DATA0..DATA3
RESULT0..RESULT3
```

## 14.3 Verification status

The AXI-side AES register interface has been exercised, but the final AES completion/DONE path and AES completion interrupt still require closure according to the AES integration verification record.

Therefore:

> AES register integration is not the same as complete AES end-to-end verification.

---

# 15. SHA-256 Accelerator

## 15.1 Purpose

SHA-256 is added as a complementary security primitive.

AES provides encryption.

SHA-256 provides a digest/integrity primitive.

```text
Telemetry / metadata
        |
        +--> AES-128 --> encrypted telemetry
        |
        +--> SHA-256 --> digest
```

## 15.2 Initial role

The first SHA-256 implementation should provide:

- message input
- start/control
- busy/status
- digest output
- completion indication

The exact register map is an open item until the RTL interface is frozen.

## 15.3 Initial scope

Do not initially build a complete HMAC or TLS engine.

The first milestone is a hardware SHA-256 accelerator with a clean CPU register interface and verified known-answer vectors.

---

# 16. UART

## 16.1 Role

UART is the primary software-visible reporting path.

It is used for:

- boot messages
- diagnostics
- packet statistics
- CRC status
- encrypted telemetry output
- SHA-256 digest output
- verification markers

## 16.2 Current architecture

The documented UART interface is TX-oriented.

Top-level output:

```text
uart_tx
```

The existing Phase-3 record reports successful end-to-end:

```text
VeeR
  -> AHB-Lite
  -> AHB-to-AXI bridge
  -> AXI interconnect
  -> UART
  -> uart_tx
```

The UART E2E test transmitted:

```text
"UART\n"
```

and passed the integrated regression.

## 16.3 Current UART address

```text
0x1000_0000 - 0x1000_0FFF
```

The implemented UART IP-native register map must remain the source of truth for RTL/software integration; the Phase-3 record explicitly notes that the implementation register map differs from the older architecture table.

## 16.4 UART interrupt

The current implementation is TX-only and does not use a UART interrupt.

Software polls the transmitter status and writes bytes.

---

# 17. System Bus Architecture

## 17.1 Baseline

The system-level CPU bus remains:

> **64-bit AHB-Lite**

VeeR instruction and load/store traffic reach system slaves through the AHB-Lite fabric.

## 17.2 Main AHB-Lite slaves

```text
AHB-Lite
 |
 +-- IMEM
 +-- DMEM
 +-- UART
 +-- Timer
 +-- GPIO
 +-- NTE
 +-- AES
 +-- CRC
 +-- Timestamp Unit
 +-- Packet/Flow Buffer
 +-- DMA
 +-- SHA-256
 +-- Ethernet MAC control/status
```

The exact number of slave ports and decoder implementation will be frozen during integration.

## 17.3 AXI subsystem

The project already uses an AHB-to-AXI path for selected peripheral integration.

Current verified UART path:

```text
VeeR
  |
AHB-Lite
  |
AHB-to-AXI
  |
AXI interconnect
  |
UART AXI slave
```

AES has also been integrated into the AXI-side verification environment.

The project should avoid introducing multiple unrelated system buses. AXI is primarily an integration/interconnect mechanism where already justified by the existing implementation.

---

# 18. Proposed Memory Map

The existing documented memory map provides the baseline:

| Address | Size | Block |
|---|---:|---|
| `0x0000_0000` | 32 KB | IMEM |
| `0x0001_0000` | 32 KB | DMEM |
| `0x1000_0000` | 4 KB | UART |
| `0x1000_1000` | 4 KB | Timer |
| `0x1000_2000` | 4 KB | GPIO |
| `0x1000_3000` | 4 KB | Network Telemetry Engine |
| `0x1000_4000` | 4 KB | AES-128 |
| `0x1000_5000` | 4 KB | CRC32 |

### Proposed extension window

The new blocks should be allocated additional non-overlapping 4-KB windows.

**Do not freeze these new addresses until the complete integration map is reviewed.**

Candidate organization:

| Address | Size | Proposed block | Status |
|---|---:|---|---|
| `0x1000_6000` | 4 KB | Ethernet MAC | Proposed |
| `0x1000_7000` | 4 KB | Timestamp Unit | Proposed |
| `0x1000_8000` | 4 KB | Packet/Flow Buffer | Proposed |
| `0x1000_9000` | 4 KB | DMA | Proposed |
| `0x1000_A000` | 4 KB | SHA-256 | Proposed |
| `0x1000_B000` | 4 KB | Packet Parser/Classifier | Proposed |

These addresses are **planning values**, not frozen RTL requirements.

---

# 19. Interrupt Architecture

The interrupt system should preserve the existing event-driven model.

Important sources include:

```text
Network packet/event IRQ
        |
AES completion IRQ
        |
Timer IRQ
        |
DMA completion/error IRQ
        |
Buffer threshold/overflow IRQ
        |
MAC event/error IRQ
        |
SHA-256 completion IRQ
        |
        v
Interrupt Controller / VeeR PIC
        |
        v
VeeR EL2
```

UART remains non-interrupt driven in the current TX-only implementation.

The exact interrupt source numbering must be frozen before software interrupt code is finalized.

---

# 20. End-to-End Application Flow

The intended complete system transaction is:

### Step 1 — Ethernet reception

```text
External network / simulation PHY
             |
             v
        Ethernet MAC
```

### Step 2 — Integrity checking

```text
Ethernet MAC
      |
      v
CRC/FCS Checker
```

### Step 3 — Timestamp

```text
Packet event
     |
     v
Hardware Timestamp Unit
```

### Step 4 — Parsing and classification

```text
Packet bytes
     |
     v
Parser / Classifier
     |
     +--> metadata
     +--> traffic class
```

### Step 5 — Telemetry

```text
metadata
   |
   v
NTE
   |
   +--> counters
   +--> length
   +--> errors
   +--> telemetry snapshot
   +--> NET_IRQ
```

### Step 6 — Buffering

```text
packet / flow / telemetry
          |
          v
Packet/Flow Buffer
```

### Step 7 — DMA

```text
Packet/Flow Buffer
        |
        v
       DMA
        |
        v
      DMEM
```

### Step 8 — CPU service

```text
NET_IRQ
   |
   v
VeeR EL2
   |
   v
read telemetry/status
```

### Step 9 — Security

```text
Telemetry
   |
   +----> AES-128 ----> ciphertext
   |
   +----> SHA-256 ----> digest
```

### Step 10 — Reporting

```text
VeeR
 |
 v
UART
 |
 v
uart_tx
```

---

# 21. Telemetry Record

The existing architecture defines a 128-bit telemetry record.

The current conceptual flow is:

```text
NTE registers
     +
CRC status
     +
timestamp
     +
packet metadata
     |
     v
128-bit telemetry record
```

The record is then submitted to AES-128.

The exact field allocation should remain tied to the frozen architecture specification and must not be silently changed during the new IP integration.

---

# 22. Software Architecture

## 22.1 Firmware structure

The existing software organization includes:

```text
sw/
├── src/
│   ├── startup.S
│   ├── main.c
│   ├── uart.c
│   ├── timer.c
│   ├── gpio.c
│   ├── network.c
│   ├── crc.c
│   ├── aes.c
│   └── interrupts.c
│
└── include/
    └── platform.h
```

The new architecture should extend this with drivers such as:

```text
ethernet.c / ethernet.h
timestamp.c / timestamp.h
buffer.c / buffer.h
dma.c / dma.h
sha256.c / sha256.h
classifier.c / classifier.h
```

## 22.2 Main firmware flow

```c
system_init();

uart_init();
timer_init();
gpio_init();

ethernet_init();
timestamp_init();
crc_init();
nte_init();
buffer_init();
dma_init();

aes_init();
sha256_init();

interrupts_init();

enable_network_processing();

while (1) {
    service_events();
    retrieve_telemetry();
    process_security();
    report_results_uart();
}
```

This is an architectural pseudocode flow, not final firmware.

---

# 23. Verification Strategy

## 23.1 Level 1 — IP verification

Each new block gets a dedicated testbench.

### Ethernet MAC

Verify:

- RX frame
- TX frame
- frame boundaries
- configuration registers
- MAC address
- error conditions

### Timestamp Unit

Verify:

- counter increment
- reset
- capture
- packet-event association
- wraparound

### Packet/Flow Buffer

Verify:

- write
- read
- full
- empty
- wraparound
- overflow
- packet boundaries

### SHA-256

Verify:

- known-answer vectors
- message lengths
- control/status
- digest output
- completion

### Parser/Classifier

Verify:

- valid Ethernet frames
- malformed frames
- metadata extraction
- classification rules

---

# 24. Integration Verification

After standalone IP verification:

```text
MAC
 |
 v
CRC
 |
 v
Parser
 |
 +--> NTE
 |
 +--> Buffer
 |
 v
DMA
 |
 v
DMEM
```

Verify:

- packet flow
- metadata correctness
- telemetry correctness
- buffer correctness
- DMA correctness
- interrupt correctness

---

# 25. Security Verification

## AES

Use known AES-128 test vectors.

Verify:

```text
key + plaintext
       |
       v
     AES
       |
       v
expected ciphertext
```

Then verify:

```text
VeeR
 |
AHB/AXI
 |
AES registers
 |
completion
 |
IRQ
 |
ciphertext
```

## SHA-256

Use standard SHA-256 known-answer vectors.

Verify:

```text
message
   |
   v
SHA-256 accelerator
   |
   v
expected digest
```

---

# 26. SoC End-to-End Verification

The final regression should demonstrate:

```text
Ethernet packet
      |
      v
Ethernet MAC
      |
      v
CRC
      |
      v
Timestamp
      |
      v
Parser / Classifier
      |
      +----------+
      |          |
      v          v
     NTE       Buffer
      |          |
      |          v
      |         DMA
      |          |
      |          v
      |         DMEM
      |
      v
    IRQ
      |
      v
   VeeR EL2
      |
      +------------------+
      |                  |
      v                  v
   AES-128             SHA-256
      |                  |
      +--------+---------+
               |
               v
             UART
               |
               v
            uart_tx
```

The scoreboard should compare:

- received packet count
- byte count
- packet length
- CRC/FCS result
- timestamp/event association
- classification result
- buffer contents
- DMA destination data
- telemetry record
- AES ciphertext
- SHA-256 digest
- UART output

---

# 27. Current Verified Baseline

The project already has meaningful verified foundations.

## 27.1 VeeR / software flow

The project has an established VeeR EL2 bare-metal software/build/simulation flow.

The documented toolchain uses the RISC-V bare-metal configuration associated with the project.

## 27.2 AHB memory path

The project has demonstrated VeeR system-bus accesses to project memories.

## 27.3 UART

The Phase-3 UART record reports:

```text
VeeR
 -> AHB-Lite
 -> AHB-to-AXI
 -> AXI interconnect
 -> UART
 -> uart_tx
```

as an end-to-end passing path.

## 27.4 AES

The AXI-side AES register integration has been exercised.

The final completion/DONE/interrupt path remains an integration item according to the AES verification record.

## 27.5 Network telemetry

The NTE architecture is defined around a packet byte stream and packet-completion telemetry interrupt.

---

# 28. Current vs Planned Status

| Block | Current state |
|---|---|
| VeeR EL2 | Existing project baseline |
| IMEM | Existing |
| DMEM | Existing |
| AHB-Lite | Existing |
| AHB-to-AXI path | Existing / verified in UART path |
| UART | **E2E PASS** |
| Timer | Existing architecture |
| GPIO | Existing architecture |
| NTE | Existing custom architecture |
| CRC32/FCS | Existing architecture |
| AES-128 | AXI integration exercised; completion closure pending |
| Ethernet MAC | **New / planned** |
| Timestamp Unit | **New / planned** |
| Packet/Flow Buffer | **New / planned** |
| Packet Parser/Classifier | **New / planned** |
| SHA-256 | **New / planned** |
| DMA | Planned integration target |
| PRNG | Planned |
| Watchdog | Planned |
| SPI | Planned / optional |
| FFT | **Removed from current network-centric plan** |

---

# 29. Implementation Phases

## Phase 0 — Architecture Freeze

Freeze:

- top-level block diagram
- IP responsibilities
- bus topology
- clock/reset scheme
- memory map
- register maps
- interrupt map
- packet interfaces
- buffer format
- telemetry format

**Definition of done:** no ambiguous ownership between blocks.

---

## Phase 1 — Network Connectivity

Implement:

1. Ethernet MAC
2. RX packet stream
3. TX packet stream
4. basic MAC registers
5. simulation PHY/MAC interface

**Gate:** valid Ethernet frames enter and leave the MAC correctly.

---

## Phase 2 — Timestamp + CRC

Integrate:

1. CRC/FCS checker
2. hardware timestamp unit
3. packet event association

**Gate:** every test packet produces correct CRC status and timestamp.

---

## Phase 3 — Parser / Classifier

Implement:

1. Ethernet header parser
2. metadata extraction
3. basic classification
4. optional IPv4/UDP extension

**Gate:** known packets produce correct metadata/classification.

---

## Phase 4 — NTE Integration

Connect:

```text
Parser -> NTE
```

Verify:

- packet count
- byte count
- errors
- length
- telemetry snapshot
- NET_IRQ

**Gate:** hardware telemetry matches reference model.

---

## Phase 5 — Packet / Flow Buffer

Implement:

- packet FIFO
- flow record storage
- telemetry queue
- ring pointers
- overflow handling

**Gate:** no data corruption across wraparound tests.

---

## Phase 6 — DMA

Implement:

```text
Buffer -> DMA -> DMEM
```

Verify:

- source/destination
- length
- completion
- error
- interrupt

**Gate:** memory contents exactly match expected buffered data.

---

## Phase 7 — Security

Complete:

1. AES-128
2. SHA-256

AES must first close its completion/DONE path.

SHA-256 must pass known-answer vectors.

**Gate:** CPU-controlled cryptographic jobs produce reference results.

---

## Phase 8 — UART Reporting

Extend the already verified UART path to report:

```text
packet statistics
CRC status
timestamp
classification
AES ciphertext
SHA-256 digest
DMA/buffer status
```

**Gate:** final UART stream matches expected software output.

---

## Phase 9 — Full SoC Regression

Run the complete chain:

```text
Ethernet
 -> MAC
 -> CRC
 -> Timestamp
 -> Parser
 -> NTE
 -> Buffer
 -> DMA
 -> VeeR
 -> AES/SHA
 -> UART
```

**Final gate:** reproducible end-to-end PASS with waveform and scoreboard evidence.

---

# 30. Definition of Done

The project should be considered functionally complete only when:

- [ ] VeeR EL2 boots the final SoC
- [ ] AHB-Lite routing is verified
- [ ] UART remains E2E verified
- [ ] Ethernet MAC RX is verified
- [ ] Ethernet MAC TX is verified
- [ ] CRC/FCS is verified
- [ ] Hardware timestamp capture is verified
- [ ] Parser/classifier is verified
- [ ] NTE telemetry is verified
- [ ] Packet/flow buffer is verified
- [ ] DMA transfers are verified
- [ ] AES completion is verified
- [ ] AES interrupt is verified
- [ ] SHA-256 is verified
- [ ] Interrupt aggregation is verified
- [ ] Firmware controls all required blocks
- [ ] Telemetry record is generated correctly
- [ ] AES ciphertext is correct
- [ ] SHA-256 digest is correct
- [ ] UART reports the expected result
- [ ] Full end-to-end packet-to-UART regression passes
- [ ] Waveforms are archived
- [ ] Test logs are archived
- [ ] Register/memory maps match RTL and firmware
- [ ] No undocumented interface changes remain

---

# 31. Important Architecture Boundaries

To keep the project clean, responsibilities should not overlap unnecessarily.

| Block | Owns | Does not own |
|---|---|---|
| Ethernet MAC | Ethernet RX/TX framing | Telemetry |
| CRC | Frame integrity | Classification |
| Timestamp | Packet/event time | Packet statistics |
| Parser | Header/metadata extraction | Long-term storage |
| Classifier | Traffic category/rules | Cryptography |
| NTE | Network statistics/telemetry | Packet storage |
| Buffer | Temporary packet/flow storage | CPU control policy |
| DMA | Data movement | Packet interpretation |
| AES | Encryption | Hashing |
| SHA-256 | Digest | Encryption |
| UART | Serial reporting | Packet processing |
| VeeR | Control/software | High-rate byte processing |

---

# 32. Key Open Items Before RTL Freeze

The following must be resolved before the new blocks are treated as architectural requirements.

1. Exact Ethernet MAC external interface:
   - MII
   - GMII
   - RGMII
   - simulation-only stream for first milestone

2. Ethernet MAC clocking and reset.

3. Exact packet-stream handshake between MAC and downstream blocks.

4. Exact timestamp capture event:
   - first byte
   - last byte
   - accepted packet boundary

5. Timestamp width and rollover behavior.

6. Parser scope:
   - Ethernet only
   - Ethernet + IPv4
   - Ethernet + IPv4 + UDP

7. Classifier rule count and rule format.

8. Packet/flow buffer depth and entry format.

9. DMA channel count and descriptor format.

10. SHA-256 register map.

11. New IP base addresses.

12. New interrupt source IDs.

13. Final clock/reset domain strategy.

14. Final telemetry record field allocation.

15. Whether external Ethernet PHY hardware is required for the final demonstration or simulation is sufficient.

---

# 33. Architecture Consistency Notes

There are two important source-level distinctions that must remain explicit.

### 33.1 NTE packet scope

The implementation-oriented architecture document describes the current NTE around Ethernet II frames and states that IPv4/higher-layer parsing is a future extension.

The PRD describes the intended broader Ethernet/IPv4/UDP capability.

Therefore the project should treat:

```text
Ethernet II telemetry
```

as the safe baseline, while:

```text
IPv4 / UDP parsing
```

is a planned extension unless separately implemented and verified.

### 33.2 UART status

UART is already integrated through the AHB-to-AXI path and has an end-to-end verification record.

The UART implementation record also notes that the actual IP-native register map differs from an older architecture table.

Therefore:

> RTL/IP-native UART register behavior is the source of truth for firmware integration.

---

# 34. Recommended Final Project Story

The project can be presented as one coherent system:

> **A VeeR EL2-based secure network telemetry and edge-processing SoC that receives Ethernet traffic, performs hardware packet integrity checking, timestamps and classifies network traffic, collects telemetry, buffers and DMA-transfers packet information, protects telemetry using AES-128 and SHA-256 hardware accelerators, and reports results through UART.**

This gives each major IP a defined role in one end-to-end application.

---

# 35. Final Architecture at a Glance

```text
                              ┌──────────────────┐
                              │    VeeR EL2      │
                              │    RV32IMC CPU    │
                              └────────┬─────────┘
                                       │
                                  64-bit AHB-Lite
                                       │
                  ┌────────────────────┴────────────────────┐
                  │          SYSTEM INTERCONNECT             │
                  └──┬────┬────┬────┬────┬────┬────┬──────┘
                     │    │    │    │    │    │    │
                    IMEM DMEM UART Timer GPIO AES  SHA
                                                   |
                                              Security path

 NETWORK PATH
 ──────────────────────────────────────────────────────────────

 External PHY / simulation
            │
            v
     ┌──────────────┐
     │ Ethernet MAC │
     └──────┬───────┘
            │
            v
     ┌──────────────┐
     │ CRC / FCS    │
     └──────┬───────┘
            │
            v
     ┌──────────────┐
     │ Timestamp    │
     └──────┬───────┘
            │
            v
     ┌─────────────────┐
     │ Parser /        │
     │ Classifier      │
     └──────┬────┬─────┘
            │    │
            │    └──────────────┐
            v                   v
     ┌─────────────┐    ┌─────────────────┐
     │     NTE     │    │ Packet / Flow   │
     │  Telemetry  │    │ Buffer          │
     └──────┬──────┘    └────────┬────────┘
            │                    │
            │ IRQ                │
            │                    v
            │                  DMA
            │                    │
            │                    v
            │                  DMEM
            │
            v
         VeeR EL2
            │
       ┌────┴─────┐
       │          │
       v          v
     AES-128    SHA-256
       │          │
       └────┬─────┘
            │
            v
          UART
            │
            v
         uart_tx


 SYSTEM SUPPORT
 ──────────────────────────────────────────────────────────────

 Timer
 GPIO
 Interrupt Controller
 Watchdog
 PRNG
 SPI
```

---

# 36. Source Basis

This planning document is based on the project's existing uploaded architecture and verification records, especially:

- `RISC_V_Network_Telemetry_SoC_Architecture_Document_v3.md`
- `RISC_V_Network_Telemetry_SoC_Progress_and_Architecture.md`
- `PRD_RISCV_Network_Telemetry_SoC.md`
- `RISC_V_Network_Telemetry_SoC_Port_List.md`
- `AES_AXI_Integration_Verification_Record.md`
- `Phase3_UART_End_To_End_Completion_Record.md`
- `RISC_V_SW_Build_and_Simulation_Image_Architecture_Specification.md`
- `Fw0_C_Toolchain_Build_and_Gate_Record.md`
- `Firmware_Build_and_AHB_RW_Verification_Record.md`

The newly selected Ethernet MAC, Hardware Timestamp Unit, SHA-256 Accelerator, Packet/Flow Buffer, and the group-level network pipeline are treated as **new planned additions** rather than retroactively claimed as already verified.

---

# 37. Immediate Next Actions

The recommended next implementation sequence is:

```text
1. Freeze final block diagram
        ↓
2. Freeze IP responsibility table
        ↓
3. Freeze clock/reset architecture
        ↓
4. Freeze expanded memory map
        ↓
5. Freeze interrupt map
        ↓
6. Freeze packet-stream interfaces
        ↓
7. Freeze buffer/DMA data structures
        ↓
8. Implement Ethernet MAC interface
        ↓
9. Implement Timestamp Unit
        ↓
10. Integrate Parser/Classifier
        ↓
11. Integrate NTE
        ↓
12. Integrate Packet/Flow Buffer
        ↓
13. Integrate DMA
        ↓
14. Close AES completion path
        ↓
15. Add SHA-256
        ↓
16. Extend UART reporting
        ↓
17. Run complete packet → telemetry → crypto → UART test
```

**Architecture milestone:** Once items 1–7 are frozen, the team should treat subsequent interface changes as controlled design changes rather than ad-hoc RTL modifications.
