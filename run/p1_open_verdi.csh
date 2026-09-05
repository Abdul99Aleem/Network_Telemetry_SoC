#!/bin/csh -f
# ============================================================================
# Open Phase-1 hello_world waveforms in Verdi (THIS is the script that
# opens Verdi — run it in your terminal, not in Verdi).
#
# Usage:  ./p1_open_verdi.csh [workdir]   # default: /tmp/opencode/veer_p1
# Needs:  dump.fsdb + simv.daidir in workdir (run ./p1_full_flow.csh first),
#         Xvfb on :42 (or setenv DISPLAY yourself before running).
# ============================================================================

if ($#argv >= 1) then
    set WORK = $1
else
    set WORK = /tmp/opencode/veer_p1
endif

if (! -e $WORK/dump.fsdb) then
    echo "No $WORK/dump.fsdb — run ./p1_full_flow.csh first."
    exit 1
endif
if (! -d $WORK/simv.daidir) then
    echo "No $WORK/simv.daidir — run ./p1_full_flow.csh first."
    exit 1
endif
# Use your own screen: if DISPLAY is already set (physical console/VNC),
# keep it. Otherwise assume the physical console :0 — NOT :42 (that was a
# headless virtual screen with no viewer).
if ($?DISPLAY == 0) then
    setenv DISPLAY :0
    echo "DISPLAY was unset — trying physical console :0."
endif

cd $WORK
verdi -ssf dump.fsdb -dbdir simv.daidir \
  -sswr /home/student/Documents/honours_project/run/p1_wave.rc &
echo "Verdi launching on DISPLAY=$DISPLAY — wave RC p1_wave.rc loads automatically."
echo ""
echo "Fallback (TCL signal script, same signals):"
echo "  verdi -ssf dump.fsdb -dbdir simv.daidir -play /home/student/Documents/honours_project/run/p1_verdi_ahb.tcl &"
