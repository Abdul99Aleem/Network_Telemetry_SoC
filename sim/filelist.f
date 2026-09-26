// ============================================================================
// Project : RISC-V Network Telemetry SoC
// Script  : sim/filelist.f
// Desc    : VCS command file for the fw0 / Phase-2 VeeR-through-fabric bench.
//
//           Environment variables expanded by VCS inside command files
//           (run/p2_veer_soc_run.f already relies on this for $RV_ROOT):
//             $FW_SNAP  - VeeR p2_soc snapshot.  PROJECT-LOCAL, decision D6:
//                         build/snapshots/p2_soc.  Never /tmp/opencode — that
//                         tree is root-owned and unwritable (plan finding N4).
//             $FW_PROJ  - repository root.
//             $RV_ROOT  - VeeR EL2 source tree.
// ============================================================================

+incdir+$RV_ROOT/testbench
+incdir+$RV_ROOT/design/include
+incdir+$FW_SNAP

$FW_SNAP/common_defines.vh
$RV_ROOT/design/include/el2_def.sv
$FW_SNAP/el2_pdef.vh

-f $RV_ROOT/testbench/flist

// ---- project SoC RTL ----
$FW_PROJ/rtl/ahb/ahb_interconnect.sv
$FW_PROJ/rtl/ahb/ahb_sram.sv
$FW_PROJ/rtl/ahb/ahb_default_slave.sv
$FW_PROJ/rtl/soc_top.sv

// ---- UART subsystem (Phase-3, attached at 0x1000_0000) ----
-f $FW_PROJ/run/uart_rtl.f

// ---- testbench ----
// tb_ahb_cycle_monitor precedes the top: tb_veer_p2_soc instantiates it.
$FW_PROJ/tb/tb_ahb_cycle_monitor.sv
$FW_PROJ/tb/tb_veer_p2_soc.sv

-top tb_veer_p2_soc
