#!/bin/csh -f
# ============================================================================
# P1 hello_world AHB-Lite bring-up — MAGIC RUN FILE
# VeeR EL2 (default_ahb) + VCS + Verdi FSDB for hello_world
#
# Usage:
#   csh
#   source /home/student/cshrc
#   ./p1_hello_world_ahb.csh [workdir]
#
# Default workdir: /tmp/opencode/veer_p1 (preserves the Phase-1 PASS build).
# Produces: simv, program.hex, dump.fsdb, console.log, exec.log,
#           trace_port.csv, TEST_PASSED on stdout.
# Then view waveforms:
#   verdi -ssf dump.fsdb -dbdir simv.daidir -play $RV_ROOT/../../run/p1_verdi_ahb.tcl &
# ============================================================================

setenv RV_ROOT /home/student/Documents/honours_project/core/Cores-VeeR-EL2
if ($?1) then
    set WORK = $1
else
    set WORK = /tmp/opencode/veer_p1
endif

echo "=== P1 WORK=$WORK RV_ROOT=$RV_ROOT ==="
mkdir -p $WORK
cd $WORK

# 1. Generate locked AHB-Lite configuration (no-op if up to date)
echo "--- [1/4] veer.config -target=default_ahb ---"
env BUILD_PATH=$WORK/snapshots/default_ahb RV_ROOT=$RV_ROOT \
  $RV_ROOT/configs/veer.config -target=default_ahb -snapshot=default_ahb
if ($status != 0) exit 1
grep -E 'RV_BUILD_AHB_LITE|RV_RESET_VEC|RV_DCCM_SADR|RV_ICCM_SADR|RV_PIC_BASE_ADDR' \
  $WORK/snapshots/default_ahb/common_defines.vh

# 2. Build VCS model with FSDB debug (defines VCS_DEBUG -> $fsdbDumpfile)
echo "--- [2/4] vcs-build debug=1 ---"
make -f $RV_ROOT/tools/Makefile target=default_ahb snapshot=default_ahb \
  TEST=hello_world vcs-build debug=1
if ($status != 0) exit 1

# 3. program.hex (canned: no riscv64-unknown-elf-gcc on this host)
echo "--- [3/4] program.hex ---"
make -f $RV_ROOT/tools/Makefile target=default_ahb snapshot=default_ahb \
  TEST=hello_world program.hex
if ($status != 0) exit 1

# 4. Run -> dump.fsdb + TEST_PASSED
echo "--- [4/4] simv ---"
./simv +dumpon +vcs+lic+wait -a vcs_run.log
echo "--- console.log ---"
cat console.log
echo ""
echo "WAVEFORM: verdi -ssf $WORK/dump.fsdb -dbdir $WORK/simv.daidir &"
ls -la $WORK/dump.fsdb
