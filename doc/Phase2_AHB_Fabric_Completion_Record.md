# PHASE 2 — AHB-Lite System Fabric: Completion Record

**Project:** RISC-V Network Telemetry SoC
**Phase:** 2 — project AHB-Lite fabric + IMEM/DMEM + VeeR integration
**Status:** PASS (all 14 user gates)
**Date:** 2026-09-05
**Toolchain:** Synopsys VCS U-2023.03 + Verdi U-2023.03-SP1
**Workdir:** `/tmp/opencode/veer_p2` (`tb1/` directed, `tb2/` VeeR; own KDB each)

---

## 1. What was built

| File | Desc |
|---|---|
| `rtl/ahb/ahb_interconnect.sv` | 2-master (IFU/LSU, LSU fixed priority) x 3-slave AHB-Lite fabric, 64-bit data. Combinational address-phase arb + registered data-phase owner; one-hot HSEL; HRDATA/HREADY/HRESP steering |
| `rtl/ahb/ahb_sram.sv` | Parameterized slave SRAM (base/size/hex/wait-states), HSIZE+HADDR lane enables, zero-wait OKAY |
| `rtl/ahb/ahb_default_slave.sv` | Two-cycle ERROR slave for unmapped + not-yet-implemented regions |
| `rtl/soc_top.sv` | Fabric + IMEM (`0x0000_0000`/32K) + DMEM (`0x0001_0000`/32K) + default |
| `tb/tb_ahb_fabric.sv` | TB1: BFM-driven directed tests T1–T10 + one-hot-HSEL monitor |
| `tb/tb_veer_p2_soc.sv` | TB2: `veer_wrapper` (locked submodule, referenced) + `soc_top` + behavioral ICCM/DCCM/ICache SRAMs (VeeR `tb_top` pattern) + DMEM mailbox monitor |
| `scripts/p2_prog_gen.py` | RV32I mini-assembler emitting `p2_prog.hex` (self-checked vs Phase-1 evidence) |
| `run/p2_fabric_run.f`, `run/p2_veer_soc_run.f` | VCS filelists |
| `run/p2_full_flow.csh` | One-shot: snapshot → hex → TB1 → TB2 with PASS gating |
| `run/p2_wave.rc`, `run/p2_veer_wave.rc` | Wave RCs (same style as `axi_wave.rc`) |

No VeeR RTL/TB modified. SoC boots from IMEM: new `p2_soc` snapshot is
`default_ahb` + `-set=reset_vec=0x00000000` (reset vector is RTL-CONFIG
DEPENDENT per v3 §25 — this freezes the SoC choice; frozen map untouched).

## 2. P2 program (TB2 stimulus, 10 insns @ IMEM 0x0)

`lui gp,0x10; 'P'->DMEM[0]; '2'->DMEM[1]; lw a1,0(gp); sw a1,4(gp);
0xFF->DMEM[2]; park`. Proves fetch, execute, `sb`/`lw`/`sw` through the
fabric. Expected `DMEM[0..7] = 50 32 FF 00 50 32 00 00`.

## 3. Gate results vs user criteria

| # | Gate | Test | Evidence |
|---|---|---|---|
| 1 | VeeR reset | TB2 | halt/run handshake, `reset_vec=0x0`, `CPU running` |
| 2 | VeeR instruction execution | TB2 | PASS monitor on DMEM record |
| 3 | VeeR instruction fetch | TB2 | `trace_rv_i_valid_ip` + `ic_haddr` from `0x0` in FSDB |
| 4 | AHB-Lite read | TB1 T2/T3, TB2 `lw` | PASS |
| 5 | AHB-Lite write | TB1 T2/T7, TB2 `sb`/`sw` | PASS |
| 6 | Address decoding | TB1 T4 (window tops) | PASS |
| 7 | Slave selection | TB1 T4 + one-hot monitor, TB2 groups | PASS |
| 8 | Response routing | TB1 T8 (contention), TB2 | PASS |
| 9 | HREADY propagation | TB1 T5 (stall low→high) | PASS |
| 10 | HRESP propagation | TB1 T6 (ERROR=1), T2 (`=0`) | PASS |
| 11 | Unmapped access behavior | TB1 T6 (`0x20000000` → 2-cycle ERROR) | PASS |
| 12 | Back-to-back accesses | TB1 T7 (true 1/cycle pipelined x4) | PASS |
| 13 | Project memory access | TB1 T2/T3/T9/T10, TB2 DMEM record | PASS=16 FAIL=0 / TB2 PASS |
| 14 | VeeR software through project fabric | TB2 | `P2_TB2_RESULT: PASS` @ ~1085 ns |

Full logs: `tb1/sim_p2_fabric.log`, `tb2/sim_p2_veer_soc.log`.
Waveforms: `tb1/p2_fabric.fsdb` (+`p2_wave.rc`, cursor T2),
`tb2/p2_veer_soc.fsdb` (+`p2_veer_wave.rc`, cursor PASS).
Reproduce: `./p2_full_flow.csh` (exit 0 = both PASS).

## 4. Root causes fixed during verification (recorded per debug rules)

1. **BFM sampled AHB responses a cycle early** (address-phase cycle instead
   of data-phase) → systematic false FAILs. Fixed with NBA-settle `#1` +
   full data-phase wait in transfer tasks.
2. **`ahb_sram` double-counted the byte offset** (`mem[word_addr+b]` with
   low bits in both) → unaligned writes landed at `addr+size`. Fixed with
   cleared word base `{addr[AW-1:3],3'b0}`. Found via T10 (`rd=0000ccdd00bb0000`).
3. **Pipelined BFM drove HWDATA together with HADDR**; AHB pipelines data a
   cycle behind address → every write committed its neighbor's data
   (`[w1,w2,w3,w3]` signature). Fixed with data-lagging-addr T7 loop.
   RTL was correct in all three cases except (2); no masking, all root-caused.
4. **TB2 bring-up sequence:** `pt` is a module *parameter* (`#include`
   inside `#(...)`); `mem_clk` is core-driven (extra assign = double
   driver); `$readmemh` needs byte-per-token hex. Fixed.

## 4b. File change inventory (before → after + behavioral impact)

No existing RTL/TB was modified — Phase 2 is purely additive except for
project-level config/docs. VeeR submodule untouched (`06ad26a`).

**New RTL (did not exist before; behavior added):**

| File | Before | After + behavioral impact |
|---|---|---|
| `rtl/ahb/ahb_interconnect.sv` | No project fabric; VeeR masters wired straight to TB memories | 2-master/3-slave AHB-Lite fabric. Effect: LSU wins arbitration over IFU; IMEM/DMEM decode at `0x0000_0000`/`0x0001_0000`; everything else gets ERROR instead of hanging the bus |
| `rtl/ahb/ahb_sram.sv` | TB-only `ahb_sif` models | Owned synthesizable SRAM slave. Effect: byte/half/word/dword lanes honored; optional wait-states; hex preload. Initial bug (low bits double-counted) corrupted unaligned writes — fixed, see §4(2) |
| `rtl/ahb/ahb_default_slave.sv` | Unmapped accesses had no defined target | Two-cycle ERROR completions. Effect: illegal/peripheral-region accesses terminate cleanly with `HRESP=1` instead of locking `HREADY` low forever |
| `rtl/soc_top.sv` | No SoC top | Fabric + IMEM + DMEM + default wired. Effect: single integration point VeeR plugs into; extended with real slaves in later phases |

**New verification/SW (did not exist before):**

| File | Purpose + impact |
|---|---|
| `tb/tb_ahb_fabric.sv` | T1–T10 directed gates + one-hot-HSEL monitor. Caught the SRAM offset bug and two BFM protocol violations before VeeR ever ran |
| `tb/tb_veer_p2_soc.sv` | VeeR + `soc_top` + SRAM models + DMEM mailbox PASS monitor. This is the gate-14 proof vehicle |
| `scripts/p2_prog_gen.py` | Generates the 10-insn P2 program; self-checks encodings against Phase-1 `exec.log` evidence, so no hand-assembly errors |
| `run/p2_fabric_run.f`, `run/p2_veer_soc_run.f` | VCS filelists. `p2_fabric_run.f` was first written with workdir-relative paths (build failed `SFCOR`) → switched to absolute paths |
| `run/p2_full_flow.csh` | One-shot flow with PASS gating; gained `tb1/`+`tb2/` split (separate KDBs) and cshrc-independent tool env |
| `run/p2_wave.rc`, `run/p2_veer_wave.rc` | Wave layouts; scope paths corrected (`-holdScope` inherits, no `dut/` duplication) |

**Modified project files (old → new):**

| File | Before | After + impact |
|---|---|---|
| `.gitignore` | `!run/p1_*` exceptions only | Generalized to `!run/p[0-9]_.*` so all phase scripts/RCs are versionable. No behavior change to RTL |
| `README.md` | Phase-2 NOT STARTED, no P2 commands | P2 section + commands + PASS status. Docs only |
| `run/p2_veer_soc_run.f` (during bring-up) | Referenced `snapshots/default_ahb` | Points at `snapshots/p2_soc` (`reset_vec=0`). Effect: SoC boots from IMEM instead of faulting on first fetch |

**Not changed:** `core/Cores-VeeR-EL2/*`, `rtl/aes/*`, `rtl/interconnects/*`
(AXI), `tb/tb_aes*`, AES docs. Deliberately out of Phase-2 scope.

## 5. Known limitations

- Peripheral regions (UART/Timer/GPIO/NET/AES/CRC) → default ERROR slave
  until later phases. SB-debug master + DMA slave tied off in TB2.
- IMEM writable (no ROM enforcement) — acceptable for Phase 2.
- `run/p2_*` scripts/RCs/filelists are versioned (`.gitignore` `p[0-9]_`
  exceptions); sim build dirs (`tb1/`, `tb2/` under `/tmp`) are local —
  snapshots + hex regenerate via `./p2_full_flow.csh`.
- TB1 `%0t` numbers are ps (1 ps precision), TB labels say "ns" — cosmetic.

## 6. Traceability (v3 arch doc)

§9 map → `soc_top` decode; §11 protocol (NONSEQ/HTRANS/HREADY/HRESP,
LSU>IFU §11.8, unmapped ERROR) → `ahb_interconnect` + TB1;
§2.3 64-bit boundary → all data paths; §13 single-clock/active-low reset.
Peripheral register maps (§10) not yet implemented — Phase 3+.

## 7. Status

| Phase | Status |
|---|---|
| 1 VeeR bring-up | PASS |
| **2 AHB-Lite fabric** | **PASS (this record)** |
| 3 AES integration | NOT STARTED (isolated AXI-AES PASS pre-exists) |
| 4 Telemetry + IRQ | NOT STARTED |
| 5 Full SoC | NOT STARTED |
