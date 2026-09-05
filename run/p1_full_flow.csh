#!/bin/csh -f
# ============================================================================
# P1 FULL FLOW — VeeR EL2 default_ahb hello_world: config -> build -> run.
# Place: honours_project/run/p1_full_flow.csh
#
# Run it (needs Synopsys env first):
#   csh
#   source /home/student/cshrc
#   ./p1_full_flow.csh [workdir]     # default workdir: /tmp/opencode/veer_p1
#
# Result: TEST_PASSED + dump.fsdb in workdir. Waveforms opened separately
# (step 4) since Verdi needs your DISPLAY terminal.
# ============================================================================

setenv RV_ROOT /home/student/Documents/honours_project/core/Cores-VeeR-EL2
if ($#argv >= 1) then
    set WORK = $1
else
    set WORK = /tmp/opencode/veer_p1
endif

echo "=== P1 FULL FLOW  WORK=$WORK ==="
mkdir -p $WORK
cd $WORK
if ($status != 0) exit 1

echo "--- [1/4] veer.config -target=default_ahb ---"
env BUILD_PATH=$WORK/snapshots/default_ahb RV_ROOT=$RV_ROOT \
  $RV_ROOT/configs/veer.config -target=default_ahb -snapshot=default_ahb
if ($status != 0) exit 1

echo "--- [2/4] vcs-build debug=1 (FSDB on) ---"
make -f $RV_ROOT/tools/Makefile target=default_ahb snapshot=default_ahb \
  TEST=hello_world vcs-build debug=1
if ($status != 0) exit 1

echo "--- [3/4] program.hex (canned, no GCC on host) + simv ---"
make -f $RV_ROOT/tools/Makefile target=default_ahb snapshot=default_ahb \
  TEST=hello_world program.hex
if ($status != 0) exit 1
./simv +dumpon +vcs+lic+wait -a vcs_run.log
echo "--- console.log ---"
cat console.log
ls -la $WORK/dump.fsdb

echo ""
echo "=== DONE. Now open waveforms (needs DISPLAY, e.g. :42) ==="
echo "  cd $WORK"
echo "  setenv DISPLAY :42"
echo "  verdi -ssf dump.fsdb -dbdir simv.daidir -play /home/student/Documents/honours_project/run/p1_verdi_ahb.tcl &"
echo "Then in Verdi console:  source /home/student/Documents/honours_project/run/p1_verdi_ahb.tcl"
