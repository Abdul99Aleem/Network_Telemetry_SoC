#!/bin/csh -f
# ============================================================================
# P2 FULL FLOW — AHB-Lite fabric (TB1) + VeeR through fabric (TB2).
# Usage:  ./p2_full_flow.csh [workdir]   # default: /tmp/opencode/veer_p2
# Needs:  source /home/student/cshrc (VCS + Verdi) beforehand.
# Result: TB1 16/16 PASS + TB2 PASS, FSDB pair in tb1/ and tb2/.
# ============================================================================

setenv RV_ROOT /home/student/Documents/honours_project/core/Cores-VeeR-EL2
# Tool env (already present if user did `source ~/cshrc`; set here as fallback)
if (! $?VCS_HOME) setenv VCS_HOME /home/student/snps_tools_target/vcs/U-2023.03
if (! $?VERDI_HOME) setenv VERDI_HOME /home/student/snps_tools_target/verdi/U-2023.03-SP1
if (! $?SNPSLMD_LICENSE_FILE) setenv SNPSLMD_LICENSE_FILE 27021@14.139.1.126
setenv PATH ${VCS_HOME}/bin:${VERDI_HOME}/bin:${PATH}
set PROJ = /home/student/Documents/honours_project
if ($#argv >= 1) then
    set WORK = $1
else
    set WORK = /tmp/opencode/veer_p2
endif

echo "=== P2 FULL FLOW  WORK=$WORK ==="
mkdir -p $WORK/tb1 $WORK/tb2
cd $WORK

echo "--- [1/5] p2_soc snapshot (reset_vec=0, boot from IMEM) ---"
env BUILD_PATH=$WORK/snapshots/p2_soc RV_ROOT=$RV_ROOT \
  $RV_ROOT/configs/veer.config -target=default_ahb -snapshot=p2_soc \
  -set=reset_vec=0x00000000
if ($status != 0) exit 1

echo "--- [2/5] P2 program hex ---"
python3 $PROJ/scripts/p2_prog_gen.py $WORK/tb2/p2_prog.hex
if ($status != 0) exit 1

echo "--- [3/5] TB1 directed fabric ---"
cd $WORK/tb1
vcs -full64 -sverilog -f $PROJ/run/p2_fabric_run.f \
  -debug_access+all -kdb -l compile_p2_fabric.log
if ($status != 0) exit 1
./simv -l sim_p2_fabric.log
grep -q "P2_TB1_RESULT: PASS" sim_p2_fabric.log
if ($status != 0) then
    echo "TB1 FAILED — see $WORK/tb1/sim_p2_fabric.log"
    exit 1
endif

echo "--- [4/5] TB2 VeeR through fabric ---"
cd $WORK/tb2
vcs -full64 -sverilog -f $PROJ/run/p2_veer_soc_run.f \
  -debug_access+all -kdb +define+RV_OPENSOURCE +error+500 \
  -timescale=1ns/10ps -l compile_p2_veer_soc.log
if ($status != 0) exit 1
./simv -l sim_p2_veer_soc.log
grep -q "P2_TB2_RESULT: PASS" sim_p2_veer_soc.log
if ($status != 0) then
    echo "TB2 FAILED — see $WORK/tb2/sim_p2_veer_soc.log"
    exit 1
endif

echo ""
echo "=== P2 FLOW: TB1 PASS + TB2 PASS ==="
echo "  cd $WORK/tb1; setenv DISPLAY :0"
echo "  verdi -ssf p2_fabric.fsdb -dbdir simv.daidir -sswr $PROJ/run/p2_wave.rc &"
echo "  cd $WORK/tb2"
echo "  verdi -ssf p2_veer_soc.fsdb -dbdir simv.daidir -sswr $PROJ/run/p2_veer_wave.rc &"
