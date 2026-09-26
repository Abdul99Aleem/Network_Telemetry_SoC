#!/bin/csh -f
# ============================================================================
# UART END-TO-END FLOW — VeeR -> AHB-Lite -> AHB/AXI bridge -> UART -> uart_tx.
# Usage:  ./p3_uart_flow.csh [workdir]   # default: /tmp/opencode/uart_e2e
# Needs:  source /home/student/cshrc (VCS + Verdi) beforehand.
#
#   1. build the VeeR "uart_soc" snapshot (reset_vec=0, boots from IMEM)
#   2. assemble the bare-metal UART program (scripts/p3_uart_prog_gen.py)
#   3. compile + run tb_veer_uart_soc   -> UART_E2E_RESULT: PASS
#   4. compile + run tb_ahb_fabric (TB1 regression, now incl. bridge T11/T12)
#      -> P2_TB1_RESULT: PASS
# Exit 0 = both PASS.
# ============================================================================
setenv RV_ROOT /home/student/Documents/honours_project/core/Cores-VeeR-EL2
if (! $?VCS_HOME) setenv VCS_HOME /home/student/snps_tools_target/vcs/U-2023.03
if (! $?VERDI_HOME) setenv VERDI_HOME /home/student/snps_tools_target/verdi/U-2023.03-SP1
if (! $?SNPSLMD_LICENSE_FILE) setenv SNPSLMD_LICENSE_FILE 27021@14.139.1.126
setenv PATH ${VCS_HOME}/bin:${VERDI_HOME}/bin:${PATH}
set PROJ = /home/student/Documents/honours_project
if ($#argv >= 1) then
    set WORK = $1
else
    set WORK = /tmp/opencode/uart_e2e
endif

echo "=== UART E2E FLOW  WORK=$WORK ==="
mkdir -p $WORK/tb $WORK/tb1
cd $WORK

echo "--- [1/4] uart_soc snapshot (reset_vec=0, boot from IMEM) ---"
env BUILD_PATH=$WORK/snapshots/uart_soc RV_ROOT=$RV_ROOT \
  $RV_ROOT/configs/veer.config -target=default_ahb -snapshot=uart_soc \
  -set=reset_vec=0x00000000
if ($status != 0) exit 1

echo "--- [2/4] UART program hex ---"
python3 $PROJ/scripts/p3_uart_prog_gen.py $WORK/tb/uart_prog.hex
if ($status != 0) exit 1

echo "--- [3/4] UART end-to-end (VeeR -> AHB -> AXI -> UART) ---"
cd $WORK/tb
vcs -full64 -sverilog -f $PROJ/run/p3_uart_soc_run.f \
  -debug_access+all -kdb +define+RV_OPENSOURCE +error+500 \
  -timescale=1ns/10ps -l compile_uart_e2e.log
if ($status != 0) then
    echo "UART E2E COMPILE FAILED (see $WORK/tb/compile_uart_e2e.log)"
    exit 1
endif
./simv -l sim_uart_e2e.log
grep -q "UART_E2E_RESULT: PASS" sim_uart_e2e.log
if ($status != 0) then
    echo "UART E2E TEST FAILED (see $WORK/tb/sim_uart_e2e.log)"
    exit 1
endif

echo "--- [4/4] fabric regression incl. bridge (TB1) ---"
cd $WORK/tb1
vcs -full64 -sverilog -f $PROJ/run/p2_fabric_run.f \
  -debug_access+all -kdb -l compile_p2_fabric.log
if ($status != 0) then
    echo "TB1 COMPILE FAILED (see compile_p2_fabric.log)"
    exit 1
endif
./simv -l sim_p2_fabric.log
grep -q "P2_TB1_RESULT: PASS" sim_p2_fabric.log
if ($status != 0) then
    echo "TB1 FAILED (see $WORK/tb1/sim_p2_fabric.log)"
    exit 1
endif

echo ""
echo "=== UART E2E FLOW: E2E PASS + TB1 PASS ==="
echo "  cd $WORK/tb; setenv DISPLAY :0"
echo "  verdi -ssf uart_veer_soc.fsdb -dbdir simv.daidir -sswr $PROJ/run/uart_e2e_wave.rc &"
