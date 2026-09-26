+incdir+../rtl/uart
+incdir+../rtl/uart/ip
+incdir+../rtl/interconnects
+incdir+../tb

../rtl/uart/axi_uart_wrapper.v

../rtl/interconnects/axi_interconnect_wrap_2x8.v
../rtl/interconnects/axi_interconnect.v
../rtl/interconnects/arbiter.v
../rtl/interconnects/priority_encoder.v

../rtl/uart/uart_axi_slave.v
../rtl/uart/ip/axi_internal_fifo.v
../rtl/uart/ip/uart_parity_bit_compute.v
../rtl/uart/ip/uart_receiver.v
../rtl/uart/ip/uart_transmitter.v
../rtl/uart/ip/uart_controller.v
../rtl/uart/ip/axi_uart_top.v

../tb/tb_axi_interconnect_uart.sv

-top tb_axi_interconnect_uart
