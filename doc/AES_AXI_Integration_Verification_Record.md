# AES-128 Accelerator Integration and Verification Record

**Project:** RISC-V Network Telemetry and Secure Packet Monitoring SoC\
**Component:** AES-128 hardware accelerator\
**Current wrapper:** `rtl/aes/aes_axi_slave.v`\
**Standalone AES source:** `aes/aes_core-master/`\
**Verification:** Synopsys VCS + Verdi/FSDB\
**Status:** AXI register interface verified; AES completion path not yet
verified\
**Date:** 2026-09-05

------------------------------------------------------------------------

## 1. Purpose of This Document

This document records the AES integration work performed so far:

1.  The standalone AES RTL was compiled and tested with VCS.
2.  The AES repository structure and original testbench were inspected.
3.  A memory-mapped AES register specification was established.
4.  An AXI slave wrapper was created around the AES core.
5.  An AXI testbench was created for register and control verification.
6.  VCS compilation was moved to the project `run/` directory.
7.  Verdi KDB and FSDB dumping were enabled.
8.  AXI write/read handshaking and register readback were brought to a
    passing state.
9.  The current remaining failure is AES `DONE`/completion: `BUSY`
    asserts but never clears and the testbench times out.

The document deliberately separates the **architecture specification**
from the **current RTL implementation status**. Where the two differ,
the difference is called out explicitly.

------------------------------------------------------------------------

# 2. Architecture Baseline

The project architecture defines AES-128 as a memory-mapped accelerator
controlled by the VeeR EL2 processor.

The architecture document specifies:

-   AES-128 only.
-   One 128-bit plaintext telemetry record per encryption transaction.
-   Software-controlled key loading.
-   Software-controlled encryption start.
-   Hardware AES computation.
-   Interrupt-driven completion.
-   Software-readable ciphertext.

The intended control path is:

``` text
VeeR EL2
   |
   v
System Interconnect
   |
   v
AES Register Wrapper
   |
   +--> KEY0..KEY3
   +--> DATA0..DATA3
   +--> CONTROL
   +--> STATUS
   +--> RESULT0..RESULT3
   |
   v
AES-128 Core
```

The AES core is not connected directly to the packet stream. The CPU
first obtains packet telemetry, constructs a 128-bit telemetry record,
writes it to AES, waits for completion, and reads the ciphertext.

------------------------------------------------------------------------

# 3. Important Bus Architecture Distinction

There are two different things that must not be conflated.

## 3.1 Project architecture baseline

The current architecture document defines the SoC system bus as:

``` text
VeeR EL2
   |
   v
AHB-Lite interconnect
   |
   +--> IMEM
   +--> DMEM
   +--> UART
   +--> Timer
   +--> GPIO
   +--> Network Telemetry
   +--> AES
   +--> CRC32
```

The architecture document specifies a 64-bit AHB-Lite connection at the
VeeR/system-bus boundary.

## 3.2 Current isolated AES verification

The AES block is currently being verified behind an AXI-style slave
wrapper:

``` text
AXI master testbench
        |
        v
aes_axi_slave
        |
        v
AES core
```

This is an **isolated IP verification stage**, not yet the final VeeR
SoC connection.

The supplied VeeR EL2 PRM states that the core's system bus can be
configured as either:

``` text
64-bit AXI4
or
64-bit AHB-Lite
```

Therefore, an AXI-based AES wrapper is compatible with a VeeR
configuration that uses AXI, but it does not by itself prove
compatibility with the currently documented AHB-Lite SoC fabric.

### Integration decision still required

Before final SoC integration, the project must freeze one of these
architectures:

``` text
Option A:
VeeR AXI4
   |
AXI interconnect
   |
AES AXI slave

Option B:
VeeR AHB-Lite
   |
AHB-Lite interconnect
   |
AHB-to-AES wrapper/adapter
   |
AES register interface
```

Do not silently mix an AXI AES slave into an AHB-Lite system.

------------------------------------------------------------------------

# 4. AES Memory Map

The project architecture assigns AES the following 4-KB peripheral
window:

  Address range                      Size Peripheral
  -------------------------------- ------ ------------
  `0x1000_4000` -- `0x1000_4FFF`     4 KB AES-128

The AES base address is therefore:

``` text
AES_BASE = 32'h1000_4000
```

The register addresses are:

    Offset   Absolute address Register   Access
  -------- ------------------ ---------- --------
    `0x00`      `0x1000_4000` CONTROL    R/W
    `0x04`      `0x1000_4004` STATUS     R
    `0x08`      `0x1000_4008` KEY0       R/W
    `0x0C`      `0x1000_400C` KEY1       R/W
    `0x10`      `0x1000_4010` KEY2       R/W
    `0x14`      `0x1000_4014` KEY3       R/W
    `0x18`      `0x1000_4018` DATA0      R/W
    `0x1C`      `0x1000_401C` DATA1      R/W
    `0x20`      `0x1000_4020` DATA2      R/W
    `0x24`      `0x1000_4024` DATA3      R/W
    `0x28`      `0x1000_4028` RESULT0    R
    `0x2C`      `0x1000_402C` RESULT1    R
    `0x30`      `0x1000_4030` RESULT2    R
    `0x34`      `0x1000_4034` RESULT3    R

The remaining addresses inside `0x1000_4000–0x1000_4FFF` are reserved.

------------------------------------------------------------------------

# 5. Why `0x1000_4000` Was Selected

`0x1000_4000` was not selected because VeeR EL2 requires AES to live
there.

It is a **project-level peripheral address assignment**.

The project memory map divides the system MMIO region into simple 4-KB
peripheral windows:

``` text
0x1000_0000 – 0x1000_0FFF   UART
0x1000_1000 – 0x1000_1FFF   Timer
0x1000_2000 – 0x1000_2FFF   GPIO
0x1000_3000 – 0x1000_3FFF   Network Telemetry
0x1000_4000 – 0x1000_4FFF   AES
0x1000_5000 – 0x1000_5FFF   CRC32
```

This has several engineering advantages:

-   Each peripheral has a 4-KB decode window.
-   Peripheral decode is simple.
-   The low address bits select registers inside the peripheral.
-   No peripheral windows overlap.
-   Software receives stable symbolic base addresses.
-   The address map is easy to extend.

The VeeR EL2 PRM provides an **example** memory map in which system
memory-mapped CSRs occupy the region beginning at `0x1000_0000`. The PRM
does not prescribe the project's individual UART/AES/CRC addresses.
Those addresses are part of the SoC integration design.

Therefore:

``` text
VeeR requirement:
0x1000_4000 is valid as part of the system MMIO address space.

Project requirement:
AES is assigned the 4-KB window 0x1000_4000–0x1000_4FFF.
```

That distinction is important.

------------------------------------------------------------------------

# 6. Register Bit Definitions

## 6.1 CONTROL --- `0x1000_4000`

Current project register definition:

  ----------------------------------------------------------------------------------
               Bit Name           R/W                     Reset Meaning
  ---------------- -------------- ------------ ---------------- --------------------
             `[0]` `START_INIT`   W                         `0` Starts/initializes
                                                                an AES transaction
                                                                according to the
                                                                wrapper control
                                                                sequence

             `[1]` `IRQ_ENABLE`   R/W                       `0` Enables AES
                                                                completion interrupt

          `[31:2]` Reserved       ---                       `0` Reserved; write zero
  ----------------------------------------------------------------------------------

The current testbench starts AES by writing:

``` text
CONTROL = 32'h0000_0001
```

which sets:

``` text
CONTROL[0] = 1
```

The project architecture describes this field as `START/INIT`.

### Important implementation note

The exact separation between:

``` text
INIT
NEXT/START
```

inside the underlying AES core must be preserved when adapting the core.

The software-visible project register is intentionally simpler than the
native AES-core control interface.

------------------------------------------------------------------------

# 7. STATUS --- `0x1000_4004`

Current project definition:

         Bit Name       R/W   Meaning
  ---------- ---------- ----- --------------------------------
       `[0]` `BUSY`     R     AES transaction is in progress
       `[1]` `DONE`     R     AES transaction has completed
    `[31:2]` Reserved   ---   Read as zero

Expected state sequence:

``` text
Idle:
BUSY = 0
DONE = 0

Start:
BUSY = 1
DONE = 0

Completion:
BUSY = 0
DONE = 1
```

If completion is interrupt-driven, the expected interrupt relationship
is:

``` text
AES completion
     |
     +--> DONE = 1
     |
     +--> AES_IRQ = 1 when IRQ_ENABLE = 1
```

The current simulation reaches the first transition:

``` text
BUSY = 1
```

but never reaches:

``` text
DONE = 1
BUSY = 0
```

This is the current open failure.

------------------------------------------------------------------------

# 8. KEY Registers

The AES-128 key is 128 bits and is exposed as four 32-bit software
registers.

  Register     Offset Bits
  ---------- -------- ----------
  KEY0         `0x08` `[31:0]`
  KEY1         `0x0C` `[31:0]`
  KEY2         `0x10` `[31:0]`
  KEY3         `0x14` `[31:0]`

The current test used:

``` text
KEY0 = 0x0c0d0e0f
KEY1 = 0x08090a0b
KEY2 = 0x04050607
KEY3 = 0x00010203
```

The resulting 128-bit key, when concatenated in this software-visible
order, is:

``` text
0c0d0e0f08090a0b0405060700010203
```

The exact internal byte/word mapping into the AES core must be verified
against the core's native `key[127:0]` convention. AXI register ordering
and AES state-byte ordering are separate concerns.

------------------------------------------------------------------------

# 9. DATA Registers

The plaintext is 128 bits:

  Register     Offset Bits
  ---------- -------- ----------
  DATA0        `0x18` `[31:0]`
  DATA1        `0x1C` `[31:0]`
  DATA2        `0x20` `[31:0]`
  DATA3        `0x24` `[31:0]`

Current test:

``` text
DATA0 = 0xccddeeff
DATA1 = 0x8899aabb
DATA2 = 0x44556677
DATA3 = 0x00112233
```

Concatenated software-visible plaintext:

``` text
ccddeeff8899aabb4455667700112233
```

Again, the wrapper must map these words correctly into the underlying
AES core's 128-bit `text_in` convention.

------------------------------------------------------------------------

# 10. RESULT Registers

The ciphertext is exposed as four read-only 32-bit registers.

  Register     Offset Bits
  ---------- -------- ----------
  RESULT0      `0x28` `[31:0]`
  RESULT1      `0x2C` `[31:0]`
  RESULT2      `0x30` `[31:0]`
  RESULT3      `0x34` `[31:0]`

Software reconstructs the ciphertext from these four words.

Expected flow:

``` text
RESULT0
RESULT1
RESULT2
RESULT3
     |
     v
128-bit ciphertext
```

The RESULT registers should not be considered valid until AES completion
has occurred.

------------------------------------------------------------------------

# 11. Register Access Sequence

The intended software sequence is:

``` text
1. Write KEY0
2. Write KEY1
3. Write KEY2
4. Write KEY3

5. Write DATA0
6. Write DATA1
7. Write DATA2
8. Write DATA3

9. Start AES

10. Poll STATUS.BUSY/DONE
    or wait for AES_IRQ

11. Read RESULT0
12. Read RESULT1
13. Read RESULT2
14. Read RESULT3
```

For interrupt-driven operation:

``` text
CPU
 |
 +-- load key
 +-- load plaintext
 +-- enable AES IRQ
 +-- start
 |
 |       AES hardware
 |            |
 |            +-- encrypt
 |            |
 |            +-- DONE
 |            |
 |            +-- AES_IRQ
 |
 +<-- AES ISR
      |
      +-- read RESULT0..RESULT3
```

------------------------------------------------------------------------

# 12. AES Core Source Actually Tested

The tested source tree contains:

``` text
aes_core-master/
├── aes_core.core
├── bench/
│   └── verilog/
│       └── test_bench_top.v
└── rtl/
    └── verilog/
        ├── aes_cipher_top.v
        ├── aes_inv_cipher_top.v
        ├── aes_inv_sbox.v
        ├── aes_key_expand_128.v
        ├── aes_rcon.v
        ├── aes_sbox.v
        └── timescale.v
```

The core file contains:

``` text
name : asics.ws::aes:1.1
```

and the original RTL/testbench comments identify the implementation as
the older OpenCores/asics.ws AES core.

## Provenance discrepancy

The project PRD currently describes the selected AES IP as:

``` text
secworks/aes
```

However, the repository that was actually cloned and tested contains:

``` text
asics.ws::aes:1.1
```

and files such as:

``` text
aes_cipher_top.v
aes_key_expand_128.v
aes_sbox.v
```

Therefore the project must not describe the currently tested RTL as
`secworks/aes` until the actual repository is confirmed and the RTL is
replaced or the documentation is corrected.

This is a documentation/provenance issue, not merely a naming issue. The
IP license, interface, microarchitecture, and verification evidence must
correspond to the actual RTL used.

------------------------------------------------------------------------

# 13. Standalone AES Verification

Before adding the AXI wrapper, the AES core was tested independently.

The original FuseSoC metadata was inspected, but FuseSoC was
intentionally not used for project simulation.

The project uses:

``` text
VCS
+
Verdi
+
FSDB
```

instead.

The original testbench was found at:

``` text
bench/verilog/test_bench_top.v
```

with top-level module:

``` text
module test;
```

The standalone VCS simulation completed with:

``` text
Started random test ...

Test Done. Found 0 Errors.
```

This established a useful baseline:

``` text
AES core alone
     |
     v
Original testbench
     |
     v
PASS
```

The later failure is therefore associated with the wrapper/control
integration path rather than being evidence that the AES RTL itself is
nonfunctional.

------------------------------------------------------------------------

# 14. VCS/Verdi Setup

Simulation is launched from:

``` text
honours_project/run/
```

This is valid because the file list uses paths relative to `run/`.

The important VCS options are:

``` text
-full64
-sverilog
-f aes_run.f
-debug_access+all
-kdb
```

`-kdb` is required for Verdi KDB generation.

The simulation produces:

``` text
simv
simv.daidir/
aes_axi_slave.fsdb
sim_aes_axi.log
```

The environment currently reports:

``` text
VCS U-2023.03_Full64
Verdi U-2023.03-SP1
```

The Rocky Linux warning is an environment compatibility warning:

``` text
Unsupported Linux version
Rocky Linux release 8.10
```

It did not prevent compilation or simulation.

------------------------------------------------------------------------

# 15. Run File Structure

The AES AXI simulation file list is conceptually:

``` text
../rtl/aes/aes_axi_slave.v

../aes/aes_core-master/rtl/verilog/timescale.v
../aes/aes_core-master/rtl/verilog/aes_rcon.v
../aes/aes_core-master/rtl/verilog/aes_sbox.v
../aes/aes_core-master/rtl/verilog/aes_key_expand_128.v
../aes/aes_core-master/rtl/verilog/aes_cipher_top.v

../tb/tb_aes_axi_slave.sv
```

Because the AES source contains:

``` verilog
`include "timescale.v"
```

the AES RTL directory must be available to the Verilog include search
path.

The earlier compile failure was:

``` text
Source file "timescale.v" cannot be opened
```

The file-list/include-path handling was then corrected, after which VCS
successfully compiled the design.

------------------------------------------------------------------------

# 16. Problems Encountered During Verification

## 16.1 Wrong file-list name

The first VCS command used:

``` text
-f aes_run.f
```

but the file had initially been created as:

``` text
run.f
```

VCS therefore reported:

``` text
Cannot open file
Unable to open 'aes_run.f'
```

Resolution:

``` text
Create/use aes_run.f
```

inside:

``` text
honours_project/run/
```

------------------------------------------------------------------------

## 16.2 `timescale.v` include failure

The AES RTL explicitly includes:

``` verilog
`include "timescale.v"
```

The first compile attempt could locate the source file itself but not
the included file.

The error was:

``` text
Source file "timescale.v" cannot be opened
```

Resolution:

Ensure the AES RTL directory is included in the Verilog include path.

------------------------------------------------------------------------

## 16.3 Testbench syntax error

The first generated AXI testbench contained an unintended Markdown
code-fence character.

VCS reported:

``` text
Syntax error
token is '`'
```

The testbench was corrected and subsequently compiled successfully.

------------------------------------------------------------------------

## 16.4 AXI write channels initially did not handshake

Verdi initially showed:

``` text
AWVALID = 0
WVALID  = 0
```

so no write transfer could occur.

The wrapper contained:

``` verilog
assign s_axi_awready = !aw_pending && !bvalid_reg;
assign s_axi_wready  = !w_pending  && !bvalid_reg;

assign aw_handshake = s_axi_awvalid && s_axi_awready;
assign w_handshake  = s_axi_wvalid  && s_axi_wready;
```

The important AXI rule is:

``` text
AW handshake = AWVALID && AWREADY
W handshake  = WVALID  && WREADY
```

Both channels must actually be driven by the master testbench.

After correcting the testbench/master behavior, AXI register accesses
worked.

------------------------------------------------------------------------

# 17. Current AXI Verification Result

The latest simulation successfully performed:

``` text
Loading AES key...

AXI WRITE  ADDR=10004008 DATA=0c0d0e0f
AXI WRITE  ADDR=1000400c DATA=08090a0b
AXI WRITE  ADDR=10004010 DATA=04050607
AXI WRITE  ADDR=10004014 DATA=00010203

Loading plaintext...

AXI WRITE  ADDR=10004018 DATA=ccddeeff
AXI WRITE  ADDR=1000401c DATA=8899aabb
AXI WRITE  ADDR=10004020 DATA=44556677
AXI WRITE  ADDR=10004024 DATA=00112233
```

Readback succeeded:

``` text
AXI READ   ADDR=10004008 DATA=0c0d0e0f
AXI READ   ADDR=1000400c DATA=08090a0b
AXI READ   ADDR=10004010 DATA=04050607
AXI READ   ADDR=10004014 DATA=00010203

AXI READ   ADDR=10004018 DATA=ccddeeff
AXI READ   ADDR=1000401c DATA=8899aabb
AXI READ   ADDR=10004020 DATA=44556677
AXI READ   ADDR=10004024 DATA=00112233

Register readback PASS
```

This proves the following:

``` text
AXI address decode             PASS
AXI AW channel                 PASS
AXI W channel                  PASS
AXI write response             PASS
Register write storage         PASS
AXI AR channel                 PASS
AXI R channel                  PASS
Register readback              PASS
Key register mapping           PASS
Plaintext register mapping     PASS
```

------------------------------------------------------------------------

# 18. Current Failure

The test then performed:

``` text
AXI WRITE  ADDR=10004000 DATA=00000001
```

which corresponds to:

``` text
CONTROL[0] = START/INIT
```

The following read returned:

``` text
AXI READ   ADDR=10004004 DATA=00000001
```

which means:

``` text
STATUS.BUSY = 1
```

The testbench correctly detected:

``` text
BUSY asserted
```

However, repeated polling returned:

``` text
STATUS = 0x00000001
```

and never:

``` text
STATUS = 0x00000000
```

or:

``` text
STATUS = 0x00000002
```

The testbench eventually reported:

``` text
ERROR: AES timeout
```

Therefore the current state is:

``` text
CONTROL write              PASS
BUSY assertion             PASS
AES completion             FAIL
DONE assertion             FAIL
BUSY deassertion            FAIL
AES completion IRQ          NOT YET VERIFIED
RESULT verification         NOT YET REACHED
```

------------------------------------------------------------------------

# 19. What the Timeout Does and Does Not Prove

The timeout does **not** prove that the AES core is broken.

The standalone AES test already passed with:

``` text
Found 0 Errors.
```

The timeout indicates that the wrapper-to-core transaction sequencing is
not yet correct.

Potential fault classes are:

1.  AES core `start`/`init`/`next` control sequencing.
2.  AES core `ready`/`done` signal mapping.
3.  Reset polarity or reset timing.
4.  Key-load pulse generation.
5.  Plaintext-load pulse generation.
6.  Core input word/byte ordering.
7.  Wrapper FSM waiting for the wrong completion condition.
8.  Wrapper FSM never observing the core's completion signal.
9.  `DONE` being generated internally but not copied into `STATUS`.
10. AES IRQ being generated with the wrong polarity or condition.
11. Control register bit semantics not matching the underlying AES core.

The correct next step is to inspect the actual AES core control/status
interface and trace it in Verdi. Do not change the timeout value or mask
the problem.

------------------------------------------------------------------------

# 20. Verdi Waveform Verification

The FSDB generated by the latest test is:

``` text
run/aes_axi_slave.fsdb
```

The KDB was generated during VCS elaboration because:

``` text
-kdb
```

was supplied.

Launch Verdi from `run/` using the VCS simulation database.

Typical command:

``` bash
verdi -ssf aes_axi_slave.fsdb -dbdir simv.daidir
```

If the installed Verdi flow accepts the generated KDB directly through
the simulation database, the waveform can also be opened from the Verdi
GUI.

------------------------------------------------------------------------

# 21. Signals to Add in Verdi

## 21.1 AXI write path

Add:

``` text
s_axi_awaddr
s_axi_awvalid
s_axi_awready

s_axi_wdata
s_axi_wstrb
s_axi_wvalid
s_axi_wready

s_axi_bvalid
s_axi_bready
s_axi_bresp
```

Verify:

``` text
AWVALID && AWREADY
WVALID  && WREADY
BVALID  && BREADY
```

Do not require AW and W to handshake on the same clock. AXI allows their
channels to operate independently.

------------------------------------------------------------------------

## 21.2 AXI read path

Add:

``` text
s_axi_araddr
s_axi_arvalid
s_axi_arready

s_axi_rdata
s_axi_rvalid
s_axi_rready
s_axi_rresp
```

Verify:

``` text
ARVALID && ARREADY
RVALID  && RREADY
```

------------------------------------------------------------------------

## 21.3 Wrapper internal state

Add:

``` text
aw_pending
awaddr_reg

w_pending
wdata_reg
wstrb_reg

bvalid_reg

rvalid_reg
rdata_reg
```

These prove whether the bus wrapper is accepting and completing
transactions correctly.

------------------------------------------------------------------------

# 22. AES Control Signals to Trace

The most important next Verdi hierarchy is:

``` text
tb_aes_axi_slave
    |
    +-- dut
        |
        +-- aes_axi_slave
            |
            +-- AES core instance
```

Add every control/status signal exposed by the AES core, especially
signals corresponding to:

``` text
clk
reset
key
key load / key enable
plaintext / text input
start / next
ready
done
ciphertext / text output
```

The exact signal names must be taken from the instantiated AES RTL
rather than guessed.

The key question is:

``` text
CONTROL[0]
   |
   v
wrapper start logic
   |
   v
AES core control input
   |
   v
AES core internal operation
   |
   v
AES core completion/ready
   |
   v
wrapper DONE
   |
   v
STATUS[1]
```

Find the first point where this chain stops.

------------------------------------------------------------------------

# 23. Required AES Completion Waveform

A successful transaction should look conceptually like:

``` text
                 start
                  |
CONTROL[0]  ______|‾|________________________

BUSY        ________|‾‾‾‾‾‾‾‾‾‾‾|__________

core_start  ________|‾|______________________

core_busy   ________|‾‾‾‾‾‾‾‾‾‾‾|__________

core_done   _______________________|‾|________

DONE        _______________________|‾‾‾‾_____

AES_IRQ     _______________________|‾|________

RESULT      XXXXXXXXXXXXXXXXXXXXXXXX|valid|____
```

The exact number of cycles is core-dependent.

The important ordering is:

``` text
START
  ->
core operation
  ->
core completion
  ->
DONE
  ->
AES_IRQ
  ->
RESULT read
```

------------------------------------------------------------------------

# 24. AXI Address Decode

The wrapper should select the AES register block using the AES address
range:

``` text
AES_BASE = 0x1000_4000
AES_END  = 0x1000_4FFF
```

Within the AES wrapper, register decoding should use the local offset:

``` text
local_offset = address - AES_BASE
```

For example:

``` text
0x1000_4000 -> 0x00 -> CONTROL
0x1000_4004 -> 0x04 -> STATUS
0x1000_4008 -> 0x08 -> KEY0
...
0x1000_4034 -> 0x34 -> RESULT3
```

A cleaner implementation is to use the low address bits after the
peripheral has already been selected by the SoC interconnect.

------------------------------------------------------------------------

# 25. Why 32-bit Registers Were Used

The AES data path is 128 bits, but the software-visible registers are 32
bits.

This gives:

``` text
128-bit key
   |
   +-- 32-bit KEY0
   +-- 32-bit KEY1
   +-- 32-bit KEY2
   +-- 32-bit KEY3
```

and:

``` text
128-bit plaintext
   |
   +-- 32-bit DATA0
   +-- 32-bit DATA1
   +-- 32-bit DATA2
   +-- 32-bit DATA3
```

This is convenient for RV32 software because the VeeR EL2 processor is
RV32.

It also makes the register map naturally word-aligned:

``` text
+0x00
+0x04
+0x08
+0x0C
...
```

This does not imply that the VeeR system bus must be 32 bits wide. The
supplied architecture currently specifies a 64-bit system-bus interface
while using 32-bit software-visible peripheral registers.

------------------------------------------------------------------------

# 26. Relationship to the 128-bit Telemetry Record

The project telemetry record is 128 bits.

The intended flow is:

``` text
Network Telemetry registers
        |
        v
RISC-V software
        |
        v
128-bit telemetry record
        |
        +------------------+
        |                  |
        v                  v
DATA0              DATA1 DATA2 DATA3
        |
        v
AES-128
        |
        v
RESULT0..RESULT3
```

The AES block therefore does not need to understand:

-   Ethernet
-   IPv4
-   UDP
-   CRC
-   packet timestamps
-   telemetry field meanings

Those functions remain outside the AES accelerator.

AES only sees:

``` text
128-bit key
128-bit plaintext
start/init
```

and produces:

``` text
128-bit ciphertext
completion
```

------------------------------------------------------------------------

# 27. Verification Layers

The AES work should be completed in the following verification order.

## Layer 1 --- AES core

Already completed:

``` text
Original AES testbench
        |
        v
Known/random vectors
        |
        v
0 errors
```

## Layer 2 --- Register wrapper

Already mostly completed:

``` text
AXI writes
AXI reads
address decode
register storage
readback
```

## Layer 3 --- AES transaction

Current failure:

``` text
START
  |
  v
BUSY
  |
  X
DONE
```

This is the immediate task.

## Layer 4 --- Interrupt

After DONE works:

``` text
AES completion
     |
     v
AES_IRQ
```

must be verified.

## Layer 5 --- Result

After completion:

``` text
RESULT0..RESULT3
```

must be compared against an independent AES reference.

## Layer 6 --- SoC integration

Only after the isolated wrapper passes:

``` text
VeeR
 |
system interconnect
 |
AES slave
```

should be integrated.

------------------------------------------------------------------------

# 28. Required AES Functional Tests

At minimum, test:

### Test 1 --- Register readback

``` text
write KEY0..KEY3
read KEY0..KEY3

write DATA0..DATA3
read DATA0..DATA3
```

Status:

``` text
PASS
```

### Test 2 --- Start/busy

``` text
write CONTROL[0]
read STATUS
```

Expected:

``` text
BUSY = 1
```

Status:

``` text
PASS
```

### Test 3 --- Completion

Expected:

``` text
BUSY = 0
DONE = 1
```

Status:

``` text
CURRENTLY FAILING
```

### Test 4 --- Ciphertext

Compare:

``` text
DUT RESULT
```

against an independent AES-128 reference model.

Status:

``` text
NOT YET EXECUTED THROUGH AXI WRAPPER
```

### Test 5 --- Interrupt

Verify:

``` text
DONE && IRQ_ENABLE -> AES_IRQ
```

Status:

``` text
NOT YET VERIFIED
```

### Test 6 --- Multiple transactions

Run at least:

``` text
transaction 1
transaction 2
transaction 3
...
```

and ensure no stale `DONE`, key, plaintext, or result state leaks
between transactions.

------------------------------------------------------------------------

# 29. Standalone Reference Vector

A standard AES-128 reference transaction should be included in the
wrapper testbench.

The canonical NIST-style vector is:

``` text
KEY:
000102030405060708090a0b0c0d0e0f

PLAINTEXT:
00112233445566778899aabbccddeeff

CIPHERTEXT:
69c4e0d86a7b0430d8cdb78070b4c55a
```

This should be used only after the wrapper's word-order convention has
been explicitly mapped to the AES core's native 128-bit ordering.

A byte-order error can produce a valid-looking but incorrect ciphertext,
so the testbench must not compare arbitrary concatenations without
defining the mapping.

------------------------------------------------------------------------

# 30. Current Project Status

  Item                                    Status
  --------------------------------------- ----------------
  AES source obtained                     PASS
  AES source compiled standalone          PASS
  Original AES testbench executed         PASS
  Standalone AES random test              PASS, 0 errors
  VCS flow                                PASS
  Verdi KDB generation                    PASS
  FSDB generation                         PASS
  AES AXI wrapper compilation             PASS
  AXI AW handshake                        PASS
  AXI W handshake                         PASS
  AXI B response                          PASS
  AXI AR handshake                        PASS
  AXI R response                          PASS
  AES key register write/readback         PASS
  AES plaintext register write/readback   PASS
  START control write                     PASS
  BUSY assertion                          PASS
  AES core completion                     **FAIL**
  STATUS.DONE                             **FAIL**
  BUSY deassertion                        **FAIL**
  AES IRQ                                 Pending
  RESULT correctness                      Pending
  VeeR integration                        Pending
  Final SoC bus compatibility             Pending

------------------------------------------------------------------------

# 31. Immediate Next Debug Task

Do not modify the address map or AXI register logic yet.

The next debug target is exclusively:

``` text
aes_axi_slave
        |
        v
AES core control interface
```

Trace:

``` text
CONTROL[0]
   |
   v
wrapper start/init pulse
   |
   v
AES core key-load/init
   |
   v
AES core start/next
   |
   v
AES core ready/done
   |
   v
wrapper busy/done
```

The goal is to determine exactly which signal fails to transition.

Only after that is known should the RTL be modified.

------------------------------------------------------------------------

# 32. Architecture Compliance Summary

## Compliant

The following are aligned with the project architecture:

-   AES-128 accelerator.
-   Memory-mapped control.
-   `CONTROL`, `STATUS`, key, data, and result registers.
-   AES base address `0x1000_4000`.
-   4-KB AES peripheral window.
-   Four 32-bit key registers.
-   Four 32-bit plaintext registers.
-   Four 32-bit result registers.
-   Software-controlled start.
-   Busy/done status model.
-   Interrupt-driven completion as the final intended behavior.

## Not yet frozen/verified

-   Exact internal AES-core control sequencing.
-   Native AES core word/byte ordering.
-   Completion signal mapping.
-   AES interrupt polarity/behavior.
-   Final VeeR-to-AES bus protocol.

## Important architecture discrepancy

The project architecture baseline uses AHB-Lite, while the current
isolated AES wrapper is AXI-based.

This is acceptable for the current wrapper-level verification stage only
if the final SoC integration resolves the protocol choice explicitly.

------------------------------------------------------------------------

# 33. Source Basis

This record is based on:

1.  Project AES architecture and register-map specification.
2.  Project PRD memory-map and AES-IP specification.
3.  Supplied VeeR EL2 Programmer's Reference Manual.
4.  The actual AES repository structure and `aes_core.core` contents
    inspected during the project.
5.  The actual VCS/Verdi simulation results produced during AES wrapper
    verification.
6.  The current AXI AES wrapper and testbench behavior observed during
    simulation.

The project architecture document defines the AES register map and
`0x1000_4000` peripheral window. The VeeR EL2 PRM establishes that
system-bus interfaces are configurable as 64-bit AXI4 or AHB-Lite and
that system memory-mapped I/O occupies the system address space; it does
not prescribe `0x1000_4000` specifically as an AES address.

------------------------------------------------------------------------

# 34. Final State Diagram

The desired final AES hardware/software contract is:

``` text
              RESET
                |
                v
        +---------------+
        | AES IDLE      |
        | BUSY=0        |
        | DONE=0        |
        +-------+-------+
                |
        write KEY0..KEY3
                |
        write DATA0..DATA3
                |
        write CONTROL.START
                |
                v
        +---------------+
        | AES BUSY      |
        | BUSY=1        |
        | DONE=0        |
        +-------+-------+
                |
                | AES core completes
                v
        +---------------+
        | AES DONE      |
        | BUSY=0        |
        | DONE=1        |
        +-------+-------+
                |
        +-------+-------+
        |               |
        v               v
   AES_IRQ         RESULT0..3
        |               |
        +-------+-------+
                |
                v
        software consumes
          ciphertext
                |
                v
              IDLE
```

The current implementation reaches the `AES BUSY` state but does not yet
reach `AES DONE`. That transition is the next verification milestone.
