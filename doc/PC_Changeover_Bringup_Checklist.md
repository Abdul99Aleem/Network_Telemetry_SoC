# PC Changeover — Bringup Checklist

| Field | Value |
| ----- | ----- |
| Purpose | Reproduce a working dev box from scratch after an OS reinstall / PC swap |
| Repo | `https://github.com/Abdul99Aleem/Network_Telemetry_SoC.git` |
| Branch | `feature/sw-build-ahb-rw` |
| Submodule pin | `core/Cores-VeeR-EL2` @ `06ad26aa8951d0f91068d19d106ed97f8f8ed257` (`2.0-350-g06ad26a`) |
| Repo path (assumed identical on both PCs) | `/home/student/Documents/honours_project` |
| Baseline recorded from | Rocky Linux 8.10 x86_64, 12 cores, 31 GB RAM, hostname `vlsi45` |
| Companion docs | `doc/RISC_V_GNU_Toolchain_Setup_and_Validation_Record.md`, `README.md` §8/§10 |

> **Assumption this document makes:** the new PC keeps the same username
> (`student`) and the same repo path
> (`/home/student/Documents/honours_project`). That is what makes §7 free —
> every `run/*.f` filelist hard-codes absolute paths and needs **zero edits**.
> If either changes, read §7.2 before starting.

> **Scope:** this project is **simulation-only**. No Vivado, no Quartus, no
> bitstream, no synthesis (`README.md:16,314`). Design Compiler and PrimeTime
> appear in `~/cshrc` but are unused by this flow — you do not need them.
> See §7.4 if you want to skip copying them.

---

## 0. TL;DR — the order that works

```
1.  Base OS + host packages          (§1)   ~10 min
2.  Carry over 4 out-of-repo items    (§2)   ~60 min of copying
3.  Synopsys VCS + Verdi             (§3)   ~60 min
4.  cshrc + license env               (§4)   ~2 min
5.  RISC-V cross toolchain            (§5)   ~90 min build
6.  Clone repo + submodule            (§6)   ~15 min
7.  Paths / symlinks                  (§7)   ~2 min
8.  Prove it: make + gates            (§8)   ~15 min
9.  Verdi GUI check                   (§9)   ~5 min
10. Re-run regressions p1/p2/p3       (§10)  ~30 min
```

Total: roughly **half a day**, most of it copying 87 GB of Synopsys tools and
building the compiler.

**The single most important gate** — if §8.3 prints both tokens, you are done:

```text
[SIM] PASS  P2_TB2_RESULT: PASS
[SIM] PASS  AHB_RW_MONITOR: PASS
```

---

## 1. Base OS and host packages

### 1.1 OS

VCS U-2023.03 officially supports RHEL8 derivatives. Rocky Linux 8.10 works and
is what this project was proven on.

```bash
cat /etc/redhat-release     # expect: Rocky Linux release 8.10 (Green Obsidian)
uname -r                    # expect: 4.18.0-553.el8_10.x86_64
```

VCS will always print this on Rocky and it is **harmless**:

```text
Warning-[LNX_OS_VERUN] Unsupported Linux version ... Rocky Linux release 8.10 ... is not supported on 'x86_64' officially
```

To silence it, `export VCS_ARCH_OVERRIDE=linux`. It was **not** set during the
recorded runs, so leaving it unset reproduces the baseline exactly. Do not set
it unless the warning actually bothers you.

### 1.2 Packages

```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --set-enabled powertools
sudo dnf clean all && sudo dnf makecache
sudo dnf install -y texinfo meson ninja-build
```

Also required by the flows (all present on the baseline box):

| Tool | Why | Check |
| ---- | --- | ----- |
| `git` | repo + submodule | `git --version` |
| `make` | root / `sw` / `sim` Makefiles | `make --version` |
| `bash` | **mandatory** — `sw/Makefile:25` sets `SHELL := /bin/bash` because recipes use bash process substitution and `16#` radix arithmetic | `bash --version` |
| `csh` / `tcsh` | **mandatory** — every `run/*.csh` is `#!/bin/csh -f` | `csh -c 'echo ok'` |
| `perl` | VeeR's `configs/veer.config` is a Perl script | `perl --version` |
| `python3` | `scripts/p2_prog_gen.py`, `scripts/p3_uart_prog_gen.py` (**stdlib only** — no pip installs needed) | `python3 --version` |
| `binutils` (`nm`, `objdump`) | SW gates | `nm --version` |
| `sed`, `grep`, `awk`, `od` | image post-processing, gates | — |
| X11 (`xwininfo`, `libX11.so.6`, `libXtst.so.6`) | only for the Verdi dialog dismisser (§9.3) | `rpm -q libX11 libXtst` |

> **Do not install `pyelftools`.** The spec records it as deliberately absent
> (`RISC_V_SW_Build_and_Simulation_Image_Architecture_Specification.md:160`) —
> use `objcopy`, not Python ELF parsing.

> **`python3` version.** The baseline had Python **3.6**. `scripts/*.py` use
> only stdlib so any 3.6+ works. But if you rebuild the §9.3 dialog
> dismisser, note 3.6 has no `subprocess.run(capture_output=True)`.

### 1.3 Disk and RAM budget

Measured on the baseline box:

| Item | Size | Mount | Note |
| ---- | ---- | ----- | ---- |
| `~/snps_tools_target/` (full tree) | **87 GB** | `/home` | only `vcs`+`verdi`+`verdi_supp` = **61 GB** needed (§7.4) |
| `/opt/riscv` (built toolchain) | **3.3 GB** | `/` | root fs — make sure `/` has room |
| `riscv-gnu-toolchain` build source | **17 GB** | `/home` | delete after §5 |
| `build/sim/fw0` (FSDB + simv.daidir) | ~1–2 GB | `/home` | `make clean` to reclaim |
| `/tmp/opencode/*` Phase-1/2/3 trees | ~3 GB | `/tmp` | regenerable, do **not** migrate |

Baseline had 699 GB free on `/home`. Budget **70 GB minimum**.

---

## 2. What lives OUTSIDE the repo (the 4 things git cannot save you)

This is the part people forget. None of these are in git, and none of them
survive an OS reinstall:

| # | Path on old PC | Size | Why you need it | § |
| - | -------------- | ---- | --------------- | - |
| 1 | `~/snps_tools_target/{vcs,verdi,verdi_supp}` | 61 GB | VCS + Verdi themselves | §3 |
| 2 | `~/cshrc` | 4 KB | VCS/Verdi env + license | §4 |
| 3 | `/etc/profile.d/riscv.sh` | 33 B | puts `/opt/riscv/bin` on PATH | §5.4 |
| 4 | `/opt/riscv/` | 3.3 GB | the cross toolchain | §5 |

Everything else — the repo, the submodule, `build/`, `sw/build/`, all
`*.log`, all `*.fsdb` — is either in git or regenerable with `make`. **Do not
migrate FSDBs or build trees.**

### 2.1 Copy them off before you wipe the old machine

```bash
mkdir -p ~/pc-migration
tar -C /home/student -czf ~/pc-migration/snps_tools_target.tar.gz \
    snps_tools_target/vcs snps_tools_target/verdi snps_tools_target/verdi_supp
cp ~/cshrc ~/pc-migration/cshrc
sudo cp /etc/profile.d/riscv.sh ~/pc-migration/riscv.sh

# toolchain: copying a built /opt/riscv is fine and much faster than rebuilding
sudo tar -C /opt -czf ~/pc-migration/riscv-opt.tar.gz riscv
```

> The Synopsys tarball is ~61 GB compressed-ish and takes a long time. Start it
> first. If you would rather re-install VCS from the Synopsys installer than
> copy, see §3.3.

---

## 3. Synopsys VCS and Verdi

Target versions — **these are not negotiable**, the flow is validated against
them:

| Tool | Version string | Install dir on baseline |
| ---- | -------------- | ----------------------- |
| VCS | `U-2023.03_Full64` (compiler **and** runtime) | `~/snps_tools_target/vcs/U-2023.03` |
| Verdi | `U-2023.03-SP1 for linux64 - May 28, 2023` | `~/snps_tools_target/verdi/U-2023.03-SP1` |

### 3.1 Restore the install tree

```bash
cd /home/student
tar -xzf ~/pc-migration/snps_tools_target.tar.gz      # ~61 GB, allow time
ls ~/snps_tools_target/
# expect exactly:  verdi  verdi_supp  vcs
```

> `sentaurus/` and `syn/` also exist in that tree but are **unused** by this
> project. If you skipped them in the tar, that is fine.

### 3.2 Permissions

The baseline tree is `student`-owned. VCS is installed **without root**, under
`/home/student` — do not install it into `/opt` or run `chown root` on it.

```bash
ls -ld ~/snps_tools_target/vcs/U-2023.03/bin
chmod -R u+rwX,go+rX ~/snps_tools_target
```

### 3.3 If you re-install from the Synopsys installer instead

Install **VCS U-2023.03 Full64** and **Verdi U-2023.03-SP1**, then either:

- install to the same prefixes (`~/snps_tools_target/vcs/U-2023.03`,
  `~/snps_tools_target/verdi/U-2023.03-SP1`) so `sim/Makefile:30-31` needs no
  edit, **or**
- edit `sim/Makefile:30-31` and the `VCS_HOME`/`VERDI_HOME` fallbacks in
  `run/p2_full_flow.csh:11-13` and `run/p3_uart_flow.csh:15-17`.

```make
# sim/Makefile:30-31  -- the ONLY two lines that name tool paths
VCS_HOME   ?= /home/student/snps_tools_target/vcs/U-2023.03
VERDI_HOME ?= /home/student/snps_tools_target/verdi/U-2023.03-SP1
```

Both are `?=` so you can also override without editing:

```bash
make VCS_HOME=/path/to/vcs/U-2023.03 VERDI_HOME=/path/to/verdi/U-2023.03-SP1
```

---

## 4. Environment: `cshrc` and the license server

### 4.1 License

Everything in this project uses **one** variable, `SNPSLMD_LICENSE_FILE`:

```text
SNPSLMD_LICENSE_FILE = 27021@14.139.1.126
```

`LM_LICENSE_FILE` appears **nowhere** in this repo. If you set only that, VCS
will not find a license.

### 4.2 Restore `~/cshrc`

```bash
cp ~/pc-migration/cshrc ~/cshrc
```

`~/cshrc` also references `finesim/` and `prime/` install dirs that were never
installed on the baseline box, so it echoes paths for tools that do not exist.
**That is the baseline behaviour — leave it alone.** Only the VCS/Verdi blocks
matter.

If you need to rebuild it, these three settings are the load-bearing part:

```csh
setenv VCS_HOME   /home/student/snps_tools_target/vcs/U-2023.03
setenv VERDI_HOME  /home/student/snps_tools_target/verdi/U-2023.03-SP1
setenv SNPSLMD_LICENSE_FILE 27021@14.139.1.126
set path = ( $VCS_HOME/bin $VERDI_HOME/bin $path )
```

### 4.3 CRITICAL: `VCS_HOME` / `VERDI_HOME` must be **exported**

`sim/Makefile:28-29` records why:

> `VCS_HOME`/`VERDI_HOME` must be *exported*, not just used to build PATH: the
> vcs wrapper resolves its own scripts (`vcsMsgReport` etc.) from
> `$VCS_HOME/bin`.

If you only prepend to `PATH` and forget `export`, you get:

```text
Cannot find 'vcsMsgReport' script in /bin
```

`sim/Makefile:32-34` already does the right thing (`export` + PATH), so the
Make flow is safe. This only bites you if you hand-roll a shell for `run/*.csh`.

### 4.4 Verify

```csh
csh
source ~/cshrc
which vcs verdi                 # both must resolve under ~/snps_tools_target
echo $SNPSLMD_LICENSE_FILE      # 27021@14.139.1.126
echo $VCS_HOME ; echo $VERDI_HOME
```

> **Do not use `vcs -ID` as the smoke test.** It prints
> `vcs script version : U-2023.03` correctly but also emits two *harmless* errors
> on this box, because the helper binaries resolve their own libraries and
> `libnsl.so.1` is not installed anywhere:
>
> ```text
> .../linux/bin/vcsMsgReport1: error while loading shared libraries: libnsl.so.1: cannot open shared object file
> .../linux/bin/vcs1: error while loading shared libraries: libelf.so.1: cannot open shared object file
> ```
>
> A real invocation is unaffected — the `vcs` wrapper sets its own
> `LD_LIBRARY_PATH` from `linux64/lib`. Use the compile probe in §8.5 instead.

### 4.5 One host library VCS links against

```bash
rpm -q numactl-libs      # must be installed; provides /usr/lib64/libnuma.so.1
ls /usr/lib64/libnuma.so.1
```

VCS's link step passes `-l /usr/lib64/libnuma.so.1` explicitly. If it is
missing you get a link error, not a compile error.

---

## 5. RISC-V cross toolchain

### 5.1 What you need

| Item | Value |
| ---- | ----- |
| Triple | `riscv64-unknown-elf` |
| GCC | **16.1.0** |
| Binutils | **2.47.20260726** |
| Install prefix | `/opt/riscv` |
| Source | `https://github.com/riscv/riscv-gnu-toolchain` |
| Pin | tag **`2026.08.27`**, commit **`d118e53`**, branch `master` |
| How obtained | `git clone` + local build (**not** a package, **not** a prebuilt tarball) |

> The version string printed by the baseline compiler has an **empty**
> parenthetical — `riscv64-unknown-elf-gcc () 16.1.0` — because it came from a
> git checkout, not a release tarball. A prebuilt 16.1.0 will print `(GCC)`.
> Both are the same compiler; don't be alarmed by the difference.

### 5.2 Fast path — copy the built tree (recommended)

```bash
sudo tar -C /opt -xzf ~/pc-migration/riscv-opt.tar.gz
sudo chown -R root:root /opt/riscv
/opt/riscv/bin/riscv64-unknown-elf-gcc --version    # expect 16.1.0
```

Skip to §5.4. Takes 2 minutes instead of 90.

### 5.3 Slow path — rebuild from source

Only if you do not have the tarball. **Requires network + ~17 GB scratch.**

```bash
cd /home/student
git clone https://github.com/riscv/riscv-gnu-toolchain
cd riscv-gnu-toolchain
git checkout 2026.08.27                  # d118e53
```

`./configure` is **mandatory** — a fresh clone ships only `Makefile.in`, no
`Makefile`, so a bare `make` dies with:

```text
make: *** No targets specified and no makefile found.  Stop.
```

```bash
# meson/ninja need to trust the git-owned tree
git config --global --add safe.directory /home/student/riscv-gnu-toolchain

./configure --prefix=/opt/riscv
sudo make -j$(nproc) install
```

If you built as `student` and want `/opt/riscv` owned by root afterwards:

```bash
sudo chown -R root:root /opt/riscv
rm -rf /home/student/riscv-gnu-toolchain      # reclaim 17 GB
```

### 5.4 Put it on PATH

```bash
echo 'export PATH=/opt/riscv/bin:$PATH' | sudo tee /etc/profile.d/riscv.sh
```

New shells pick it up automatically. For the current shell:

```bash
export PATH=/opt/riscv/bin:$PATH
```

There is **no** `RISCV`, `RISCV_CC`, `RISCV_PREFIX` or `CROSS_COMPILE`
environment variable in this project. `sw/Makefile:23` uses a Make variable:

```make
CROSS_COMPILE ?= riscv64-unknown-elf-
```

So a bare `riscv64-unknown-elf-gcc` on `PATH` is the whole contract.

### 5.5 Validate

```bash
riscv64-unknown-elf-gcc   --version   # riscv64-unknown-elf-gcc () 16.1.0
riscv64-unknown-elf-objdump --version # GNU objdump (GNU Binutils) 2.47.20260726
riscv64-unknown-elf-as    --version   # GNU assembler (GNU Binutils) 2.47.20260726
which riscv64-unknown-elf-gcc         # must be /opt/riscv/bin/...
```

### 5.6 ⚠ The `/opt/riscv` toolchain has NO RV32 multilib

This trips people up and it is expected, not a broken install:

```console
$ ls /opt/riscv/riscv64-unknown-elf/lib/rv32imc_zicsr_zifencei/ilp32/
ls: cannot access '...': No such file or directory
$ readelf -h /opt/riscv/lib/gcc/riscv64-unknown-elf/16.1.0/libgcc.a | grep Class
  Class: ELF64
```

The project targets `-march=rv32imc_zicsr_zifencei -mabi=ilp32` on an
ELF64-only toolchain. It works **only** because `sw/Makefile` passes
`-nostdlib` and **never** `-lgcc`.

> **Rule: never add `-lgcc`.** The first 64-bit helper (`__udivdi3`) or a
> `memcpy` will abort with
> `libgcc.a(div.o): file class ELFCLASS64 incompatible with ELFCLASS32`.
> Use the freestanding implementations already in `sw/src/lib.c`.
> (Amendment A1, `sw/Makefile:11-20`, `doc/Fw0_C_Toolchain_Build_and_Gate_Record.md:215`.)

There was an **older** GCC 12.2.0 toolchain at `/root/tools/riscv-gnu/2023.04.29`
which *did* have a real RV32 multilib and a working `libgcc.a`. It was kept on
the baseline box but is **not** part of this flow and did not survive the
migration. Do not go looking for it.

### 5.7 Optional: older toolchain

Not required. If you want a second cross compiler with proper RV32 multilib
support for experiments, install to a *separate* prefix and never put it ahead
of `/opt/riscv` on `PATH`.

---

## 6. Clone the repo and the submodule

```bash
cd /home/student/Documents
git clone https://github.com/Abdul99Aleem/Network_Telemetry_SoC.git honours_project
cd honours_project
git checkout feature/sw-build-ahb-rw
git submodule update --init core/Cores-VeeR-EL2
git submodule status
```

**Verify the pin.** The leading space means "matches the recorded commit":

```text
 06ad26aa8951d0f91068d19d106ed97f8f8ed257 core/Cores-VeeR-EL2 (2.0-350-g06ad26a)
```

If you get a `+` prefix, the submodule is on a different commit — do **not**
proceed; the RTL snapshot output is commit-dependent:

```bash
git -C core/Cores-VeeR-EL2 checkout 06ad26aa8951d0f91068d19d106ed97f8f8ed257
```

`core/Cores-VeeR-EL2` is a **locked submodule — never edit it.** Wrap, don't
fork (`README.md:648`).

Only one submodule is declared:

```bash
git config -f .gitmodules --get-regexp path    # -> core/Cores-VeeR-EL2
```

---

## 7. Hard-coded paths

### 7.1 Same path (the expected case) — you are done

Measured 2026-09-26, about a dozen tracked files embed
`/home/student/Documents/honours_project`, `/tmp/opencode/...` and
`~/snps_tools_target/...`. **With the same username and the same repo path,
none of them need editing.** You only need to recreate the `/tmp` scratch dirs
that the older `run/*.csh` Phase-1/2/3 flows use:

```bash
mkdir -p /tmp/opencode/veer_p1 /tmp/opencode/veer_p2 /tmp/opencode/uart_e2e
```

> On the baseline box those dirs were **root-owned and unwritable** by
> `student`, which is why decision **D6** moved the VeeR snapshot into the repo
> at `build/snapshots/p2_soc` and made `sim/filelist.f` read `$FW_SNAP` from the
> environment. On a fresh box you own `/tmp`, so the older absolute-path flows
> work again. **The `make` flow (§8) is the supported entry point either way** —
> it uses the project-local snapshot and does not care about `/tmp` ownership.

If `make` complains about the snapshot dir, you almost certainly skipped §8.1.

### 7.2 If the path or username changes

Rewriting the filelists is error-prone. Cheaper options, in order:

1. **Symlink the old path to the new one** (zero edits):
   ```bash
   sudo mkdir -p /home/student/Documents
   sudo ln -s /new/path/to/repo /home/student/Documents/honours_project
   ```
2. **`git config --global` insteadOf** to redirect the remote — does *not* fix
   the filelists, only the clone.
3. **Edit the files.** This is the full list of what names absolute paths:

| File | What to change |
| ---- | -------------- |
| `sim/Makefile:30-31` | `VCS_HOME`, `VERDI_HOME` |
| `run/p1_full_flow.csh`, `p1_hello_world_ahb.csh`, `p1_open_verdi.csh` | `RV_ROOT`, `WORK=/tmp/opencode/veer_p1` |
| `run/p2_full_flow.csh`, `p2_open_verdi.csh` | `PROJ`, `RV_ROOT`, `WORK=/tmp/opencode/veer_p2`, `VCS_HOME`, `VERDI_HOME`, license |
| `run/p3_uart_flow.csh` | `PROJ`, `RV_ROOT`, `WORK=/tmp/opencode/uart_e2e`, `VCS_HOME`, `VERDI_HOME`, license |
| `run/p2_fabric_run.f` | **every** entry is an absolute `/home/student/Documents/honours_project/...` |
| `run/p2_veer_soc_run.f` | absolute repo paths + `/tmp/opencode/veer_p2/snapshots/p2_soc/...` |
| `run/p3_uart_soc_run.f` | absolute repo paths + `/tmp/opencode/uart_e2e/snapshots/uart_soc/...` |
| `run/uart_rtl.f` | **all** entries absolute (note: `README.md:444` claims `run/uart_*.f` are relative — that is only true of `uart_axi_run.f`, `uart_axi_interconnect_run.f`, `uart_axi_2master_run.f`) |
| `run/fw_wave.rc`, `p1_wave.rc`, `p2_wave.rc`, `p2_veer_wave.rc` | FSDB paths for Verdi |
| `run/uart_wave.rc`, `uart_2master_wave.rc`, `uart_axi_slave_wave.rc` | FSDB paths |
| `run/axi_wave.rc:29` | already stale/dead on the baseline — `/home/student/Desktop/Honours-34/...` |

Find them all with:

```bash
grep -rn '/home/student\|/tmp/opencode' --include='*.csh' --include='*.f' \
     --include='*.rc' --include='Makefile' sim/ run/ | grep -v '^run/csrc/'
```

**Clean, no absolute paths** — these relocate for free: `tb/*.sv`, `rtl/**`,
`sw/src/*`, `sw/linker/veer.ld`, `sw/include/soc.h`, root `Makefile`,
`sim/filelist.f`, `scripts/*.py`, `run/uart_full_flow.csh` (it uses
``cd `dirname $0` ``).

Delete these before migrating — they are git-ignored generated junk carrying
stale absolute paths:

```bash
make clean                     # removes sw/build, build/sim, build/snapshots
rm -rf run/csrc run/bld_uart_axi run/simv.daidir run/elabcomLog run/verdiLog
rm -f  run/novas.rc run/novas.conf run/ucli.key run/vc_hdrs.h run/verdi_config_file
```

### 7.3 Generated artifacts with stale paths — do not migrate

`run/csrc/Makefile`, `run/bld_uart_axi/Makefile`,
`build/sim/fw0/csrc/Makefile`, `run/novas.rc`, `run/elabcomLog/novas.rc`,
`run/verdiLog/novas.rc` — all embed the old absolute paths. `make clean` plus
the `rm -rf` above removes every one.

### 7.4 If you want to slim the copy

`~/snps_tools_target` is 87 GB total but this project only needs 61 GB:

```text
vcs/          28 GB   <- needed
verdi/        26 GB   <- needed
verdi_supp/  7.3 GB   <- needed (Verdi support libs)
sentaurus/             <- NOT needed by this project
syn/                   <- NOT needed (Design Compiler, unused)
finesim/               <- referenced by cshrc but never installed
prime/                 <- referenced by cshrc but never installed
```

---

## 8. Prove it works — the full gate sequence

Run from the repo root. This is the **only** entry point you need.

```bash
cd /home/student/Documents/honours_project
make
```

`make` = `firmware mem veer-config rtl sim` (root `Makefile:22`).

### 8.1 Stage by stage, if you want to see where it breaks

```bash
make firmware      # -> sw/build/firmware.elf        (SW gates G1-G7, G11)
make inspect       # ELF gates G1-G7, G11 re-run with detail
make mem           # -> imem.mem + dmem.mem + firmware.ihex  (G8-G10, G12)
make dis           # -> sw/build/firmware.dis
make veer-config   # -> build/snapshots/p2_soc        (decision D6, project-local)
make rtl           # VCS compile -> build/sim/fw0/simv
make sim           # run + gate on BOTH tokens
make wave          # print the verdi command without launching it
```

### 8.2 The VeeR snapshot

```make
# sim/Makefile:67-69
env BUILD_PATH=$(SNAP) RV_ROOT=$(RV_ROOT) \
    $(RV_ROOT)/configs/veer.config -target=default_ahb -snapshot=p2_soc \
    -set=reset_vec=0x00000000
```

Output lands in `build/snapshots/p2_soc` — `el2_param.vh`, `el2_pdef.vh`,
`common_defines.vh`, `defines.h`, `link.ld`. There are **no checked-in
`el2_param.vh` files** in the repo; this Perl step is the only generator, and
`sim/Makefile:71` hard-gates on `el2_param.vh` existing.

Log: `build/veer_config.log`.

### 8.3 Expected success output

```text
[ROOT] fw0 flow complete — both tokens gated in 'make sim'
[SIM] PASS snapshot: ...
[SIM] PASS compile
[SIM] PASS  P2_TB2_RESULT: PASS   (spec §22 fw0 — pre-existing monitor, unmodified)
[SIM] PASS  AHB_RW_MONITOR: PASS   (plan §5.2 — read/write proof)
[SIM] PASS  no *.ihex in build/sim/fw0
[SIM] FSDB  build/sim/fw0/p2_veer_soc.fsdb
[SIM] DONE
```

If you see both `PASS` lines, the toolchain, the license, the submodule and
the snapshot all work. That is your green light.

Artifacts:

| File | What |
| ---- | ---- |
| `build/sim/fw0/simv` | the elaborated simulator |
| `build/sim/fw0/sim.log` | run log, holds the two gate tokens |
| `build/sim/fw0/compile.log` | VCS compile log, holds the version banner |
| `build/sim/fw0/p2_veer_soc.fsdb` | waveform for Verdi |
| `build/sim/fw0/simv.daidir/` | debug database for Verdi |
| `sw/build/firmware.elf` | firmware |
| `sw/build/imem.mem`, `dmem.mem`, `firmware.ihex` | memory images |
| `build/snapshots/p2_soc/` | generated VeeR snapshot |

### 8.4 Cross-check the recorded baseline

```bash
grep -m1 'Version' build/sim/fw0/compile.log
# expect: Version U-2023.03_Full64
grep -m1 'Runtime version' build/sim/fw0/sim.log
# expect: Runtime version U-2023.03_Full64
```

If the version differs from `U-2023.03_Full64`, the results are not comparable
to the recorded records — fix §3 before trusting any gate.

### 8.5 30-second toolchain probe (before the long build)

Run this first. It isolates VCS + license from the repo entirely, so if it
fails you know the problem is §3/§4 and not your clone.

```csh
csh
source ~/cshrc
mkdir -p /tmp/vcsprobe && cd /tmp/vcsprobe
echo 'module t; initial $display("PROBE_OK"); endmodule' > t.sv
vcs -full64 -sverilog t.sv -o probe
./probe
```

Expected — version banner, then the run prints `PROBE_OK` and a VCS
simulation report, exit 0:

```text
  V C S   S i m u l a t i o n   R e p o r t
PROBE_OK
```

If `vcs` dies at the licence step here, nothing in the repo will work either.
`cd /tmp && rm -rf vcsprobe` afterwards.

---

## 9. Verdi (waveform GUI)

### 9.1 DISPLAY

```bash
echo $DISPLAY              # expect :0 — the PHYSICAL display
ls /tmp/.X11-unix/X0       # socket must exist
```

**Never force `:42`** on a headless box — that is a recorded failure mode
(`doc/Firmware_Build_and_AHB_RW_Verification_Record.md:48`).

### 9.2 Launch

```csh
csh
source ~/cshrc
cd /home/student/Documents/honours_project/build/sim/fw0
verdi -ssf p2_veer_soc.fsdb -dbdir simv.daidir -sswr ../../../run/fw_wave.rc &
```

Or from the repo root, without launching anything:

```bash
make wave     # prints the exact verdi command
```

### 9.3 Known blocker N8 — the license dialog

Verdi can pop a modal:

```text
*WARN* Verdi-Elite (Verdi) license is not available. Try to check out Verdi-Apex (Verdi-Ultra) license.
```

On the baseline box this was dismissed with a small out-of-repo ctypes/X11
helper at **`/tmp/opencode/dismiss.py`** — **ephemeral, it will not survive the
PC changeover.** Rebuild it if you hit this.

Requirements: `xdotool`, `wmctrl`, `pyautogui` and `python3-xlib` are **all
absent** on the baseline box, and it needed `libX11.so.6` + `libXtst.so.6`
directly via ctypes. Also note the baseline Python is **3.6**, so
`subprocess.run(..., capture_output=True)` is not available.

**To kill a stuck Verdi — use `pkill -x verdi`.** Do **not** run
`pkill -f VERDI_HOME`; that pattern matches your own shell and kills it
(`doc/Firmware_Build_and_AHB_RW_Verification_Record.md:661-662`).

---

## 10. Re-run the committed regressions

Do this before declaring the new PC good. Each flow needs `csh` and
`source ~/cshrc`, and runs from `run/`.

```csh
cd /home/student/Documents/honours_project/run
source ~/cshrc
```

### 10.1 Phase 1 — VeeR bring-up

```csh
./p1_full_flow.csh      # veer.config -> vcs build -> program.hex -> simv
./p1_open_verdi.csh     # Verdi: dump.fsdb + p1_wave.rc signal groups
```

Expected, reproduced 2026-09-26:

```text
[117000 ns] -------------------------
[455000 ns] Hello World from VeeR EL2
[1142000 ns] TEST_PASSED
Finished : minstret = 330, mcycle = 1134
```

> **Gotcha that WILL bite you.** VeeR's `program.hex` rule builds with GCC
> **if `riscv64-unknown-elf-gcc` is on `PATH`**. It then needs the
> `third_party/picolibc` submodule, which is empty, and fails with
> `ERROR: Neither directory contains a build file meson.build`.
>
> Either initialise picolibc (needs network + meson/ninja, both installed by §1.2):
> ```bash
> git -C core/Cores-VeeR-EL2 submodule update --init third_party/picolibc
> ```
> …or hide the cross compiler so VeeR falls back to its canned hex. This is how
> the Phase-1 PASS was originally produced:
> ```csh
> setenv PATH `echo $PATH | tr ":" "\n" | grep -v riscv | paste -sd:`
> ./p1_full_flow.csh
> ```

> `default_ahb` has **no AXI**. Inspect `ic_` / `lsu_` / `mux_` AHB signals, not
> AXI.

### 10.2 Phase 2 — AHB fabric

```csh
./p2_full_flow.csh
./p2_open_verdi.csh
```

### 10.3 Phase 3 — UART end-to-end

```csh
./p3_uart_flow.csh
```

### 10.4 Reset the environment afterwards

```csh
setenv PATH `echo $PATH | tr ":" "\n" | grep -v '^/opt/riscv/bin$' | paste -sd:`
```

---

## 11. Troubleshooting

| Symptom | Cause | Fix |
| ------- | ----- | --- |
| `Cannot find 'vcsMsgReport' script in /bin` | `VCS_HOME` not exported, only on PATH | §4.3 |
| `No such file or directory` on `vcs` | tree not restored / wrong prefix | §3.1, check `VCS_HOME` |
| VCS hangs silently, then exits | license checkout failed | check `SNPSLMD_LICENSE_FILE`, run the §8.5 probe |
| `command not found: riscv64-unknown-elf-gcc` | `/etc/profile.d/riscv.sh` missing, or toolchain not built | §5.2–5.4 |
| `libgcc.a(div.o): file class ELFCLASS64 incompatible with ELFCLASS32` | `-lgcc` crept into `LDFLAGS` | §5.6 — remove it, keep `-nostdlib` |
| `[SIM] FAIL: el2_param.vh not generated` | submodule not initialised, or wrong commit | §6 — verify pin `06ad26a` |
| `[SIM] FAIL: sw/build/imem.mem missing` | skipped `make mem` | `make mem` |
| `ERROR: Neither directory contains a build file meson.build` | VeeR `program.hex` rule picked up the cross compiler; picolibc empty | §10.1 |
| `00000000\r` breaking `$readmemh` | CRLF from `objcopy -O verilog` | already handled by `sw/Makefile:49` `sed -i 's/\r$//'` — do not remove |
| `Permission denied` writing `/tmp/opencode/veer_p2` | dir root-owned from a previous session | `sudo chown -R student:student /tmp/opencode` |
| Gate token missing from `sim.log` | run failed earlier in the flow | `grep -n 'AHB_CYCLES\|P2_TB2_RESULT' build/sim/fw0/sim.log` |
| Verdi `*WARN*` license modal | N8 | §9.3; kill with `pkill -x verdi` |
| Shell dies when killing Verdi | used `pkill -f VERDI_HOME` | use `pkill -x verdi` |

---

## 12. Final acceptance checklist

Tick all of these. Anything unticked means the PC is not ready.

- [ ] `cat /etc/redhat-release` → Rocky Linux 8.x
- [ ] `csh -c 'echo ok'` works
- [ ] `which vcs verdi` both resolve, `VCS_HOME`/`VERDI_HOME` exported
- [ ] `rpm -q numactl-libs` installed
- [ ] §8.5 probe compiles and prints `PROBE_OK`, exit 0
- [ ] `echo $SNPSLMD_LICENSE_FILE` → `27021@14.139.1.126`
- [ ] `riscv64-unknown-elf-gcc --version` → **16.1.0**
- [ ] `riscv64-unknown-elf-objdump --version` → **2.47.20260726**
- [ ] `git submodule status` → ` 06ad26aa...` with a **leading space**
- [ ] `make firmware` → ELF, gates G1–G7 + G11 pass
- [ ] `make mem` → `imem.mem`, `dmem.mem`, `firmware.ihex`, gates G8–G10 + G12
- [ ] `make veer-config` → `build/snapshots/p2_soc/el2_param.vh` exists
- [ ] `make rtl` → `build/sim/fw0/simv`
- [ ] `make sim` → **both** `P2_TB2_RESULT: PASS` and `AHB_RW_MONITOR: PASS`
- [ ] `grep 'Version' build/sim/fw0/compile.log` → `U-2023.03_Full64`
- [ ] `echo $DISPLAY` → `:0`, `/tmp/.X11-unix/X0` exists
- [ ] Verdi opens `build/sim/fw0/p2_veer_soc.fsdb` with `run/fw_wave.rc`
- [ ] `./p1_full_flow.csh` → `TEST_PASSED`
- [ ] `./p2_full_flow.csh` → exit 0
- [ ] `./p3_uart_flow.csh` → exit 0

Once this list is fully ticked, update `README.md` §8 with the new machine's
hostname and date, and delete the "measured on 2026-09-26" caveat in §10.

---

## 13. Out of scope

- **FPGA / synthesis / bitstream.** Explicitly last, and not started
  (`README.md:16,216,314`). No Vivado or Quartus anywhere in the repo.
- **Design Compiler / PrimeTime / FinSim / Sentaurus.** Installed or referenced
  in `~/cshrc`, entirely unused by this project's flow. Copy them only if you
  want them for other work (§7.4).
- **The old GCC 12.2.0 toolchain** at `/root/tools/riscv-gnu/2023.04.29`. Kept
  on the baseline box, unused, and not part of this flow (§5.6).
- **Migrating FSDBs, `build/`, `sw/build/`, `/tmp/opencode/*`.** All
  regenerable with `make`.

---

## 14. Source records

Everything above was extracted from these; check them if a version or a path
here disagrees with reality.

| Record | Covers |
| ------ | ------ |
| `doc/RISC_V_GNU_Toolchain_Setup_and_Validation_Record.md` | toolchain clone, build, versions, validation, PATH |
| `doc/Fw0_C_Toolchain_Build_and_Gate_Record.md` | GCC version string, frozen flags, G1–G13, the two `objcopy` defects |
| `doc/Firmware_Build_and_AHB_RW_Verification_Record.md` | VCS/Verdi versions, license, `VCS_HOME` export rationale, N8 |
| `doc/Firmware_Build_and_AHB_RW_Verification_Plan.md` | findings N4/N8, snapshot/D6 rationale |
| `doc/RISC_V_SW_Build_and_Simulation_Image_Architecture_Specification.md` | rev 1.5, steps S1–S11, levels L1–L4, toolchain table |
| `doc/Phase1_VeeR_Bringup_Completion_Record.md` | submodule pin, Phase-1 PASS transcript |
| `doc/Phase2_AHB_Fabric_Completion_Record.md` | Phase-2 gates |
| `doc/Phase3_UART_End_To_End_Completion_Record.md` | Phase-3 gates, simulation-only statement |
| `README.md` §8, §10, §11 | fresh-clone steps, hard-coded paths, regressions |