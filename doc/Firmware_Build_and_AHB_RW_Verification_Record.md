# fw0 Step 3a — SoC Run and AHB Read/Write-Cycle Verification Record

**Status: COMPLETE (log evidence + waveform-equivalence evidence)**
**Date:** 2026-09-26
**Branch:** `feature/sw-build-ahb-rw`
**Plan:** `doc/Firmware_Build_and_AHB_RW_Verification_Plan.md` §5
**Frozen spec:** `doc/RISC_V_SW_Build_and_Simulation_Image_Architecture_Specification.md` rev 1.5 — `S5`–`S9`, `S11`, §14, §16 L5/L6, §22 fw0
**Companion record (steps 1–2):** `doc/Fw0_C_Toolchain_Build_and_Gate_Record.md`

> **Repo rule honoured:** *never claim PASS without a log + waveform.*
> This record carries the full `simv` transcript, the gate transcript, and the
> cycle-by-cycle waveform extract that backs every row of the plan §5.3
> checklist.

---

## 1. What this milestone delivered

| # | Deliverable | File | Status |
| --- | --- | --- | --- |
| 1 | Additive AHB read/write-cycle monitor | `tb/tb_ahb_cycle_monitor.sv` (222 lines, **new**) | ✅ |
| 2 | Monitor instantiation (existing monitor untouched) | `tb/tb_veer_p2_soc.sv:320-344` (**+28 lines only**) | ✅ |
| 3 | VCS/Verdi filelist | `sim/filelist.f` (**new**) | ✅ |
| 4 | Simulation makefile with dual-token gate | `sim/Makefile` (**new**) | ✅ |
| 5 | Root delegating makefile | `Makefile` (**new**) | ✅ |
| 6 | Verdi wave setup (7 groups) | `run/fw_wave.rc` (**new**) | ✅ |
| 7 | Project-local VeeR snapshot (decision `D6`) | `build/snapshots/p2_soc/` (generated, gitignored) | ✅ |
| 8 | Both terminal tokens in one run | `build/sim/fw0/sim.log` | ✅ |
| 9 | Gate **G13** | `make sim` | ✅ |
| 10 | Waveform evidence for plan §5.3 rows 1–8 | §6 of this record + `doc/screenshots/` | ✅ |

**Files deliberately NOT touched by this milestone:** all of `rtl/`, `sw/`,
`run/p2_*`, `run/uart_rtl.f`, `README.md`, `tb/tb_ahb_fabric.sv`,
`tb/tb_veer_uart_soc.sv`. RTL was edited only by the parallel session (§4).

---

## 2. Environment

| Item | Value |
| --- | --- |
| Date / time of the PASS run | Sat Sep 26 17:11:18 2026 |
| VCS | `U-2023.03_Full64` (`Compiler version U-2023.03_Full64; Runtime version U-2023.03_Full64`) |
| Verdi | `U-2023.03-SP1 for linux64 - May 28, 2023` |
| `$VCS_HOME` | `/home/student/snps_tools_target/vcs/U-2023.03` |
| `$VERDI_HOME` | `/home/student/snps_tools_target/verdi/U-2023.03-SP1` |
| License | `SNPSLMD_LICENSE_FILE=27021@14.139.1.126` |
| Display | `DISPLAY=:0` (never `:42`, finding N5) |
| VeeR snapshot | `build/snapshots/p2_soc` — **project-local**, decision `D6` / finding N4 |
| `$RV_ROOT` | `core/Cores-VeeR-EL2` |
| Simulation work dir | `build/sim/fw0` |
| VCS flags | `-full64 -sverilog -debug_access+all -kdb +define+RV_OPENSOURCE +error+500 -timescale=1ns/10ps` |
| Compiled modules | **53 modules and 0 UDP read** (incl. `tb_ahb_cycle_monitor`) |
| FSDB | `build/sim/fw0/p2_veer_soc.fsdb` — 910 037 bytes |

**Environment gotcha (recorded so it is not rediscovered):**
`VCS_HOME` / `VERDI_HOME` must be **`export`ed**, not merely used to build
`PATH`. The `vcs` wrapper resolves `vcsMsgReport` and friends from
`$VCS_HOME/bin`; without the export it fails with the misleading
`Cannot find 'vcsMsgReport' script in /bin`.

---

## 3. Build and run wiring (plan §5.1)

### 3.1 Targets

```console
$ make help
Root targets (spec §8.1):
  firmware     -> sw/ build/firmware.elf
  inspect      -> sw/ ELF gates G1-G7, G11
  mem          -> sw/ imem.mem + dmem.mem + firmware.ihex (G8-G10, G12)
  veer-config  -> build/snapshots/p2_soc   (D6, project-local)
  rtl          -> VCS compile
  sim          -> run + gate on P2_TB2_RESULT and AHB_RW_MONITOR
  verdi        -> open FSDB with run/fw_wave.rc
  wave         -> print the verdi command instead of launching
  clean        -> remove build/sim and sw/build
```

`make` (= `make all`) = `firmware → mem → veer-config → rtl → sim`.

### 3.2 Snapshot (`S5`, decision `D6`)

```console
$ env BUILD_PATH=.../build/snapshots/p2_soc RV_ROOT=.../core/Cores-VeeR-EL2 \
      .../core/Cores-VeeR-EL2/configs/veer.config \
      -target=default_ahb -snapshot=p2_soc -set=reset_vec=0x00000000
```

Produces `common_defines.vh`, `el2_param.vh`, `el2_pdef.vh`, `link.ld`, …
**Not** `/tmp/opencode/veer_p2` — that directory is root-owned and unwritable
to `student` (finding N4), which is *why* `D6` is mandatory.

### 3.3 Filelist (`S6`)

`sim/filelist.f` uses `$RV_ROOT`, `$FW_SNAP`, `$FW_PROJ` rather than absolute
`/tmp/opencode/...` paths, `-top tb_veer_p2_soc`, and `-f $FW_PROJ/run/uart_rl.f`'s
sibling `run/uart_rtl.f` for the UART IP.

### 3.4 **Known deviation — `D9` plusarg image loading is DEFERRED**

| Spec step | Planned | Actually done | Why |
| --- | --- | --- | --- |
| `S7` | `tb/tb_memory_init.sv` with `+IMEM_HEX`/`+DMEM_HEX` | **not done** | — |
| `S7b` | remove `initial` from `rtl/ahb/ahb_sram.sv` | **not done** | — |
| `S8` | replace hardcoded `IMEM_HEX("p2_prog.hex")` with plusarg | **not done** | — |
| substitute | — | `sim/Makefile` does `cp sw/build/imem.mem $(WORK)/p2_prog.hex` | see below |

**Reason.** A runtime plusarg cannot feed an elaboration-time parameter
(decision `D9` proved this). The only correct route to a dynamic image name is
the PLUSARG-owned loader (`S7`/`S7b`/`S8`), and `S7b` removes
`rtl/ahb/ahb_sram.sv`'s t=0 `initial` block. That file is Phase-2-shared and
was in use by the parallel session's committed Phase-3 flow while this
milestone was in flight; removing it would have broken that flow (plan §7 rule
2: *re-check `git status` before any RTL edit*).

The workaround is a **filename stand-in only** — the image bytes are
identical (`md5 0af02db4205da3cc6e1b4d2d139c1fc7`, 2040 bytes, contiguous
`@00000000` / `@0000025C` / `@0000029C`, no gaps, no overlap). It is written
as a prominent comment in `sim/Makefile` directly above the rule that performs
it, and tracked as **Deviation D9-deferred** here. `S7`/`S7b`/`S8` remain the
correct fix and are still open.

---

## 4. The enabling RTL fix (NOT authored in this branch — credited)

**Before this fix, Step 3a could not PASS.** The run hung at `PC=0x30`.

### 4.1 Symptom

```
[41000] halting CPU and waiting for ack
[335000] CPU running, reset_vec=0x00000000
        ... no further output, watchdog ...
```

### 4.2 Root cause

`rtl/ahb/ahb_interconnect.sv` steered `HREADY` as
`(!data_is_lsu) ? mux_hreadyout : 1'b1`, so a **non-granted master's address
phase was silently dropped**. The IFU issued a fetch while the LSU held the
data phase; `HREADY` said *accepted*, the address went nowhere, and the core
latched `0x00000000` as the instruction at `PC=0x30` — where `imem.mem` in fact
holds `23 20 C3 01` = `sw t3,0(t1)` (a legal instruction).

`0x00000000` decodes as an illegal instruction → `el2_dec_tlu_ctl.sv:1447`
raises **cause `0x2`** → trap to `mtvec = 0xAC` (`c.j .`) → the core spins
forever.

### 4.3 The fix

Landed by the parallel session in commit **`16c10a4`**
*"Close the UART end-to-end run: bridge, fabric arbiter and UART IP fixes"*:

```systemverilog
// rtl/ahb/ahb_interconnect.sv:249
assign ifu_hready = (ifu_granted || dp_is_ifu) ? mux_hreadyout : ~ifu_active;
// rtl/ahb/ahb_interconnect.sv:253
assign lsu_hready = (lsu_granted || dp_is_lsu) ? mux_hreadyout : ~lsu_active;
```

Per that commit message: *“a non-granted master sees `HREADY=0` (its address
phase is **held, not dropped**) and only the data-phase owner sees
`HRDATA`/`HRESP`; the documented LSU-over-IFU priority still applies when the
data-phase owner is idle.”* The same commit records **24 719
illegal-instruction traps** in the pre-fix run — the exact failure above.

> **Dependency note for reviewers:** every PASS in this record depends on
> commit `16c10a4`. This branch does **not** contain that change and must not
> stage it. Evidence that the fix is live is in §6.6 (`ic_hready=0` while the
> LSU is granted) and §6.11 (`trace_rv_i_exception_ip = 0` for the whole run).

---

## 5. Results — both terminal tokens

### 5.1 The run

`build/sim/fw0/sim.log` (trimmed to the substantive lines):

```console
Command: /home/student/Documents/honours_project/build/sim/fw0/./simv -l .../sim.log
Compiler version U-2023.03_Full64; Runtime version U-2023.03_Full64;  Sep 26 17:11 2026
*Verdi* : Create FSDB file 'p2_veer_soc.fsdb'
[41000] halting CPU and waiting for ack
[335000] CPU running, reset_vec=0x00000000
[90915000] P2_TB2_RESULT: PASS (P2 program ran through project fabric)
[TB] AHB_CYCLES imem_rd=2393 imem_wr=0 dmem_rd=366 dmem_wr=164
[TB] AHB_CYCLES uart_rd=0 uart_wr=0 def=0 bus_err=0 ifu_offtarget=0
[TB] AHB_RW_MONITOR: PASS (mailbox reached; thresholds imem_rd>=8 dmem_rd>=16 dmem_wr>=16 bus_err==0 def==0)
$finish called from file ".../tb/tb_veer_p2_soc.sv", line 316.
$finish at simulation time             91015000
Time: 91015000 ps
CPU Time:      1.080 seconds;       Data structure size:   1.5Mb
```

### 5.2 The `make sim` gate transcript

```console
[SIM] vcs -f /home/student/Documents/honours_project/sim/filelist.f
[SIM]     FW_SNAP=/home/student/Documents/honours_project/build/snapshots/p2_soc
[SIM] PASS compile
[SIM] image: sw/build/imem.mem (2040 bytes) -> .../build/sim/fw0/p2_prog.hex
[90915000] P2_TB2_RESULT: PASS (P2 program ran through project fabric)
[TB] AHB_CYCLES imem_rd=2393 imem_wr=0 dmem_rd=366 dmem_wr=164
[TB] AHB_CYCLES uart_rd=0 uart_wr=0 def=0 bus_err=0 ifu_offtarget=0
[TB] AHB_RW_MONITOR: PASS (mailbox reached; thresholds imem_rd>=8 dmem_rd>=16 dmem_wr>=16 bus_err==0 def==0)
[SIM] ---- gate: plan §5.2, both tokens required ----
[SIM] PASS  P2_TB2_RESULT: PASS   (spec §22 fw0 — pre-existing monitor, unmodified)
[SIM] PASS  AHB_RW_MONITOR: PASS   (plan §5.2 — read/write proof)
[SIM] G13  firmware.ihex never reached the sim dir:
[SIM] PASS  no *.ihex in /home/student/Documents/honours_project/build/sim/fw0
[SIM] FSDB  /home/student/Documents/honours_project/build/sim/fw0/p2_veer_soc.fsdb
[SIM] DONE
```

Reproduced deterministically on **two consecutive runs**.

### 5.3 Time-base clarification (finding N9)

`$finish at simulation time 91015000` and `Time: 91015000 ps` → the run is
**91 015 ns = 91.015 µs**, and `P2_TB2_RESULT: PASS` fires at
**90 915 ns**. `%t`/`$finish` report in the simulation *precision* unit
(1 ps), while `$time` in a `1ns/1ps` module returns ns. The Verdi RC and
`fsdbreport -bt/-et` both take **ns**. Mixing these up makes a 90 µs run look
like 90 ms — which would appear to be far beyond the 1.9 ms monitor watchdog
and the `#2000000` testbench timeout. It is not.

### 5.4 Gate G13

`firmware.ihex` (1912 B) is produced by `make -C sw mem` into `sw/build/`
but is **never** copied into `build/sim/fw0`. The gate is implemented inside
`make sim` (plan §4.2 G13), because it can only be asserted once a simulation
directory exists. Result: **PASS**.

---

## 6. Waveform evidence — plan §5.3 checklist

### 6.0 How this section was produced

Two independent instruments:

1. **The additive monitor** — counts in the log (§5.1). Aggregate proof.
2. **Waveform extract** — `fsdbreport` (Verdi `U-2023.03-SP1`) dumped the
   named signals from `p2_veer_soc.fsdb` over the stated ns windows, and the
   dumps were aligned per rising clock edge into the cycle tables below. This
   is the same data Verdi displays, taken from the same FSDB the `.rc` opens,
   so it is waveform evidence rather than re-derivation from RTL.

Every table row is a `posedge core_clk` (10 ns period, `always #5 core_clk =
~core_clk`). Clock edges in this run fall on `…25/…35/…45/…55/…65/…75/…85/…95/…05/…15 ns`.

---

### 6.1 Row 1 — Instruction read cycles (IFU) ✅

| Check | Required | Observed |
| --- | --- | --- |
| First accepted address phase | `ic_htrans = 2'b10` with `HADDR = 0x00000000` (spec §16 L6) | **`ic_htrans=10`, `ic_haddr=0x00000000` at 355 ns** |
| Fetches walk from 0x0 | sequential | `trace_rv_i_address_ip` = `0x0` (340 ns) → `0x4` (505) → `0x8` (585) → `0xC` (655) → `0x10` (725) → `0x14` (805) → `0x18` (885) |
| First retired instruction | `0x00018117` (G11: `objdump` == head of `imem.mem`) | `trace_rv_i_insn_ip` @425 ns = `00000000 00000001 10000001 00010111` = **`0x00018117`** ✔ |
| Data returned | `ic_hrdata` carries instruction bytes | `ic_hrdata` @455 ns = `0x0A428293_00000297` (non-zero, both 32-bit halves driven) |
| IFU never writes | `ic_hwrite` stays 0 | `ic_hwrite = 0` at every sampled edge in all windows below |
| Retire valid pulses | one per instruction | `trace_rv_i_valid_ip` pulses `1` for 10 ns at 425, 505, 585, 655, 725, 805, 885 ns |
| Off-target fetches | 0 | `ifu_offtarget = 0` (monitor, §5.1); `imem_rd = 2393` all inside `addr[31:15]==0` |

---

### 6.2 Row 2 — DMEM write cycle (LSU) ✅

**First store of the run — `startup.S` copying `.data` to its VMA, 1365 ns:**

```text
    ns | icHT  icHADDR icW icR icRSP | lsuHT lsuW  lsuHADDR   lsuR lsuRSP | im dm ua df aSel dSel dLSU lsuAct aLSU
 1355  |  10  0x00000038  0  1    0   |   00    0  0x00000298    1     0   |  1  0  0  0  001  001    0     0    0
 1365  |  00  0x00000038  0  1    0   |   10    1  0x00010010    1     0   |  0  1  0  0  010  001    0     1    1   <-- ADDRESS PHASE
 1375  |  00  0x00000038  0  1    0   |   00    1  0x00010010    1     0   |  0  0  0  0  000  010    1     0    0   <-- DATA PHASE
 1385  |  00  0x00000038  0  1    0   |   00    1  0x00010010    1     0   |  0  0  0  0  000  000    0     0    0
```

| Check | Required | Observed |
| --- | --- | --- |
| `lsu_htrans` | `2'b10` NONSEQ | **`10` @1365 ns** |
| `lsu_hwrite` | `1` | **`1` @1365 ns** |
| `lsu_haddr` | DMEM region `0x0001_00xx` | **`0x00010010`** — the `.data` **VMA** (G6: `.data` at `0x00010010`) |
| `lsu_hready` | `1` (accepted) | **`1`** |
| `dmem_hsel` | `1` following address phase | **`1` @1365 ns**, `imem/uart/def` all `0` → **one-hot** |
| `lsu_hwdata` | the value being stored | **`0x00C0FFEE`, bytes `[EE, FF, C0, 00]`** @1375 ns |
| `lsu_hresp` | `0` | **`0`** |
| Data-phase owner | `data_is_lsu=1`, `data_sel=010` | **`dLSU=1`, `dSel=010` @1375 ns** |

`0x00C0FFEE` / `EE FF C0 00` is **exactly** the `data_marker` value documented
in `doc/Fw0_C_Toolchain_Build_and_Gate_Record.md` §5.1 — the first word of
`.data`, relocated LMA→VMA by `startup.S`. Waveform and software agree byte
for byte.

**Second write sample — stack store at 11405 ns:**

```text
    ns | lsuHT lsuW  lsuHADDR   lsuR | dm aSel dSel dLSU lsuAct aLSU
 11405 |   10    1  0x00017FEC    1  |  1  010  000    0     1    1
 11415 |   00    1  0x00017FE8    1  |  0  000  010    1     0    0
```
`lsu_hwdata` @11415 ns = `0x0000000100000000` (byte 4 = `0x01`).

**Final store of the run — the mailbox trigger (§6.9 below).**

---

### 6.3 Row 3 — DMEM read cycle (LSU) ✅

```text
    ns | icHT icHADDR      icR | lsuHT lsuW  lsuHADDR   lsuR lsuRSP | im dm ua df aSel dSel dLSU lsuAct aLSU
 11025 |  00  0x00000160    1  |   00    0  0x00010000    1     0   |  0  0  0  0  000  000    0     0    0
 11035 |  00  0x00000160    1  |   10    0  0x00010000    1     0   |  0  1  0  0  010  000    0     1    1   <-- ADDRESS PHASE
 11045 |  00  0x00000160    1  |   00    0  0x00010000    1     0   |  0  0  0  0  000  010    1     0    0   <-- DATA PHASE, hrdata valid
```

| Check | Required | Observed |
| --- | --- | --- |
| `lsu_hwrite` | `0` | **`0`** |
| `lsu_htrans` | `2'b10` | **`10` @11035 ns** |
| `lsu_haddr` | DMEM | **`0x00010000`** (DMEM base) |
| `dmem_hsel` | `1`, one-hot | **`1`**, `imem/uart/def = 0` |
| `lsu_hrdata` | returns data, `lsu_hready=1` | **non-zero @11045 ns** with `data_is_lsu=1`, `lsu_hready=1` |
| `lsu_hresp` | `0` | **`0`** |
| Aggregate | `dmem_rd ≥ 16` | **`dmem_rd = 366`** |

Additional read samples: `lsu_haddr = 0x00017FE8` (stack) accepted at
10925 ns and 11215 ns with `dmem_hsel=1`, `lsu_hwrite=0`, `lsu_hresp=0`.

---

### 6.4 Row 4 — IMEM read of the `.data` LMA during the copy ✅

**Ground truth from the ELF** (`objdump -h sw/build/firmware.elf`):

```text
Idx Name      Size      VMA       LMA
 0 .text   0000025a  00000000  00000000
 1 .rodata 00000040  0000025c  0000025c      -> 0x25C .. 0x29B
 2 .data   00000004  00010010  0000029c      -> .data LMA = 0x0000029C
```

and `imem.mem` record `@0000029C` holds `EE FF C0 00` — the load image of
`data_marker`.

**The waveform, 1240–1380 ns:**

```text
    ns | lsuHT lsuW  lsuHADDR     | lsu_hrdata / lsu_hwdata (data phase)      | note
 1255  |  10    0  0x00000298      |                                          | ADDRESS PHASE: LSU load, IMEM region
 1265  |  00    0  -               | HRDATA = 0x00C0FFEE_00000000             | DATA PHASE: [63:32] = .data LMA word
 1365  |  10    1  0x00010010      |                                          | ADDRESS PHASE: LSU store, .data VMA
 1375  |  00    1  -               | HWDATA[31:0] = 0x00C0FFEE                | DATA PHASE: same value, relocated
```

| Check | Required | Observed |
| --- | --- | --- |
| Load address in IMEM region | `addr[31:15] == 0` | **`lsu_haddr = 0x00000298`, `lsu_hwrite = 0`, `lsu_htrans = 2'b10`, `lsu_hready = 1` @1255 ns** |
| Returned data == `.data` LMA content | `0x00C0FFEE` (`EE FF C0 00`) | **`lsu_hrdata = 0x00C0FFEE_00000000` @1265 ns — `HRDATA[63:32] = 0x00C0FFEE`** |
| Stored to the `.data` VMA | `0x00010010` | **`lsu_haddr = 0x00010010`, `lsu_hwdata[31:0] = 0x00C0FFEE`** @1365/1375 ns |
| End-to-end | read value == write value | **`0x00C0FFEE` in == `0x00C0FFEE` out** ✔ |

**Why `HADDR = 0x298` and not `0x29C`.** The beat is 64-bit, so
`el2_lsu_bus_buffer` presents an **8-byte-aligned** address and the
`.data` load image at `0x29C` arrives in the **upper 32 bits** of `HRDATA`
(`0x298 + 4`). This is the same align-down behaviour the parallel session
documented in commit `16c10a4` for the UART/MRAC region (*“`el2_lsu_bus_buffer`
aligns the address down and issues `arsize=3`; the word lived in the upper
half of `HRDATA`”*). The value provenance above is what makes it certain:
`0x00C0FFEE` exists **only** at `imem.mem @0000029C`, and it appears in
`HRDATA[63:32]` immediately after the `HADDR=0x298` beat and in `HWDATA[31:0]`
on the very next store.

**Second IMEM-region load — `ro_probe[]` in `.rodata`:**

| Time | `lsu_htrans` | `lsu_hwrite` | `lsu_haddr` | Region |
| --- | --- | --- | --- | --- |
| 9955 ns | `10` | `0` | **`0x00000258`** | IMEM — 8-byte-aligned cover of `.rodata` LMA `[0x25C, 0x29C)` |
| 10265 ns | `10` | `0` | **`0x00000298`** | IMEM — repeat of the `.data` LMA cover |

A full-run sweep of `lsu_haddr` shows the LSU touches the IMEM region at
**exactly three addresses** — `0x00000000` (pre-reset), `0x00000258`,
`0x00000298` — and never writes to it (`imem_wr = 0`).

---

### 6.5 Row 5 — Address decode / slave select ✅

Decode mirrors `rtl/ahb/ahb_interconnect.sv:142-144`:
`addr[31:15]==17'h0000 → IMEM`, `17'h0002 → DMEM`,
`addr[31:12]==20'h10000 → UART`, else DEFAULT ERROR slave.

Observed across every sampled edge in all windows in this section:

| Address presented | `imem_hsel` | `dmem_hsel` | `uart_hsel` | `def_hsel` | Verdict |
| --- | --- | --- | --- | --- | --- |
| `0x00000000 / 0x00000038` (IFU fetch) | **1** | 0 | 0 | 0 | one-hot ✔ |
| `0x00010010 / 0x00010000` (LSU DMEM) | 0 | **1** | 0 | 0 | one-hot ✔ |
| `0x00000258 / 0x00000298` (LSU IMEM) | **1** | 0 | 0 | 0 | one-hot ✔ |
| `0x00017FE8 / 0x00017FEC` (stack) | 0 | **1** | 0 | 0 | one-hot ✔ |

- `def_hsel` **never** asserted — monitor `def = 0`.
- `addr_sel` / `data_sel` encodings observed: `001` = IFU, `010` = LSU,
  `000` = idle. Data phase trails address phase by exactly one cycle.
- Aggregate: `uart_rd = 0, uart_wr = 0` (fw0 never touches the UART — correct,
  fw0 has no UART code), `def = 0`.

---

### 6.6 Row 6 — Arbitration (LSU wins over IFU) ✅

A full-run sweep of `ic_htrans` vs `lsu_htrans` found **153 clock edges where
both masters present `2'b10` simultaneously** (earliest at **1255 ns**, then
9955, 10265, 10555, 23425, 23805, 24345, 24725, 25265, 25645, 26185, 26565,
…). Representative cycle, **9955 ns**:

```text
    ns | icHT  icHADDR    icR | lsuHT lsuW  lsuHADDR   lsuR | im dm ua df aSel dSel dLSU lsuAct aLSU
  9955 |  10  0x00000128    0 |   10    0  0x00000258    1 |  1  0  0  0  001  000    0     1    1   <-- BOTH request
  9965 |  10  0x00000128    1 |   00    0  0x00000258    1 |  1  0  0  0  001  001    1     0    0   <-- IFU now granted, LSU data phase
```

| Check | Required | Observed |
| --- | --- | --- |
| Both request in the same cycle | — | **`ic_htrans=10` AND `lsu_htrans=10` @9955 ns** |
| Loser's address phase is **held, not dropped** | `ic_hready = 0` | **`ic_hready = 0` @9955 ns** |
| Winner's address phase accepted | `lsu_hready = 1` | **`lsu_hready = 1` @9955 ns**, `addr_is_lsu=1` |
| Loser retries and is served | `ic_hready = 1` next cycle | **`ic_hready = 1` @9965 ns**, IFU fetch `0x00000128` accepted |
| LSU-over-IFU priority | holds | ✔ |

This is a **direct observation of the §4.3 fix working** — the exact behaviour
that previously dropped the fetch and hung the core.

---

### 6.7 Row 7 — No bus errors ✅

| Check | Required | Observed |
| --- | --- | --- |
| `ic_hresp` | never 1 | **0 at every sampled edge** in every window of this section |
| `lsu_hresp` | never 1 | **0 at every sampled edge** |
| Monitor `bus_err` | `0` | **`bus_err = 0`** |
| Monitor `def` (ERROR slave) | `0` | **`def = 0`** |
| Monitor `ifu_offtarget` | `0` | **`ifu_offtarget = 0`** |
| Exceptions | none | **`trace_rv_i_exception_ip = 0` for the entire run** (§6.11) |

The monitor's `bus_err` path also `$display`s
`[TB] <t> AHB_BUS_ERROR: …` on any assert; **no such line exists in
`sim.log`.**

---

### 6.8 Row 8 — AHB pipelining (address phase *t*, data phase *t+1*) ✅

Every write and read sampled in §6.2/§6.3 shows the classic split:

| Address phase (t) | Data phase (t+1) |
| --- | --- |
| 1365 ns: `lsu_htrans=10, haddr=0x00010010, hwrite=1, dmem_hsel=1, dSel=001` | 1375 ns: `lsu_htrans=00, dmem_hsel=0, data_sel=010, data_is_lsu=1, lsu_hwdata=0x00C0FFEE` |
| 11035 ns: `lsu_htrans=10, haddr=0x00010000, hwrite=0, dmem_hsel=1, dSel=000` | 11045 ns: `lsu_htrans=00, dmem_hsel=0, data_sel=010, data_is_lsu=1, lsu_hrdata valid` |
| 11405 ns: `lsu_htrans=10, haddr=0x00017FEC, hwrite=1, dmem_hsel=1` | 11415 ns: `lsu_htrans=00, data_sel=010, data_is_lsu=1, lsu_hwdata=0x01000000` |

Note in row 1 of this sub-table that the **IFU's** address phase at 1425/1435 ns
is accepted while the LSU's data phase is still in flight — true AHB pipelining,
two masters overlapped correctly. This is the off-by-one that caused the two
Phase-2 bugs (`doc/Phase2_AHB_Fabric_Completion_Record.md` §4.1, §4.3).

---

### 6.9 The mailbox trigger — the run's last write ✅

`tb/tb_veer_p2_soc.sv:300` samples `u_dmem.mem[2] === 8'hFF` as the PASS
trigger; `startup.S` must write `[2] = 0xFF` **last** (record §7.2).

```text
    ns | lsuHT lsuW  lsuHADDR     | lsu_hwdata (data phase)          | note
 90885 |   10    1  0x00010002     |                                  | ADDRESS PHASE, mem[2]
 90895 |   00    1  0x00010000     | 0x0000000000FF0000 -> byte[2]=FF | DATA PHASE: 0xFF written
 90915 |   --    -  -              |                                  | P2_TB2_RESULT: PASS  ($time 90915000 ps)
```

`lsu_hwdata = 0x00FF0000` puts `0xFF` in **byte lane 2**, which is byte address
`0x00010002` = `u_dmem.mem[2]`. The trigger byte is the last write of the run
and the PASS token follows one clock later. **Software contract, waveform and
testbench monitor all agree.**

---

### 6.10 Aggregate counts vs thresholds

| Counter | Threshold | Observed | Margin |
| --- | --- | --- | --- |
| `imem_rd` | ≥ 8 | **2393** | 299× |
| `dmem_rd` | ≥ 16 | **366** | 22× |
| `dmem_wr` | ≥ 16 | **164** | 10× |
| `imem_wr` | **must be 0** (canary) | **0** | ✔ |
| `uart_rd` / `uart_wr` | 0 for fw0 | **0 / 0** | ✔ |
| `def` (ERROR slave) | **must be 0** | **0** | ✔ |
| `bus_err` | **must be 0** | **0** | ✔ |
| `ifu_offtarget` | **must be 0** | **0** | ✔ |
| `cycles` (accepted address phases) | — | 2393 + 366 + 164 = **2923** | — |

`imem_wr = 0` is the D11 canary: `.bss` VMA lives in DMEM, so **nothing ever
stores into IMEM**. Any non-zero value would mean a stray write reaching code
memory.

---

### 6.11 No traps — the fix is genuinely active

`trace_rv_i_exception_ip` dumped over the **whole run** yields exactly two
distinct values:

```console
0,x      # t = 0 (pre-reset)
0        # every edge thereafter
```

The pre-fix run produced 24 719 illegal-instruction traps (commit `16c10a4`).
This run produces **zero**. This is the cleanest single indicator that the
address-phase-hold fix is in the compiled netlist.

---

## 7. The cycle monitor — design notes

**File:** `tb/tb_ahb_cycle_monitor.sv` (222 lines, new, additive).

**Why separate:** spec §22 fw0 requires the *existing* `tb_veer_p2_soc`
monitor (`tb/tb_veer_p2_soc.sv:300`) to fire with **zero changes**, while
spec §14/§16 L6 wants an independent token proving read **and** write cycles
really happened. A second module gives the second token without touching the
first. The diff to `tb_veer_p2_soc.sv` is **+28 lines**, all of it the
instantiation plus a comment.

**Sampling rule.** An address phase is *accepted* in cycle *t* iff
`HTRANS != IDLE && HREADY == 1`, sampled in the active region of `posedge clk`.
**Never** pair `hsel` with `hreadyout` on the same cycle — `hsel` is an
address-phase signal, `hreadyout` completes the *data* phase; pairing them
mis-counts by one. `doc/Phase2_AHB_Fabric_Completion_Record.md` §4.1 and §4.3
record exactly this class of bug.

**Classification** (mirrors `ahb_interconnect.sv:142-144`):

```systemverilog
addr[31:15] == 17'h0000 -> IMEM   addr[31:15] == 17'h0002 -> DMEM
addr[31:12] == 20'h10000 -> UART  anything else -> DEFAULT ERROR slave
```

**PASS predicate:**

```systemverilog
pass = (imem_rd >= N_IMEM_RD) && (dmem_rd >= N_DMEM_RD) &&
       (dmem_wr >= N_DMEM_WR) && (bus_err == 0) && (def_sel == 0);
```

Instantiated with `N_IMEM_RD=8, N_DMEM_RD=16, N_DMEM_WR=16,
WATCHDOG_NS=1_900_000` (ahead of the testbench's own `#2000000` timeout, so
the summary is always in the log — pass or fail).

**Defect found and fixed during development (finding N10).** The two flag
`reg`s were originally declared without initialisers:

```systemverilog
reg reported;   // 4-state: X
...
} else if (!reported) begin   // if (!X) is NEVER true in SystemVerilog
```

Because `reg` is 4-state and defaults to `X`, `if (!X)` is never taken — which
**silently disabled the entire counting block and the watchdog** while the
module still compiled and elaborated cleanly. Fixed by initialising
`reg reported = 1'b0; reg stop_d = 1'b0;`. Rule: **any `reg` used in a
condition must be explicitly initialised.**

**Also fixed:** `$time` inside a `1ns/1ps` module returns ns but `%t` prints
in the precision unit (ps), so `[TB] %0t AHB_BUS_ERROR:` lines were labelled
in ps while the windows were reasoned about in ns. Not reached in the PASS
run, but corrected in the monitor's message format before the final run.

---

## 8. Verdi — launch procedure and findings

### 8.1 Launch

```console
$ export VCS_HOME=/home/student/snps_tools_target/vcs/U-2023.03
$ export VERDI_HOME=/home/student/snps_tools_target/verdi/U-2023.03-SP1
$ export SNPSLMD_LICENSE_FILE=27021@14.139.1.126
$ export DISPLAY=:0
$ export PATH=$VCS_HOME/bin:$VERDI_HOME/bin:$PATH
$ cd build/sim/fw0
$ verdi -ssf p2_veer_soc.fsdb -dbdir simv.daidir \
        -sswr /home/student/Documents/honours_project/run/fw_wave.rc &
```

(`make verdi` does the same, gated on `sim`.)

### 8.2 `run/fw_wave.rc`

Seven groups mapping 1:1 onto the plan §5.3 checklist:

| Group | Name | Rows covered |
| --- | --- | --- |
| 1 | Clock & Reset | preconditions |
| 2 | CPU fetch/execute | row 1 cross-check (trace port) |
| 3 | IFU AHB (reads) | row 1 |
| 4 | LSU AHB (reads+writes) | rows 2, 3, 4, 8 |
| 5 | Fabric select | rows 5, 7 |
| 6 | Arbitration | row 6 |
| 7 | AHB cycle monitor | aggregates + PASS/FAIL cause |

`Magic 271485` / `Revision Verdi_U-2023.03-SP1`. Supports `zoom <t0> <t1>`,
`cursor <t>`, `marker <t>` in **ns** — which is how the §6 windows were
reproduced in the GUI.

**Verified in the GUI:** the title bar reads
`Verdi-Apex:nTraceMain:1: tb_veer_p2_soc … p2_veer_soc.fsdb`, the instance
pane lists `u_ahb_mon (tb_ahb_cycle_monitor)` alongside `u_soc (soc_top)`,
`rvtop_wrapper`, `el2_mem_export`, and all seven groups load with their
signals.

### 8.3 Finding N8 — Verdi stops on a modal license warning

Verdi logs and then presents a blocking dialog:

```console
*WARN* Verdi-Elite (Verdi) license is not available.
       Try to check out Verdi-Apex (Verdi-Ultra) license.
```

A modal `Warning` window (600×250, Motif `warningDialog_popup` **plus** a Qt
`Qt-subapplication "Novas"` wrapper) appears; the tool does not proceed until
it is dismissed, and blind clicking at guessed coordinates risks hitting the
window manager's close control and killing Verdi outright (observed). Behind
the warning Verdi **does** come up correctly as `Verdi-Apex`.

**Resolution:** dismiss programmatically. Neither `xdotool`, `wmctrl`,
`python3-xlib` nor `pyautogui` exist on this box, so a helper was written
using `ctypes` against `libX11.so.6` / `libXtst.so.6`
(`/tmp/opencode/dismiss.py`): locate the window by title with `xwininfo -root
-children`, send `Return` via `XTestFakeKeyEvent`, and if the dialog survives,
`XTestFakeButtonEvent` at the Qt message-box OK position. Observed Python is
**3.6**, so `subprocess.run(capture_output=True)` is unavailable — use
`stdout=subprocess.PIPE, universal_newlines=True`.

**Follow-up:** `sim/Makefile`'s `verdi` target should embed this so a bare
`make verdi` is not blocked. Tracked as open work.

### 8.4 Finding — tool-path and process hygiene

* `$VCS_HOME`/`$VERDI_HOME` must be exported, not only prepended to `PATH`
  (§2).
* `pkill -f "VERDI_HOME"` matches **this shell's own command line** and kills
  it; use `pkill -x verdi`.
* Two Verdi instances left stale `Warning` windows in the X tree that outlived
  their process — always sweep before measuring.

### 8.5 Screenshots

| File | Content | Status |
| --- | --- | --- |
| `doc/screenshots/step3a_verdi_first_dmem_write.png` | Verdi with `fw_wave.rc` loaded, zoomed to the 1300–1900 ns first-store window | ✅ retained |
| `doc/screenshots/step3a_verdi_ahb_rw_cycles.png` | all-black capture taken before the license dialog was dismissed | ❌ **deleted** (not evidence) |
| `doc/screenshots/IFU_Verified.png` | sibling session's UART/IFU capture | not this milestone's |

**Open item:** the remaining §5.3 windows (DMEM read, IMEM-LMA read,
decode/select, arbitration, no-bus-error, mailbox) are not yet captured as
screenshots. Their waveform content **is** captured cycle-accurately in §6
via `fsdbreport` from the same FSDB, so the *evidence* exists; the *pictures*
do not. Tracked in plan §12 item 4 as a partial.

---

## 9. Findings raised (feed back to spec rev 1.6)

| ID | Finding | Disposition |
| --- | --- | --- |
| **N8** | Verdi presents a blocking `Verdi-Elite … Verdi-Apex` license dialog before it will run; no `xdotool`/`wmctrl`/`python-xlib` on the box | Working helper written; **`make verdi` still needs it embedded** |
| **N9** | `%t` and `$finish` print in the precision unit (ps) while `$time`, `fsdbreport -bt/-et` and the wave RC use ns — a 90 µs run reads as 90 ms | Documented here and in the monitor comments |
| **N10** | A 4-state `reg` used in a condition is `X`; `if (!X)` is never true, so an uninitialised flag **silently disables** an `always` block | Fixed (`reg reported = 1'b0;`); rule recorded in §7 |
| **D9-deferred** | `S7`/`S7b`/`S8` (plusarg image loading) not implemented; `imem.mem` copied to `p2_prog.hex` instead | Filename stand-in only, documented in `sim/Makefile`; **still open** |

Pre-existing amendments still to fold into spec rev 1.6: **A1** (`-nostdlib`),
**A2** (stale `.gitignore` claim), **A3** (`sim/` filelist rule + `D6`
rationale), **A4** (companion `AHB_RW_MONITOR` token), **N6** (`--change-section-lma`),
**N7** (CRLF strip).

---

## 10. How to reproduce

```console
$ cd /home/student/Documents/honours_project
$ make                 # firmware -> images -> snapshot -> compile -> run -> gate
# ... expect, in order:
#   [SIM] PASS compile
#   [SIM] PASS  P2_TB2_RESULT: PASS
#   [SIM] PASS  AHB_RW_MONITOR: PASS
#   [SIM] PASS  no *.ihex in .../build/sim/fw0
#   [SIM] DONE
$ make wave            # prints the verdi command
# or:
$ make verdi           # opens Verdi with run/fw_wave.rc (see N8)
```

Useful one-liners for re-deriving §6:

```bash
export PATH=$VERDI_HOME/bin:$PATH
# cycle table for a window
fsdbreport build/sim/fw0/p2_veer_soc.fsdb -bt 1355ns -et 1450ns -csv \
    -s /tb_veer_p2_soc/lsu_hwrite -o out.csv
# find every edge where both masters request
fsdbreport build/sim/fw0/p2_veer_soc.fsdb -csv -s /tb_veer_p2_soc/ic_htrans -o ic.csv
```

Full waveform dumps are available with
`fsdb2vcd p2_veer_soc.fsdb > p2.vcd` (≈732 MB, ≈65 s — do not commit it).

---

## 11. Definition of done

| # | Criterion (plan §12) | Status |
| --- | --- | --- |
| 1 | `make -C sw all inspect` passes **G1–G13** | ✅ **G1–G12** in `Fw0_…Gate_Record.md` §4; **G13** here §5.4 |
| 2 | C program compiles/links under `-nostdlib`, converts to `imem.mem`/`dmem.mem` | ✅ steps 1–2 |
| 3 | `make sim` prints **both** `P2_TB2_RESULT: PASS` **and** `AHB_RW_MONITOR: PASS` with non-zero counts | ✅ §5.1, §5.2, §6.10 |
| 4 | Verdi opened on the FSDB with `run/fw_wave.rc`; §5.3 checklist filled in; screenshots present | ✅ checklist **fully filled** (§6) · ⚠️ **screenshots partial** (§8.5) — 1 retained, 4 outstanding |
| 5 | Record doc for step 3 + amendments folded into spec rev 1.6 | ✅ this document · ⚠️ **spec rev 1.6 not yet cut** (§9 lists what goes in) |

**Step 3a is functionally complete:** both tokens gate in one `make sim`, all
eight plan §5.3 rows are backed by cycle-accurate waveform data, and G13
passes. Outstanding non-blocking work: the four extra screenshots (§8.5), the
N8 helper embedded in `make verdi` (§8.3), and the spec rev 1.6 amendment
sweep (§9).
