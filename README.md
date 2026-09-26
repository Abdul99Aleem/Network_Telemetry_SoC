# RISC-V Network Telemetry & Secure Packet Monitoring SoC

**An edge SoC that looks at network traffic in hardware, wraps what it saw
into a 128-bit record, encrypts that record with a hardware AES-128 engine,
and reports it over UART — all driven by a VeeR EL2 RISC-V core.**

![last commit](https://img.shields.io/github/last-commit/Abdul99Aleem/Network_Telemetry_SoC)
![commit activity](https://img.shields.io/github/commit-activity/m/Abdul99Aleem/Network_Telemetry_SoC)
![contributors](https://img.shields.io/github/contributors/Abdul99Aleem/Network_Telemetry_SoC)
![code size](https://img.shields.io/github/languages/code-size/Abdul99Aleem/Network_Telemetry_SoC)
![top language](https://img.shields.io/github/languages/top/Abdul99Aleem/Network_Telemetry_SoC)
![repo size](https://img.shields.io/github/repo-size/Abdul99Aleem/Network_Telemetry_SoC)

- **Repo:** <https://github.com/Abdul99Aleem/Network_Telemetry_SoC> (`main`; built on `feature/sw-build-ahb-rw`)
- **Toolchain:** Synopsys VCS U-2023.03 + Verdi U-2023.03-SP1 (FSDB), bare-metal RISC-V GCC
- **Built and verified in:** RTL simulation + bare-metal C (FPGA/silicon later)
- **Verification methodology:** directed self-checking SystemVerilog today →
  layered **UVM** environment next (UVM factory overrides + `uvm_config_db`,
  see [§5](#5-verification-methodology-directed-today-uvm-next))
- **README last re-verified against a live run:** 2026-09-26

---

## 1. Why this project exists

Edge devices — industrial gateways, IoT hubs, network appliances — increasingly
have to account for traffic *locally* instead of shipping raw packets to some
central analysis service. A device that depends on a remote endpoint goes blind
the moment that link is slow, down, or untrusted, and pushing packet metadata
upstream means handing it to intermediaries on the way.

So the question I set out to answer is a concrete one:

> **Can a small RISC-V SoC inspect, validate, timestamp and encrypt its own
> network telemetry — fast enough to be worth doing in hardware, and simple
> enough that the whole thing can be verified end-to-end in RTL simulation?**

What makes it interesting is the split of labour:

- **Hardware** does the repetitive, timing-sensitive work — byte-by-byte packet
  parsing, CRC32 integrity checking, and AES-128 encryption. Doing that in a
  tight software loop burns instructions and leaves keys and intermediate
  telemetry sitting in memory longer than they need to.
- **The RISC-V core** does the work that actually needs judgement —
  configuration, interrupt handling, assembling the telemetry record, kicking
  off crypto jobs, and reporting.

That split is what this project is about: one coherent data path, from packet
bytes in to encrypted report out, instead of a pile of unrelated peripherals
sitting on a bus.

---

## 2. The high-end goal

The goal: a single end-to-end scenario, proven by one system-level testbench —
this is what "finished" looks like:

```text
  testbench streams Ethernet frames (8-bit streaming interface)
        │
        ▼
  Network Telemetry Engine ── parses headers, counts packets/bytes/errors,
        │                      captures addrs/ports/length, stamps timestamp
        ├── CRC32 ──────────── integrity/FCS check running concurrently
        │
        ▼  packet-complete interrupt
  VeeR EL2 (RV32IMC, AHB-Lite)
        │  reads the hardware-captured fields over MMIO
        │  assembles a 128-bit telemetry record in software
        ▼
  AES-128 accelerator ────── encrypts the record (completion is interrupt-driven)
        │
        ▼
  UART (TX) ──────────────── reports packet stats + CRC status + ciphertext
```

That is the last row of the status table in §4.2. Everything in this repo so
far is the groundwork that makes that final demo defensible: a booted CPU, a
working system bus, accelerators proven in isolation, and now the first
peripheral wired onto the SoC through the bridge.

**Definition of done for the whole project** (from the frozen architecture
document): packet stream in → correct telemetry + CRC + timestamp → CPU
submits → correct ciphertext → reported over UART, with a clean regression and
waveform evidence behind every claim.

---

## 3. Where the ideas come from

Where the pieces came from — the documents I was given, the open-source IP
I built on, and the parts I wrote myself.

### 3.1 Problem framing and architecture

| Source | What it gave me |
|---|---|
| `doc/RISC_V_Network_Telemetry_Project_Abstract.docx` (faculty-supplied) | Problem statement, the HW/SW partition rationale, minimum-of-three-IP requirement |
| `doc/RISC_V_Network_Telemetry_Architecture_Document.docx`, `..._Block_Diagram.docx`, `..._Port_List.md` | Block diagram, port list, IP selection |
| Supplied `PRD_RISCV_Network_Telemetry_SoC.md` | Requirements, IP list — referenced by the architecture document, held outside this repo (see the AES note in §3.3) |
| `RISC-V VeeR EL2 PRM` + upstream RTL | Bus, interrupt, reset and memory behaviour — authoritative over any document |
| `doc/RISC_V_Network_Telemetry_SoC_Architecture_Document_v3.md` | The **frozen** baseline this repo actually implements (AHB-Lite, memory map, PIC IDs 1=NET / 2=AES / 3=Timer, CPU-observed timestamp, AES-128-only, TX-only UART). Where the older docs disagree with v3, **v3 wins.** |

### 3.2 IP borrowed from open source

| Block | Origin | Licence | How it is used here |
|---|---|---|---|
| **CPU** — VeeR EL2 RV32IMC | `chipsalliance/Cores-VeeR-EL2` | Apache-2.0 | Git submodule, **pinned at `06ad26a` and never modified** — wrapped, not forked |
| **AES-128 core** | OpenCores [`aes_core`](http://www.opencores.org/cores/aes_core) — Rudolf Usselmann, `asics.ws::aes:1.1` | OpenCores permissive (use/distribute with copyright intact) | Vendored in `aes/aes_core-master/`, driven through my own AXI slave wrapper |
| **UART** | [`m4j0rt0m/axi-lite_uart-ipcore`](https://github.com/m4j0rt0m/axi-lite_uart-ipcore) | MIT (Abraham J. Ruiz R.) | Sources copied into `rtl/uart/ip/`, wrapped as a memory-mapped AXI slave |
| **CRC32** (planned, not yet in RTL) | `alexforencich/verilog-lfsr` | MIT | Specified in the architecture document for Ethernet-FCS duty |
| **Integration patterns** | VeeRwolf reference SoC | — | Read for structure only; **not a dependency**, not in the final SoC |

### 3.3 Things I wrote myself

The AHB-Lite interconnect, SRAM slaves and default ERROR slave; the AXI 2x8
interconnect, arbiter and priority encoder; the AXI slave wrappers around AES
and UART; every testbench in `tb/`; every flow script in `run/`; the RV32I
mini-assembler in `scripts/p2_prog_gen.py`; and the verification records in
`doc/`. The custom Network Telemetry Engine — the main original part of this
project — is what I'm building next.

> **A note on the AES source:** the project PRD names the AES IP as
> `secworks/aes`, but the RTL that was actually cloned, compiled and tested
> identifies itself as `asics.ws::aes:1.1` (the older OpenCores core, files
> `aes_cipher_top.v`, `aes_key_expand_128.v`, `aes_sbox.v`). It's written up
> under "Provenance discrepancy" in
> `doc/AES_AXI_Integration_Verification_Record.md`, so the docs follow the RTL
> that really runs.

---

## 4. Project tracker

### 4.1 Numbers

Snapshot as of **2026-09-26**. Badges above update themselves; this table is
the manual record.

| Metric | Value |
|---|---|
| Commits so far (`git rev-list --count HEAD`) | **22** |
| Active window | **28 days** — 2026-08-29 → 2026-09-26 |
| Developers | **1** (two git identities: lab account + GitHub) |
| Tracked files | **112** |
| Lines committed in `HEAD` (excl. CPU submodule) | **41,332** |
| → RTL (`rtl/`) | 7,489 lines / 26 files |
| → Testbenches (`tb/`) | 6,678 lines / 10 benches |
| → Flow (`run/`) | 1,419 lines / 26 files (11 filelists, 7 `csh` flows, Verdi RCs) |
| → Firmware (`sw/`) | 788 lines / 6 files |
| → Scripts (`scripts/`) | 607 lines / 3 generators |
| → Documentation (`doc/`) | 19,815 lines / 17 documents |
| Submodules | 1 — `core/Cores-VeeR-EL2`, locked at `06ad26a` |
| Regression groups passing | **6** (VeeR bring-up, AHB fabric, AXI+AES single-master, AXI+AES 2-master, UART isolated, Phase 3 UART end-to-end) |
| Regression groups in progress | **0** |

Counted against `HEAD`, so the numbers reproduce identically on a fresh clone
rather than shifting with whatever happens to be dirty in your working tree:

```bash
git rev-list --count HEAD                                    # 22 commits
git log --reverse --format=%ad --date=short | head -1        # first commit
git ls-files | wc -l                                         # 112 tracked files
git archive HEAD | tar -xO | wc -l                           # 41332 committed lines
for d in rtl tb run scripts doc sw; do                       # per-directory
  printf '%-8s %6d %3d files\n' "$d" \
    "$(git archive HEAD $d | tar -xO | wc -l)" \
    "$(git ls-files "$d/*" | wc -l)"
done
git shortlog -sn --all                                       # contributors
```

### 4.2 Phase status

| Milestone | Deliverable | Status | Evidence |
|---|---|---|---|
| M1 | VeeR EL2 bring-up (`default_ahb`) | **PASS** | `doc/Phase1_VeeR_Bringup_Completion_Record.md` — re-run 2026-09-26 |
| M2 | AHB-Lite fabric, IMEM/DMEM, VeeR-through-fabric (TB1+TB2) | **PASS** | `doc/Phase2_AHB_Fabric_Completion_Record.md` — re-run 2026-09-26 |
| — | AXI 2x8 interconnect + AES-128, isolated | **PASS** | `doc/AES_AXI_Integration_Verification_Record.md` — re-run 2026-09-26 |
| — | UART AXI subsystem, isolated (direct / interconnect / 2-master) | **PASS** | `UART AXI SLAVE DIRECT: PASS`, `AXI INTERCONNECT -> UART INTEGRATION: PASS`, 2-master 19/0 — run 2026-09-26 15:18 |
| — | RISC-V GNU toolchain bring-up | **PASS** | `doc/RISC_V_GNU_Toolchain_Setup_and_Validation_Record.md` |
| M3 | UART on the SoC: AHB→AXI bridge at `0x1000_0000` + E2E testbench | **PASS** | `doc/Phase3_UART_End_To_End_Completion_Record.md` — `UART_E2E_RESULT: PASS` (`55 41 52 54 0a` + `DMEM[2]=ff` + `DMEM[4..7]=60 00 00 00`) and fabric TB1 `23/23` → `P2_TB1_RESULT: PASS`, run 2026-09-26 17:42 |
| M4 | AES on the SoC (bridge + driver) | **NOT STARTED** | |
| M5 | Network Telemetry Engine + CRC32 + IRQs | **NOT STARTED** | |
| M6 | Full SoC + bare-metal app + end-to-end TB | **NOT STARTED** | |

*Milestone numbers follow this repo's completion records (M1 = VeeR
bring-up). The architecture document §24 numbers the same work starting at 0 —
same milestones, one-off-by-one offset. M6 is the goal drawn out in §2.*

### 4.3 Roadmap

- [x] Repo setup: clean `.gitignore`, pinned submodule, README kept in step with the code
- [x] VeeR EL2 boots and prints `TEST_PASSED` in VCS
- [x] Custom AHB-Lite fabric: 2 masters, 3 slaves, arbitration, ERROR slave
- [x] CPU fetches and executes through that fabric (program in IMEM, mailbox in DMEM)
- [x] AXI 2x8 interconnect with a real AES-128 slave behind it, known-answer tested
- [x] AES two-master simultaneous traffic, IRQ assertion and known-answer ciphertext readback (19 PASS / 0 FAIL)
- [x] RISC-V cross-toolchain installed and validated
- [x] UART AXI slave read handshake fixed; all three UART benches now pass (direct, interconnect, 2-master 19/0) with watchdogs instead of silent stalls
- [x] AHB↔AXI bridge + UART attached to `soc_top` at `0x1000_0000`, fabric TB1 extended with bridge T11/T12 (PASS)
- [x] UART end-to-end run completing: `UART_E2E_RESULT: PASS` — 5/5 serial bytes, DMEM terminator, LSR read-back through the bridge, zero exceptions (`doc/Phase3_UART_End_To_End_Completion_Record.md`)
- [ ] UVM base environment: `uvm_component_utils`-registered components, virtual interfaces handed around with `uvm_config_db`, one `run_test()` entry point
- [ ] UVM factory overrides so the same env runs directed / random / constrained-random tests without editing the environment
- [ ] UVM agents + scoreboards + functional coverage for AXI, AHB-Lite and UART
- [ ] AES on the SoC through the same bridge (driver + interrupt)
- [ ] Network Telemetry Engine + CRC32/FCS (the custom contribution)
- [ ] Bare-metal C application: init, IRQ, record assembly, crypto job, UART report
- [ ] End-to-end packet → encrypted telemetry testbench
- [ ] Synthesis / FPGA (only after simulation is stable — explicitly last)

---

## 5. Verification methodology: directed today, UVM next

### 5.1 Where the regression is right now

Ten self-checking SystemVerilog testbenches in `tb/`, run under VCS with
Verdi/FSDB debug. They are **flat/directed**: BFM tasks drive the bus, an
expected-value scoreboard compares, and a `pass_count`/`fail_count` pair decides
the exit status. Known-answer vectors (AES, DMEM mailboxes), response monitors
and one-hot `HSEL` checks do the heavy lifting.

That style is the right one for bringing up a bus — every gate in the Phase 1
and Phase 2 records was proved this way, and the AES 2-master regression runs
19 checks / 0 failures the same way. It does not scale to the full SoC:
stimulus lives in one big `initial` block, there is no reusable driver, no
coverage model, and swapping one scenario for another means editing the
testbench.

### 5.2 Where it is going — a UVM environment

The plan is to rebuild the regression as a layered UVM environment, IP by IP,
rather than growing the directed benches forever.

| UVM element | Planned use in this SoC |
|---|---|
| `uvm_agent` (driver / monitor / sequencer) | AHB-Lite master agent (IFU+LSU), AXI master agent, AXI slave agent, UART TX agent |
| `uvm_sequence` + `uvm_sequence_item` | AHB/AXI transactions, UART byte streams, packet-chunk stimuli |
| `uvm_scoreboard` + analysis ports | expected-vs-observed data, AES known-answer ciphertext, CRC/FCS results, telemetry records |
| Functional coverage (`covergroup`) | address-map regions, `HTRANS`/`HBURST`/`HSIZE`, AXI strobes, ERROR responses, IRQ events |
| **UVM factory** (`uvm_component_utils` + overrides) | Register every component once, then override it per test — e.g. swap a bus-functional model for the real VeeR master, or an AES reference model for the synthesizable core, **without editing the environment** |
| **`uvm_config_db#(virtual ...)`** | Pass virtual interfaces, clock and reset handles from the top-level testbench down to each component in `build_phase` — no cross-module hierarchical references, so the env is portable and reusable between benches |
| `uvm_reg` / register model | The MMIO map itself (UART, Timer, GPIO, Telemetry, AES-128, CRC32) as a register block |
| Phasing (`build_phase` → `run_phase` → `report_phase`) | Deterministic construction, objection-controlled test end, single place to raise PASS/FAIL |
| `uvm_report_server` | One collection point for the whole regression — the exit code a CI job would gate on |

Two pieces do most of the reuse work, and they are the reason the migration is
worth it:

- **Factory** — components are registered with a type name, and
  `set_type_override()` / `set_inst_override()` at `run_test()` time swaps the
  implementation. The same environment runs directed, random and
  constrained-random scenarios by changing the *test class only*.
- **`uvm_config_db`** — the top-level testbench `uvm_config_db#(virtual axi_if)::set()`s
  the interfaces once; agents and scoreboards `get()` them. Adding a new test,
  a new instance, or a second DUT is a string-and-path change, not a
  hierarchical-signal edit.

### 5.3 Order of migration

1. **AXI 2x8 + AES** — already isolated and passing, so it is the first UVM
   env: AXI master/slave agents, AES reference model in the scoreboard,
   factory-swappable DUT, functional coverage on the register map.
2. **UART** — TX agent + coverage on framing/parity/baud; also the natural
   place to fix the open hang, using the monitor rather than a directed task.
3. **AHB-Lite fabric + VeeR master agent** — IFU/LSU as two sequencers with
   priority scenarios, coverage on arbitration and ERROR responses.
4. **SoC-level virtual sequence** — the end-to-end goal from §2 as one
   `uvm_test`: packet chunks in → telemetry → AES → UART report out.

None of this is built yet — §4.2 has what's actually passing today, and this
section is the plan I'll move into that table one IP at a time.

---

## 6. Where things stand

Some notes on the current state and what I'm taking on next.

1. **Phase 3 is closed: the UART end-to-end run passes.** VeeR boots through
   the 4-slave fabric, writes THR, polls LSR, transmits `UART\n` on `uart_tx`
   (5/5 bytes, 8690 ns bit period) and stores the LSR read-back plus the `0xFF`
   terminator in DMEM — with **zero** exceptions. It took three real bugs to
   get there, all recorded in
   [`doc/Phase3_UART_End_To_End_Completion_Record.md`](doc/Phase3_UART_End_To_End_Completion_Record.md):
   the AHB→AXI bridge returned only one half of VeeR's 64-bit AHB read (the
   TEMT poll never terminated), the fabric arbiter dropped the IFU's address
   phase whenever the LSU was active (24,719 illegal-instruction traps), and
   the vendored UART IP held its TX FIFO in soft-reset from power-on (every
   frame carried the first byte). Fabric TB1 grew `T13`/`T14` to lock both
   protocol fixes down — now 23/23.
2. **UART is on the bus; the rest of the peripherals aren't.** `soc_top` now
   carries the VeeR wrapper, the AHB fabric, IMEM, DMEM, the default ERROR
   slave and — new — the AHB→AXI bridge with the UART at `0x1000_0000`.
   Timer, GPIO, Network Telemetry, AES and CRC32 still decode to the default
   slave, so M4 onwards reuses that same bridge pattern.
3. **The UART register map deviates from arch doc §10.1** and needs an
   amendment: the IP uses `0x00` THR/RBR, `0x04` IER, `0x08` baud (DLAB=1),
   `0x0C` LCR, `0x14` LSR. We keep the IP-native map rather than fork the
   vendored core — §10.1 should be rewritten to match.
4. **The AES record needs a rewrite.**
   `doc/AES_AXI_Integration_Verification_Record.md` still carries the 05-Sep
   status table where `AES core completion`, `STATUS.DONE` and
   `BUSY deassertion` were failing. Those were fixed afterwards and the
   regression runs 19 PASS / 0 FAIL with the ciphertext included — I'll update
   that table so it matches the log.
5. **Everything so far is simulation.** No synthesis, no FPGA, no PPA numbers
   yet — Phase 8 in the plan, and it stays last until simulation is stable.
6. **A few flows still carry hard-coded absolute paths** (`/home/student/...`,
   `/tmp/opencode/veer_p2`): the P1/P2 scripts and filelists. The `run/uart_*`
   filelists use relative paths and relocate cleanly. Details in
   [§10](#10-hard-coded-paths).
7. **Single-author project.** CI and a top-level `LICENSE` are both on the list;
   the vendored cores keep their own licences in the meantime.
8. **CRC32 and the Network Telemetry Engine are specified but not written yet.**
   They exist in the architecture document and the memory map — next RTL to land.
9. **The testbenches are still directed SystemVerilog.** The UVM environment in
   [§5](#5-verification-methodology-directed-today-uvm-next) — factory-registered
   components, `uvm_config_db` for virtual interfaces, scoreboards, coverage —
   is the next step for verification.

Every PASS listed above has a log and a waveform behind it, and §14 has the
commands to reproduce them.

---

## 7. Repository layout

```text
Network_Telemetry_SoC/
├── README.md
├── .gitignore                  # generated files only (see Git policy)
├── .gitmodules                 # 1 submodule: core/Cores-VeeR-EL2
├── core/
│   └── Cores-VeeR-EL2/         # CPU submodule, LOCKED at 06ad26a (do not modify)
├── rtl/
│   ├── soc_top.sv              # SoC top: VeeR + AHB fabric + IMEM/DMEM + bridge/UART
│   ├── ahb/                    # AHB-Lite interconnect, SRAM, default slave, AHB→AXI bridge
│   ├── aes/                    # AES AXI slave wrapper + vendored AES IP (ip/)
│   ├── uart/                   # UART AXI slave wrapper + vendored UART IP (ip/)
│   └── interconnects/          # AXI 2x8 interconnect, arbiter, priority encoder
├── sw/                         # bare-metal firmware: src/, include/, linker/, Makefile
├── tb/                         # self-checking testbenches (*.sv), one per regression
├── run/                        # VCS filelists (*.f), flow scripts (*.csh),
│                               # Verdi signal groups (*.rc), tcl
├── scripts/                    # generators (axi_interconnect_wrap.py, p2_prog_gen.py)
├── aes/                        # OpenCores/asics.ws AES-128 core (vendored)
├── axi-lite_uart-ipcore-develop/  # original UART drop-in (git-ignored; sources
│                               #   copied into rtl/uart/ip/)
└── doc/                        # architecture docs, phase records, screenshots
```

Notes:

- `rtl/` is what simulation compiles; `rtl/aes/ip/` holds the subset of the
  AES core used by the interconnect regressions, while `aes/aes_core-master/`
  is the full upstream core used by `run/aes_run.f`.
- `aes/axi_aes_wrapper.v` is an older copy; the filelists use
  `rtl/aes/axi_aes_wrapper.v`.
- UART IP sources in `rtl/uart/ip/` were copied out of
  `axi-lite_uart-ipcore-develop/` (third-party drop-in, git-ignored).

---

## 8. Fresh clone / setup on a new machine

```bash
git clone https://github.com/Abdul99Aleem/Network_Telemetry_SoC.git
cd Network_Telemetry_SoC
git submodule update --init core/Cores-VeeR-EL2    # CPU, pinned at 06ad26a
git submodule status                               # should show ' 06ad26a...' (leading space)
```

> On the lab machine this checkout lives at
> `/home/student/Documents/honours_project`, and that is the path the flow
> scripts hard-code — see [§10](#10-hard-coded-paths) before moving it.

Synopsys environment (lab machine):

```csh
csh
source /home/student/cshrc     # VCS_HOME, VERDI_HOME, license, PATH
which vcs verdi                # both must resolve
```

RISC-V cross compiler (only needed for firmware, not for Phase 1/2 RTL sims):

```text
/opt/riscv/bin/riscv64-unknown-elf-gcc      # installed 2026-09-26
/root/tools/riscv-gnu/2023.04.29/bin/...    # older, GCC 12.2.0, kept
PATH += /opt/riscv/bin                      # via /etc/profile.d/riscv.sh
```

Details and validation: `doc/RISC_V_GNU_Toolchain_Setup_and_Validation_Record.md`.

> **Portability note:** several flow scripts and filelists embed absolute
> paths (`/home/student/Documents/honours_project`, `/tmp/opencode/veer_p2`).
> See [§10](#10-hard-coded-paths) before moving the repo.

---

## 9. Memory map

| Range | Size | Block | Access |
|---|---|---|---|
| `0x0000_0000` | 32 KB | IMEM | IFU read/execute |
| `0x0001_0000` | 32 KB | DMEM | LSU read/write |
| `0x1000_0000` | 4 KB | UART (TX-only) | LSU read/write |
| `0x1000_1000` | 4 KB | Timer | LSU read/write |
| `0x1000_2000` | 4 KB | GPIO | LSU read/write |
| `0x1000_3000` | 4 KB | Network Telemetry | LSU read/write |
| `0x1000_4000` | 4 KB | AES-128 | LSU read/write |
| `0x1000_5000` | 4 KB | CRC32 | LSU read/write |

(Source: `doc/RISC_V_Network_Telemetry_SoC_Architecture_Document_v3.md` §9.)

The map above is the target layout; what is wired into `soc_top` today is in
[§6](#6-where-things-stand) point 2.

---

## 10. Hard-coded paths

Measured on 2026-09-26; fix them (or symlink) when relocating the repo:

| File | Embedded path |
|---|---|
| `run/p1_full_flow.csh`, `p1_hello_world_ahb.csh`, `p1_open_verdi.csh` | `RV_ROOT=/home/student/Documents/honours_project/core/Cores-VeeR-EL2`, `/tmp/opencode/veer_p1` |
| `run/p2_full_flow.csh`, `p2_open_verdi.csh` | `PROJ=/home/student/Documents/honours_project`, `/tmp/opencode/veer_p2`, `VCS_HOME`, `VERDI_HOME`, license host |
| `run/p2_fabric_run.f`, `p2_veer_soc_run.f` | absolute `/home/student/Documents/honours_project/rtl/...` |
| `run/p2_veer_soc_run.f` | `/tmp/opencode/veer_p2/snapshots/p2_soc/...` |
| `run/p1_wave.rc`, `p2_wave.rc`, `p2_veer_wave.rc` | absolute FSDB paths for Verdi |
| `run/uart_full_flow.csh` | relative (relocates cleanly) |

`run/uart_*.f` filelists use `../rtl/...` relatives — those are portable.

---

## 11. Running the regressions

All flows run from `run/` and need `csh` + `source /home/student/cshrc`.
Everything they generate (`simv`, `*.log`, `*.fsdb`, `csrc/`, `verdiLog/`) is
git-ignored; build products stay in `/tmp` for Phase 1/2.

### Phase 1 — VeeR bring-up (PASS)

```csh
cd ~/Documents/honours_project/run
./p1_full_flow.csh      # veer.config -> vcs-build -> program.hex -> simv
./p1_open_verdi.csh     # Verdi: dump.fsdb + p1_wave.rc signal groups
```

Expected (reproduced 2026-09-26):

```text
[117000 ns] -------------------------
[455000 ns] Hello World from VeeR EL2
[1142000 ns] TEST_PASSED
Finished : minstret = 330, mcycle = 1134
```

Waveform times: banner `117000` ns, Hello-World bytes `455000` ns,
PASS `1142000` ns. `default_ahb` has **no AXI** — inspect `ic_/lsu_/mux_` AHB
signals, not AXI. Verdi needs a visible `$DISPLAY` (physical `:0`); never
force `:42` on a headless box.

> **Note (verified 2026-09-26):** VeeR's `program.hex` rule builds with GCC
> **if `riscv64-unknown-elf-gcc` is on PATH**, which then needs the
> `third_party/picolibc` submodule (currently empty) and fails with
> `ERROR: Neither directory contains a build file meson.build`. Two ways around it:
>
> 1. Hide the cross compiler so VeeR uses its canned hex (fast, this is how
>    the Phase-1 PASS was produced):
>
>    ```csh
>    csh
>    source /home/student/cshrc
>    setenv PATH `echo $PATH | tr ":" "\n" | grep -v riscv | paste -sd:`
>    cd ~/Documents/honours_project/run
>    ./p1_full_flow.csh
>    ```
>
> 2. Or initialise picolibc (needs network + meson/ninja, both installed):
>
>    ```bash
>    git -C core/Cores-VeeR-EL2 submodule update --init third_party/picolibc
>    ```

Manual equivalents (workdir `/tmp/opencode/veer_p1`):

```csh
setenv RV_ROOT ~/Documents/honours_project/core/Cores-VeeR-EL2
env BUILD_PATH=$PWD/snapshots/default_ahb RV_ROOT=$RV_ROOT \
  $RV_ROOT/configs/veer.config -target=default_ahb -snapshot=default_ahb
make -f $RV_ROOT/tools/Makefile target=default_ahb snapshot=default_ahb TEST=hello_world vcs-build debug=1
make -f $RV_ROOT/tools/Makefile target=default_ahb snapshot=default_ahb TEST=hello_world program.hex
./simv +dumpon +vcs+lic+wait -a vcs_run.log
verdi -ssf dump.fsdb -dbdir simv.daidir -sswr ~/Documents/honours_project/run/p1_wave.rc &
```

### Phase 2 — AHB-Lite fabric (PASS)

Project fabric (`rtl/ahb/`, `rtl/soc_top.sv`): IFU/LSU masters, LSU priority,
IMEM `0x0000_0000` + DMEM `0x0001_0000` (32 KB each), default ERROR slave.
SoC boots from IMEM (`p2_soc` snapshot, `reset_vec=0`).

```csh
cd ~/Documents/honours_project/run
./p2_full_flow.csh      # TB1 directed fabric (16/16) + TB2 VeeR-through-fabric
```

Expected (reproduced 2026-09-26): `P2_TB1_RESULT: PASS`,
`P2_TB2_RESULT: PASS`, final line `=== P2 FLOW: TB1 PASS + TB2 PASS ===`.

> Use the **default workdir** (`/tmp/opencode/veer_p2`): `p2_veer_soc_run.f`
> hard-codes snapshot paths under it. Passing another workdir fails with
> `Source file "/tmp/opencode/veer_p2/snapshots/p2_soc/common_defines.vh"
> cannot be opened`.

Waveforms:

```csh
cd /tmp/opencode/veer_p2/tb1
verdi -ssf p2_fabric.fsdb -dbdir simv.daidir -sswr ~/Documents/honours_project/run/p2_wave.rc &
cd ../tb2
verdi -ssf p2_veer_soc.fsdb -dbdir simv.daidir -sswr ~/Documents/honours_project/run/p2_veer_wave.rc &
```

### AES / AXI regression (isolated subsystem, PASS)

```csh
cd ~/Documents/honours_project/run
vcs -full64 -sverilog -f aes_axi_interconnect_run.f -debug_access+all -kdb -l compile_aes_axi_interconnect.log
./simv -l sim_aes_axi_interconnect.log        # expect: AXI INTERCONNECT -> AES INTEGRATION: PASS
vcs -full64 -sverilog -f aes_axi_2master_run.f -debug_access+all -kdb -l compile_aes_2master.log
./simv -l sim_aes_2master.log                 # expect: PASS checks : 19 / FAIL checks : 0
```

Both were re-run and passed on 2026-09-26. Known-answer vector everywhere:
key `00010203...0f`, pt `00112233...ff`, ct `69c4e0d86a7b0430d8cdb78070b4c55a`.

### UART regression (PASS, isolated)

```csh
cd ~/Documents/honours_project/run
./uart_full_flow.csh    # [1/3] direct slave -> [2/3] interconnect -> [3/3] 2-master
```

Expected (run 2026-09-26 15:18): `UART AXI SLAVE DIRECT: PASS`,
`AXI INTERCONNECT -> UART INTEGRATION: PASS`,
`PASS checks : 19 / FAIL checks : 0`. The read-channel fix in
`rtl/uart/uart_axi_slave.v` plus the watchdogs in all three benches is what
took this from a silent stall to a passing run. Waveform configs:
`uart_wave.rc`, `uart_axi_slave_wave.rc`, `uart_2master_wave.rc`.

### Phase 3 — UART on the SoC (PASS)

```csh
cd ~/Documents/honours_project/run
./p3_uart_flow.csh    # uart_soc snapshot -> program -> E2E TB -> TB1 fabric regression
```

Exit 0 = both pass. The path under test is the whole story of this project in
miniature: VeeR → AHB fabric → `ahb_to_axi_bridge` → `uart_axi_slave` →
`axi_uart_top` → `uart_tx_o` (8N1 serial). The bench auto-calibrates the bit
period from the first byte, then checks `UART\n` on the wire, the DMEM
completion terminator and the LSR value read back through the bridge.

Last run (2026-09-26 17:42), exit 0:

```
UART MONITOR: calibrated bit period = 8690000 ns (869 clk)
 UART RX[0..4] = 0x55 0x41 0x52 0x54 0x0a   ("UART\n")
 DMEM[2]      : 0xff (expect FF)
 DMEM[4..7]   : 60 00 00 00 (LSR via bridge, expect 60 00 00 00)
 uart_irq     : 0 (expect 0, TX-only)
 UART_E2E_RESULT: PASS (VeeR -> AHB -> AXI -> UART -> uart_tx)
P2 FABRIC: PASS=23 FAIL=0
P2_TB1_RESULT: PASS
```

`grep -c "EXC cause=" sim_uart_e2e.log` is 0 — no traps at all.
Full record: [`doc/Phase3_UART_End_To_End_Completion_Record.md`](doc/Phase3_UART_End_To_End_Completion_Record.md).

### Verdi

```csh
setenv DISPLAY :0        # physical display; do not force :42 headless
verdi -ssf <wave.fsdb> -dbdir simv.daidir -sswr run/<name>_wave.rc &
```

---

## 12. Documentation index

| Document | Purpose |
|---|---|
| `doc/RISC_V_Network_Telemetry_SoC_Architecture_Document_v3.md` | Frozen architecture (memory map, registers, phases, DoD) |
| `doc/RISC_V_Network_Telemetry_SoC_Port_List.md` | Top-level port list |
| `doc/RISC_V_Network_Telemetry_SoC_Progress_and_Architecture.md` | Progress + AXI/AES baseline |
| `doc/Phase1_VeeR_Bringup_Completion_Record.md` | Phase 1 evidence |
| `doc/Phase2_AHB_Fabric_Completion_Record.md` | Phase 2 evidence |
| `doc/Phase3_UART_End_To_End_Completion_Record.md` | Phase 3 evidence: VeeR → AHB → AXI → UART → `uart_tx`, plus the three root causes fixed (bridge 64-bit split, fabric arbiter, UART IP TX FIFO reset) |
| `doc/AES_AXI_Integration_Verification_Record.md` | AES/AXI subsystem evidence (status table update pending — §6.3) |
| `doc/RISC_V_GNU_Toolchain_Setup_and_Validation_Record.md` | Cross-toolchain install/validation |
| `doc/RISC_V_SW_Build_and_Simulation_Image_Architecture_Specification.md` | Frozen firmware build → simulation image flow |
| `doc/SW_HW_Memory_Image_Architecture_First_Principles_and_Spec_Amendments.md` | Image-conversion first principles + amendments H.1–H.9 |
| `doc/Firmware_Build_and_AHB_RW_Verification_Plan.md` | Execution plan — C firmware → Makefile → hex → AHB R/W in Verdi (Steps 1–2 **done**) |
| `doc/Fw0_C_Toolchain_Build_and_Gate_Record.md` | fw0 C toolchain: build output, gates G1–G13, two image defects found |
| `doc/screenshots/` | Verdi captures |

---

## 13. Git policy

**Tracked** — anything a fresh clone needs to reproduce a result: RTL
(`rtl/`, `aes/`), testbenches (`tb/`), flow scripts and filelists
(`run/*.f *.csh *.tcl *.rc`), generators (`scripts/`), docs (`doc/`), and
the pinned CPU submodule.

**Ignored** — anything a tool regenerates: `simv`, `csrc/`, `*.log`,
`*.fsdb/*.vcd`, `verdiLog/`, `novas.*`, coverage DBs, firmware build
outputs, editor/OS junk, plus local archives (`*.zip`) and third-party
drop-ins whose sources already live in `rtl/`.

Rules of thumb (both enforced by `.gitignore`):

1. New flow script or filelist in `run/`? **Tracked automatically** — the
   ignore file whitelists `run/*.{f,csh,tcl,rc}` instead of listing names,
   so adding `uart_*` needed no change.
2. Source file (`*.v`, `*.sv`, `*.vh`, `*.c`, `*.h`, `main.c`)? **Never
   ignored** — no source patterns are ignored anywhere.
3. Verdi drops `run/novas.rc` and `run/verdi_config_file`; both are
   re-ignored after the whitelist.

Other rules:

- `core/Cores-VeeR-EL2` is a locked submodule — never edit; wrap, don't fork.
- Commit per phase with evidence; never claim PASS without a log + waveform.
- `git status` should show nothing but your intended changes; if an untracked
  source file appears under `run/`, it is a new asset and belongs in the repo.

---

## 14. README ↔ repository verification checklist

Run these from the repo root to confirm this file still matches reality:

```bash
# 1. Submodule pinned at 06ad26a, single submodule declared
git submodule status | grep '^ 06ad26a' && grep -c '^\[submodule' .gitmodules   # 06ad26a / 1

# 2. No tracked file is ignored, no source file is ignored
git ls-files | git check-ignore --stdin | wc -l                                  # 0
git check-ignore rtl/uart/uart_axi_slave.v tb/tb_uart_axi_slave.sv; echo $?       # 1 (not ignored)

# 3. Repo is in sync with GitHub (0 0 only after a push)
git fetch && git rev-list --left-right --count origin/main...HEAD                 # 0  0

# 4. Tracker numbers still match §4.1
git rev-list --count HEAD          # 22
git ls-files | wc -l               # 112
git archive HEAD | tar -xO | wc -l # 41332

# 5. Every path referenced above exists
for p in rtl/soc_top.sv rtl/ahb rtl/aes rtl/uart rtl/interconnects scripts doc sw \
         run/p1_full_flow.csh run/p2_full_flow.csh run/uart_full_flow.csh \
         run/p3_uart_flow.csh run/aes_axi_interconnect_run.f run/aes_axi_2master_run.f \
         doc/RISC_V_Network_Telemetry_SoC_Architecture_Document_v3.md \
         doc/Phase1_VeeR_Bringup_Completion_Record.md \
         doc/Phase2_AHB_Fabric_Completion_Record.md \
         doc/Phase3_UART_End_To_End_Completion_Record.md \
         doc/RISC_V_GNU_Toolchain_Setup_and_Validation_Record.md \
         core/Cores-VeeR-EL2/configs/veer.config; do
  [ -e "$p" ] || echo "MISSING: $p"
done

# 6. Regressions actually pass (needs Synopsys env)
csh -fc 'source /home/student/cshrc; cd run; ./p1_full_flow.csh; echo EXIT=$status'
csh -fc 'source /home/student/cshrc; cd run; ./p2_full_flow.csh; echo EXIT=$status'
csh -fc 'source /home/student/cshrc; cd run; ./p3_uart_flow.csh; echo EXIT=$status'
```

Last run: 2026-09-26 — Phase 1 `TEST_PASSED` (minstret=330), Phase 2
`TB1 PASS + TB2 PASS`, AES interconnect `INTEGRATION: PASS`, AES 2-master
`19 PASS / 0 FAIL`, UART direct/interconnect/2-master all PASS (15:18),
Phase 3 UART end-to-end `UART_E2E_RESULT: PASS` + fabric TB1 `PASS=23 FAIL=0`
(17:42), exit 0.
