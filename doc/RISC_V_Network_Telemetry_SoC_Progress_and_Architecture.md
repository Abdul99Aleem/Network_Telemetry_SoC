# RISC-V Network Telemetry & Secure Packet Monitoring SoC

## Project Progress, Architecture Baseline, AXI Interconnect, AES Integration and Verification Record

**Document status:** Current implementation/progress snapshot\
**Architecture baseline:** V2.0 / implementation-oriented baseline\
**Processor target:** VeeR EL2 RV32IMC\
**System-level bus baseline:** AHB-Lite\
**Current isolated peripheral-integration bus:** AXI4\
**Current verified subsystem:** AXI 2×8 interconnect → AES-128 AXI
slave\
**Primary tools:** Synopsys VCS, Verdi/FSDB\
**Current date:** 2026-09-05

------------------------------------------------------------------------

# Table of Contents

1.  [Purpose of This Document](#1-purpose-of-this-document)
2.  [Project Objective](#2-project-objective)
3.  [Overall SoC Architecture](#3-overall-soc-architecture)
4.  [Control Path and Data Path](#4-control-path-and-data-path)
5.  [System Memory Map](#5-system-memory-map)
6.  [VeeR EL2 Role](#6-veer-el2-role)
7.  [Why AXI Is Being Used Now](#7-why-axi-is-being-used-now)
8.  [AXI 2×8 Interconnect
    Architecture](#8-axi-28-interconnect-architecture)
9.  [AXI Address Decode](#9-axi-address-decode)
10. [AXI Arbitration Architecture](#10-axi-arbitration-architecture)
11. [AXI Master and Slave Topology](#11-axi-master-and-slave-topology)
12. [AES-128 Accelerator
    Architecture](#12-aes-128-accelerator-architecture)
13. [AES AXI Slave Wrapper](#13-aes-axi-slave-wrapper)
14. [AES Register Map](#14-aes-register-map)
15. [AES Transaction Flow](#15-aes-transaction-flow)
16. [AXI Interconnect → AES Wrapper](#16-axi-interconnect--aes-wrapper)
17. [Standalone AES Verification](#17-standalone-aes-verification)
18. [Single-Master AXI → AES
    Verification](#18-single-master-axi--aes-verification)
19. [Two-Master Contention
    Verification](#19-two-master-contention-verification)
20. [Observed Two-Master Result and Root
    Cause](#20-observed-two-master-result-and-root-cause)
21. [Verification Evidence
    Collected](#21-verification-evidence-collected)
22. [Current RTL File Structure](#22-current-rtl-file-structure)
23. [Current Simulation and VCS
    Flow](#23-current-simulation-and-vcs-flow)
24. [Verdi Waveform Strategy](#24-verdi-waveform-strategy)
25. [Architecture Decisions Made](#25-architecture-decisions-made)
26. [Architecture Decisions Not Yet
    Frozen](#26-architecture-decisions-not-yet-frozen)
27. [What Has Been Proven](#27-what-has-been-proven)
28. [What Has Not Been Proven](#28-what-has-not-been-proven)
29. [Next Implementation Stage](#29-next-implementation-stage)
30. [Risk and Debug Strategy](#30-risk-and-debug-strategy)
31. [Final Current-State Summary](#31-final-current-state-summary)
32. [Source and IP Provenance](#32-source-and-ip-provenance)

------------------------------------------------------------------------

# 1. Purpose of This Document

This document records the engineering work completed so far on the
RISC-V Network Telemetry and Secure Packet Monitoring SoC and
establishes the exact architectural state at the current milestone.

The purpose is to prevent the project from becoming a collection of
disconnected RTL experiments. Every implemented block is described in
terms of:

-   its architectural role,
-   its interface,
-   its address space,
-   its relationship to other blocks,
-   its verification status,
-   what has actually been demonstrated in simulation,
-   and what remains unverified.

The current work has deliberately been split into two layers.

### System architecture

The final SoC is intended to contain:

``` text
                    +----------------------+
                    |      VeeR EL2        |
                    |      RV32IMC         |
                    |                      |
                    | IFU master           |
                    | LSU master           |
                    | PIC / interrupts     |
                    +----------+-----------+
                               |
                               v
                         AHB-Lite fabric
                               |
       +-----------+-----------+-----------+-----------+
       |           |           |           |           |
      IMEM        DMEM       UART        Timer       GPIO

                               |
                 +-------------+-------------+
                 |                           |
                 v                           v
          Network Telemetry              AES-128
              Engine                    Accelerator
                 |                           |
                 v                           v
              CRC32                       Ciphertext
```

### Current isolated integration work

The current work intentionally does not touch VeeR:

``` text
AXI Master 0 ----+
                 |
                 v
          +-------------+
AXI Master 1 --> AXI 2×8|
          | Interconnect|
          +------+------+
                 |
                 | M06
                 v
          +-------------+
          | AES AXI     |
          | Slave       |
          +------+------+
                 |
                 v
            AES-128 Core
```

This isolated AXI subsystem is the current development and verification
boundary.

------------------------------------------------------------------------

# 2. Project Objective

The project objective is to build a compact RISC-V-based SoC capable of
locally processing network traffic and generating protected telemetry.

The intended end-to-end application is:

``` text
Simulated Ethernet-like packet
             |
             v
Network Telemetry Engine
             |
       packet metadata
       counters
       timestamp
             |
             +----> CRC32/FCS verification
             |
             v
          VeeR EL2
             |
             v
     Software assembles
      128-bit telemetry
          record
             |
             v
         AES-128
             |
             v
       128-bit ciphertext
             |
             v
            UART
```

The project intentionally uses hardware/software co-design.

### Hardware responsibilities

-   packet byte reception,
-   protocol/header parsing,
-   packet and byte counters,
-   error accounting,
-   CRC32/FCS checking,
-   timestamp capture,
-   AES encryption.

### Software responsibilities

-   initialization,
-   configuration,
-   interrupt handling,
-   telemetry retrieval,
-   construction of the 128-bit telemetry record,
-   AES job submission,
-   ciphertext retrieval,
-   UART reporting.

The RISC-V processor is therefore a coordinator rather than the engine
for every byte-level operation.

------------------------------------------------------------------------

# 3. Overall SoC Architecture

The current architecture baseline defines the following major blocks.

  -----------------------------------------------------------------------
  Block                   Role                    Current status
  ----------------------- ----------------------- -----------------------
  VeeR EL2                Central RV32IMC         Architecture selected;
                          processor               final integration
                                                  pending

  AHB-Lite interconnect   System-level control    Architecture defined
                          fabric                  

  IMEM                    Program storage         Planned

  DMEM                    Data/stack storage      Planned

  UART                    Telemetry/status output Planned

  Timer                   Timing and packet-event Planned
                          timestamp               

  GPIO                    Status/debug indication Planned

  Network Telemetry       Packet parsing and      Planned/custom RTL
  Engine                  metadata                

  CRC32                   Ethernet FCS integrity  Planned
                          checking                

  AES-128                 Hardware encryption     AXI wrapper/integration
                                                  under active
                                                  verification

  AXI 2×8 fabric          Current isolated        Verified for current
                          integration fabric      AES path

  AES AXI slave           AXI-to-AES              Register path verified
                          register/control        
                          adapter                 

  Two-master testbench    Interconnect contention Implemented; AES vector
                          verification            ordering correction
                                                  pending rerun
  -----------------------------------------------------------------------

The project architecture reserves a 4-KB MMIO window for each
peripheral.

------------------------------------------------------------------------

# 4. Control Path and Data Path

The architecture has two distinct paths.

## 4.1 Control path

The control path carries memory-mapped software transactions.

``` text
VeeR EL2
   |
   v
AHB-Lite
   |
   +--> UART
   +--> Timer
   +--> GPIO
   +--> Network Telemetry registers
   +--> AES registers
   +--> CRC32 registers
```

For the current isolated AES work, the corresponding control path is:

``` text
AXI testbench master
        |
        v
AXI interconnect
        |
        v
AES AXI slave
        |
        +--> KEY registers
        +--> DATA registers
        +--> CONTROL
        +--> STATUS
        +--> RESULT registers
        |
        v
AES core
```

## 4.2 Data path

The network data path is separate from the CPU control path.

``` text
Packet stream
   |
   +------------------+
   |                  |
   v                  v
Telemetry Engine    CRC32
   |                  |
   +--------+---------+
            |
            v
       packet event
            |
            v
           CPU
            |
            v
      128-bit record
            |
            v
          AES-128
            |
            v
        ciphertext
```

The AES accelerator does not parse packets. It only consumes a 128-bit
plaintext block and a 128-bit key.

------------------------------------------------------------------------

# 5. System Memory Map

The project-level proposed memory map is:

  Address range                    Size Block
  ----------------------------- ------- --------------------
  `0x0000_0000 – 0x0000_7FFF`     32 KB Instruction memory
  `0x0001_0000 – 0x0001_7FFF`     32 KB Data memory
  `0x1000_0000 – 0x1000_0FFF`      4 KB UART
  `0x1000_1000 – 0x1000_1FFF`      4 KB Timer
  `0x1000_2000 – 0x1000_2FFF`      4 KB GPIO
  `0x1000_3000 – 0x1000_3FFF`      4 KB Network Telemetry
  `0x1000_4000 – 0x1000_4FFF`      4 KB AES-128
  `0x1000_5000 – 0x1000_5FFF`      4 KB CRC32

The AES base address is therefore:

``` text
AES_BASE = 0x1000_4000
```

The address assignment is a project-level integration decision. It is
not a requirement imposed by VeeR EL2 itself.

The current AXI interconnect simulation independently confirms the same
4-KB downstream windows:

``` text
M00: 0x0000_0000 - 0x0000_7FFF
M01: 0x0001_0000 - 0x0001_7FFF
M02: 0x1000_0000 - 0x1000_0FFF
M03: 0x1000_1000 - 0x1000_1FFF
M04: 0x1000_2000 - 0x1000_2FFF
M05: 0x1000_3000 - 0x1000_3FFF
M06: 0x1000_4000 - 0x1000_4FFF
M07: 0x1000_5000 - 0x1000_5FFF
```

This is an important integration result: the implemented AXI fabric
currently follows the project peripheral address organization.

------------------------------------------------------------------------

# 6. VeeR EL2 Role

VeeR EL2 is the selected central processor and is specified by the
project architecture as RV32IMC.

The final system is intended to use the processor for:

1.  boot and initialization,
2.  peripheral configuration,
3.  network-event interrupt service,
4.  telemetry retrieval,
5.  CRC status checking,
6.  AES key/data programming,
7.  AES completion handling,
8.  ciphertext retrieval,
9.  UART reporting.

The supplied VeeR EL2 documentation indicates that the core family
supports configurable system-bus options including AXI4 and AHB-Lite
configurations.

The final project architecture currently uses AHB-Lite as the system-bus
baseline. Therefore the current AXI work is deliberately an isolated
subsystem milestone and is not being presented as the final VeeR
connection.

------------------------------------------------------------------------

# 7. Why AXI Is Being Used Now

The current work intentionally focuses on:

``` text
AXI interconnect
        +
AXI bridge/wrapper
        +
AES
```

without touching VeeR.

This isolates several engineering problems:

-   AXI channel handshaking,
-   address decode,
-   arbitration,
-   master routing,
-   slave response routing,
-   register access,
-   AES control sequencing,
-   result retrieval.

This is a better debugging boundary than simultaneously changing:

``` text
VeeR
+
AHB
+
AHB-to-AXI bridge
+
AXI interconnect
+
AES wrapper
+
AES core
```

The current milestone is therefore:

> Prove that a multi-master AXI fabric can reliably access AES as a
> memory-mapped peripheral.

Only after that boundary is stable should the VeeR-side bridge be
introduced.

------------------------------------------------------------------------

# 8. AXI 2×8 Interconnect Architecture

The implemented interconnect is based on an AXI4 2-master × 8-slave
topology.

``` text
                 +----------------------+
                 |   AXI 2×8 Fabric     |
                 |                      |
S00 ------------>|                      |---- M00
                 |                      |---- M01
S01 ------------>| Address Decode       |---- M02
                 | Arbitration          |---- M03
                 | Routing              |---- M04
                 | Response Multiplex   |---- M05
                 |                      |---- M06 ---> AES
                 |                      |---- M07
                 +----------------------+
```

The wrapper file is:

``` text
rtl/interconnects/axi_interconnect_wrap_2x8.v
```

The underlying generic interconnect is:

``` text
rtl/interconnects/axi_interconnect.v
```

The arbitration support is:

``` text
rtl/interconnects/arbiter.v
```

The priority selection support is:

``` text
rtl/interconnects/priority_encoder.v
```

The source contains the Alex Forencich permissive-license headers and is
being used as the AXI fabric implementation.

------------------------------------------------------------------------

# 9. AXI Address Decode

The wrapper assigns:

``` text
M00_BASE_ADDR = 0x0000_0000
M01_BASE_ADDR = 0x0001_0000

M02_BASE_ADDR = 0x1000_0000
M03_BASE_ADDR = 0x1000_1000
M04_BASE_ADDR = 0x1000_2000
M05_BASE_ADDR = 0x1000_3000
M06_BASE_ADDR = 0x1000_4000
M07_BASE_ADDR = 0x1000_5000
```

The peripheral windows M02--M07 are 4 KB wide.

For AES:

``` text
M06_BASE_ADDR = 0x1000_4000
M06_ADDR_WIDTH = 12
```

which produces:

``` text
0x1000_4000 - 0x1000_4FFF
```

The simulation prints the decoded address table at startup. This gives
direct evidence that the fabric is decoding M06 as the AES window.

------------------------------------------------------------------------

# 10. AXI Arbitration Architecture

The generic interconnect uses the supplied arbiter and priority encoder.

The arbiter accepts:

``` text
request
acknowledge
```

and generates:

``` text
grant
grant_valid
grant_encoded
```

The priority encoder converts an active request vector into:

``` text
output_valid
output_encoded
output_unencoded
```

The current arbiter configuration in the generic design is
fixed-priority unless explicitly configured for round-robin.

The two-master verification was intentionally designed so both masters
can target the same downstream M06 window.

That is the correct way to test contention.

Testing:

``` text
S00 -> M06
S01 -> M07
```

would test routing but would not exercise arbitration on the same
destination.

The contention case is:

``` text
S00 ----+
        |
        +----> M06 ----> AES
        |
S01 ----+
```

Both requesters therefore compete for the same downstream resource.

------------------------------------------------------------------------

# 11. AXI Master and Slave Topology

The current AES integration uses 32-bit AXI data:

``` text
DATA_WIDTH = 32
ADDR_WIDTH = 32
ID_WIDTH   = 8
STRB_WIDTH = 4
```

The AXI channels are:

### Write address

``` text
AWID
AWADDR
AWLEN
AWSIZE
AWBURST
AWLOCK
AWCACHE
AWPROT
AWQOS
AWUSER
AWVALID
AWREADY
```

### Write data

``` text
WDATA
WSTRB
WLAST
WUSER
WVALID
WREADY
```

### Write response

``` text
BID
BRESP
BUSER
BVALID
BREADY
```

### Read address

``` text
ARID
ARADDR
ARLEN
ARSIZE
ARBURST
ARLOCK
ARCACHE
ARPROT
ARQOS
ARUSER
ARVALID
ARREADY
```

### Read response

``` text
RID
RDATA
RRESP
RLAST
RUSER
RVALID
RREADY
```

The AES slave uses the same AXI channel structure.

------------------------------------------------------------------------

# 12. AES-128 Accelerator Architecture

The selected AES source is based on the `secworks/aes` project.

The project architecture uses AES-128 because the telemetry record is
exactly 128 bits.

The intended software sequence is:

``` text
1. Load key
2. Load plaintext telemetry record
3. Start/initiate AES
4. Wait for completion
5. Read ciphertext
6. Report ciphertext
```

The AES core itself is not responsible for:

-   packet parsing,
-   CRC,
-   telemetry timestamping,
-   UART,
-   CPU interrupts,
-   AXI routing.

Those responsibilities belong to the surrounding SoC.

------------------------------------------------------------------------

# 13. AES AXI Slave Wrapper

The implemented wrapper is:

``` text
rtl/aes/aes_axi_slave.v
```

Its job is to translate AXI transactions into:

-   register writes,
-   register reads,
-   AES control,
-   AES key input,
-   AES plaintext input,
-   AES result capture,
-   completion indication,
-   interrupt indication.

The wrapper separates AXI protocol handling from the AES algorithm.

Conceptually:

``` text
                 AXI
                  |
                  v
       +----------------------+
       | aes_axi_slave        |
       |                      |
       | AW/W/B handling      |
       | AR/R handling        |
       | Register decode      |
       | AES control          |
       +----------+-----------+
                  |
             AES native
             interface
                  |
                  v
             AES core
```

This separation is important because the AES core does not need to
understand AXI.

------------------------------------------------------------------------

# 14. AES Register Map

The AES peripheral occupies:

``` text
0x1000_4000 - 0x1000_4FFF
```

The implemented register map is:

    Offset         Address Register   Access
  -------- --------------- ---------- --------
    `0x00`   `0x1000_4000` CONTROL    R/W
    `0x04`   `0x1000_4004` STATUS     R
    `0x08`   `0x1000_4008` KEY0       R/W
    `0x0C`   `0x1000_400C` KEY1       R/W
    `0x10`   `0x1000_4010` KEY2       R/W
    `0x14`   `0x1000_4014` KEY3       R/W
    `0x18`   `0x1000_4018` DATA0      R/W
    `0x1C`   `0x1000_401C` DATA1      R/W
    `0x20`   `0x1000_4020` DATA2      R/W
    `0x24`   `0x1000_4024` DATA3      R/W
    `0x28`   `0x1000_4028` RESULT0    R
    `0x2C`   `0x1000_402C` RESULT1    R
    `0x30`   `0x1000_4030` RESULT2    R
    `0x34`   `0x1000_4034` RESULT3    R

## CONTROL

Current wrapper definition:

``` text
CONTROL[0] = START
CONTROL[1] = CLEAR DONE / IRQ
```

The testbench starts an operation by writing:

``` text
0x0000_0001
```

## STATUS

``` text
STATUS[0] = BUSY
STATUS[1] = DONE
```

Expected lifecycle:

``` text
IDLE:
BUSY = 0
DONE = 0

START:
BUSY = 1
DONE = 0

COMPLETE:
BUSY = 0
DONE = 1
```

## Key registers

``` text
KEY0 = bits [31:0]
KEY1 = bits [63:32]
KEY2 = bits [95:64]
KEY3 = bits [127:96]
```

Therefore the wrapper constructs:

``` verilog
aes_key = {key3_reg, key2_reg, key1_reg, key0_reg};
```

## Data registers

Likewise:

``` text
DATA0 = plaintext [31:0]
DATA1 = plaintext [63:32]
DATA2 = plaintext [95:64]
DATA3 = plaintext [127:96]
```

and:

``` verilog
aes_text_in = {data3_reg, data2_reg, data1_reg, data0_reg};
```

## Result registers

The 128-bit result is exposed through:

``` text
RESULT0
RESULT1
RESULT2
RESULT3
```

with the same low-word-to-high-word register organization.

------------------------------------------------------------------------

# 15. AES Transaction Flow

A complete AXI-driven AES operation is:

``` text
                    AXI MASTER
                        |
                        |
                write KEY0..KEY3
                        |
                        v
                  AES registers
                        |
                write DATA0..DATA3
                        |
                        v
                  AES registers
                        |
                write CONTROL[0]
                        |
                        v
                 aes_ld pulse
                        |
                        v
                   AES core
                        |
                        | encryption
                        v
                  aes_text_out
                        |
                        v
                 RESULT0..3
                        |
                        v
                 AXI read result
```

The wrapper also drives:

``` text
busy_reg
done_reg
irq_reg
```

The AES completion signal from the core is intended to close the
transaction.

------------------------------------------------------------------------

# 16. AXI Interconnect → AES Wrapper

The current integration adds a top-level wrapper around the AXI
interconnect and AES slave.

Conceptually:

``` text
S00 AXI
   |
   v
+----------------------------+
| axi_interconnect_wrap_2x8  |
|                            |
| Address decode             |
| M06 selection              |
+-------------+--------------+
              |
              | M06
              v
+----------------------------+
| aes_axi_slave              |
|                            |
| AXI register interface     |
+-------------+--------------+
              |
              v
+----------------------------+
| AES-128 core               |
+----------------------------+
```

The M06 connection is internal to the wrapper. The external interface is
the AXI testbench-facing S00 interface plus the AES interrupt output.

This was the first complete integration boundary between the
already-built AXI interconnect and the AES peripheral.

------------------------------------------------------------------------

# 17. Standalone AES Verification

Before using the AXI fabric, the AES source was tested independently.

The standalone AES verification established that the selected AES RTL is
functional under its original verification environment.

This is an important bottom-up verification principle:

``` text
AES algorithm
    |
    v
Standalone PASS
    |
    v
AES AXI wrapper
    |
    v
AXI register access
    |
    v
AXI interconnect
    |
    v
Multi-master contention
```

If the final system fails, the verified lower layers reduce the
debugging search space.

------------------------------------------------------------------------

# 18. Single-Master AXI → AES Verification

The first integration test used one AXI master.

The testbench exercised:

1.  key register writes,
2.  plaintext register writes,
3.  register readback,
4.  AES start,
5.  BUSY,
6.  DONE,
7.  IRQ,
8.  result reads,
9.  AES known-answer comparison.

The test used the AES-128 known-answer vector:

``` text
Key:
000102030405060708090a0b0c0d0e0f

Plaintext:
00112233445566778899aabbccddeeff

Expected ciphertext:
69c4e0d86a7b0430d8cdb78070b4c55a
```

The register values are loaded according to the wrapper's
little-word-order convention:

``` text
KEY0  = 0c0d0e0f
KEY1  = 08090a0b
KEY2  = 04050607
KEY3  = 00010203

DATA0 = ccddeeff
DATA1 = 8899aabb
DATA2 = 44556677
DATA3 = 00112233
```

The simulation produced:

``` text
WRITE  10004008 <= 0c0d0e0f
WRITE  1000400c <= 08090a0b
WRITE  10004010 <= 04050607
WRITE  10004014 <= 00010203
WRITE  10004018 <= ccddeeff
WRITE  1000401c <= 8899aabb
WRITE  10004020 <= 44556677
WRITE  10004024 <= 00112233
```

All eight register reads returned the expected values.

Then:

``` text
WRITE  10004000 <= 00000001
```

produced:

``` text
BUSY ASSERTED
DONE ASSERTED
IRQ ASSERTED
```

The result reads were:

``` text
RESULT0 = 70b4c55a
RESULT1 = d8cdb780
RESULT2 = 6a7b0430
RESULT3 = 69c4e0d8
```

When reconstructed in the documented word order:

``` text
69c4e0d86a7b0430d8cdb78070b4c55a
```

which matches the expected AES-128 ciphertext.

The single-master integration therefore passed.

------------------------------------------------------------------------

# 19. Two-Master Contention Verification

The next milestone was to prove that the AXI fabric can arbitrate
between two independent masters while both access AES.

The new testbench is:

``` text
tb/tb_axi_interconnect_aes_2master.sv
```

The testbench uses:

``` text
S00
S01
```

as independent AXI requesters.

Both target the same AES M06 region:

``` text
0x1000_4000 - 0x1000_4FFF
```

This intentionally creates contention.

The test architecture is:

``` text
                   +---------------------+
                   | AXI 2×8 interconnect|
                   |                     |
S00 -------------->|                     |
                   |      arbiter        |---- M06 ---> AES
S01 -------------->|                     |
                   +---------------------+
```

The test verifies that:

-   both masters can issue requests,
-   the interconnect accepts both requesters,
-   only the appropriate requester receives the transaction response,
-   IDs are preserved,
-   read data returns to the correct master,
-   AES register ownership remains coherent,
-   AES can operate while the second master continues generating
    traffic.

------------------------------------------------------------------------

# 20. Observed Two-Master Result and Root Cause

The first two-master run produced:

``` text
PASS M0 AES KEY0 write response
PASS M1 AES KEY1 write response
```

Then:

``` text
PASS M0 READ addr=10004008
PASS M1 READ addr=1000400c
```

This demonstrated that the two masters could access different AES
registers correctly under contention.

The remaining AES programming transactions also passed.

The AES operation itself reached:

``` text
BUSY
DONE
```

and the interrupt asserted.

The test then reported four result mismatches:

``` text
RESULT0:
DUT = c7e1bfd0
EXPECTED = 70b4c55a

RESULT1:
DUT = e7a7579a
EXPECTED = d8cdb780

RESULT2:
DUT = 906e274b
EXPECTED = 6a7b0430

RESULT3:
DUT = 29a7a5cc
EXPECTED = 69c4e0d8
```

The failure was traced to the testbench's AES input word ordering.

The first test had used:

``` text
KEY0 = 03020100
KEY1 = 07060504
KEY2 = 0b0a0908
KEY3 = 0f0e0d0c

DATA0 = 33221100
DATA1 = 77665544
DATA2 = bbaa9988
DATA3 = ffeeddcc
```

Those values are byte-reversed relative to the already passing AES
vector convention.

Therefore the AES core was correctly encrypting a different input.

The two-master testbench was corrected to use:

``` text
KEY0 = 0c0d0e0f
KEY1 = 08090a0b
KEY2 = 04050607
KEY3 = 00010203

DATA0 = ccddeeff
DATA1 = 8899aabb
DATA2 = 44556677
DATA3 = 00112233
```

The corrected testbench file retains the same project filename:

``` text
tb_axi_interconnect_aes_2master.sv
```

The corrected file has been generated, but the corrected two-master
simulation still needs to be rerun.

This distinction is critical:

> The first two-master run did not demonstrate an interconnect failure.
> The four failures were caused by the test vector's byte/word ordering.

------------------------------------------------------------------------

# 21. Verification Evidence Collected

The following evidence has been produced.

## 21.1 Address decode

The simulation prints:

``` text
0: 00000000 / 15 -- 00000000-00007fff
1: 00010000 / 15 -- 00010000-00017fff
2: 10000000 / 12 -- 10000000-10000fff
3: 10001000 / 12 -- 10001000-10001fff
4: 10002000 / 12 -- 10002000-10002fff
5: 10003000 / 12 -- 10003000-10003fff
6: 10004000 / 12 -- 10004000-10004fff
7: 10005000 / 12 -- 10005000-10005fff
```

M06 is therefore confirmed as the AES window.

## 21.2 Register routing

Single-master test:

``` text
KEY0..KEY3: PASS
DATA0..DATA3: PASS
```

## 21.3 AXI write path

Verified through:

``` text
AW
W
B
```

including independent AW/W behavior in the AES slave.

## 21.4 AXI read path

Verified through:

``` text
AR
R
```

including correct data and response behavior.

## 21.5 AES operation

Verified:

``` text
START
BUSY
DONE
IRQ
RESULT
```

in the passing single-master test.

## 21.6 Two-master access

The first contention run verified:

``` text
S00 -> AES register
S01 -> AES register
```

and correct routing of IDs/responses.

## 21.7 VCS/Verdi

The environment successfully performed:

``` text
VCS compile
VCS elaboration
KDB generation
FSDB generation
simulation
```

The generated FSDB was:

``` text
axi_interconnect_2x8.fsdb
```

for the two-master run.

------------------------------------------------------------------------

# 22. Current RTL File Structure

The current relevant RTL organization is:

``` text
honours_project/
|
+-- rtl/
|   |
|   +-- aes/
|   |   |
|   |   +-- aes_axi_slave.v
|   |   |
|   |   +-- ip/
|   |       |
|   |       +-- aes_cipher_top.v
|   |       +-- aes_key_expand_128.v
|   |       +-- aes_rcon.v
|   |       +-- aes_sbox.v
|   |       +-- timescale.v
|   |
|   +-- interconnects/
|       |
|       +-- arbiter.v
|       +-- axi_interconnect.v
|       +-- axi_interconnect_wrap_2x8.v
|       +-- priority_encoder.v
|
+-- tb/
|   |
|   +-- tb_axi_interconnect_aes.sv
|   +-- tb_axi_interconnect_aes_2master.sv
|
+-- run/
|   |
|   +-- aes_axi_interconnect_run.f
|   +-- aes_axi_2master_run.f
|   +-- compile logs
|   +-- FSDB files
|   +-- VCS generated directories
|
+-- doc/
```

The top-level AXI-to-AES integration wrapper used during this work is:

``` text
rtl/aes/axi_aes_wrapper.v
```

when present in the active project tree.

------------------------------------------------------------------------

# 23. Current Simulation and VCS Flow

The VCS flow is run from:

``` text
run/
```

The single-master AXI/AES file list is:

``` text
aes_axi_interconnect_run.f
```

The two-master contention file list is:

``` text
aes_axi_2master_run.f
```

The compile command is:

``` bash
vcs -full64 -sverilog \
-f aes_axi_interconnect_run.f \
-debug_access+all -kdb \
-l compile_aes_axi_interconnect.log
```

Then:

``` bash
./simv -l sim_aes_axi_interconnect.log
```

For the two-master test:

``` bash
vcs -full64 -sverilog \
-f aes_axi_2master_run.f \
-debug_access+all -kdb \
-l compile_aes_2master.log
```

and:

``` bash
./simv -l sim_aes_2master.log
```

Verdi can be launched with the generated FSDB:

``` bash
verdi -ssf axi_interconnect_2x8.fsdb &
```

The Linux-version warning reported by VCS on Rocky Linux 8.10 is
environmental and did not prevent compilation, elaboration, or
simulation.

The ASLR save/restore informational message is also not a functional RTL
error.

------------------------------------------------------------------------

# 24. Verdi Waveform Strategy

Waveform inspection should be performed hierarchically.

## 24.1 Top-level AXI

Observe:

``` text
S00:
s00_axi_awvalid
s00_axi_awready
s00_axi_awaddr
s00_axi_wvalid
s00_axi_wready
s00_axi_wdata
s00_axi_bvalid
s00_axi_bready

s00_axi_arvalid
s00_axi_arready
s00_axi_araddr
s00_axi_rvalid
s00_axi_rready
s00_axi_rdata
s00_axi_rid
```

For S01, observe the equivalent signals.

## 24.2 Arbitration

Inspect the actual arbiter hierarchy and signals such as:

``` text
request
acknowledge
grant
grant_valid
grant_encoded
```

The exact hierarchy should be selected from the elaborated design rather
than guessed.

The important property is:

``` text
when S00 and S01 request the same resource,
one requester is granted for the active transaction
and the response returns to the correct requester.
```

## 24.3 M06

Observe:

``` text
m06_axi_awvalid
m06_axi_awready
m06_axi_awaddr

m06_axi_wvalid
m06_axi_wready
m06_axi_wdata

m06_axi_bvalid
m06_axi_bready

m06_axi_arvalid
m06_axi_arready
m06_axi_araddr

m06_axi_rvalid
m06_axi_rready
m06_axi_rdata
m06_axi_rid
```

## 24.4 AES wrapper

Observe:

``` text
aw_pending
w_pending
write_complete

key0_reg
key1_reg
key2_reg
key3_reg

data0_reg
data1_reg
data2_reg
data3_reg

busy_reg
done_reg
irq_reg
aes_ld

aes_key
aes_text_in
aes_text_out
aes_done
```

The most important control relationship is:

``` text
AXI CONTROL write
        |
        v
aes_ld pulse
        |
        v
AES core starts
        |
        v
aes_done
        |
        +--> busy clears
        +--> done sets
        +--> result registers update
        +--> irq sets
```

------------------------------------------------------------------------

# 25. Architecture Decisions Made

The following decisions are currently established.

## 25.1 AES is a memory-mapped accelerator

AES is not connected directly to the packet byte stream.

Instead:

``` text
packet
  |
  v
telemetry
  |
  v
CPU
  |
  v
128-bit record
  |
  v
AES
```

## 25.2 AES address

``` text
0x1000_4000
```

is the project-level AES base address.

## 25.3 AES window

``` text
0x1000_4000 - 0x1000_4FFF
```

is a 4-KB window.

## 25.4 32-bit software-visible registers

The RV32 processor naturally accesses:

``` text
32-bit CONTROL
32-bit STATUS
32-bit KEYx
32-bit DATAx
32-bit RESULTx
```

The AES datapath remains 128 bits.

## 25.5 AXI is the current isolated verification interface

The AES peripheral is currently driven through AXI so that the
interconnect and wrapper can be validated before VeeR integration.

## 25.6 Two-master contention targets M06

Both S00 and S01 can target:

``` text
M06 = AES
```

to test real arbitration.

## 25.7 VeeR is intentionally not being changed yet

The VeeR-side bridge is deferred until the AXI/AES subsystem is stable.

------------------------------------------------------------------------

# 26. Architecture Decisions Not Yet Frozen

Several items remain open.

## 26.1 Final VeeR bus protocol

The architecture baseline currently specifies AHB-Lite.

The VeeR EL2 family also supports AXI4 configuration.

Therefore the final system must explicitly choose one of:

``` text
Option A

VeeR AXI4
    |
AXI fabric
    |
AES AXI
```

or:

``` text
Option B

VeeR AHB-Lite
    |
AHB fabric
    |
AHB-to-AES adapter
    |
AES register interface
```

The current AXI work does not decide this by itself.

## 26.2 Final bridge architecture

The user-selected future direction is a bridge-based integration.

The bridge must eventually translate the VeeR/system-bus transaction
format into the peripheral interface used by the AES subsystem.

The exact bridge must be designed only after the VeeR build
configuration is frozen.

## 26.3 Interrupt integration

The AES wrapper provides an `aes_irq` signal.

The final path will be:

``` text
AES
 |
aes_irq
 |
interrupt aggregation/PIC
 |
VeeR
```

The exact aggregation mechanism depends on the supplied VeeR
configuration.

## 26.4 AES word ordering

The software-visible register order is defined, but the mapping between:

``` text
KEY0..KEY3
DATA0..DATA3
RESULT0..RESULT3
```

and the AES core's native byte/state convention must remain explicitly
documented.

The corrected testbench now uses the convention proven by the passing
single-master vector.

------------------------------------------------------------------------

# 27. What Has Been Proven

The following statements are supported by actual simulation results.

## 27.1 The AXI interconnect compiles and elaborates

VCS completed:

``` text
0 error(s)
0 warning(s)
```

for the successful integration compilation.

## 27.2 M06 address decode is correct

The simulation explicitly reports:

``` text
M06 = 0x1000_4000 - 0x1000_4FFF
```

## 27.3 AXI writes reach AES registers

The single-master test successfully wrote all key and data registers.

## 27.4 AXI reads return AES register contents

All key and data register readbacks passed.

## 27.5 AES START is reachable through AXI

Writing:

``` text
0x1000_4000 = 1
```

caused AES operation to start.

## 27.6 AES completion occurs

The passing single-master run reached:

``` text
BUSY
DONE
IRQ
```

## 27.7 AES ciphertext is correct

The single-master test matched:

``` text
69c4e0d86a7b0430d8cdb78070b4c55a
```

## 27.8 Two masters can access AES

The first two-master run demonstrated successful register writes and
reads from both masters.

## 27.9 AXI response IDs are preserved

The two-master log showed:

``` text
M1 READ ... RID=55 expRID=55
M1 READ ... RID=56 expRID=56
...
```

The response ID routing was therefore behaving correctly in the tested
transactions.

------------------------------------------------------------------------

# 28. What Has Not Been Proven

The following are not yet complete.

## 28.1 Corrected two-master AES result test

The testbench has been corrected for the byte-order issue, but the
corrected simulation must still be run.

## 28.2 Long-duration arbitration fairness

A short contention test does not establish starvation freedom or
fairness over long sequences.

## 28.3 Burst transactions

The current AES use case is register-oriented and word-based. AXI burst
behavior has not been exhaustively verified against the AES slave.

## 28.4 Error responses

Invalid AES register accesses and unmapped interconnect addresses
require explicit negative testing.

## 28.5 Backpressure stress

Long-lasting READY deassertion and response stalls should be tested
independently.

## 28.6 Final VeeR integration

No VeeR CPU transaction is currently part of this AXI/AES test.

## 28.7 AHB-to-AXI bridge

The bridge is not yet implemented.

## 28.8 Full telemetry-to-AES flow

The Network Telemetry Engine, CRC32, CPU software, timestamp path, and
UART have not yet been connected into one executable end-to-end SoC.

------------------------------------------------------------------------

# 29. Next Implementation Stage

The immediate next action is:

``` text
Rerun corrected two-master AXI -> AES test
```

Expected result:

``` text
PASS checks : 19
FAIL checks : 0
```

with ciphertext:

``` text
69c4e0d86a7b0430d8cdb78070b4c55a
```

If that passes, the AXI subsystem milestone can be considered complete
at the current functional level.

The next stage should then be:

``` text
              Current verified boundary
                       |
                       v
             +------------------+
             | AXI 2×8          |
             | Interconnect     |
             +--------+---------+
                      |
                     M06
                      |
                      v
                   AES AXI
                      |
                      v
                    AES
```

followed by bridge work:

``` text
VeeR system bus
       |
       v
+----------------+
| Bus Bridge     |
| AHB/AXI        |
+-------+--------+
        |
        v
 AXI interconnect
        |
        v
      AES
```

The exact direction depends on the final VeeR bus configuration.

------------------------------------------------------------------------

# 30. Risk and Debug Strategy

The current project should continue using layered verification.

## Rule 1: Do not debug multiple protocols simultaneously

Do not introduce VeeR/AHB while AXI/AES failures remain.

## Rule 2: Verify each boundary

Required boundaries:

``` text
AES core
   |
AES register wrapper
   |
AXI interconnect
   |
bridge
   |
VeeR
```

## Rule 3: Use known-answer vectors

AES debugging should always use a known vector before randomized
testing.

## Rule 4: Treat byte ordering as an explicit architectural interface

A 128-bit value is not enough information by itself.

The project must define:

``` text
register order
word order
byte order
core vector order
```

and test those mappings explicitly.

## Rule 5: Separate routing failures from algorithm failures

If:

``` text
wrong RESULT
```

first verify:

``` text
KEY registers
DATA registers
```

before modifying the AES core.

If those are correct, inspect:

``` text
aes_key
aes_text_in
aes_ld
aes_done
```

before changing AXI logic.

## Rule 6: Preserve the passing regression

The single-master test should remain as a baseline.

Do not replace it with the two-master test.

The regression structure should be:

``` text
Test 1:
AXI -> AES single master

Test 2:
AXI -> AES two-master contention

Test 3:
future bridge -> AXI -> AES

Test 4:
future VeeR -> bridge -> AXI -> AES
```

------------------------------------------------------------------------

# 31. Final Current-State Summary

The project has progressed from independent IP study into actual
subsystem integration.

The current verified architecture is:

``` text
                         S00 AXI MASTER
                               |
                               |
                         S01 AXI MASTER
                               |
                               v
                   +----------------------+
                   |      AXI 2×8         |
                   |      Interconnect    |
                   |                      |
                   | Address decode       |
                   | Arbitration          |
                   | Routing              |
                   | Response return      |
                   +----------+-----------+
                              |
                             M06
                              |
                     0x1000_4000
                              |
                              v
                   +----------------------+
                   |     AES AXI Slave    |
                   |                      |
                   | CONTROL              |
                   | STATUS               |
                   | KEY0..KEY3           |
                   | DATA0..DATA3         |
                   | RESULT0..RESULT3     |
                   +----------+-----------+
                              |
                              v
                   +----------------------+
                   |      AES-128         |
                   |       Core           |
                   +----------+-----------+
                              |
                              v
                         ciphertext
```

The broader final SoC remains:

``` text
                         VeeR EL2
                         RV32IMC
                            |
                         AHB-Lite
                            |
                 +----------+----------+
                 |                     |
             System IP             Accelerators
                 |                     |
       +---------+---------+       +---+-------+
       |         |         |       |           |
      IMEM      DMEM      UART    AES         CRC
                 |                  ^
               Timer                |
                 |            telemetry record
               GPIO                 |
                                    |
                            Network Telemetry
                                  Engine
                                    ^
                                    |
                             packet stream
```

### Completed milestones

-   project architecture baseline established,
-   system memory map established,
-   AES address window established,
-   AES register map established,
-   AES source integrated,
-   AES AXI slave wrapper implemented,
-   AXI 2×8 interconnect integrated,
-   M06 mapped to AES,
-   single-master AXI → AES testbench completed,
-   AXI register routing verified,
-   AES start/busy/done/IRQ path verified in the passing single-master
    run,
-   AES known-answer ciphertext verified,
-   two-master contention testbench implemented,
-   two-master register routing and response-ID behavior verified,
-   byte-order issue in the first two-master AES vector identified,
-   corrected two-master testbench generated,
-   VCS/Verdi/FSDB flow established.

### Immediate remaining item

Run the corrected:

``` text
tb_axi_interconnect_aes_2master.sv
```

and obtain:

``` text
19 PASS
0 FAIL
```

### Explicitly deferred

-   VeeR integration,
-   AHB-to-AXI bridge,
-   final interrupt/PIC integration,
-   Network Telemetry Engine integration,
-   CRC32 integration,
-   software driver/application,
-   complete packet-to-AES-to-UART end-to-end test.

The current engineering boundary is therefore deliberately:

``` text
AXI master(s)
      |
      v
AXI 2×8 interconnect
      |
     M06
      |
      v
AES AXI slave
      |
      v
AES-128
```

This is the subsystem that should be made fully regression-clean before
introducing the VeeR-side bridge.

------------------------------------------------------------------------

# 32. Source and IP Provenance

The project architecture documents identify the following major sources.

  ----------------------------------------------------------------------------
  Component               Source                       Role
  ----------------------- ---------------------------- -----------------------
  VeeR EL2                CHIPS Alliance               CPU
                          Cores-VeeR-EL2               

  VeeR reference          CHIPS Alliance VeeRwolf      Reference SoC
  ecosystem                                            architecture

  AES                     secworks/aes                 AES-128/256 core source

  CRC32                   alexforencich/verilog-lfsr   CRC implementation

  AXI interconnect        Alex Forencich AXI           Current isolated AXI
                          components                   fabric
  ----------------------------------------------------------------------------

The current project-specific integration work includes:

``` text
aes_axi_slave.v
AXI/AES integration wrapper
single-master AES AXI testbench
two-master contention testbench
address-map integration
register mapping
verification infrastructure
```

The final report should preserve upstream copyright/license notices in
reused RTL and clearly distinguish:

``` text
third-party IP
```

from:

``` text
project-authored RTL
```

------------------------------------------------------------------------

# Appendix A --- Key Addresses

``` text
AES_BASE = 0x1000_4000

CONTROL  = 0x1000_4000
STATUS   = 0x1000_4004

KEY0     = 0x1000_4008
KEY1     = 0x1000_400C
KEY2     = 0x1000_4010
KEY3     = 0x1000_4014

DATA0    = 0x1000_4018
DATA1    = 0x1000_401C
DATA2    = 0x1000_4020
DATA3    = 0x1000_4024

RESULT0  = 0x1000_4028
RESULT1  = 0x1000_402C
RESULT2  = 0x1000_4030
RESULT3  = 0x1000_4034
```

------------------------------------------------------------------------

# Appendix B --- Known AES Test Vector

``` text
Key:
000102030405060708090a0b0c0d0e0f

Plaintext:
00112233445566778899aabbccddeeff

Expected ciphertext:
69c4e0d86a7b0430d8cdb78070b4c55a
```

Register representation:

``` text
KEY0  = 0c0d0e0f
KEY1  = 08090a0b
KEY2  = 04050607
KEY3  = 00010203

DATA0 = ccddeeff
DATA1 = 8899aabb
DATA2 = 44556677
DATA3 = 00112233
```

Expected result registers:

``` text
RESULT0 = 70b4c55a
RESULT1 = d8cdb780
RESULT2 = 6a7b0430
RESULT3 = 69c4e0d8
```

------------------------------------------------------------------------

# Appendix C --- Verification Hierarchy

``` text
LEVEL 0
AES core
    |
    +-- known-answer tests

LEVEL 1
AES AXI slave
    |
    +-- AXI write
    +-- AXI read
    +-- register readback
    +-- START
    +-- STATUS
    +-- RESULT

LEVEL 2
AXI 2×8 + AES
    |
    +-- M06 address decode
    +-- S00 access
    +-- response routing

LEVEL 3
AXI 2×8 + AES + S00/S01 contention
    |
    +-- arbitration
    +-- ID routing
    +-- simultaneous traffic
    +-- AES correctness

LEVEL 4
Future bridge
    |
    +-- system bus -> AXI
    +-- protocol conversion
    +-- ordering
    +-- backpressure

LEVEL 5
VeeR SoC
    |
    +-- CPU boot
    +-- MMIO
    +-- interrupts
    +-- AES software driver

LEVEL 6
Complete application
    |
    +-- packet input
    +-- telemetry
    +-- CRC
    +-- timestamp
    +-- CPU
    +-- AES
    +-- UART
```

------------------------------------------------------------------------

# Appendix D --- Current Definition of Done for AXI/AES Subsystem

The current AXI/AES subsystem should be considered complete only when
all of the following pass:

-   [ ] Single-master register test
-   [ ] Single-master AES known-answer test
-   [ ] Two-master simultaneous write contention
-   [ ] Two-master simultaneous read contention
-   [ ] Correct response ID routing
-   [ ] AES operation while second master is active
-   [ ] Corrected AES ciphertext comparison
-   [ ] IRQ verification
-   [ ] Invalid register access
-   [ ] Mapped/unmapped address test
-   [ ] AXI backpressure test
-   [ ] Reset/restart test
-   [ ] Multiple sequential AES transactions
-   [ ] Clean VCS regression
-   [ ] Waveform evidence captured in Verdi

Once this list is clean, the subsystem is a suitable stable target for
the next bridge-integration phase.
