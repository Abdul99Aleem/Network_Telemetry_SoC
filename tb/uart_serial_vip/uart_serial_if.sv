// =============================================================================
// VIP: uart_serial_if
// File: uart_serial_if.sv
//
// Description:
//   SystemVerilog interface for the physical UART serial signals.
//   Supports observing the physical external signals of soc_top:
//     uart_tx_o  — serial TX bitstream (DUT output, VIP monitor observes)
//     uart_irq_o — interrupt output (DUT output, VIP monitor observes;
//                  expected 0 in TX-only operation per SoC v3 §10.1)
//     reset_n    — active-low system reset
//
//   Also provides uart_rx_i for active stimulus generation (VIP driver)
//   during unit-level loopback, receiver tests, and Test 11 verification.
// =============================================================================
`timescale 1ns/1ps

interface uart_serial_if (input logic clk);

    // Physical signals matching soc_top external ports
    logic uart_tx_o;   // Transmitted serial bitstream from DUT
    logic uart_irq_o;  // Interrupt status output from DUT
    logic reset_n;     // Active-low asynchronous reset

    // Serial RX input signal (driven by VIP in active mode, default idle high)
    logic uart_rx_i;

    initial begin
        uart_rx_i = 1'b1;
    end

    // Clocking block for synchronous VIP driver operations
    clocking drv_cb @(posedge clk);
        default input #1step output #100ps;
        output uart_rx_i;
        input  uart_tx_o;
        input  uart_irq_o;
        input  reset_n;
    endclocking

    // Clocking block for synchronous VIP monitor sampling
    clocking mon_cb @(posedge clk);
        default input #1step;
        input uart_tx_o;
        input uart_rx_i;
        input uart_irq_o;
        input reset_n;
    endclocking

    modport drv_mp (clocking drv_cb, output uart_rx_i, input reset_n);
    modport mon_mp (clocking mon_cb, input uart_tx_o, input uart_irq_o, input reset_n);

endinterface : uart_serial_if
