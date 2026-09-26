# RISC-V Network Telemetry SoC

VeeR EL2 (RV32IMC) based System-on-Chip that ingests simulated Ethernet traffic
in hardware, builds 128-bit telemetry records in software, encrypts them with a
hardware AES-128 accelerator, and reports over UART. Final system bus:
**AHB-Lite**. RTL simulation + bare-metal C is the primary proof.

- **Remote:** <https://github.com/Abdul99Aleem/honours_project> (branch `main`)
- **Tools:** Synopsys VCS U-2023.03 + Verdi U-2023.03-SP1 (FSDB)
- **Last full README verification:** 2026-09-26 (every flow below was re-run;
  see [Verification checklist](#readme--repository-verification-checklist))

---

## Status

| Item | Status | Evidence |
|---|---|---|
| Phase 1 — VeeR bring-up (`default_ahb`) | **PASS** | `doc/Phase1_VeeR_Bringup_Completion_Record.md`, re-verified 2026-09-26 |
| Phase 2 — AHB-Lite fabric (TB1 + TB2) | **PASS** | `doc/Phase2_AHB_Fabric_Completion_Record.md`, re-verified 2026-09-26 |
| AXI 2x8 interconnect + AES-128 (isolated) | **PASS** | `doc/AES_AXI_Integration_Verification_Record.md`, re-verified 2026-09-26 |
| UART AXI subsystem (isolated) | **IN PROGRESS** | direct-slave TB hangs after `TX IDLE HIGH PASS`; sources not yet committed |
| RISC-V GNU toolchain bring-up | **PASS** | `doc/RISC_V_GNU_Toolchain_Setup_and_Validation_Record.md` |
| Phase 3 — AES integration into SoC | NOT STARTED | |
| Phase 4 — Telemetry + IRQ | NOT STARTED | |
| Phase 5 — Full SoC | NOT STARTED | |

Authoritative architecture: `doc/RISC_V_Network_Telemetry_SoC_Architecture_Document_v3.md`
(frozen: AHB-Lite, memory map, PIC IDs 1=NET / 2=AES / 3=Timer, CPU-observed
timestamp, AES-128-only, TX-only UART).

---

## Repository layout

```text
honours_project/
├── README.md
├── .gitignore                  # generated files only (see Git policy)
├── .gitmodules                 # 1 submodule: core/Cores-VeeR-EL2
├── core/
│   └── Cores-VeeR-EL2/         # CPU submodule, LOCKED at 06ad26a (do not modify)
├── rtl/
│   ├── soc_top.sv              # SoC top (VeeR + AHB fabric + peripherals)
│   ├── ahb/                    # AHB-Lite interconnect, SRAM, default slave
│   ├── aes/                    # AES AXI slave wrapper + vendored AES IP (ip/)
│   ├── uart/                   # UART AXI slave wrapper + vendored UART IP (ip/)
│   └── interconnects/          # AXI 2x8 interconnect, arbiter, priority encoder
├── tb/                         # testbenches (*.sv), one per regression
├── run/                        # VCS filelists (*.f), flow scripts (*.csh),
│                               # Verdi signal groups (*.rc), tcl
├── scripts/                    # generators (axi_interconnect_wrap.py, p2_prog_gen.py)
├── aes/                        # asics.ws AES-128 core (vendored, used by aes_run.f)
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

## Fresh clone / setup on a new machine

```bash
git clone https://github.com/Abdul99Aleem/honours_project.git
cd honours_project
git submodule update --init core/Cores-VeeR-EL2    # CPU, pinned at 06ad26a
git submodule status                               # should show ' 06ad26a...' (leading space)
```

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

> **Portability warning:** several flow scripts and filelists embed absolute
> paths (`/home/student/Documents/honours_project`, `/tmp/opencode/veer_p2`).
> See [Hard-coded paths](#hard-coded-paths) before moving the repo.

---

## Memory map

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

---

## Running the regressions

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

> **Gotcha (verified 2026-09-26):** VeeR's `program.hex` rule builds with GCC
> **if `riscv64-unknown-elf-gcc` is on PATH**, which then needs the
> `third_party/picolibc` submodule (currently empty) and fails with
> `ERROR: Neither directory contains a build file meson.build`. Two ways out:
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

### UART regression (IN PROGRESS)

```csh
cd ~/Documents/honours_project/run
./uart_full_flow.csh    # [1/3] direct slave -> [2/3] interconnect -> [3/3] 2-master
```

Current state: step 1 compiles and elaborates, prints `TX IDLE HIGH PASS`,
then **hangs** (no `UART AXI SLAVE DIRECT: PASS`). Steps 2 and 3 have never
completed. Waveform configs: `uart_wave.rc`, `uart_axi_slave_wave.rc`,
`uart_2master_wave.rc`.

### Verdi

```csh
setenv DISPLAY :0        # physical display; do not force :42 headless
verdi -ssf <wave.fsdb> -dbdir simv.daidir -sswr run/<name>_wave.rc &
```

---

## Hard-coded paths

These were measured on 2026-09-26; fix them (or symlink) when relocating the
repo:

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

## Documentation index

| Document | Purpose |
|---|---|
| `doc/RISC_V_Network_Telemetry_SoC_Architecture_Document_v3.md` | Frozen architecture (memory map, registers, phases, DoD) |
| `doc/RISC_V_Network_Telemetry_SoC_Port_List.md` | Top-level port list |
| `doc/RISC_V_Network_Telemetry_SoC_Progress_and_Architecture.md` | Progress + AXI/AES baseline |
| `doc/Phase1_VeeR_Bringup_Completion_Record.md` | Phase 1 evidence |
| `doc/Phase2_AHB_Fabric_Completion_Record.md` | Phase 2 evidence |
| `doc/AES_AXI_Integration_Verification_Record.md` | AES/AXI subsystem evidence |
| `doc/RISC_V_GNU_Toolchain_Setup_and_Validation_Record.md` | Cross-toolchain install/validation |
| `doc/screenshots/` | Verdi captures |

---

## Git policy

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

## README ↔ repository verification checklist

Run these from the repo root to confirm this file still matches reality:

```bash
# 1. Submodule pinned at 06ad26a, single submodule declared
git submodule status | grep '^ 06ad26a' && grep -c '^\[submodule' .gitmodules   # 06ad26a / 1

# 2. No tracked file is ignored, no source file is ignored
git ls-files | git check-ignore --stdin | wc -l                                  # 0
git check-ignore rtl/uart/uart_axi_slave.v tb/tb_uart_axi_slave.sv; echo $?       # 1 (not ignored)

# 3. Repo is in sync with GitHub
git fetch && git rev-list --left-right --count origin/main...HEAD                 # 0  0

# 4. Every path referenced above exists
for p in rtl/soc_top.sv rtl/ahb rtl/aes rtl/uart rtl/interconnects scripts doc \
         run/p1_full_flow.csh run/p2_full_flow.csh run/uart_full_flow.csh \
         run/aes_axi_interconnect_run.f run/aes_axi_2master_run.f \
         doc/RISC_V_Network_Telemetry_SoC_Architecture_Document_v3.md \
         doc/Phase1_VeeR_Bringup_Completion_Record.md \
         doc/Phase2_AHB_Fabric_Completion_Record.md \
         doc/RISC_V_GNU_Toolchain_Setup_and_Validation_Record.md \
         core/Cores-VeeR-EL2/configs/veer.config; do
  [ -e "$p" ] || echo "MISSING: $p"
done

# 5. Regressions actually pass (needs Synopsys env)
csh -fc 'source /home/student/cshrc; cd run; ./p1_full_flow.csh; echo EXIT=$status'
csh -fc 'source /home/student/cshrc; cd run; ./p2_full_flow.csh; echo EXIT=$status'
```

Last run: 2026-09-26 — Phase 1 `TEST_PASSED` (minstret=330), Phase 2
`TB1 PASS + TB2 PASS`, AES interconnect `INTEGRATION: PASS`, AES 2-master
`19 PASS / 0 FAIL`, UART step 1 hangs at `TX IDLE HIGH PASS`.
