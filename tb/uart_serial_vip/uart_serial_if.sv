// =============================================================================
// VIP: uart_serial_if
// File: uart_serial_if.sv
//
// Description:
//   SystemVerilog interface for the physical UART pins that cross the
//   soc_top boundary:
//     uart_tx_o  — serial TX bitstream (DUT output, TB observes)
//     uart_irq_o — RX-data interrupt (DUT output, TB observes; expected 0
//                  in TX-only operation per v3 §10.1)
//
//   This interface is ONLY for the two signals that are ports of soc_top.
//   The AXI wires between ahb_to_axi_bridge and uart_axi_slave are internal
//   to soc_top and are NOT in this interface.
//
//   The UART agent using this interface is passive: it only monitors
//   uart_tx_o, it never drives it.  No driver-side clocking block is needed.
// =============================================================================
`timescale 1ns/1ps

interface uart_serial_if (input logic clk);

    // Serial TX output from soc_top.  The monitor watches this signal.
    logic uart_tx_o;

    // Interrupt output.  Should remain 0 in TX-only operation.
    logic uart_irq_o;

    // Reset — used by tb_top to drive soc_top.reset_n; also sampled by
    // the monitor to suppress false start-bit detection during reset.
    logic reset_n;

endinterface : uart_serial_if
