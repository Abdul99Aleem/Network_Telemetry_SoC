+incdir+$RV_ROOT/testbench
+incdir+$RV_ROOT/design/include
+incdir+/tmp/opencode/uart_e2e/snapshots/uart_soc

/tmp/opencode/uart_e2e/snapshots/uart_soc/common_defines.vh
$RV_ROOT/design/include/el2_def.sv
/tmp/opencode/uart_e2e/snapshots/uart_soc/el2_pdef.vh

-f $RV_ROOT/testbench/flist

/home/student/Documents/honours_project/rtl/ahb/ahb_interconnect.sv
/home/student/Documents/honours_project/rtl/ahb/ahb_sram.sv
/home/student/Documents/honours_project/rtl/ahb/ahb_default_slave.sv
/home/student/Documents/honours_project/rtl/soc_top.sv

-f /home/student/Documents/honours_project/run/uart_rtl.f

/home/student/Documents/honours_project/tb/tb_veer_uart_soc.sv

-top tb_veer_uart_soc
