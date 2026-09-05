# RISC-V Network Telemetry SoC

VeeR EL2 (RV32IMC) based System-on-Chip that ingests simulated Ethernet traffic
in hardware, builds 128-bit telemetry records in software, encrypts them with
a hardware AES-128 accelerator, and reports over UART. Final system bus:
**AHB-Lite**. RTL simulation + bare-metal C is the primary proof.

## Repo layout

```text
honours_project/
├── core/Cores-VeeR-EL2/   # CPU submodule, LOCKED at 06ad26a (do not modify)
├── rtl/                   # SoC RTL: aes/ + interconnects/
├── tb/                    # AXI/AES testbenches
├── run/                   # VCS filelists (*.f) + Phase-1 flow scripts (p1_*)
├── scripts/               # generators (axi_interconnect_wrap.py)
├── aes/                   # AES core sources (asics.ws, adapted)
├── doc/                   # architecture docs + phase completion records
└── README.md
```

Authoritative architecture: `doc/RISC_V_Network_Telemetry_SoC_Architecture_Document_v3.md`
(frozen: AHB-Lite, memory map, PIC IDs 1=NET/2=AES/3=Timer, CPU-observed
timestamp, AES-128-only, TX-only UART). Phase evidence:
`doc/Phase1_VeeR_Bringup_Completion_Record.md`.

Memory map: IMEM `0x0000_0000`, DMEM `0x0001_0000`, UART `0x1000_0000`,
Timer `0x1000_1000`, GPIO `0x1000_2000`, Telemetry `0x1000_3000`,
AES `0x1000_4000`, CRC `0x1000_5000`.

## Prerequisites (lab machine)

```csh
csh
source /home/student/cshrc   # VCS U-2023.03 + Verdi U-2023.03-SP1 + licenses
```

No RISC-V GCC here — VeeR tests use canned hex. No Verilator — use VCS.
Build outputs go to `/tmp/opencode/veer_p1` (outside the repo, see `.gitignore`).

## Phase 1 — VeeR bring-up (PASS)

```csh
cd ~/Documents/honours_project/run
./p1_full_flow.csh      # config -> vcs-build (FSDB) -> program.hex -> simv -> TEST_PASSED
./p1_open_verdi.csh     # opens Verdi: dump.fsdb + p1_wave.rc signal groups
```

Expect `TEST_PASSED` (`minstret=330, mcycle=1134`). Waveform times: banner
`117000` ns, Hello-World bytes `455000` ns, PASS `1142000` ns. Needs a visible
`$DISPLAY` (physical `:0`); never force `:42` (headless). `default_ahb` has
**no AXI** — verify `ic_/lsu_/mux_` AHB signals, not AXI.

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

## AES / AXI regression (isolated subsystem, pre-existing)

```csh
cd run
vcs -full64 -sverilog -f aes_axi_interconnect_run.f -debug_access+all -kdb -l compile_aes_axi_interconnect.log
./simv -l sim_aes_axi_interconnect.log        # expect INTEGRATION: PASS
vcs -full64 -sverilog -f aes_axi_2master_run.f -debug_access+all -kdb -l compile_aes_2master.log
./simv -l sim_aes_2master.log                 # expect PASS 19 / FAIL 0
```

Known-answer vector everywhere: key `00010203…0f`, pt `00112233…ff`,
ct `69c4e0d86a7b0430d8cdb78070b4c55a`.

## Git policy

- `core/Cores-VeeR-EL2` is a locked submodule — never edit; wrap, don't fork.
- `run/` holds only filelists + flow scripts; binaries/logs/waveforms are
  git-ignored (see `.gitignore`). Sim work stays in `/tmp`.
- Commit per phase with evidence; never claim PASS without a log + waveform.

## Phase status

| Phase | Status |
|---|---|
| 1 VeeR bring-up | PASS (`doc/Phase1_VeeR_Bringup_Completion_Record.md`) |
| 2 AHB-Lite fabric | NOT STARTED |
| 3 AES integration | NOT STARTED (isolated AXI-AES PASS pre-exists) |
| 4 Telemetry + IRQ | NOT STARTED |
| 5 Full SoC | NOT STARTED |
