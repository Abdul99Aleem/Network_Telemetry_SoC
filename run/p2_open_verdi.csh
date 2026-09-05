#!/bin/csh -f
# ============================================================================
# Open Phase-2 waveforms in Verdi (run in your terminal, not in Verdi).
#
# Usage:  ./p2_open_verdi.csh [tb1|tb2] [workdir]
#   tb2 (default) = VeeR-through-fabric waves (the gate-14 proof)
#   tb1           = directed fabric test waves
# Needs:  ./p2_full_flow.csh has been run (FSDB + KDB in tb1//tb2/).
# ============================================================================

set PROJ = /home/student/Documents/honours_project
set TB = tb2
if ($#argv >= 1) then
    if ($1 == "tb1" || $1 == "tb2") then
        set TB = $1
    else
        echo "usage: $0 [tb1|tb2] [workdir]"
        exit 1
    endif
endif
if ($#argv >= 2) then
    set WORK = $2
else
    set WORK = /tmp/opencode/veer_p2
endif

if ($TB == "tb1") then
    set FSDB = p2_fabric.fsdb
    set RC = $PROJ/run/p2_wave.rc
else
    set FSDB = p2_veer_soc.fsdb
    set RC = $PROJ/run/p2_veer_wave.rc
endif

if (! -e $WORK/$TB/$FSDB) then
    echo "No $WORK/$TB/$FSDB — run ./p2_full_flow.csh first."
    exit 1
endif
if (! -d $WORK/$TB/simv.daidir) then
    echo "No $WORK/$TB/simv.daidir — run ./p2_full_flow.csh first."
    exit 1
endif
if ($?DISPLAY == 0) then
    setenv DISPLAY :0
    echo "DISPLAY was unset — trying physical console :0."
endif

cd $WORK/$TB
verdi -ssf $FSDB -dbdir simv.daidir -sswr $RC &
echo "Verdi launching on DISPLAY=$DISPLAY ($TB waves + RC)."
