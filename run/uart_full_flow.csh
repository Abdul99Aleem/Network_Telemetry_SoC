#!/bin/csh -f
# ============================================================================
# UART AXI FULL FLOW - direct + interconnect + 2-master (VCS + FSDB).
# Mirrors the AES regression in README ("AES / AXI regression") but for UART
# on M02 (0x1000_0000). Run from honours_project/run/ after:
#   csh; source /home/student/cshrc
#
#   ./uart_full_flow.csh
#
# Each step compiles with VCS (-full64 -sverilog -debug_access+all -kdb) and
# runs ./simv. FSDBs (uart_axi_slave.fsdb, uart_axi_interconnect.fsdb,
# uart_axi_2master.fsdb) land in run/ for Verdi (see uart_*_wave.rc).
# Exit 0 = all three PASS.
# ============================================================================

cd `dirname $0`
if ($status != 0) exit 1

set FAIL = 0

echo "=== [1/3] UART direct slave (uart_axi_run.f) ==="
vcs -full64 -sverilog -f uart_axi_run.f -debug_access+all -kdb -l compile_uart_axi.log
if ($status != 0) then
    echo "UART direct COMPILE FAILED (see compile_uart_axi.log)"
    set FAIL = 1
else
    ./simv -l sim_uart_axi.log
    grep -q "UART AXI SLAVE DIRECT: PASS" sim_uart_axi.log
    if ($status != 0) then
        echo "UART direct TEST FAILED (see sim_uart_axi.log)"
        set FAIL = 1
    else
        echo "UART direct PASS"
        ls -la uart_axi_slave.fsdb
    endif
endif

echo ""
echo "=== [2/3] UART interconnect single-master (uart_axi_interconnect_run.f) ==="
vcs -full64 -sverilog -f uart_axi_interconnect_run.f -debug_access+all -kdb -l compile_uart_axi_interconnect.log
if ($status != 0) then
    echo "UART interconnect COMPILE FAILED (see compile_uart_axi_interconnect.log)"
    set FAIL = 1
else
    ./simv -l sim_uart_axi_interconnect.log
    grep -q "AXI INTERCONNECT -> UART INTEGRATION: PASS" sim_uart_axi_interconnect.log
    if ($status != 0) then
        echo "UART interconnect TEST FAILED (see sim_uart_axi_interconnect.log)"
        set FAIL = 1
    else
        echo "UART interconnect PASS"
        ls -la uart_axi_interconnect.fsdb
    endif
endif

echo ""
echo "=== [3/3] UART 2-master contention (uart_axi_2master_run.f) ==="
vcs -full64 -sverilog -f uart_axi_2master_run.f -debug_access+all -kdb -l compile_uart_axi_2master.log
if ($status != 0) then
    echo "UART 2-master COMPILE FAILED (see compile_uart_axi_2master.log)"
    set FAIL = 1
else
    ./simv -l sim_uart_axi_2master.log
    grep -q "TWO-MASTER UART TEST PASSED" sim_uart_axi_2master.log
    if ($status != 0) then
        echo "UART 2-master TEST FAILED (see sim_uart_axi_2master.log)"
        set FAIL = 1
    else
        echo "UART 2-master PASS"
        ls -la uart_axi_2master.fsdb
    endif
endif

echo ""
if ($FAIL == 0) then
    echo "=== UART FULL FLOW: ALL PASS ==="
    echo "Verdi (from run/):"
    echo "  verdi -ssf uart_axi_slave.fsdb -dbdir simv.daidir -sswr ./uart_axi_slave_wave.rc &"
    echo "  verdi -ssf uart_axi_interconnect.fsdb -dbdir simv.daidir -sswr ./uart_wave.rc &"
    echo "  verdi -ssf uart_axi_2master.fsdb -dbdir simv.daidir -sswr ./uart_2master_wave.rc &"
    exit 0
else
    echo "=== UART FULL FLOW: FAIL (see logs above) ==="
    exit 1
endif
