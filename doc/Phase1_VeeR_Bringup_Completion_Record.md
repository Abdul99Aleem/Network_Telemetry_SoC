# PHASE 1 — VeeR EL2 Bring-up: Completion Record

**Project:** RISC-V Network Telemetry SoC
**Phase:** 1 — VeeR EL2 Bring-up (`default_ahb`, AHB-Lite)
**Status:** PASS
**Date:** 2026-09-05
**VeeR checkout:** `core/Cores-VeeR-EL2` @ `06ad26a` (locked commit, unmodified)
**Toolchain:** Synopsys VCS U-2023.03 + Verdi U-2023.03-SP1 (`source /home/student/cshrc`)
**Simulator workdir:** `/tmp/opencode/veer_p1` (kept out of the repo by design)

---

## 1. Objective

Prove the supplied VeeR EL2 resets, fetches, executes, performs an AHB-Lite
memory transaction, and reaches deterministic PASS — reusing the supplied
testbench infrastructure with zero RTL modifications.

## 2. Exit criteria (all met)

| # | Criterion | Evidence |
|---|---|---|
| 1 | Reset assertion/deassertion, PC = reset vector | TB halt/run handshake + boot at `0x80000000` (`vcs_run.log`) |
| 2 | Instruction fetch + PC progression | `exec.log` PCs `0x80000000…`, `trace_rv_i_valid_ip` in `dump.fsdb` |
| 3 | Instruction execution | `minstret = 330` |
| 4 | AHB-Lite transaction (mailbox `sb` to `0xD0580000`) | `lsu_haddr/hwrite/hwdata` in `dump.fsdb`, `mailbox_write` |
| 5 | Correct readback / console output | `Hello World from VeeR EL2` in `console.log` |
| 6 | Deterministic PASS/FAIL | `TEST_PASSED` @ 1142000 ns, `$finish` @ 2642000, `mcycle = 1134` |
| 7 | No HRESP errors, no stuck HREADY, no protocol corruption | Clean `vcs_run.log`, `0 error(s)` elaboration |

## 3. Locked VeeR configuration (`default_ahb`)

Generated via `configs/veer.config -target=default_ahb` (see
`snapshots/default_ahb/common_defines.vh` in the workdir):

| Item | Value |
|---|---|
| Bus | AHB-Lite (`RV_BUILD_AHB_LITE=1`, `SDVT_AHB=1`, `build_axi4=0`), 64-bit data (`RV_EXT_DATAWIDTH=64`) |
| Reset / NMI vectors | `0x80000000` / `0x11110000` |
| DCCM | 64 KB, `0xF0040000–0xF004FFFF`, 4 banks |
| ICCM | 64 KB, `0xEE000000–0xEE00FFFF`, 4 banks |
| ICache | 16 KB, 2-way, 64 B lines, ECC on |
| PIC | base `0xF00C0000`, 32 KB, 31 external ints |
| Mailbox (PASS/FAIL) | `0xD0580000` (`0xFF`=PASS, `0x01`=FAIL) |
| PMP / misc | 16 entries, `smepmp=0`, `user_mode=0`, BTB 512 / BHT 512 |

No overlap with the SoC map (`0x0000_xxxx`/`0x1000_xxxx`): VeeR tightly-coupled
regions live at `0xEE…`/`0xF0…`.

## 4. What was (not) changed

**No RTL changed.** Reused `testbench/tb_top.sv`, `ahb_sif.sv`,
`ahb_lite_2to1_mux.sv`, `ahb_lsu_dma_bridge.sv`, `veer_wrapper.sv`,
`tools/Makefile`, canned `testbench/hex/user_mode0/hello_world.hex`
(no RISC-V GCC on this host).

**Files added** (all under `run/`, git-ignored by `run/*` + `*.rc` rules —
local-only unless force-added):

| File | Purpose |
|---|---|
| `run/p1_full_flow.csh` | One-shot: config → `vcs-build debug=1` → `program.hex` → `simv` → `TEST_PASSED` |
| `run/p1_hello_world_ahb.csh` | Same (earlier copy; `p1_full_flow.csh` is canonical) |
| `run/p1_open_verdi.csh` | Opens Verdi with FSDB + wave RC on the user's `$DISPLAY` |
| `run/p1_verdi_ahb.tcl` | Verdi-TCL fallback: 5 signal groups (Verdi console only, never `./`) |
| `run/p1_wave.rc` | nWave-style wave RC, same layout as `axi_wave.rc` but `tb_top` scope |

Also reverted Verdi GUI side-effect noise (`run/novas.*`, `run/verdiLog/*`).

## 5. Verification record

### P1-T1 — hello_world on default_ahb (VCS, FSDB)

- **Purpose:** reset → fetch → execute → AHB-Lite store → PASS.
- **RTL/config:** stock VeeR `default_ahb` (see §3); `program.hex` = canned
  `hello_world.hex` loaded at `0x80000000`.
- **Stimulus:** `./simv +dumpon +vcs+lic+wait`.
- **Expected:** `Hello World from VeeR EL2` + `TEST_PASSED`.
- **Actual:** PASS — banner @ 117000/455000/793000 ns, `TEST_PASSED` @
  1142000 ns, `Finished : minstret = 330, mcycle = 1134`.
- **Result:** PASS (run twice: 15:55 and 16:11/16:12, identical signature).
- **Sim command:** `./p1_full_flow.csh` (workdir `/tmp/opencode/veer_p1`).
- **Waveform:** `/tmp/opencode/veer_p1/dump.fsdb` (858378 B; KDB-linked —
  open with `-dbdir simv.daidir`).
- **Signals:** groups `1_clk_rst` (`core_clk/rst_l/porst_l`), `2_cpu`
  (`trace_rv_i_address_ip/insn_ip/valid_ip`, `mailbox_write/data`),
  `3_ifu_ahb`, `4_lsu_ahb`, `5_mux_mem`
  (`*_haddr/htrans/hwrite/hsize/hburst/hprot/hwdata/hrdata/hready/hresp`).
- **Waveform check (user-verified):** hex bytes cross-checked against
  `lsu_hwdata`/`mailbox_data`; `HRESP=0`, `HREADY=1` throughout.
- **Notes:** `default_ahb` has **no AXI** — the `axi_crossbar` lines in the
  log are a TB helper. AXI verification belongs to Phase 3 (AES TBs).

## 6. How to reproduce / view

```csh
source /home/student/cshrc
cd ~/Documents/honours_project/run
./p1_full_flow.csh        # rebuilds + reruns sim, ends with Verdi hint
./p1_open_verdi.csh       # verdi -ssf dump.fsdb -dbdir simv.daidir -sswr p1_wave.rc
```

Key times: `117000` ns banner, `455000` ns Hello-World bytes,
`1142000` ns `TEST_PASSED`. Requires a visible `$DISPLAY` (physical `:0`);
do not force `:42` (headless Xvfb).

## 7. Known limitations

1. Canned hex — no GCC/picolibc rebuild path verified on this host.
2. FSDB signal names resolve only with `simv.daidir` KDB (`fsdbreport`
   alone finds nothing; Verdi `-dbdir` required).
3. Verdi checks out Apex fallback license (Elite unavailable) — benign.
4. `run/*` + `*.rc` are git-ignored: P1 scripts/RC are **not versioned**
   (`git add -f run/p1_*` if they must be kept; `!run/wave.rc` is the only
   RC exception in `.gitignore`).
5. Build artifacts live in `/tmp/opencode/veer_p1` — ephemeral; rerun
   `./p1_full_flow.csh` to regenerate.

## 8. Traceability

| Requirement (v3 arch doc) | RTL/TB | Test | Result |
|---|---|---|---|
| Active-low reset, defined boot (§13) | `tb_top.sv` rst + `RV_RESET_VEC` | P1-T1 | PASS |
| 64-bit AHB-Lite VeeR boundary (§2.3) | `veer_wrapper.sv:224-280` | P1-T1 | PASS |
| RV32 software execution (§18) | `hello_world` @ mailbox | P1-T1 | PASS |
| No AXI in system fabric (§22–23) | `build_axi4=0` | P1-T1 | PASS (by construction) |

## 9. Phase status

| Phase | Status | Evidence |
|---|---|---|
| 1 VeeR bring-up | PASS | This record + `dump.fsdb` + `console.log` |
| 2 AHB-Lite fabric | NOT STARTED | — |
| 3 AES integration | NOT STARTED (isolated AXI-AES PASS logs pre-exist) | `run/sim_aes*.log` |
| 4 Telemetry + IRQ | NOT STARTED | — |
| 5 Full SoC | NOT STARTED | — |

## 10. Docs audited for this phase

- `doc/RISC_V_Network_Telemetry_SoC_Architecture_Document_v3.md` (authoritative)
- `doc/RISC_V_Network_Telemetry_SoC_Port_List.md` (stale: 32-bit bus — v3 wins)
- `doc/RISC_V_Network_Telemetry_SoC_Progress_and_Architecture.md`
- `doc/AES_AXI_Integration_Verification_Record.md` (stale DONE-timeout — superseded by PASS logs)
- `RISC_V_Network_Telemetry_Architecture_Document.docx` v1.0 + Abstract +
  Block-Diagram `.docx` (extracted; v3 supersedes on timestamp/UART/IRQ/scope)
