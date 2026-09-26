# RISC-V GNU Toolchain Installation and Validation Record

**Project context:** RISC-V Network Telemetry SoC  
**Purpose:** Detailed record of the RISC-V cross-toolchain setup, troubleshooting, verification, and lessons learned.  
**Environment observed during this session:** Rocky Linux 8.x, x86_64 host, shell prompt shown as `root@vlsi45`.  
**Date of this work:** 2026-09-26

---

## 1. Why This Work Was Done

The project ultimately requires a RISC-V bare-metal software flow that can produce machine-code images suitable for execution by the RISC-V processor in RTL simulation.

The immediate task provided by the professor was to:

1. Install the required Linux packages.
2. Obtain the `riscv-gnu-toolchain` source.
3. Build/install the RISC-V GNU toolchain under `/opt/riscv`.
4. Put the toolchain in `PATH`.
5. Compile a simple C program into a RISC-V ELF executable.
6. Convert the ELF into Intel HEX.

This was treated as a toolchain bring-up and sanity-validation exercise before moving toward VeeR EL2-specific firmware and SoC simulation.

---

# 2. Important Project Context

The larger project uses a RISC-V processor and a bare-metal software flow. The generic compiler test is therefore only the first layer of verification.

The conceptual flow is:

```text
C source
   |
   v
RISC-V cross compiler
   |
   v
ELF executable
   |
   v
HEX / memory image
   |
   v
Processor RTL / SoC simulation
```

A successful generic compiler test does **not** by itself prove that the resulting image matches the final VeeR EL2 memory map, reset address, linker script, or RTL memory-loading mechanism.

Those VeeR/SoC-specific checks are a later stage.

---

# 3. Earlier Toolchain State Before This Session

Before following the professor's newer procedure, another RISC-V GNU toolchain had already been installed and validated under:

```text
/root/tools/riscv-gnu/2023.04.29
```

That earlier toolchain was specifically checked for:

- GCC 12.2.0
- RV32IMC/ILP32 compilation
- Newlib headers
- `stdint.h`
- `libgcc.a`
- RV32 multilib support

The earlier validation reported:

```text
READY: RISC-V RV32IMC/ILP32 TOOLCHAIN OK
```

The important `libgcc.a` path from that installation was:

```text
/root/tools/riscv-gnu/2023.04.29/lib/gcc/riscv64-unknown-elf/12.2.0/rv32imc/ilp32/libgcc.a
```

That older installation was not deleted.

---

# 4. Professor's New Procedure

The professor subsequently supplied a different procedure.

The essential sequence was:

```bash
cd /home/student
git clone https://github.com/riscv/riscv-gnu-toolchain
```

As root, install:

```bash
dnf install -y dnf-plugins-core
dnf config-manager --set-enabled powertools
dnf clean all
dnf makecache
dnf install -y texinfo meson ninja-build
```

Verify:

```bash
makeinfo --version
meson --version
ninja --version
```

Then:

```bash
cd /home/student/riscv-gnu-toolchain
git config --global --add safe.directory /home/student/riscv-gnu-toolchain
git config --global --get-all safe.directory
```

The expected safe-directory entry was:

```text
/home/student/riscv-gnu-toolchain
```

The professor then instructed:

```bash
make -j$(nproc)
```

and expected the installed compiler at:

```text
/opt/riscv/bin/riscv64-unknown-elf-gcc
```

The environment was then to be configured with:

```bash
echo 'export PATH=/opt/riscv/bin:$PATH' > /etc/profile.d/riscv.sh
source /etc/profile.d/riscv.sh
```

Finally, the professor requested a simple C compilation:

```bash
riscv64-unknown-elf-gcc -O0 -o hello.elf hello.c
```

followed by:

```bash
riscv64-unknown-elf-objcopy -O ihex hello.elf hello.hex
```

---

# 5. Host Package Installation

The required packages were installed successfully.

The final package installation output included:

```text
meson-0.58.2-2.el8.noarch
ninja-build-1.8.2-1.el8.x86_64
perl-Unicode-EastAsianWidth-1.33-13.el8.noarch
platform-python-devel-3.6.8-62.el8_10.rocky.0.x86_64
python3-rpm-generators-5-8.el8.noarch
python36-devel-3.6.8-39.module+el8.10.0+1910+234ad790.x86_64
texinfo-6.5-7.el8.x86_64
```

The package manager ended with:

```text
Complete!
```

Therefore the requested host-side package installation succeeded.

---

# 6. Initial `make` Failure

After entering:

```bash
cd /home/student/riscv-gnu-toolchain
```

the first attempt was:

```bash
make -j$(nproc)
```

It failed with:

```text
make: *** No targets specified and no makefile found.  Stop.
```

At first glance this suggested a bad clone, so the repository was inspected.

---

# 7. Repository Inspection

The directory was:

```text
/home/student/riscv-gnu-toolchain
```

The directory contained:

```text
binutils/
configure
configure.ac
contrib/
dejagnu/
gcc/
gdb/
glibc/
linux-headers/
llvm/
Makefile.in
musl/
newlib/
picolibc/
pk/
qemu/
README.md
scripts/
spike/
test/
uclibc-ng/
.git/
.gitmodules
```

The repository was therefore not empty or corrupted.

`git status` reported:

```text
On branch master
Your branch is up to date with 'origin/master'.
nothing to commit, working tree clean
```

The remote was:

```text
origin  https://github.com/riscv/riscv-gnu-toolchain
```

The latest commit was:

```text
d118e53 (HEAD -> master, tag: 2026.08.27, origin/master, origin/HEAD)
ci: Derive Flang compile job limit from runner CPU count
```

This established an important fact:

> The new checkout was a current upstream checkout tagged `2026.08.27`, not the earlier pinned `2023.04.29` toolchain.

---

# 8. Why the First `make` Failed

The repository contained:

```text
Makefile.in
```

but not:

```text
Makefile
```

The actual build Makefile had not yet been generated for the host configuration.

Therefore, the correct next step was to configure the source tree.

The command used was:

```bash
./configure --prefix=/opt/riscv
```

This generated the build configuration and established:

```text
/opt/riscv
```

as the installation prefix.

After configuration, the full build could proceed.

---

# 9. Full Toolchain Build

The toolchain was built using:

```bash
make -j$(nproc)
```

The build produced a large amount of output and compiled numerous components, including GDB.

During the build, warnings were observed such as:

```text
warning: ... may be used uninitialized
```

These were compiler warnings, not fatal build errors.

The build continued through many compilation stages.

A particularly important final stage was:

```text
build-gcc-newlib-stage2
```

The successful completion included:

```text
make[3]: Leaving directory '/home/student/riscv-gnu-toolchain/build-gcc-newlib-stage2/gcc'
make[2]: Leaving directory '/home/student/riscv-gnu-toolchain/build-gcc-newlib-stage2'
make[1]: Leaving directory '/home/student/riscv-gnu-toolchain/build-gcc-newlib-stage2'
mkdir -p stamps/ && touch stamps/build-gcc-newlib-stage2
```

The shell prompt returned:

```text
[root@vlsi45 riscv-gnu-toolchain]#
```

This established that the build completed successfully.

---

# 10. Installed GCC Verification

The compiler was verified with:

```bash
ls -l /opt/riscv/bin/riscv64-unknown-elf-gcc
```

Result:

```text
-rwxr-xr-x. 2 root root 45337432 Sep 26 10:50 /opt/riscv/bin/riscv64-unknown-elf-gcc
```

The compiler version was:

```text
riscv64-unknown-elf-gcc () 16.1.0
Copyright (C) 2026 Free Software Foundation, Inc.
```

Therefore the newly built toolchain contains:

```text
GCC 16.1.0
```

This differs from the previously installed/pinned toolchain, which was:

```text
GCC 12.2.0
```

---

# 11. Binutils Verification

The object dump utility was verified:

```bash
/opt/riscv/bin/riscv64-unknown-elf-objdump --version
```

Result:

```text
GNU objdump (GNU Binutils) 2.47.20260726
```

The assembler was verified:

```bash
/opt/riscv/bin/riscv64-unknown-elf-as --version
```

Result:

```text
GNU assembler (GNU Binutils) 2.47.20260726
```

The assembler reported:

```text
This assembler was configured for a target of `riscv64-unknown-elf'.
```

Therefore the newly built toolchain includes:

```text
GCC       16.1.0
Binutils  2.47.20260726
Target    riscv64-unknown-elf
```

---

# 12. PATH Configuration

The professor's requested system-wide PATH configuration was applied:

```bash
echo 'export PATH=/opt/riscv/bin:$PATH' > /etc/profile.d/riscv.sh
source /etc/profile.d/riscv.sh
```

Then:

```bash
which riscv64-unknown-elf-gcc
```

returned:

```text
/opt/riscv/bin/riscv64-unknown-elf-gcc
```

A subsequent:

```bash
riscv64-unknown-elf-gcc --version
```

reported:

```text
riscv64-unknown-elf-gcc () 16.1.0
```

Therefore the shell resolves the compiler from the newly installed `/opt/riscv` toolchain.

---

# 13. The `hello.c` Test

The professor requested a simple C program.

The intended source was:

```c
#include <stdio.h>

int main(void)
{
    printf("Hello, RISC-V!\n");
    return 0;
}
```

Initially the file was accidentally created as:

```text
main.c
```

while the requested compiler command referred to:

```text
hello.c
```

The command:

```bash
riscv64-unknown-elf-gcc -O0 -o hello.elf hello.c
```

therefore produced:

```text
cc1: fatal error: hello.c: No such file or directory
compilation terminated.
```

The source itself was inspected with:

```bash
cat main.c
```

and was correct.

The problem was only the filename.

The file was renamed:

```bash
mv main.c hello.c
```

---

# 14. Successful C → ELF Compilation

After renaming, the exact professor-requested compilation command was run:

```bash
riscv64-unknown-elf-gcc -O0 -o hello.elf hello.c
```

This time there was no compiler or linker error.

The resulting file was:

```text
-rwxr-xr-x. 1 root root 23K Sep 26 11:55 hello.elf
```

Therefore:

```text
hello.c → hello.elf
```

was successfully demonstrated.

---

# 15. Successful ELF → Intel HEX Conversion

The command:

```bash
riscv64-unknown-elf-objcopy -O ihex hello.elf hello.hex
```

completed successfully.

The final files were:

```text
hello.elf  → 23 KB
hello.hex  → 37 KB
```

The final verification was:

```bash
ls -lh hello.elf hello.hex
```

with:

```text
-rwxr-xr-x. 1 root root 23K Sep 26 11:55 hello.elf
-rw-r--r--. 1 root root 37K Sep 26 11:55 hello.hex
```

This proves the complete generic toolchain flow:

```text
hello.c
   |
   | riscv64-unknown-elf-gcc -O0
   v
hello.elf
   |
   | riscv64-unknown-elf-objcopy -O ihex
   v
hello.hex
```

---

# 16. What Has Been Proven

The following has been successfully demonstrated.

## Host environment

- RISC-V toolchain source successfully cloned.
- Git repository is valid.
- Git `safe.directory` was configured.
- Required host packages were installed.
- `texinfo`, `meson`, and `ninja-build` were installed.
- Toolchain configured with `/opt/riscv` as installation prefix.

## Toolchain build

- GNU toolchain build completed.
- GCC/Newlib stage 2 completed.
- GCC installed under `/opt/riscv`.
- Binutils installed under `/opt/riscv`.

## Toolchain binaries

- `riscv64-unknown-elf-gcc` works.
- `riscv64-unknown-elf-objdump` works.
- `riscv64-unknown-elf-as` works.
- `/opt/riscv/bin` is in PATH.

## Software build flow

- C source was compiled successfully.
- ELF executable was generated.
- ELF was successfully converted to Intel HEX.

---

# 17. What Has NOT Yet Been Proven

This is important for interviews and future projects.

The generic `hello.c` test does **not** yet prove:

1. That the compiler generated RV32IMC code.
2. That the ABI is ILP32.
3. That the image matches the VeeR EL2 instruction-set configuration.
4. That the linker script matches the VeeR EL2 memory map.
5. That the reset vector is correct for the target RTL.
6. That the generated HEX can be loaded into the VeeR EL2 instruction memory.
7. That VeeR EL2 can execute the image in VCS.
8. That the UART/peripheral addresses match the SoC.
9. That interrupts work.
10. That the firmware can access the project's telemetry registers.
11. That the firmware can access the AES subsystem.
12. That the resulting image is suitable for the final Network Telemetry SoC.

These are the next verification layers.

---

# 18. Two Toolchains Now Exist on the Machine

There are currently two relevant installations.

## Earlier validated toolchain

```text
Location:
/root/tools/riscv-gnu/2023.04.29

GCC:
12.2.0

Validated:
RV32IMC/ILP32
Newlib
stdint.h
libgcc.a
RV32 multilib
```

## Newly built professor-requested toolchain

```text
Source:
/home/student/riscv-gnu-toolchain

Install:
/opt/riscv

GCC:
16.1.0

Binutils:
2.47.20260726

Target:
riscv64-unknown-elf

Status:
Successfully built and tested with hello.c
```

The current shell PATH points to the new installation:

```text
/opt/riscv/bin
```

Therefore:

```bash
which riscv64-unknown-elf-gcc
```

returns:

```text
/opt/riscv/bin/riscv64-unknown-elf-gcc
```

---

# 19. Important Lesson: Generic Target vs VeeR Target

The compiler executable name:

```text
riscv64-unknown-elf-gcc
```

does **not** mean every program produced by it must be RV64.

RISC-V GCC can generate different ISA/ABI combinations using options such as:

```text
-march
-mabi
```

For example, the earlier validated environment explicitly checked:

```text
-march=rv32imc_zicsr_zifencei
-mabi=ilp32
```

The current `hello.c` test deliberately followed the professor's exact generic command:

```bash
riscv64-unknown-elf-gcc -O0 -o hello.elf hello.c
```

Therefore we have not yet explicitly verified the architecture attributes of this new `hello.elf`.

That is the next technical step.

---

# 20. Planned Next Step: Inspect the ELF

The next commands should be:

```bash
cd /home/student

riscv64-unknown-elf-readelf -h hello.elf
riscv64-unknown-elf-readelf -A hello.elf
```

These should be used to inspect:

- ELF class
- machine type
- architecture attributes
- RISC-V ISA information
- ABI-related information

Then the program can be explicitly compiled for VeeR's intended ISA configuration, for example:

```bash
riscv64-unknown-elf-gcc \
    -march=rv32imc \
    -mabi=ilp32 \
    -O0 \
    -o hello_rv32imc.elf \
    hello.c
```

That image should then be inspected and converted to HEX.

**This has not yet been executed as part of this record.**

---

# 21. Troubleshooting Record

## Problem 1 — Caliptra directory was missing

A search was performed:

```bash
find /root /home -maxdepth 4 -type d \( -iname '*caliptra*' -o -iname 'Caliptra_SS_V1' \) 2>/dev/null
```

No Caliptra directory was found.

Conclusion:

- The RISC-V toolchain itself was already available.
- `Caliptra_SS_V1` was not present on the machine.
- The professor subsequently supplied a different direct RISC-V toolchain procedure, so the work proceeded with that procedure.

## Problem 2 — `make` reported no Makefile

Initial error:

```text
make: *** No targets specified and no makefile found. Stop.
```

Investigation showed:

```text
Makefile.in
```

was present but:

```text
Makefile
```

was absent.

The Git repository itself was valid.

Resolution:

```bash
./configure --prefix=/opt/riscv
```

Then the build was started again.

## Problem 3 — Build generated many warnings

GDB compilation generated warnings such as:

```text
warning: ... may be used uninitialized
```

The build continued.

Resolution:

- Do not stop a large build merely because a non-fatal warning appears.
- Check whether `make` eventually exits with an error.
- Successful stage completion and return to the shell prompt confirmed the build completed.

## Problem 4 — `hello.c` did not exist

The source had been created as:

```text
main.c
```

but the command expected:

```text
hello.c
```

Error:

```text
cc1: fatal error: hello.c: No such file or directory
```

Resolution:

```bash
mv main.c hello.c
```

The same source then compiled successfully.

---

# 22. Interview-Level Explanation

If asked:

### "What did you actually do?"

A concise technical answer is:

> I brought up a RISC-V bare-metal cross-compilation environment on Rocky Linux. I cloned the RISC-V GNU toolchain, installed the required host dependencies, configured it with `/opt/riscv` as the installation prefix, built the GCC/Newlib toolchain, verified GCC and Binutils, configured the compiler in the system PATH, and validated the complete C-to-ELF-to-HEX flow using a simple RISC-V C program.

### "Why is a cross compiler required?"

The host is an x86_64 Linux machine, while the target processor is RISC-V. The normal host GCC generates x86_64 code. A RISC-V cross compiler generates RISC-V machine code that can execute on the target processor.

### "What is ELF?"

ELF is the executable/object file format used to represent the compiled program, including sections, symbols, metadata, and machine-code contents.

### "Why convert ELF to HEX?"

RTL memories commonly need an initialization image rather than a full ELF executable. `objcopy` can extract/convert the relevant binary representation into formats such as Intel HEX.

### "What is Newlib?"

Newlib is a C library commonly used in embedded/bare-metal environments. It provides standard C library facilities and headers for cross-compiled embedded applications.

### "Why did `make` initially fail?"

The repository had `Makefile.in`, but the host-specific `Makefile` had not yet been generated. Running `./configure --prefix=/opt/riscv` generated the required build configuration.

### "What does `-O0` mean?"

It disables normal compiler optimization, making the generated code easier to inspect and debug during initial bring-up.

### "Does `riscv64-unknown-elf-gcc` necessarily generate RV64 code?"

No. The compiler executable name identifies the toolchain target family. The actual ISA/ABI can be controlled using options such as `-march` and `-mabi`.

---

# 23. Current Status

```text
============================================================
RISC-V GNU TOOLCHAIN BRING-UP STATUS
============================================================

Host packages                 PASS
Git repository                PASS
Repository configuration      PASS
Toolchain build               PASS
GCC installation              PASS
GCC 16.1.0                    PASS
Binutils 2.47                 PASS
PATH configuration            PASS
C compilation                 PASS
ELF generation                PASS
ELF -> HEX conversion         PASS

Generic RISC-V build flow     COMPLETE

RV32IMC/ILP32 verification    NEXT
VeeR EL2 firmware              NEXT
VeeR memory map                NEXT
Linker script                 NEXT
RTL HEX loading               NEXT
VCS execution                 NEXT
============================================================
```

---

# 24. Reusable Command Checklist

For future machines, the core professor-requested flow is:

```bash
# Clone
cd /home/student
git clone https://github.com/riscv/riscv-gnu-toolchain

# Host packages (root)
dnf install -y dnf-plugins-core
dnf config-manager --set-enabled powertools
dnf clean all
dnf makecache
dnf install -y texinfo meson ninja-build

# Verify host tools
makeinfo --version
meson --version
ninja --version

# Configure repository
cd /home/student/riscv-gnu-toolchain
git config --global --add safe.directory /home/student/riscv-gnu-toolchain

# Generate Makefile
./configure --prefix=/opt/riscv

# Build
make -j$(nproc)

# Verify installation
ls -l /opt/riscv/bin/riscv64-unknown-elf-gcc
/opt/riscv/bin/riscv64-unknown-elf-gcc --version
/opt/riscv/bin/riscv64-unknown-elf-objdump --version
/opt/riscv/bin/riscv64-unknown-elf-as --version

# PATH
echo 'export PATH=/opt/riscv/bin:$PATH' > /etc/profile.d/riscv.sh
source /etc/profile.d/riscv.sh
which riscv64-unknown-elf-gcc

# C test
cd /home/student
nano hello.c

# Compile
riscv64-unknown-elf-gcc -O0 -o hello.elf hello.c

# Convert
riscv64-unknown-elf-objcopy -O ihex hello.elf hello.hex

# Verify
ls -lh hello.elf hello.hex
```

---

# 25. Final Takeaway

The most important engineering distinction from this exercise is:

```text
Toolchain installed
        ≠
Target firmware validated
        ≠
RTL execution validated
```

We have completed the first layer and demonstrated the second at a **generic** level:

```text
Toolchain
    ↓
C compilation
    ↓
ELF
    ↓
HEX
```

The next work should deliberately close the remaining gaps:

```text
RV32IMC + ILP32
       ↓
VeeR EL2 ISA/configuration
       ↓
linker script + memory map
       ↓
firmware image
       ↓
HEX loading
       ↓
VCS simulation
       ↓
Verdi waveform verification
```

That distinction is useful both for the project and for explaining the work clearly in an interview.
